import Foundation
import SwiftUI
import CoreNFC

/// Prepares a blank or damaged tag for NDEF: capability container, empty message, zeroed user memory.
@MainActor
struct FormatToolView: View {
    @Environment(AppState.self) private var app
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Label("Writes the capability container if the tag has none.", systemImage: "1.circle")
                Label("Writes an empty NDEF message.", systemImage: "2.circle")
                Label("Fills the rest of the user memory with zeros.", systemImage: "3.circle")
            } header: {
                Text("What formatting does")
            } footer: {
                Text("Use this on a blank tag that other apps cannot write, or on a tag whose memory was damaged by a bad write. Works on NTAG, MIFARE Ultralight and ISO 15693 tags. The serial number, lock bytes and configuration pages are left alone.")
            }

            Section {
                ScanButton("Format tag", systemImage: "arrow.triangle.2.circlepath") {
                    showingConfirmation = true
                }
            } footer: {
                Text("Formatting erases every record on the tag.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Format memory")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Format this tag?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Format tag", role: .destructive) {
                format()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All user memory on the tag you scan next will be erased and replaced with an empty message.")
        }
        .alertItem($alert)
    }

    private func format() {
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag to format it.",
                    successMessage: "Tag formatted."
                ) { session, tag in
                    try await TagOperations.format(session, tag)
                }
                Haptics.success()
                alert = AlertItem.success("The tag is formatted and ready to write.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
