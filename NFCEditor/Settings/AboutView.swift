import Foundation
import SwiftUI

struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/katsuma0/nfc-editor")

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
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
                Text("NFC Editor reads, writes and edits NFC tags. Scan a tag to see its chip, serial number, memory and records. Write text, links, contacts, Wi-Fi networks and more, several records to one tag. Use Tools to erase, copy, lock, format, set a password, send raw commands and edit memory page by page.")
            }

            Section("Privacy") {
                Text("Everything stays on your iPhone. No accounts, no analytics.")
            }

            Section("Limits") {
                Text("iOS does not let apps read MIFARE Classic data blocks or emulate a tag, so NFC Editor does neither. Core NFC only works while the app is open and in front.")
            }

            Section("Trademarks") {
                Text("MIFARE, NTAG and ICODE are trademarks of NXP B.V. FeliCa is a trademark of Sony Corporation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let url = AboutView.repositoryURL {
                    Link(destination: url) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
