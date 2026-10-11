import Foundation
import SwiftUI

/// Options applied to the next write from the Write tab.
@MainActor
struct WriteOptionsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var queue = app.writeQueue
        Form {
            Section {
                Toggle("Verify after write", isOn: $queue.options.verifyAfterWrite)
            } footer: {
                Text("Reads the tag back after writing and checks that every byte matches.")
            }

            Section {
                Toggle("Erase before write", isOn: $queue.options.eraseFirst)
            } footer: {
                Text("Writes an empty message first so nothing is left over from a previous use.")
            }

            Section {
                Toggle("Lock tag after write", isOn: $queue.options.lockAfterWrite)
            } footer: {
                Text("Locking is permanent. A locked tag becomes read only and can never be written or erased again, by this app or any other. This option turns itself off after each write.")
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Write options")
        .navigationBarTitleDisplayMode(.inline)
    }
}
