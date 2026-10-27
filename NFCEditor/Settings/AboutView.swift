import Foundation
import SwiftUI

struct AboutView: View {
    private static let privacyURL = URL(string: "https://katsuma.ca/nfc-editor/privacy.html")
    private static let supportURL = URL(string: "https://katsuma.ca/nfc-editor/support.html")
    private static let shortcutsURL = URL(string: "shortcuts://")

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("NFC Editor")
                        .font(.title2.weight(.semibold))
                    Text("Version \(versionLine)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("What it does") {
                Text("NFC Editor reads, writes and edits NFC tags. Scan a tag to see its chip, serial number, memory and records. Write text, links, contacts, Wi-Fi networks and more, several records to one tag or the same records to many tags. Use Tools to erase, copy, lock, format, set a password, send raw commands and edit memory page by page.")
            }

            Section {
                Text("iOS runs automations on a tag scan from the Shortcuts app, not from other apps. To set one up:")
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open Shortcuts and tap Automation.")
                    Text("2. Tap New Automation, or the plus button, and choose NFC.")
                    Text("3. Tap Scan and hold your iPhone near the tag, then name it.")
                    Text("4. Choose Run Immediately if you do not want to be asked each time.")
                    Text("5. Pick the action to run, for example Open URL, Set Focus or an NFC Editor action.")
                }
                .font(.subheadline)
                if let url = AboutView.shortcutsURL {
                    Link(destination: url) {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                    }
                }
            } header: {
                Text("Automations")
            } footer: {
                Text("iOS reads the tag for the automation itself, so the tag does not need any records and NFC Editor does not need to be open.")
            }

            Section {
                intentRow(
                    "Read NFC tag",
                    detail: "Opens the app, scans a tag and returns its records as text, one line per record.",
                    systemImage: "wave.3.right"
                )
                intentRow(
                    "Write profile to tag",
                    detail: "Opens the app and writes a saved profile to the next tag you hold, then checks it.",
                    systemImage: "square.and.pencil"
                )
            } header: {
                Text("Shortcuts actions")
            } footer: {
                Text("Find both in the Shortcuts app under NFC Editor, or ask Siri to \"Read an NFC tag with NFC Editor\". iOS only lets an app use NFC while it is in front, so both actions open the app and show the scanning sheet.")
            }

            Section("Privacy") {
                Text("Everything stays on your iPhone. No accounts, no analytics.")
            }

            Section("Limits") {
                Text("iOS does not let apps read MIFARE Classic data blocks or emulate a tag, so NFC Editor does neither. Core NFC only works while the app is open and in front, and an app cannot start an action on its own when a tag is scanned; use a Shortcuts automation for that.")
            }

            Section("Trademarks") {
                Text("MIFARE, NTAG and ICODE are trademarks of NXP B.V. FeliCa is a trademark of Sony Corporation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let url = AboutView.supportURL {
                    Link(destination: url) {
                        Label("Help and support", systemImage: "questionmark.circle")
                    }
                }
                if let url = AboutView.privacyURL {
                    Link(destination: url) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // The descriptions are full sentences, so they go under the title rather than squeezed into a trailing value column.
    private func intentRow(_ title: String, detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "1.0"
        if let build = info["CFBundleVersion"] as? String, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }
}
