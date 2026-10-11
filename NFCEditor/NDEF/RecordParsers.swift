import Foundation

enum RecordAction: Hashable {
    case openURL(URL)
    case copy(String)
    case joinWiFi(WiFiCredential)
    case shareVCard(VCard)
}

struct RecordSummary: Hashable {
    var kind: RecordKind
    var title: String
    var detail: String
    var fields: [TagField]
    var actions: [RecordAction]
    var systemImage: String

    init(kind: RecordKind, title: String? = nil, detail: String, fields: [TagField] = [], actions: [RecordAction] = [], systemImage: String? = nil) {
        self.kind = kind
        self.title = title ?? kind.displayName
        self.detail = detail
        self.fields = fields
        self.actions = actions
        self.systemImage = systemImage ?? kind.systemImage
    }
}

enum RecordParsers {
    static func parse(_ record: NDEFRecord) -> RecordSummary {
        var summary = classify(record)
        let emptyRaw = summary.kind == .raw && record.payload.isEmpty
        if summary.kind != .empty, !emptyRaw, !summary.detail.isEmpty, !summary.actions.contains(.copy(summary.detail)) {
            summary.actions.append(.copy(summary.detail))
        }
        return summary
    }

    static func text(_ record: NDEFRecord) -> (text: String, language: String)? {
        guard record.isText else { return nil }
        let bytes = [UInt8](record.payload)
        guard let status = bytes.first else { return nil }
        let languageLength = Int(status & 0x3F)
        guard bytes.count >= 1 + languageLength else { return nil }
        let language = String(decoding: bytes[1..<(1 + languageLength)], as: UTF8.self)
        let body = Array(bytes[(1 + languageLength)...])
        let decoded: String
        if status & 0x80 != 0 {
            decoded = decodeUTF16(body)
        } else {
            decoded = String(decoding: body, as: UTF8.self)
        }
        return (decoded, language)
    }

    static func uri(_ record: NDEFRecord) -> String? {
        switch record.tnf {
        case .wellKnown:
            guard record.typeString == "U", let code = record.payload.first else { return nil }
            let rest = String(decoding: record.payload.dropFirst(), as: UTF8.self)
            return URIPrefixes.expand(code: code, rest: rest)
        case .absoluteURI:
            // For this TNF the URI lives in the type field; some writers put it in the payload instead.
            if !record.type.isEmpty { return record.typeString }
            if !record.payload.isEmpty { return String(decoding: record.payload, as: UTF8.self) }
            return nil
        default:
            return nil
        }
    }

    static func smartPoster(_ record: NDEFRecord) -> (uri: String, title: String?)? {
        guard record.isSmartPoster, let inner = try? NDEFMessageCodec.decode(record.payload) else { return nil }
        guard let uriRecord = inner.first(where: { $0.isURI || $0.tnf == .absoluteURI }),
              let uriValue = uri(uriRecord) else { return nil }
        let titleValue = inner.first(where: { $0.isText }).flatMap { text($0)?.text }
        return (uriValue, titleValue)
    }

    // MARK: Classification

    private static func classify(_ record: NDEFRecord) -> RecordSummary {
        switch record.tnf {
        case .empty:
            return RecordSummary(kind: .empty, detail: "No content")
        case .wellKnown:
            switch record.typeString {
            case "T":
                if let parsed = text(record) {
                    let utf16 = ((record.payload.first ?? 0) & 0x80) != 0
                    return textSummary(parsed.text, language: parsed.language, utf16: utf16)
                }
                return rawSummary(record)
            case "U":
                if let value = uri(record) { return uriSummary(value) }
                return rawSummary(record)
            case "Sp":
                if let poster = smartPoster(record) {
                    return smartPosterSummary(link: poster.uri, posterTitle: poster.title)
                }
                return rawSummary(record)
            default:
                return unknownWellKnownSummary(record)
            }
        case .absoluteURI:
            if let value = uri(record) { return uriSummary(value) }
            return rawSummary(record)
        case .media:
            return mediaSummary(record)
        case .external:
            return externalSummary(record)
        case .unknown, .unchanged:
            return rawSummary(record)
        }
    }

    private static func textSummary(_ body: String, language: String, utf16: Bool) -> RecordSummary {
        var fields: [TagField] = []
        if !language.isEmpty {
            fields.append(TagField(label: "Language", value: language, systemImage: "globe"))
        }
        fields.append(TagField(label: "Encoding", value: utf16 ? "UTF-16" : "UTF-8", systemImage: "textformat"))
        return RecordSummary(kind: .text, detail: body, fields: fields, actions: [.copy(body)])
    }

