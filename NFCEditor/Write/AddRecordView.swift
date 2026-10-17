import Foundation
import SwiftUI

/// Sheet listing every record type the Write tab can create. Picks one and closes.
struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss

    private let onPick: (RecordKind) -> Void

    init(onPick: @escaping (RecordKind) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                section("Common", kinds: AddRecordView.common)
                section("Connect", kinds: AddRecordView.connect)
                section("Advanced", kinds: AddRecordView.advanced)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add a record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(_ title: String, kinds: [RecordKind]) -> some View {
        if !kinds.isEmpty {
            Section(title) {
                ForEach(kinds) { kind in
                    Button {
                        onPick(kind)
                        dismiss()
                    } label: {
                        row(for: kind)
                    }
                }
            }
        }
    }

    private func row(for kind: RecordKind) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .foregroundStyle(.primary)
                Text(AddRecordView.description(for: kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: kind.systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }

    // MARK: Grouping

    private static let commonKinds: Set<RecordKind> = [.text, .url, .email, .contact, .phone, .sms, .geo, .address]
    private static let connectKinds: Set<RecordKind> = [.wifi, .bluetooth, .social, .app]

    // Groups keep the menu order from RecordKind.writable, so any kind added later still shows up under Advanced.
    private static var common: [RecordKind] {
        RecordKind.writable.filter { commonKinds.contains($0) }
    }

    private static var connect: [RecordKind] {
        RecordKind.writable.filter { connectKinds.contains($0) }
    }

    private static var advanced: [RecordKind] {
        RecordKind.writable.filter { !commonKinds.contains($0) && !connectKinds.contains($0) }
    }

    private static func description(for kind: RecordKind) -> String {
        switch kind {
        case .text: return "Plain text in any language."
        case .url: return "A web address that opens in Safari."
        case .email: return "Starts a new email with a subject and body."
        case .contact: return "A vCard with name, phone, email and more."
        case .phone: return "Starts a call to a number."
        case .sms: return "Starts a text message with an optional body."
        case .geo: return "Coordinates that open in Maps."
        case .address: return "A street address that opens in Maps."
        case .wifi: return "Network name and password for joining a Wi-Fi network."
        case .bluetooth: return "Pairing details for a Bluetooth device."
        case .social: return "A link to a profile on X, Instagram and other platforms."
        case .app: return "Opens or installs an Android app by package name."
        case .customURI: return "Any URI scheme, for example myapp://open."
        case .customMIME: return "A MIME type with a text or hex payload."
        case .external: return "An NFC Forum external type with a payload."
        case .raw: return "Type name format, type, ID and payload as hex."
        case .empty: return "An empty record that clears the tag."
        case .smartPoster: return "A URL with a title."
        case .handover: return "Bluetooth pairing for Android phones."
        case .unknown: return "A record of unknown type."
        }
    }
}
