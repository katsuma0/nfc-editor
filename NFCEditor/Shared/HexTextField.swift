import Foundation
import SwiftUI

/// Text field that accepts hex only, groups bytes with spaces as the user types, monospaced. `byteCount` nil = any length.
struct HexTextField: View {
    private let title: String
    private let byteCount: Int?
    @Binding private var data: Data
    @State private var text: String

    init(_ title: String, data: Binding<Data>, byteCount: Int? = nil) {
        self.title = title
        self.byteCount = byteCount
        self._data = data
        self._text = State(initialValue: HexTextField.grouped(data.wrappedValue.hexString()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                TextField(placeholder, text: $text)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(captionIsWarning ? Color.red : Color.secondary)
        }
        .onChange(of: text) { _, newValue in
            textDidChange(newValue)
        }
        .onChange(of: data) { _, newValue in
            dataDidChange(newValue)
        }
    }

    // MARK: Derived state

    private var placeholder: String {
        if let required = byteCount, required > 0 {
            return HexTextField.grouped(String(repeating: "0", count: required * 2))
        }
        return "Hex"
    }

    private var hasTrailingNibble: Bool {
        HexTextField.digits(in: text).count % 2 == 1
    }

    private var caption: String {
        if hasTrailingNibble {
            return "Finish the last byte."
        }
        guard let required = byteCount else {
            return ByteFormatter.bytes(data.count)
        }
        if data.isEmpty {
            return "Enter \(ByteFormatter.bytes(required))."
        }
        if data.count == required {
            return ByteFormatter.bytes(required)
        }
        return "\(ByteFormatter.bytes(required)) required, \(data.count) entered."
    }

    private var captionIsWarning: Bool {
        if hasTrailingNibble {
            return true
        }
        guard let required = byteCount else {
            return false
        }
        return !data.isEmpty && data.count != required
    }

    // MARK: Sync

    private func textDidChange(_ newValue: String) {
        var digits = HexTextField.digits(in: newValue)
        if let limit = byteCount, limit > 0 {
            digits = String(digits.prefix(limit * 2))
        }
        let formatted = HexTextField.grouped(digits)
        if formatted != newValue {
            // onChange runs again with the formatted text and reaches the parse below.
            text = formatted
            return
        }
        let parsed = Data(hexString: HexTextField.completeBytes(digits)) ?? Data()
        if parsed != data {
            data = parsed
        }
    }

    private func dataDidChange(_ newValue: Data) {
        let digits = HexTextField.digits(in: text)
        if newValue.hexString() != HexTextField.completeBytes(digits) {
            text = HexTextField.grouped(newValue.hexString())
        }
    }

    // MARK: Helpers

    /// Uppercase hex digits only. Separators and "0x" prefixes are dropped; anything else is ignored.
    private static func digits(in text: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-,"))
        var out = ""
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            var piece = Substring(token)
            if piece.count > 2, piece.hasPrefix("0x") || piece.hasPrefix("0X") {
                piece = piece.dropFirst(2)
            }
            for scalar in piece.uppercased().unicodeScalars {
                switch scalar.value {
                case 0x30...0x39, 0x41...0x46:
                    out.unicodeScalars.append(scalar)
                default:
                    continue
                }
            }
        }
        return out
    }

    /// "04583A" -> "04 58 3A"; a trailing single digit stays at the end.
    private static func grouped(_ digits: String) -> String {
        var out = ""
        out.reserveCapacity(digits.count + digits.count / 2)
        for (offset, character) in digits.enumerated() {
            if offset > 0 && offset % 2 == 0 {
                out.append(" ")
            }
            out.append(character)
        }
        return out
    }

    /// Drops a trailing half byte so only whole bytes reach the binding.
    private static func completeBytes(_ digits: String) -> String {
        String(digits.prefix(digits.count - digits.count % 2))
    }
}