    private static func uriSummary(_ rawURI: String) -> RecordSummary {
        let value = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scheme(of: value) {
        case "mailto":
            return emailSummary(value)
        case "tel":
            return phoneSummary(value)
        case "sms", "smsto", "mms", "mmsto":
            return smsSummary(value)
        case "geo":
            return geoURISummary(value)
        case "http", "https":
            if let maps = mapsSummary(value) { return maps }
            if let match = SocialPlatform.detect(url: value) {
                return socialSummary(platform: match.0, handle: match.1, link: value)
            }
            return urlSummary(value)
        default:
            return urlSummary(value)
        }
    }

    private static func urlSummary(_ value: String) -> RecordSummary {
        let schemeName = scheme(of: value)
        let title = (schemeName == "http" || schemeName == "https") ? "URL" : "URI"
        var actions: [RecordAction] = []
        if let url = makeURL(value) { actions.append(.openURL(url)) }
        return RecordSummary(kind: .url, title: title, detail: value, actions: actions)
    }

    private static func emailSummary(_ value: String) -> RecordSummary {
        let rest = afterScheme(value)
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address = percentDecode(String(parts.first ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let query = parts.count > 1 ? queryItems(String(parts[1]), plusIsSpace: false) : [:]

        var fields: [TagField] = []
        if let subject = query["subject"], !subject.isEmpty {
            fields.append(TagField(label: "Subject", value: subject, systemImage: "text.quote"))
        }
        if let cc = query["cc"], !cc.isEmpty {
            fields.append(TagField(label: "Cc", value: cc, systemImage: "person.2"))
        }
        if let body = query["body"], !body.isEmpty {
            fields.append(TagField(label: "Message", value: body, systemImage: "text.alignleft"))
        }

        var actions: [RecordAction] = []
        if let url = makeURL(value) { actions.append(.openURL(url)) }
        let detail = address.isEmpty ? (query["subject"] ?? "") : address
        return RecordSummary(kind: .email, detail: detail, fields: fields, actions: actions)
    }

    private static func phoneSummary(_ value: String) -> RecordSummary {
        let number = percentDecode(afterScheme(value)).trimmingCharacters(in: .whitespacesAndNewlines)
        var actions: [RecordAction] = []
        if let url = makeURL("tel:\(number)") ?? makeURL(value) { actions.append(.openURL(url)) }
        return RecordSummary(kind: .phone, detail: number, actions: actions)
    }

    private static func smsSummary(_ value: String) -> RecordSummary {
        let schemeName = scheme(of: value)
        let rest = afterScheme(value)
        var number = rest
        var body: String?
        if let separator = rest.firstIndex(where: { $0 == "?" || $0 == "&" }) {
            number = String(rest[rest.startIndex..<separator])
            let query = queryItems(String(rest[rest.index(after: separator)...]), plusIsSpace: false)
            body = query["body"]
        } else if schemeName.hasSuffix("to"), let colon = rest.firstIndex(of: ":") {
            // Android writes smsto:<number>:<message>.
            number = String(rest[rest.startIndex..<colon])
            body = percentDecode(String(rest[rest.index(after: colon)...]))
        }
        number = percentDecode(number).trimmingCharacters(in: .whitespacesAndNewlines)
        let message = body ?? ""

        var fields: [TagField] = []
        if !message.isEmpty {
            fields.append(TagField(label: "Message", value: message, systemImage: "text.alignleft"))
        }

        var target = "sms:\(number)"
        if !message.isEmpty { target += "&body=\(RecordBuilders.percentEncode(message))" }
        var actions: [RecordAction] = []
        if let url = makeURL(target) { actions.append(.openURL(url)) }

        let detail = number.isEmpty ? message : number
        return RecordSummary(kind: .sms, detail: detail, fields: fields, actions: actions)
    }

    private static func geoURISummary(_ value: String) -> RecordSummary {
        let rest = afterScheme(value)
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let coordinateText = String(parts.first ?? "").split(separator: ";").first.map(String.init) ?? ""
        let query = parts.count > 1 ? queryItems(String(parts[1]), plusIsSpace: true) : [:]
        let label = query["q"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let parsed = parseCoordinate(coordinateText)
        let isZero = parsed?.isZero ?? true
        if !label.isEmpty, isZero {
            return addressSummary(label)
        }
        guard let coordinate = parsed else { return urlSummary(value) }
        return geoSummary(coordinate, label: label.isEmpty ? nil : label)
    }

    private static func geoSummary(_ coordinate: Coordinate, label: String?) -> RecordSummary {
        var fields = [
            TagField(label: "Latitude", value: coordinate.latitudeText, systemImage: "arrow.up.and.down"),
            TagField(label: "Longitude", value: coordinate.longitudeText, systemImage: "arrow.left.and.right")
        ]
        if let label, !label.isEmpty {
            fields.append(TagField(label: "Label", value: label, systemImage: "tag"))
        }
        var actions: [RecordAction] = []
        if let url = makeURL("https://maps.apple.com/?ll=\(coordinate.latitudeText),\(coordinate.longitudeText)") {
            actions.append(.openURL(url))
        }
        let detail = "\(coordinate.latitudeText), \(coordinate.longitudeText)"
        return RecordSummary(kind: .geo, detail: detail, fields: fields, actions: actions)
    }

    private static func addressSummary(_ address: String) -> RecordSummary {
        var actions: [RecordAction] = []
        if let url = makeURL("https://maps.apple.com/?q=\(RecordBuilders.percentEncode(address))") {
            actions.append(.openURL(url))
        }
        return RecordSummary(kind: .address, detail: address, actions: actions)
    }

    private static func mapsSummary(_ value: String) -> RecordSummary? {
        guard let components = URLComponents(string: value), let rawHost = components.host?.lowercased() else {
            return nil
        }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = components.path
        let isApple = host == "maps.apple.com"
        let isGoogle = host == "maps.google.com"
            || host.hasPrefix("maps.google.")
            || host == "maps.app.goo.gl"
            || ((host == "google.com" || host.hasPrefix("google.")) && path.hasPrefix("/maps"))
        guard isApple || isGoogle else { return nil }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let key = item.name.lowercased()
            if query[key] == nil { query[key] = item.value ?? "" }
        }

        func cleaned(_ key: String) -> String? {
            guard let raw = query[key] else { return nil }
            let value = raw.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let coordinateKeys = isApple ? ["ll", "sll"] : ["ll", "center"]
        let textKeys = isApple ? ["q", "address", "daddr"] : ["query", "q", "destination"]

        for key in coordinateKeys {
            if let candidate = cleaned(key), let coordinate = parseCoordinate(candidate) {
                let label = cleaned("q").flatMap { parseCoordinate($0) == nil ? $0 : nil }
                return geoSummary(coordinate, label: label)
            }
        }
        for key in textKeys {
            guard let candidate = cleaned(key) else { continue }
            if let coordinate = parseCoordinate(candidate) { return geoSummary(coordinate, label: nil) }
            return addressSummary(candidate)
        }

        let segments = path.split(separator: "/").map(String.init)
        var placeName: String?
        if let placeIndex = segments.firstIndex(of: "place"), placeIndex + 1 < segments.count {
            let name = segments[placeIndex + 1].replacingOccurrences(of: "+", with: " ")
            placeName = name.isEmpty ? nil : name
        }
        if let marker = segments.first(where: { $0.hasPrefix("@") }),
           let coordinate = parseCoordinate(String(marker.dropFirst())) {
            return geoSummary(coordinate, label: placeName)
        }
        if let placeName {
            return addressSummary(placeName)
        }
        return nil
    }

    private static func socialSummary(platform: SocialPlatform, handle: String, link: String) -> RecordSummary {
        let field: TagField
        if platform == .whatsapp {
            field = TagField(label: "Phone number", value: handle, systemImage: "phone")
        } else {
            field = TagField(label: "Handle", value: "@\(handle)", systemImage: "at")
        }
        var actions: [RecordAction] = []
        if let url = makeURL(link) { actions.append(.openURL(url)) }
        return RecordSummary(kind: .social, title: platform.displayName, detail: link, fields: [field], actions: actions)
    }

    private static func smartPosterSummary(link: String, posterTitle: String?) -> RecordSummary {
        var fields: [TagField] = []
        if let posterTitle, !posterTitle.isEmpty {
            fields.append(TagField(label: "Title", value: posterTitle, systemImage: "textformat"))
        }
        var actions: [RecordAction] = []
        if let url = makeURL(link) { actions.append(.openURL(url)) }
        return RecordSummary(kind: .smartPoster, detail: link, fields: fields, actions: actions)
    }

    private static func mediaSummary(_ record: NDEFRecord) -> RecordSummary {
        let fullType = record.typeString
        let baseType = fullType.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? fullType.lowercased()

        switch baseType {
        case "text/vcard", "text/x-vcard", "text/directory":
            return contactSummary(record)
        case WiFiCredential.mimeType:
            return wifiSummary(record)
        case BluetoothOOB.mimeType, "application/vnd.bluetooth.le.oob":
            return bluetoothSummary(record)
        case "text/plain":
            let body = String(decoding: record.payload, as: UTF8.self)
            let fields = [TagField(label: "Type", value: fullType, systemImage: "doc")]
            return RecordSummary(kind: .text, detail: body, fields: fields, actions: [.copy(body)])
        default:
            return customMIMESummary(record)
        }
    }

    private static func contactSummary(_ record: NDEFRecord) -> RecordSummary {
        let body = String(decoding: record.payload, as: UTF8.self)
        guard let card = VCard.decode(body) else { return customMIMESummary(record) }

        var detail = card.fullName
        if detail.isEmpty { detail = card.organization }
        if detail.isEmpty { detail = card.email }
        if detail.isEmpty { detail = card.phone }
        if detail.isEmpty { detail = "Contact" }

        var fields: [TagField] = []
        func add(_ label: String, _ value: String, _ image: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { fields.append(TagField(label: label, value: trimmed, systemImage: image)) }
        }
        add("Phone", card.phone, "phone")
        add("Email", card.email, "envelope")
        add("Organization", card.organization, "building.2")
        add("Job title", card.title, "briefcase")
        add("Website", card.website, "globe")
        add("Address", card.address, "map")
        add("Note", card.note, "note.text")

        var actions: [RecordAction] = [.shareVCard(card)]
        if !card.phone.isEmpty { actions.append(.copy(card.phone)) }
        return RecordSummary(kind: .contact, detail: detail, fields: fields, actions: actions)
    }

    private static func wifiSummary(_ record: NDEFRecord) -> RecordSummary {
        guard let credential = WiFiCredential.decode(record.payload) else { return customMIMESummary(record) }

        var fields: [TagField] = []
        if !credential.password.isEmpty {
            fields.append(TagField(label: "Password", value: credential.password, systemImage: "key"))
        }
        fields.append(TagField(label: "Security", value: credential.auth.rawValue, systemImage: "lock"))
        if credential.auth != .open {
            fields.append(TagField(label: "Encryption", value: credential.encryption.rawValue, systemImage: "lock.shield"))
        }

        var actions: [RecordAction] = [.joinWiFi(credential)]
        if !credential.password.isEmpty { actions.append(.copy(credential.password)) }
        let detail = credential.ssid.isEmpty ? "Unnamed network" : credential.ssid
        return RecordSummary(kind: .wifi, detail: detail, fields: fields, actions: actions)
    }

    private static func bluetoothSummary(_ record: NDEFRecord) -> RecordSummary {
        guard let oob = BluetoothOOB.decode(record.payload) else { return customMIMESummary(record) }
        var fields = [TagField(label: "Address", value: oob.address, systemImage: "number")]
        if let name = oob.name {
            fields.append(TagField(label: "Name", value: name, systemImage: "textformat"))
        }
        let detail = oob.name ?? oob.address
        return RecordSummary(kind: .bluetooth, detail: detail, fields: fields, actions: [.copy(oob.address)])
    }

    private static func customMIMESummary(_ record: NDEFRecord) -> RecordSummary {
        let payloadString = payloadDescription(record.payload)
        var fields = [TagField(label: "Size", value: byteLabel(record.payload.count), systemImage: "externaldrive")]
        if !payloadString.isEmpty {
            fields.append(TagField(label: "Payload", value: payloadString, systemImage: "doc.text"))
        }
        var actions: [RecordAction] = []
        if !payloadString.isEmpty { actions.append(.copy(payloadString)) }
        let detail = record.typeString.isEmpty ? "Unknown type" : record.typeString
        return RecordSummary(kind: .customMIME, detail: detail, fields: fields, actions: actions)
    }

    private static func externalSummary(_ record: NDEFRecord) -> RecordSummary {
        let typeName = record.typeString
        if typeName.lowercased() == "android.com:pkg" {
            let package = String(decoding: record.payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            var actions: [RecordAction] = []
            if let url = makeURL("https://play.google.com/store/apps/details?id=\(package)") {
                actions.append(.openURL(url))
            }
            let fields = [TagField(label: "Package", value: package, systemImage: "shippingbox")]
            return RecordSummary(kind: .app, title: "Android app", detail: package, fields: fields, actions: actions)
        }

        let payloadString = payloadDescription(record.payload)
        var fields = [TagField(label: "Size", value: byteLabel(record.payload.count), systemImage: "externaldrive")]
        if !payloadString.isEmpty {
            fields.append(TagField(label: "Payload", value: payloadString, systemImage: "doc.text"))
        }
        var actions: [RecordAction] = []
        if !payloadString.isEmpty { actions.append(.copy(payloadString)) }
        let detail = typeName.isEmpty ? "External type" : typeName
        return RecordSummary(kind: .external, detail: detail, fields: fields, actions: actions)
    }

    private static func unknownWellKnownSummary(_ record: NDEFRecord) -> RecordSummary {
        let fields = [
            TagField(label: "Type", value: record.typeString, systemImage: "tag"),
            TagField(label: "Size", value: byteLabel(record.payload.count), systemImage: "externaldrive")
        ]
        return RecordSummary(kind: .unknown, detail: payloadDescription(record.payload), fields: fields)
    }

    private static func rawSummary(_ record: NDEFRecord) -> RecordSummary {
        let hex = record.payload.hexString(separator: " ")
        var fields = [TagField(label: "Type name format", value: record.tnf.label, systemImage: "number")]
        if !record.type.isEmpty {
            fields.append(TagField(label: "Type", value: payloadDescription(record.type), systemImage: "tag"))
        }
        if !record.identifier.isEmpty {
            fields.append(TagField(label: "ID", value: payloadDescription(record.identifier), systemImage: "tag"))
        }
        fields.append(TagField(label: "Size", value: byteLabel(record.payload.count), systemImage: "externaldrive"))
        let detail = hex.isEmpty ? "Empty payload" : hex
        return RecordSummary(kind: .raw, detail: detail, fields: fields)
    }

    // MARK: Helpers

    private struct Coordinate {
        var latitude: Double
        var longitude: Double
        var latitudeText: String
        var longitudeText: String

        var isZero: Bool { latitude == 0 && longitude == 0 }
    }

    private static func parseCoordinate(_ value: String) -> Coordinate? {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              abs(latitude) <= 90,
              abs(longitude) <= 180 else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude, latitudeText: parts[0], longitudeText: parts[1])
    }

    private static func scheme(of value: String) -> String {
        guard let colon = value.firstIndex(of: ":") else { return "" }
        let candidate = value[value.startIndex..<colon]
        guard let first = candidate.first, first.isLetter else { return "" }
        let valid = candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
        return valid ? candidate.lowercased() : ""
    }

    private static func afterScheme(_ value: String) -> String {
        guard let colon = value.firstIndex(of: ":") else { return value }
        var rest = String(value[value.index(after: colon)...])
        if rest.hasPrefix("//") { rest.removeFirst(2) }
        return rest
    }

    private static func queryItems(_ query: String, plusIsSpace: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first, !rawKey.isEmpty else { continue }
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let key = percentDecode(String(rawKey), plusIsSpace: plusIsSpace).lowercased()
            if result[key] == nil {
                result[key] = percentDecode(rawValue, plusIsSpace: plusIsSpace)
            }
        }
        return result
    }

    private static func percentDecode(_ value: String, plusIsSpace: Bool = false) -> String {
        let prepared = plusIsSpace ? value.replacingOccurrences(of: "+", with: " ") : value
        return prepared.removingPercentEncoding ?? prepared
    }

    private static func makeURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encoded),
              url.scheme != nil else { return nil }
        return url
    }

    private static func decodeUTF16(_ bytes: [UInt8]) -> String {
        var body = bytes
        var encoding = String.Encoding.utf16BigEndian
        if body.count >= 2 {
            if body[0] == 0xFE && body[1] == 0xFF {
                body.removeFirst(2)
            } else if body[0] == 0xFF && body[1] == 0xFE {
                body.removeFirst(2)
                encoding = .utf16LittleEndian
            }
        }
        return String(data: Data(body), encoding: encoding) ?? String(decoding: body, as: UTF8.self)
    }

    private static func payloadText(_ data: Data) -> String? {
        guard !data.isEmpty, let decoded = String(data: data, encoding: .utf8) else { return nil }
        let printable = decoded.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            if code == 0x0A || code == 0x0D || code == 0x09 { return true }
            return code >= 0x20 && code != 0x7F
        }
        return printable ? decoded : nil
    }

    private static func payloadDescription(_ data: Data) -> String {
        if data.isEmpty { return "" }
        return payloadText(data) ?? data.hexString(separator: " ")
    }

    private static func byteLabel(_ count: Int) -> String {
        count == 1 ? "1 byte" : "\(count) bytes"
    }
}
