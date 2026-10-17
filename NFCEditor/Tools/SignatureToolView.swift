import Foundation
import SwiftUI
import UIKit
import CoreNFC

/// Reads the 32-byte NXP originality signature from NTAG 21x, NTAG I2C and Ultralight EV1 chips and checks it
/// against NXP's public key on the phone.
@MainActor
struct SignatureToolView: View {
    @Environment(AppState.self) private var app
    @State private var lastRead: SignatureResult?
    @State private var copied = false
    @State private var copyCount = 0
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                ScanButton("Read signature") {
                    read()
                }
            } footer: {
                Text("NXP signs every NTAG 21x, NTAG I2C and MIFARE Ultralight EV1 chip with a 32-byte originality signature tied to its serial number. The app checks it against NXP's public key to tell a genuine NXP chip from a clone.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let lastRead {
                Section {
                    verdictRow(lastRead.verdict)
                } header: {
                    Text("Result")
                } footer: {
                    Text(TagDetailView.verdictFooter(lastRead.verdict))
                }

                Section {
                    LabeledContent("Chip", value: lastRead.chipName)
                    LabeledContent("Serial number") {
                        Text(lastRead.uid.hexString(separator: ":"))
                            .font(.body.monospaced())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signature")
                        Text(lastRead.signature.hexString(separator: " "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button {
                        copy(lastRead.signature)
                    } label: {
                        Label(copyTitle, systemImage: copyImage)
                    }
                } header: {
                    Text("Signature")
                } footer: {
                    Text("Read at \(lastRead.readAt.formatted(date: .omitted, time: .shortened)). The check uses the serial number as well as the signature, and runs on your iPhone without a network connection.")
                }
            }
        }
        .navigationTitle("Signature")
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    private func verdictRow(_ verdict: SignatureVerdict) -> some View {
        Label {
            Text(TagDetailView.verdictText(verdict))
                .fontWeight(.semibold)
                .foregroundStyle(TagDetailView.verdictColor(verdict))
        } icon: {
            Image(systemName: SignatureToolView.verdictImage(verdict))
                .foregroundStyle(TagDetailView.verdictColor(verdict))
        }
    }

    private static func verdictImage(_ verdict: SignatureVerdict) -> String {
        switch verdict {
        case .genuine:
            return "checkmark.seal.fill"
        case .notGenuine:
            return "xmark.seal.fill"
        case .noKey:
            return "questionmark.circle"
        }
    }

    private var copyTitle: String {
        copied ? "Copied" : "Copy signature"
    }

    private var copyImage: String {
        copied ? "checkmark" : "doc.on.doc"
    }

    // MARK: Actions

    private func read() {
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Signature read."
                ) { session, tag -> SignatureResult in
                    let (spec, uid) = try await TagOperations.identify(session, tag)
                    let signature = try await TagOperations.readSignature(session, tag)
                    let verdict = OriginalitySignature.verify(signature: signature, uid: uid, chip: spec)
                    return SignatureResult(chipName: spec.name, uid: uid, signature: signature, verdict: verdict, readAt: Date())
                }
                lastRead = result
                copied = false
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func copy(_ signature: Data) {
        UIPasteboard.general.string = signature.hexString()
        Haptics.tap()
        copied = true
        copyCount += 1
        let current = copyCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            // A later tap restarts the two seconds, so only the newest tap resets the label.
            if copyCount == current {
                copied = false
            }
        }
    }
}

private struct SignatureResult: Hashable, Sendable {
    var chipName: String
    var uid: Data
    var signature: Data
    var verdict: SignatureVerdict
    var readAt: Date
}
