import Foundation

/// Builds NDEF records from already validated input. RecordDraft does the validation.
enum RecordBuilders {
    static func text(_ text: String, language: String) -> NDEFRecord {
        var code = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { code = "en" }
        // The status byte keeps only six bits for the language length.
        let codeBytes = Data(Data(code.utf8).prefix(63))
        var payload = Data()
        payload.append(UInt8(codeBytes.count) & 0x3F)
        payload.append(codeBytes)
        payload.append(Data(text.utf8))
        return NDEFRecord(tnf: .wellKnown, typeString: "T", payload: payload)
    }

    static func uri(_ uri: String) -> NDEFRecord {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviated = URIPrefixes.abbreviate(trimmed)
        var payload = Data([abbreviated.code])
        payload.append(Data(abbreviated.rest.utf8))
        return NDEFRecord(tnf: .wellKnown, typeString: "U", payload: payload)
    }

    static func absoluteURI(_ uri: String) -> NDEFRecord {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        return NDEFRecord(tnf: .absoluteURI, typeString: trimmed, payload: Data())
    }

    static func email(to: String, subject: String, body: String) -> NDEFRecord {
        var result = "mailto:" + to.trimmingCharacters(in: .whitespacesAndNewlines)
        var query: [String] = []
        if !subject.isEmpty { query.append("subject=" + percentEncode(subject)) }
        if !body.isEmpty { query.append("body=" + percentEncode(body)) }
        if !query.isEmpty { result += "?" + query.joined(separator: "&") }
        return uri(result)
    }

    static func phone(_ number: String) -> NDEFRecord {
        uri("tel:" + compactNumber(number))
    }

    static func sms(number: String, body: String) -> NDEFRecord {
        var result = "sms:" + compactNumber(number)
        if !body.isEmpty { result += "?body=" + percentEncode(body) }
        return uri(result)
    }

    static func geo(latitude: Double, longitude: Double, format: String) -> NDEFRecord {
        let lat = coordinate(latitude)
        let lon = coordinate(longitude)
        switch format {
        case "apple":
            return uri("https://maps.apple.com/?ll=\(lat),\(lon)")
        case "google":
            return uri("https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)")
        default:
            return uri("geo:\(lat),\(lon)")
        }
    }

    static func address(_ address: String, format: String) -> NDEFRecord {
        let encoded = percentEncode(address.trimmingCharacters(in: .whitespacesAndNewlines))
        switch format {
        case "google":
            return uri("https://www.google.com/maps/search/?api=1&query=\(encoded)")
        case "geo":
            return uri("geo:0,0?q=\(encoded)")
        default:
            return uri("https://maps.apple.com/?q=\(encoded)")
        }
    }

    static func wifi(_ credential: WiFiCredential) -> NDEFRecord {
        mime(type: WiFiCredential.mimeType, payload: credential.encode())
    }

    static func bluetooth(_ oob: BluetoothOOB) -> NDEFRecord {
        mime(type: BluetoothOOB.mimeType, payload: oob.encode())
    }

    static func vcard(_ card: VCard) -> NDEFRecord {
        mime(type: VCard.mimeType, payload: Data(card.encode().utf8))
    }

    static func social(_ platform: SocialPlatform, handle: String) -> NDEFRecord {
        uri(platform.url(handle: handle.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    static func androidApp(package: String) -> NDEFRecord {
        let trimmed = package.trimmingCharacters(in: .whitespacesAndNewlines)
        return external(domain: "android.com", type: "pkg", payload: Data(trimmed.utf8))
    }

    static func mime(type: String, payload: Data) -> NDEFRecord {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return NDEFRecord(tnf: .media, typeString: trimmed, payload: payload)
    }

    static func external(domain: String, type: String, payload: Data) -> NDEFRecord {
        let domainPart = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let typePart = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return NDEFRecord(tnf: .external, typeString: domainPart + ":" + typePart, payload: payload)
    }

    static func raw(tnf: TypeNameFormat, type: Data, identifier: Data, payload: Data) -> NDEFRecord {
        NDEFRecord(tnf: tnf, type: type, identifier: identifier, payload: payload)
    }

    static func smartPoster(uri: String, title: String?, language: String) -> NDEFRecord {
        var inner: [NDEFRecord] = [RecordBuilders.uri(uri)]
        if let title = title, !title.isEmpty {
            inner.append(text(title, language: language))
        }
        let payload = NDEFMessageCodec.encode(inner)
        return NDEFRecord(tnf: .wellKnown, typeString: "Sp", payload: payload)
    }

    /// RFC 3986: only unreserved ASCII characters pass through untouched.
    static func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? s
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func compactNumber(_ number: String) -> String {
        number.filter { !$0.isWhitespace }
    }

    private static func coordinate(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        var result = String(format: "%.6f", value)
        if result.contains(".") {
            while result.hasSuffix("0") { result.removeLast() }
            if result.hasSuffix(".") { result.removeLast() }
        }
        if result == "-0" { result = "0" }
        return result
    }
}
