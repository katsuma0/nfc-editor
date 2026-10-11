import Foundation
import SwiftUI
import CoreNFC

/// Top of the Read tab: scan a tag, then browse the last and recent scans.
struct ReadView: View {
    @Environment(AppState.self) private var app
    @State private var path = NavigationPath()
    @State private var alert: AlertItem?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                scanSection
                lastScanSection
                recentSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Read")
            .navigationDestination(for: TagInfo.self) { info in
                TagDetailView(info: info)
            }
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
            .alertItem($alert)
        }
    }

    // MARK: Sections

    private var scanSection: some View {
        Section {
            if NFCSessionManager.isAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                    Text("Scan a tag to see its chip, serial number, memory and records.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    ScanButton("Scan tag") {
                        scan()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ContentUnavailableView(
                    "NFC is not available",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("This device cannot read NFC tags. NFC Editor needs an iPhone with NFC.")
                )
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var lastScanSection: some View {
        if let last = app.lastScan {
            Section("Last scan") {
                NavigationLink(value: last) {
                    TagSummaryRow(info: last)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recentScans.isEmpty {
            Section("Recent") {
                ForEach(recentScans) { info in
                    NavigationLink(value: info) {
                        TagSummaryRow(info: info)
                    }
                }
            }
        }
    }

    /// Everything but the newest entry, which the "Last scan" section already shows.
    private var recentScans: [TagInfo] {
        Array(app.scanHistory.dropFirst())
    }

    // MARK: Scanning

    @MainActor
    private func scan() {
        let readFull = app.settings.readFullMemoryOnScan
        Task { @MainActor in
            do {
                let info = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Tag read."
                ) { session, tag in
                    try await TagOperations.readTag(session, tag, includeDump: readFull)
                }
                app.recordScan(info)
                Haptics.success()
                path.append(info)
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

/// Compact row for a scanned tag: chip, serial, record count and time.
private struct TagSummaryRow: View {
    let info: TagInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.chipLine)
                Text(info.serialLine)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        "\(recordsLabel), \(info.scannedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var recordsLabel: String {
        switch info.records.count {
        case 0: return "No records"
        case 1: return "1 record"
        default: return "\(info.records.count) records"
        }
    }
}
