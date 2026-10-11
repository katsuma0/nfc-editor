import Foundation
import SwiftUI

/// Tools tab: one row per tag utility, each opening its own screen.
struct ToolsView: View {
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        EraseToolView()
                    } label: {
                        ToolRow(title: "Erase tag", description: "Remove every record from a tag.", systemImage: "trash")
                    }
                    NavigationLink {
                        CopyToolView()
                    } label: {
                        ToolRow(title: "Copy tag", description: "Read one tag and write it to another.", systemImage: "doc.on.doc")
                    }
                    NavigationLink {
                        LockToolView()
                    } label: {
                        ToolRow(title: "Lock tag", description: "Make a tag permanently read only.", systemImage: "lock")
                    }
                    NavigationLink {
                        FormatToolView()
                    } label: {
                        ToolRow(title: "Format memory", description: "Prepare a blank or damaged tag for NDEF.", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("Tag")
                }

                Section {
                    NavigationLink {
                        MemoryEditorView()
                    } label: {
                        ToolRow(title: "Memory editor", description: "Read and edit memory page by page.", systemImage: "memorychip")
                    }
                    NavigationLink {
                        WriteDumpView()
                    } label: {
                        ToolRow(title: "Write dump", description: "Write a saved memory dump to a tag.", systemImage: "arrow.down.doc")
                    }
                    NavigationLink {
                        AdvancedCommandView()
                    } label: {
                        ToolRow(title: "Advanced commands", description: "Send raw commands to the chip.", systemImage: "terminal")
                    }
                } header: {
                    Text("Memory")
                }

                Section {
                    NavigationLink {
                        PasswordToolView()
                    } label: {
                        ToolRow(title: "Password", description: "Protect a tag with a password, or remove one.", systemImage: "key")
                    }
                    NavigationLink {
                        CounterToolView()
                    } label: {
                        ToolRow(title: "Counter", description: "Read the tag counter or switch it on and off.", systemImage: "number")
                    }
                    NavigationLink {
                        SignatureToolView()
                    } label: {
                        ToolRow(title: "Signature", description: "Read the chip's originality signature.", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("Chip")
                } footer: {
                    Text("Most tools work on NTAG and MIFARE Ultralight tags. Each screen says what its chip needs.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

/// Icon, title and a one-line description, like a row in the Settings app.
private struct ToolRow: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }
}
