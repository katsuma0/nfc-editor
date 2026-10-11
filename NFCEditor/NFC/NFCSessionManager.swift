import Foundation
import CoreNFC
import Observation

/// One tag operation per call. Starts an NFCTagReaderSession, waits for exactly one tag,
/// connects, runs `body`, then invalidates with `successMessage` (or an error message).
@MainActor @Observable
final class NFCSessionManager {
    static let shared = NFCSessionManager()

    private(set) var isBusy = false

    nonisolated static var isAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }

    @ObservationIgnored private var activeRun: AnyObject?

    private init() {}

    func run<T: Sendable>(
        alertMessage: String,
        polling: NFCTagReaderSession.PollingOption = [.iso14443, .iso15693, .iso18092],
        successMessage: String = "Done.",
        body: @escaping @Sendable (NFCTagReaderSession, NFCTag) async throws -> T
    ) async throws -> T {
        if isBusy {
            throw NFCEditorError.failed("Another NFC operation is in progress.")
        }
        guard Self.isAvailable else {
            throw NFCEditorError.nfcUnavailable
        }
        isBusy = true
        defer {
            activeRun = nil
            isBusy = false
        }
        let operation = SessionRun<T>(successMessage: successMessage, body: body)
        activeRun = operation
        let result: Result<T, Error>
        do {
            let value = try await operation.start(alertMessage: alertMessage, polling: polling)
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        // Core NFC refuses a new session while the previous one is still closing, so stay busy until it has reported the close.
        await operation.waitUntilClosed()
        return try result.get()
    }
}

/// Delegate for a single session. The session only holds its delegate weakly, so the run
/// keeps itself alive until Core NFC reports the session closed.
private final class SessionRun<T: Sendable>: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    private let successMessage: String
    private let body: @Sendable (NFCTagReaderSession, NFCTag) async throws -> T
    private let queue = DispatchQueue(label: "NFCEditor.NFCSessionManager")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var resumed = false
    private var closed = false
    private var session: NFCTagReaderSession?
    private var task: Task<Void, Never>?
    private var retainedSelf: SessionRun?

    init(successMessage: String, body: @escaping @Sendable (NFCTagReaderSession, NFCTag) async throws -> T) {
        self.successMessage = successMessage
        self.body = body
        super.init()
    }

    @MainActor
    func start(alertMessage: String, polling: NFCTagReaderSession.PollingOption) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()

            // Bound through an explicit Optional so this compiles whether the SDK imports the initializer as failable or not.
            let created: NFCTagReaderSession? = NFCTagReaderSession(pollingOption: polling, delegate: self, queue: self.queue)
            guard let session = created else {
                self.lock.lock()
                self.closed = true
                self.lock.unlock()
                self.finish(.failure(NFCEditorError.nfcUnavailable))
                return
            }
            session.alertMessage = alertMessage

            self.lock.lock()
            self.session = session
            self.retainedSelf = self
            self.lock.unlock()

            session.begin()
        }
    }

    private func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !resumed, let continuation = continuation else {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    /// Returns once Core NFC has reported the session closed, or after a short grace period if it never does.
    func waitUntilClosed() async {
        for _ in 0..<40 {
            if isClosed() {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func isClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        finish(.failure(NFCEditorError.map(error)))
        lock.lock()
        let runningTask = task
        task = nil
        self.session = nil
        closed = true
        retainedSelf = nil
        lock.unlock()
        runningTask?.cancel()
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than one tag found. Present only one tag."
            queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.restartPolling()
            }
            return
        }
        guard let tag = tags.first else {
            session.restartPolling()
            return
        }

        let successMessage = self.successMessage
        let body = self.body
        let newTask = Task { [self] in
            do {
                try await session.connect(to: tag)
                let value = try await body(session, tag)
                session.alertMessage = successMessage
                // Resume before invalidating so the invalidation callback cannot turn a success into a cancel.
                self.finish(.success(value))
                session.invalidate()
            } catch {
                let mapped = NFCEditorError.map(error)
                self.finish(.failure(mapped))
                session.invalidate(errorMessage: mapped.errorDescription ?? "Failed.")
            }
        }

        lock.lock()
        task = newTask
        lock.unlock()
    }
}
