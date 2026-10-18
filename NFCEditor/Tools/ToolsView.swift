import Foundation
import SwiftUI

/// Tools tab: the everyday tools first, then the chip-specific ones behind Show advanced tools.
@MainActor
struct ToolsView: View {
    @Environment(AppState.self) private var app
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                everydaySection
                advancedToggleSection
                if app.settings.showAdvancedTools {
                    memorySection
                    ntagSection
                    desfireSection
                    iso15693Section
                    feliCaSection
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

    // MARK: Sections

    private var everydaySection: some View {
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
                PasswordToolView()
            } label: {
                ToolRow(title: "Password", description: "Protect a tag with a password, or remove one.", systemImage: "key")
            }
            NavigationLink {
                LockToolView()
            } label: {
                ToolRow(title: "Lock tag", description: "Make a tag read only for good.", systemImage: "lock")
            }
            NavigationLink {
                FormatToolView()
            } label: {
                ToolRow(title: "Format tag", description: "Prepare a blank or damaged tag for writing.", systemImage: "arrow.triangle.2.circlepath")
            }
            NavigationLink {
                SignatureToolView()
            } label: {
                ToolRow(title: "Check if genuine", description: "Read the NXP signature to spot a cloned chip.", systemImage: "checkmark.seal")
            }
        }
    }

    private var advancedToggleSection: some View {
        Section {
            Button {
                withAnimation {
                    app.settings.showAdvancedTools.toggle()
                }
            } label: {
                Text(app.settings.showAdvancedTools ? "Hide advanced tools" : "Show advanced tools")
            }
        } footer: {
            if !app.settings.showAdvancedTools {
                Text("Memory editor, raw commands, dumps, counters, mirroring, page locks, and tools for DESFire, ISO 15693 and FeliCa chips.")
            }
        }
    }

    private var memorySection: some View {
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
    }

    private var ntagSection: some View {
        Section {
            NavigationLink {
                CounterToolView()
            } label: {
                ToolRow(title: "Counter", description: "Read the tag counter or switch it on and off.", systemImage: "number")
            }
            NavigationLink {
                MirrorToolView()
            } label: {
                ToolRow(title: "Mirror", description: "Put the serial number or scan count into a link.", systemImage: "link.badge.plus")
            }
            NavigationLink {
                LockPagesToolView()
            } label: {
                ToolRow(title: "Lock pages", description: "See which pages are locked and lock chosen ones.", systemImage: "lock.rectangle.stack")
            }
            NavigationLink {
                UltralightCToolView()
            } label: {
                ToolRow(title: "Ultralight C key", description: "Test, set or remove the 3DES key.", systemImage: "key.horizontal")
            }
        } header: {
            Text("NTAG and Ultralight")
        } footer: {
            Text("These tools talk to NXP NTAG and MIFARE Ultralight chips. Each screen says which models it needs.")
        }
    }

    private var desfireSection: some View {
        Section {
            NavigationLink {
                DESFireToolView()
            } label: {
                ToolRow(title: "DESFire card", description: "List applications, format, or set up NDEF.", systemImage: "creditcard")
            }
        } header: {
            Text("DESFire")
        }
    }

    private var iso15693Section: some View {
        Section {
            NavigationLink {
                Type5ToolView()
            } label: {
                ToolRow(title: "Type 5 settings", description: "AFI, DSFID, block locks, SLIX and ST25TV passwords.", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("ISO 15693")
        }
    }

    private var feliCaSection: some View {
        Section {
            NavigationLink {
                FeliCaToolView()
            } label: {
                ToolRow(title: "FeliCa", description: "Read and write blocks of a service.", systemImage: "square.grid.3x3")
            }
        } header: {
            Text("FeliCa")
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
