import Foundation

struct VCard: Codable, Hashable {
    var firstName: String = ""
    var lastName: String = ""
    var organization: String = ""
    var title: String = ""
    var phone: String = ""
    var email: String = ""
    var website: String = ""
    var address: String = ""
    var note: String = ""

    static let mimeType = "text/vcard"

    var fullName: String {
        [firstName, lastName]
            .map { VCard.trim($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func encode() -> String {
        let first = VCard.trim(firstName)
        let last = VCard.trim(lastName)
        let organizationValue = VCard.trim(organization)
        let titleValue = VCard.trim(title)
        let phoneValue = VCard.trim(phone)
        let emailValue = VCard.trim(email)
        let websiteValue = VCard.trim(website)
        let addressValue = VCard.trim(address)
        let noteValue = VCard.trim(note)

        // FN is mandatory in vCard 3.0, so fall back to whatever identifies the card.
        var formattedName = fullName
        if formattedName.isEmpty { formattedName = organizationValue }
        if formattedName.isEmpty { formattedName = emailValue }
        if formattedName.isEmpty { formattedName = phoneValue }

        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(VCard.escape(last));\(VCard.escape(first));;;")
        lines.append("FN:\(VCard.escape(formattedName))")
        if !organizationValue.isEmpty { lines.append("ORG:\(VCard.escape(organizationValue))") }
        if !titleValue.isEmpty { lines.append("TITLE:\(VCard.escape(titleValue))") }
        if !phoneValue.isEmpty { lines.append("TEL;TYPE=CELL:\(VCard.singleLine(phoneValue))") }
        if !emailValue.isEmpty { lines.append("EMAIL:\(VCard.escape(emailValue))") }
        if !websiteValue.isEmpty { lines.append("URL:\(VCard.singleLine(websiteValue))") }
        if !addressValue.isEmpty { lines.append("ADR;TYPE=HOME:;;\(VCard.escape(addressValue));;;;") }
        if !noteValue.isEmpty { lines.append("NOTE:\(VCard.escape(noteValue))") }
        lines.append("END:VCARD")
        return lines.map { VCard.fold($0) }.joined(separator: "\r\n") + "\r\n"
    }

    static func decode(_ text: String) -> VCard? {
        let lines = unfoldedLines(text)
        var card = VCard()
        var foundBegin = false
        var foundField = false
        var hasStructuredName = false
        var formattedName: String?

        for line in lines {
            guard let colon = propertyColon(in: line) else { continue }
            let head = String(line[line.startIndex..<colon])
            var value = String(line[line.index(after: colon)...])

            let headParts = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard let rawName = headParts.first else { continue }
            var name = rawName.uppercased().trimmingCharacters(in: .whitespaces)
            if let dot = name.firstIndex(of: ".") {
                name = String(name[name.index(after: dot)...])
            }
            let params = headParts.dropFirst().map { $0.uppercased() }
            if params.contains(where: { $0.contains("QUOTED-PRINTABLE") }) {
                value = decodeQuotedPrintable(value)
            }
            if params.contains(where: { $0.contains("BASE64") || $0 == "ENCODING=B" }) {
                continue
            }

            switch name {
            case "BEGIN":
                if trim(value).uppercased() == "VCARD" { foundBegin = true }
            case "N":
                let parts = splitUnescaped(value, separator: ";").map { trim(unescape($0)) }
                card.lastName = parts.count > 0 ? parts[0] : ""
                var given = parts.count > 1 ? parts[1] : ""
                if parts.count > 2, !parts[2].isEmpty {
                    given = given.isEmpty ? parts[2] : "\(given) \(parts[2])"
                }
                card.firstName = given
                hasStructuredName = true
                foundField = true
            case "FN":
                formattedName = trim(unescape(value))
                foundField = true
            case "ORG":
                if card.organization.isEmpty {
                    let parts = splitUnescaped(value, separator: ";").map { trim(unescape($0)) }
                    card.organization = parts.first(where: { !$0.isEmpty }) ?? ""
                    foundField = true
                }
            case "TITLE":
                if card.title.isEmpty {
                    card.title = trim(unescape(value))
                    foundField = true
                }
            case "TEL":
                if card.phone.isEmpty {
                    var number = trim(unescape(value))
                    if number.lowercased().hasPrefix("tel:") { number = String(number.dropFirst(4)) }
                    card.phone = number
                    foundField = true
                }
            case "EMAIL":
                if card.email.isEmpty {
                    var mail = trim(unescape(value))
                    if mail.lowercased().hasPrefix("mailto:") { mail = String(mail.dropFirst(7)) }
                    card.email = mail
                    foundField = true
                }
            case "URL":
                if card.website.isEmpty {
                    card.website = trim(unescape(value))
                    foundField = true
                }
            case "ADR":
                if card.address.isEmpty {
                    let parts = splitUnescaped(value, separator: ";").map { trim(unescape($0)) }
                    card.address = parts.filter { !$0.isEmpty }.joined(separator: ", ")
                    foundField = true
                }
            case "NOTE":
                if card.note.isEmpty {
                    card.note = trim(unescape(value))
                    foundField = true
                }
            default:
                break
            }
        }

        if !hasStructuredName, let full = formattedName, !full.isEmpty {
            let words = full.split(separator: " ").map(String.init)
            if words.count > 1 {
                card.lastName = words[words.count - 1]
                card.firstName = words.dropLast().joined(separator: " ")
            } else {
                card.firstName = full
            }
        }

        guard foundBegin || foundField else { return nil }
        return card
    }

    // MARK: Line handling

    /// RFC 2426 keeps physical lines at 75 octets; a continuation line starts with one space.
    private static func fold(_ line: String) -> String {
        var out = ""
        var width = 0
        for character in line {
            let size = String(character).utf8.count
            if width > 0, width + size > 75 {
                out += "\r\n "
                width = 1
            }
            out.append(character)
            width += size
        }
        return out
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        for rawLine in normalized.components(separatedBy: "\n") {
            if let first = rawLine.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(rawLine.dropFirst())
            } else {
                lines.append(rawLine)
            }
        }

        // vCard 2.1 quoted-printable values continue on the next line after a trailing "=".
        var merged: [String] = []
        var continuing = false
        for line in lines {
            if continuing, !merged.isEmpty {
                merged[merged.count - 1].removeLast()
                merged[merged.count - 1] += line
            } else {
                merged.append(line)
            }
            let current = merged[merged.count - 1]
            continuing = current.hasSuffix("=") && isQuotedPrintable(current)
        }
        return merged
    }

    private static func isQuotedPrintable(_ line: String) -> Bool {
        guard let colon = propertyColon(in: line) else { return false }
        return line[line.startIndex..<colon].uppercased().contains("QUOTED-PRINTABLE")
    }

    private static func propertyColon(in line: String) -> String.Index? {
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ":" && !inQuotes {
                return index
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func splitUnescaped(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                current.append(character)
                escaped = true
            } else if character == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func unescape(_ value: String) -> String {
        var out = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n", "N": out.append("\n")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

    private static func escape(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case ",": out += "\\,"
            case ";": out += "\\;"
            case "\n", "\r\n": out += "\\n"
            case "\r": continue
            default: out.append(character)
            }
        }
        return out
    }

    private static func singleLine(_ value: String) -> String {
        value.filter { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
    }

    private static func decodeQuotedPrintable(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x3D, index + 2 < bytes.count,
               let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                out.append(byte)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
