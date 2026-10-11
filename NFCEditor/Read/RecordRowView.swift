import Foundation
import SwiftUI

/// One NDEF record as a list row: icon, kind title and the parsed detail.
struct RecordRowView: View {
    private let summary: RecordSummary

    init(record: NDEFRecord) {
        summary = RecordParsers.parse(record)
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.caption.smallCaps().weight(.medium))
                    .foregroundStyle(.secondary)
                Text(summary.detail.isEmpty ? "No content" : summary.detail)
                    .font(.body)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: summary.systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }
}
