import Foundation
import SwiftUI
import CoreNFC

/// Writes an empty NDEF message, optionally zeroing the whole user memory as well.
@MainActor
struct EraseToolView: View {
    @Environment(AppState.self) private var app
    @State private var zeroUserMemory = false
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Toggle("Also zero the whole user memory", isOn: $zeroUserMemory)
            } header: {
                Text("Erase")
            } footer: {
                Text("Writes an empty message so the tag holds no records. The tag stays formatted and can be written again right away. Zeroing the user memory also wipes leftover bytes from older records, which takes a little longer.")
            }

            Section {
                ScanButton("Erase tag", systemImage: "trash", role: .destructive) {
                    showingConfirmation = true
                }
            } footer: {
                Text("Locked tags cannot be erased.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Erase tag")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase this tag?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Erase tag", role: .destructive) {
                erase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alertItem($alert)
    }

    private var confirmationMessage: String {
        if zeroUserMemory {
            return "All records will be removed from the tag you scan next and its user memory will be filled with zeros."
        }
        return "All records will be removed from the tag you scan next."
    }

    private func erase() {
        let zero = zeroUserMemory
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag to erase it.",
                    successMessage: "Tag erased."
                ) { session, tag in
                    try await TagOperations.erase(session, tag, zeroUserMemory: zero)
                }
                Haptics.success()
                alert = AlertItem.success(zero ? "The tag was erased and its user memory was zeroed." : "The tag was erased.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
