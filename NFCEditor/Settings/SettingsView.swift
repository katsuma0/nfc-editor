import Foundation
import SwiftUI

/// Presented as a sheet from the gear button on the Read and Tools tabs. Everyday choices first; the rest sit behind Show advanced settings.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var language = ""
    @State private var scanLogURL: URL?
    @State private var showingClearHistory = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Verify after write", isOn: $settings.verifyAfterWrite)
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                    Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
                } footer: {
                    Text("Verify reads the tag back after each write from the Write tab and checks that every byte landed. Copying a tag and writing a saved tag always verify.")
                }

                scanHistorySection

                Section {
                    Button {
                        withAnimation {
                            settings.showAdvancedSettings.toggle()
                        }
                    } label: {
                        Text(settings.showAdvancedSettings ? "Hide advanced settings" : "Show advanced settings")
                    }
                }

                if settings.showAdvancedSettings {
                    Section {
                        Toggle("Read full memory when scanning", isOn: $settings.readFullMemoryOnScan)
                    } header: {
                        Text("Scanning")
                    } footer: {
                        Text("Shows every page of the chip and lets you save a complete dump. Large tags take a little longer.")
                    }

                    Section {
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
                        Button("Clear command history", role: .destructive) {
                            settings.clearCommandHistory()
                        }
                        .disabled(settings.commandHistory.isEmpty)
                    } header: {
                        Text("Advanced commands")
                    } footer: {
                        Text(historyFooter(count: settings.commandHistory.count))
                    }
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
            .onChange(of: app.scanHistory, initial: true) { _, _ in
                scanLogURL = writeScanLog()
            }
            .onDisappear {
                SettingsView.removeScanLogFile()
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

    private var scanHistorySection: some View {
        Section {
            if let scanLogURL {
                ShareLink(item: scanLogURL) {
                    Label("Export scan log", systemImage: "tablecells")
                }
            } else {
                Button {} label: {
                    Label("Export scan log", systemImage: "tablecells")
                }
                .disabled(true)
            }
            Button(role: .destructive) {
                showingClearHistory = true
            } label: {
                Label("Clear scan history", systemImage: "trash")
            }
            .disabled(app.scanHistory.isEmpty)
            .confirmationDialog("Clear the scan history?", isPresented: $showingClearHistory, titleVisibility: .visible) {
                Button("Clear scan history", role: .destructive) {
                    app.clearScanHistory()
                }
                Button("Cancel", role: .cancel) {}
            }
        } header: {
            Text("Scan history")
        } footer: {
            Text(scanHistoryFooter)
        }
    }

    private var scanHistoryFooter: String {
        switch app.scanHistory.count {
        case 0:
            return "No scans yet. The last 20 scans are kept until you close the app. Saved tags are not affected."
        case 1:
            return "1 scan. Exports as a spreadsheet with serial number, chip, record count and time."
        default:
            return "\(app.scanHistory.count) scans. Exports as a spreadsheet with serial number, chip, record count and time."
        }
    }

    private static var scanLogFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NFC scan log.csv")
    }

    /// The CSV only exists while Settings is open, so serial numbers never outlive the in-memory history.
    static func removeScanLogFile() {
        try? FileManager.default.removeItem(at: scanLogFileURL)
    }

    /// ShareLink needs a file up front, so the CSV is rewritten whenever the scan history changes.
    @MainActor
    private func writeScanLog() -> URL? {
        let url = SettingsView.scanLogFileURL
        guard !app.scanHistory.isEmpty else {
            SettingsView.removeScanLogFile()
            return nil
        }
        do {
            try Data(app.exportScanLogCSV().utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
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
