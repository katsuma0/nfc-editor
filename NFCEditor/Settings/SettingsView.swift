import Foundation
import SwiftUI

/// Presented as a sheet from the gear button on the Read and Tools tabs.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var language = ""

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Read full memory when scanning", isOn: $settings.readFullMemoryOnScan)
                    Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Reading the full memory shows every page and lets you save a complete dump. It takes a little longer on large tags.")
                }

                Section {
                    Toggle("Verify after write", isOn: $settings.verifyAfterWrite)
                    LabeledContent("Default text language") {
                        TextField("en", text: $language)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Writing")
                } footer: {
                    Text("Two-letter language code for new text records, for example en or fr.")
                }

                Section {
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Button("Clear command history", role: .destructive) {
                        settings.clearCommandHistory()
                    }
                    .disabled(settings.commandHistory.isEmpty)
                } header: {
                    Text("Advanced commands")
                } footer: {
                    Text(historyFooter(count: settings.commandHistory.count))
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About NFC Editor", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                language = app.settings.defaultLanguage
            }
            .onChange(of: language) { _, newValue in
                let cleaned = String(newValue.lowercased().filter { $0.isASCII && $0.isLetter }.prefix(2))
                if cleaned != newValue {
                    language = cleaned
                    return
                }
                // Settings only ever hold a complete code, so a half-typed field never breaks new text records.
                if cleaned.count == 2 {
                    app.settings.defaultLanguage = cleaned
                }
            }
        }
    }

    private func historyFooter(count: Int) -> String {
        switch count {
        case 0:
            return "No saved commands."
        case 1:
            return "1 saved command."
        default:
            return "\(count) saved commands."
        }
    }
}
