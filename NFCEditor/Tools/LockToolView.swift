import Foundation
import SwiftUI
import CoreNFC

/// Sets the lock bits so the tag becomes read only forever. Gated by an explicit acknowledgement and a confirmation.
@MainActor
struct LockToolView: View {
    @Environment(AppState.self) private var app
    @State private var acknowledged = false
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Locking is permanent. The records stay readable, but the tag can never be written, erased or formatted again, by this app or any other.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Write and verify the tag first, then read it back in the Read tab to check it holds exactly what you want.")
            }

            Section {
                Toggle("I understand this cannot be undone", isOn: $acknowledged)
            }

            Section {
                ScanButton("Lock tag", systemImage: "lock.fill", role: .destructive) {
                    showingConfirmation = true
                }
                .disabled(!acknowledged)
            } footer: {
                Text("Locking does not add a password. Use the Password tool for protection you can remove later.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Lock tag")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Lock this tag permanently?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Lock tag", role: .destructive) {
                lock()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tag you scan next becomes read only forever.")
        }
        .alertItem($alert)
    }

    private func lock() {
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Tag locked."
                ) { session, tag in
                    try await TagOperations.lock(session, tag)
                }
                // Each lock is a separate decision, so the next tag needs a fresh acknowledgement.
                acknowledged = false
                Haptics.success()
                alert = AlertItem.success("The tag is now read only.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
