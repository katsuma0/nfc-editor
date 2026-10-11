import Foundation

/// Keys for RecordDraft.fields. Use these constants; never raw strings.
enum DraftKey {
    static let text = "text", language = "language"
    static let url = "url"
    static let email = "email", subject = "subject", body = "body"
    static let phone = "phone"
    static let latitude = "latitude", longitude = "longitude", geoFormat = "geoFormat"
    static let address = "address", addressFormat = "addressFormat"
    static let ssid = "ssid", password = "password", auth = "auth", encryption = "encryption", hidden = "hidden"
    static let mac = "mac", name = "name"
    static let platform = "platform", handle = "handle"
    static let package = "package"
    static let firstName = "firstName", lastName = "lastName", organization = "organization", title = "title", website = "website", note = "note"
    static let mime = "mime", payloadText = "payloadText", payloadHex = "payloadHex", payloadIsHex = "payloadIsHex"
    static let domain = "domain", externalType = "externalType"
    static let tnf = "tnf", type = "type", identifier = "identifier"
}

/// An editable, persistable description of one record. Built into an NDEFRecord on write.
struct RecordDraft: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: RecordKind
    var fields: [String: String]

    init(kind: RecordKind, fields: [String: String] = [:]) {
        id = UUID()
        self.kind = kind
        var merged = RecordDraft.defaultFields(for: kind)
        for (key, value) in fields {
            merged[key] = value
        }
        self.fields = merged
    }

    subscript(key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue }
    }

    // MARK: Summary

    var summary: String {
        let line: String
        switch kind {
        case .text:
            line = RecordDraft.firstLine(of: self[DraftKey.text])
        case .url, .customURI, .smartPoster:
            line = value(DraftKey.url)
        case .email:
            line = value(DraftKey.email)
        case .contact:
            line = contactName
        case .phone, .sms:
            line = value(DraftKey.phone)
        case .geo:
            let lat = value(DraftKey.latitude)
            let lon = value(DraftKey.longitude)
            line = (lat.isEmpty && lon.isEmpty) ? "" : "\(lat), \(lon)"
        case .address:
            line = RecordDraft.firstLine(of: self[DraftKey.address])
        case .wifi:
            line = value(DraftKey.ssid)
        case .bluetooth:
            let name = value(DraftKey.name)
            line = name.isEmpty ? value(DraftKey.mac).uppercased() : name
        case .social:
            let handle = value(DraftKey.handle)
            if let platform = SocialPlatform(rawValue: self[DraftKey.platform]) {
                line = handle.isEmpty ? platform.displayName : "\(platform.displayName): \(handle)"
            } else {
                line = handle
            }
        case .app:
            line = value(DraftKey.package)
        case .customMIME:
            line = value(DraftKey.mime)
        case .external:
            let domain = value(DraftKey.domain)
            let type = value(DraftKey.externalType)
            line = (domain.isEmpty && type.isEmpty) ? "" : "\(domain):\(type)"
        case .raw, .unknown:
            let label = RecordDraft.tnfValue(self[DraftKey.tnf])?.label ?? "Raw"
            let count = rawPayload.count
            line = "\(label), \(count) \(count == 1 ? "byte" : "bytes")"
        case .empty:
            line = "Empty record"
        }
        return line.isEmpty ? kind.displayName : line
    }

    // MARK: Validation

    func validate() -> String? {
        switch kind {
        case .text:
            if value(DraftKey.text).isEmpty { return "Enter some text." }
            let language = value(DraftKey.language)
            if !language.isEmpty, !RecordDraft.isValidLanguage(language) {
                return "Enter a valid language code, for example en."
            }
            return nil

        case .url, .smartPoster:
            let url = value(DraftKey.url)
            if url.isEmpty { return "Enter a URL." }
            if RecordDraft.containsWhitespace(url) { return "The URL cannot contain spaces." }
            return nil

        case .customURI:
            let uri = value(DraftKey.url)
            if uri.isEmpty { return "Enter a URI." }
            if RecordDraft.containsWhitespace(uri) { return "The URI cannot contain spaces." }
            return nil

        case .email:
            let email = value(DraftKey.email)
            if email.isEmpty { return "Enter an email address." }
            if !RecordDraft.isValidEmail(email) { return "Enter a valid email address." }
            return nil

        case .contact:
            if contactName.isEmpty { return "Enter at least a name, organization, phone or email." }
            return nil

        case .phone, .sms:
            let number = value(DraftKey.phone)
            if number.isEmpty { return "Enter a phone number." }
            if !RecordDraft.isValidPhone(number) { return "Enter a valid phone number." }
            return nil

        case .geo:
            guard let lat = RecordDraft.double(value(DraftKey.latitude)), (-90.0...90.0).contains(lat) else {
                return "Enter a latitude between -90 and 90."
            }
            guard let lon = RecordDraft.double(value(DraftKey.longitude)), (-180.0...180.0).contains(lon) else {
                return "Enter a longitude between -180 and 180."
            }
            if !RecordDraft.geoFormats.contains(value(DraftKey.geoFormat)) { return "Choose a location format." }
            return nil

        case .address:
            if value(DraftKey.address).isEmpty { return "Enter an address." }
            if !RecordDraft.addressFormats.contains(value(DraftKey.addressFormat)) { return "Choose a map format." }
            return nil

        case .wifi:
            let ssid = value(DraftKey.ssid)
            if ssid.isEmpty { return "Enter a network name." }
            if ssid.utf8.count > 32 { return "The network name can be at most 32 bytes." }
            guard let auth = WiFiCredential.Auth(rawValue: self[DraftKey.auth]) else { return "Choose a security type." }
            guard WiFiCredential.Encryption(rawValue: self[DraftKey.encryption]) != nil else { return "Choose an encryption type." }
            if auth != .open {
                let password = self[DraftKey.password]
                if password.isEmpty { return "Enter the network password." }
                let count = password.utf8.count
                let isHexKey = count == 64 && password.isValidHex
                if (count < 8 || count > 63) && !isHexKey { return "The password must be 8 to 63 characters." }
            }
            return nil

        case .bluetooth:
            let mac = value(DraftKey.mac)
            if mac.isEmpty { return "Enter a Bluetooth address." }
            if !BluetoothOOB.isValidAddress(mac) { return "Enter a valid Bluetooth address, for example AA:BB:CC:DD:EE:FF." }
            return nil

        case .social:
            guard let platform = SocialPlatform(rawValue: self[DraftKey.platform]) else { return "Choose a platform." }
            if value(DraftKey.handle).isEmpty {
                return platform == .whatsapp ? "Enter a phone number." : "Enter a username."
            }
            return nil

        case .app:
            let package = value(DraftKey.package)
            if package.isEmpty { return "Enter a package name." }
            if !RecordDraft.isValidPackage(package) { return "Enter a valid package name, for example com.example.app." }
            return nil

        case .customMIME:
            let mime = value(DraftKey.mime)
            if mime.isEmpty { return "Enter a MIME type." }
            if !RecordDraft.isValidMIME(mime) { return "Enter a valid MIME type, for example text/plain." }
            if mime.utf8.count > 255 { return "The MIME type can be at most 255 bytes." }
            return payloadHexMessage

        case .external:
            let domain = value(DraftKey.domain)
            if domain.isEmpty { return "Enter a domain." }
            if !RecordDraft.isValidExternalPart(domain) { return "The domain cannot contain spaces or colons." }
            let type = value(DraftKey.externalType)
            if type.isEmpty { return "Enter a type name." }
            if !RecordDraft.isValidExternalPart(type) { return "The type name cannot contain spaces or colons." }
            if domain.utf8.count + 1 + type.utf8.count > 255 { return "The domain and type name together can be at most 254 bytes." }
            return payloadHexMessage

        case .raw, .unknown:
            guard RecordDraft.tnfValue(self[DraftKey.tnf]) != nil else { return "Choose a type name format." }
            if !RecordDraft.isValidHexOrEmpty(self[DraftKey.type]) { return "Enter the type as hex bytes." }
            if (RecordDraft.hexData(self[DraftKey.type]) ?? Data()).count > 255 { return "The type can be at most 255 bytes." }
            if !RecordDraft.isValidHexOrEmpty(self[DraftKey.identifier]) { return "Enter the ID as hex bytes." }
            if (RecordDraft.hexData(self[DraftKey.identifier]) ?? Data()).count > 255 { return "The ID can be at most 255 bytes." }
            if !RecordDraft.isValidHexOrEmpty(self[DraftKey.payloadHex]) { return "Enter the payload as hex bytes." }
            return nil

        case .empty:
            return nil
        }
    }

    // MARK: Build

    func build() throws -> NDEFRecord {
        if let message = validate() {
            throw NFCEditorError.invalidInput(message)
        }
        switch kind {
        case .text:
            let language = value(DraftKey.language)
            return RecordBuilders.text(self[DraftKey.text], language: language.isEmpty ? "en" : language)

        case .url:
            return RecordBuilders.uri(RecordDraft.withScheme(value(DraftKey.url)))

        case .customURI:
            return RecordBuilders.uri(value(DraftKey.url))

        case .email:
            return RecordBuilders.email(to: value(DraftKey.email), subject: self[DraftKey.subject], body: self[DraftKey.body])

        case .contact:
            var card = VCard()
            card.firstName = value(DraftKey.firstName)
            card.lastName = value(DraftKey.lastName)
            card.organization = value(DraftKey.organization)
            card.title = value(DraftKey.title)
            card.phone = value(DraftKey.phone)
            card.email = value(DraftKey.email)
            card.website = value(DraftKey.website)
            card.address = value(DraftKey.address)
            card.note = value(DraftKey.note)
            return RecordBuilders.vcard(card)

        case .phone:
            return RecordBuilders.phone(value(DraftKey.phone))

        case .sms:
            return RecordBuilders.sms(number: value(DraftKey.phone), body: self[DraftKey.body])

        case .geo:
            let lat = RecordDraft.double(value(DraftKey.latitude)) ?? 0
            let lon = RecordDraft.double(value(DraftKey.longitude)) ?? 0
            return RecordBuilders.geo(latitude: lat, longitude: lon, format: value(DraftKey.geoFormat))

        case .address:
            return RecordBuilders.address(value(DraftKey.address), format: value(DraftKey.addressFormat))

        case .wifi:
            let auth = WiFiCredential.Auth(rawValue: self[DraftKey.auth]) ?? WiFiCredential.Auth.wpa2PSK
            var encryption = WiFiCredential.Encryption(rawValue: self[DraftKey.encryption]) ?? WiFiCredential.Encryption.aes
            var password = self[DraftKey.password]
            if auth == WiFiCredential.Auth.open {
                encryption = WiFiCredential.Encryption.none
                password = ""
            }
            let credential = WiFiCredential(
                ssid: value(DraftKey.ssid),
                password: password,
                auth: auth,
                encryption: encryption,
                hidden: isTrue(DraftKey.hidden)
            )
            return RecordBuilders.wifi(credential)

        case .bluetooth:
            let name = value(DraftKey.name)
            let oob = BluetoothOOB(address: RecordDraft.normalizedMAC(value(DraftKey.mac)), name: name.isEmpty ? nil : name)
            return RecordBuilders.bluetooth(oob)

        case .social:
            let platform = SocialPlatform(rawValue: self[DraftKey.platform]) ?? SocialPlatform.instagram
            return RecordBuilders.social(platform, handle: value(DraftKey.handle))

        case .app:
            return RecordBuilders.androidApp(package: value(DraftKey.package))

        case .customMIME:
            return RecordBuilders.mime(type: value(DraftKey.mime), payload: payloadData)

        case .external:
            return RecordBuilders.external(domain: value(DraftKey.domain), type: value(DraftKey.externalType), payload: payloadData)

        case .raw, .unknown:
            let tnf = RecordDraft.tnfValue(self[DraftKey.tnf]) ?? TypeNameFormat.wellKnown
            return RecordBuilders.raw(
                tnf: tnf,
                type: RecordDraft.hexData(self[DraftKey.type]) ?? Data(),
                identifier: RecordDraft.hexData(self[DraftKey.identifier]) ?? Data(),
                payload: rawPayload
            )

        case .empty:
            return RecordBuilders.raw(tnf: TypeNameFormat.empty, type: Data(), identifier: Data(), payload: Data())

        case .smartPoster:
            let language = value(DraftKey.language)
            let title = value(DraftKey.text)
            return RecordBuilders.smartPoster(
                uri: RecordDraft.withScheme(value(DraftKey.url)),
                title: title.isEmpty ? nil : title,
                language: language.isEmpty ? "en" : language
            )
        }
    }

    var encodedSize: Int {
        (try? build())?.encodedSize ?? 0
    }

    // MARK: Reverse mapping

    static func from(record: NDEFRecord) -> RecordDraft {
        let parsed = RecordParsers.parse(record)
        switch parsed.kind {
        case .empty:
            return RecordDraft(kind: .empty)

        case .text:
            if record.isText, let text = RecordParsers.text(record) {
                return RecordDraft(kind: .text, fields: [
                    DraftKey.text: text.text,
                    DraftKey.language: text.language.isEmpty ? "en" : text.language,
                ])
            }
            // A text/plain media record keeps its MIME type so an edit does not change the record type.
            return mimeDraft(record)

        case .url, .customURI:
            return uriDraft(uriString(of: record))

        case .email:
            let uri = uriString(of: record)
            guard let parts = parseURI(uri), parts.scheme == "mailto" else { return uriDraft(uri) }
            var to = parts.path
            if to.isEmpty, let queryTo = parts.query["to"] { to = queryTo }
            return RecordDraft(kind: .email, fields: [
                DraftKey.email: to,
                DraftKey.subject: parts.query["subject"] ?? "",
                DraftKey.body: parts.query["body"] ?? "",
            ])

        case .phone:
            let uri = uriString(of: record)
            guard let parts = parseURI(uri), parts.scheme == "tel" else { return uriDraft(uri) }
            return RecordDraft(kind: .phone, fields: [DraftKey.phone: parts.path])

        case .sms:
            let uri = uriString(of: record)
            guard let parts = parseURI(uri), RecordDraft.smsSchemes.contains(parts.scheme) else { return uriDraft(uri) }
            var number = parts.path
            var body = parts.query["body"] ?? ""
            if parts.scheme.hasSuffix("to"), body.isEmpty, let colon = number.firstIndex(of: ":") {
                body = String(number[number.index(after: colon)...])
                number = String(number[..<colon])
            }
            return RecordDraft(kind: .sms, fields: [DraftKey.phone: number, DraftKey.body: body])

        case .geo:
            let uri = uriString(of: record)
            guard let parts = parseURI(uri), let geo = geoCoordinates(in: parts) else { return uriDraft(uri) }
            return RecordDraft(kind: .geo, fields: [
                DraftKey.latitude: geo.coordinates.latitudeText,
                DraftKey.longitude: geo.coordinates.longitudeText,
                DraftKey.geoFormat: geo.format,
            ])

        case .address:
            let uri = uriString(of: record)
            guard let parts = parseURI(uri), let address = addressText(in: parts) else { return uriDraft(uri) }
            return RecordDraft(kind: .address, fields: [
                DraftKey.address: address.text,
                DraftKey.addressFormat: address.format,
            ])

        case .wifi:
            guard let credential = WiFiCredential.decode(record.payload) else { return mimeDraft(record) }
            return RecordDraft(kind: .wifi, fields: [
                DraftKey.ssid: credential.ssid,
                DraftKey.password: credential.password,
                DraftKey.auth: credential.auth.rawValue,
                DraftKey.encryption: credential.encryption.rawValue,
                DraftKey.hidden: credential.hidden ? "true" : "false",
            ])

        case .bluetooth:
            guard let oob = BluetoothOOB.decode(record.payload) else { return mimeDraft(record) }
            return RecordDraft(kind: .bluetooth, fields: [
                DraftKey.mac: oob.address,
                DraftKey.name: oob.name ?? "",
            ])

        case .social:
            let uri = uriString(of: record)
            guard let match = SocialPlatform.detect(url: uri) else { return uriDraft(uri) }
            return RecordDraft(kind: .social, fields: [
                DraftKey.platform: match.0.rawValue,
                DraftKey.handle: match.1,
            ])

        case .app:
            let package = String(decoding: record.payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return RecordDraft(kind: .app, fields: [DraftKey.package: package])

        case .contact:
            let text = String(decoding: record.payload, as: UTF8.self)
            guard let card = VCard.decode(text) else { return mimeDraft(record) }
            return RecordDraft(kind: .contact, fields: [
                DraftKey.firstName: card.firstName,
                DraftKey.lastName: card.lastName,
                DraftKey.organization: card.organization,
                DraftKey.title: card.title,
                DraftKey.phone: card.phone,
                DraftKey.email: card.email,
                DraftKey.website: card.website,
                DraftKey.address: card.address,
                DraftKey.note: card.note,
            ])

        case .customMIME:
            return mimeDraft(record)

        case .external:
            let typeString = record.typeString
            var domain = typeString
            var type = ""
            if let colon = typeString.firstIndex(of: ":") {
                domain = String(typeString[..<colon])
                type = String(typeString[typeString.index(after: colon)...])
            }
            var fields = payloadFields(for: record.payload)
            fields[DraftKey.domain] = domain
            fields[DraftKey.externalType] = type
            return RecordDraft(kind: .external, fields: fields)

        case .smartPoster:
            guard let poster = RecordParsers.smartPoster(record) else { return rawDraft(record) }
            var language = "en"
            if let inner = try? NDEFMessageCodec.decode(record.payload),
               let textRecord = inner.first(where: { $0.isText }),
               let text = RecordParsers.text(textRecord),
               !text.language.isEmpty {
                language = text.language
            }
            return RecordDraft(kind: .smartPoster, fields: [
                DraftKey.url: poster.uri,
                DraftKey.text: poster.title ?? "",
                DraftKey.language: language,
            ])

        case .raw, .unknown:
            return rawDraft(record)
        }
    }
}

// MARK: - Private helpers

private struct ParsedURI {
    var scheme: String
    var host: String
    var path: String
    var query: [String: String]
}

private struct Coordinates {
    var latitude: Double
    var longitude: Double
    var latitudeText: String
    var longitudeText: String
}

private extension RecordDraft {
    static let geoFormats: Set<String> = ["geo", "apple", "google"]
    static let addressFormats: Set<String> = ["apple", "google", "geo"]
    static let smsSchemes: Set<String> = ["sms", "smsto", "mms", "mmsto"]
    /// Schemes where "#" is part of the number rather than a fragment delimiter.
    static let numberSchemes: Set<String> = ["tel", "sms", "smsto", "mms", "mmsto"]

    static func defaultFields(for kind: RecordKind) -> [String: String] {
        switch kind {
        case .text:
            return [DraftKey.language: "en"]
        case .geo:
            return [DraftKey.geoFormat: "geo"]
        case .address:
            return [DraftKey.addressFormat: "apple"]
        case .wifi:
            return [
                DraftKey.auth: WiFiCredential.Auth.wpa2PSK.rawValue,
                DraftKey.encryption: WiFiCredential.Encryption.aes.rawValue,
                DraftKey.hidden: "false",
            ]
        case .social:
            return [DraftKey.platform: SocialPlatform.instagram.rawValue]
        case .customMIME, .external:
            return [DraftKey.payloadIsHex: "false"]
        case .raw, .unknown:
            return [DraftKey.tnf: "1", DraftKey.payloadIsHex: "true"]
        case .smartPoster:
            return [DraftKey.language: "en"]
        case .url, .email, .contact, .phone, .sms, .bluetooth, .app, .customURI, .empty:
            return [:]
        }
    }

    func value(_ key: String) -> String {
        (fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isTrue(_ key: String) -> Bool {
        value(key).lowercased() == "true"
    }

    var contactName: String {
        let name = (value(DraftKey.firstName) + " " + value(DraftKey.lastName)).trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let organization = value(DraftKey.organization)
        if !organization.isEmpty { return organization }
        let email = value(DraftKey.email)
        if !email.isEmpty { return email }
        return value(DraftKey.phone)
    }

    /// Payload for MIME and external records, honoring the text or hex switch.
    var payloadData: Data {
        if isTrue(DraftKey.payloadIsHex) {
            return RecordDraft.hexData(self[DraftKey.payloadHex]) ?? Data()
        }
        return Data(self[DraftKey.payloadText].utf8)
    }

    /// Payload for raw records: hex when given, otherwise the text field as UTF-8.
    var rawPayload: Data {
        let hex = self[DraftKey.payloadHex]
        if !hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RecordDraft.hexData(hex) ?? Data()
        }
        return Data(self[DraftKey.payloadText].utf8)
    }

    var payloadHexMessage: String? {
        if isTrue(DraftKey.payloadIsHex), !RecordDraft.isValidHexOrEmpty(self[DraftKey.payloadHex]) {
            return "Enter the payload as hex bytes."
        }
        return nil
    }

    // MARK: Parsing and validation helpers

    static func firstLine(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = trimmed.firstIndex(where: { $0.isNewline }) {
            return String(trimmed[..<newline]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    static func containsWhitespace(_ s: String) -> Bool {
        s.contains(where: { $0.isWhitespace })
    }

    static func double(_ s: String) -> Double? {
        let normalized = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func tnfValue(_ s: String) -> TypeNameFormat? {
        guard let raw = UInt8(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return TypeNameFormat(rawValue: raw)
    }

    static func hexData(_ s: String) -> Data? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Data() }
        return Data(hexString: trimmed)
    }

    static func isValidHexOrEmpty(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.isValidHex
    }

    static func isValidLanguage(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 63 else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func isValidEmail(_ s: String) -> Bool {
        guard !containsWhitespace(s) else { return false }
        for address in s.split(separator: ",") {
            let parts = address.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        }
        return true
    }

    static func isValidPhone(_ s: String) -> Bool {
        let allowed: Set<Character> = ["+", "-", "(", ")", ".", "*", "#"]
        var hasDigit = false
        for character in s {
            if character.isWhitespace { continue }
            if character.isNumber && character.isASCII {
                hasDigit = true
                continue
            }
            if !allowed.contains(character) { return false }
        }
        return hasDigit
    }

    static func isValidPackage(_ s: String) -> Bool {
        let segments = s.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        for segment in segments {
            guard let first = segment.first, first.isLetter, first.isASCII else { return false }
            guard segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return false }
        }
        return true
    }

    static func isValidMIME(_ s: String) -> Bool {
        guard !containsWhitespace(s) else { return false }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    static func isValidExternalPart(_ s: String) -> Bool {
        !s.isEmpty && !containsWhitespace(s) && !s.contains(":")
    }

    /// Returns the lowercased scheme when the string starts with one, otherwise nil.
    static func scheme(of s: String) -> String? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let candidate = s[..<colon]
        guard let first = candidate.first, first.isASCII, first.isLetter else { return nil }
        let valid = candidate.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
        guard valid else { return nil }
        // "apple.com:8080" is a host with a port, not a scheme.
        let rest = s[s.index(after: colon)...]
        if candidate.contains("."), let next = rest.first, next.isNumber { return nil }
        return candidate.lowercased()
    }

    /// Adds https:// when the user typed a bare host such as apple.com.
    static func withScheme(_ url: String) -> String {
        scheme(of: url) == nil ? "https://" + url : url
    }

    static func normalizedMAC(_ s: String) -> String {
        let hex = s.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return s.uppercased() }
        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }
        return pairs.joined(separator: ":")
    }

    static func percentDecode(_ s: String, plusIsSpace: Bool) -> String {
        let source = plusIsSpace ? s.replacingOccurrences(of: "+", with: " ") : s
        return source.removingPercentEncoding ?? source
    }

    static func parseURI(_ uri: String) -> ParsedURI? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = RecordDraft.scheme(of: trimmed), let colon = trimmed.firstIndex(of: ":") else { return nil }
        var rest = String(trimmed[trimmed.index(after: colon)...])
        if !numberSchemes.contains(scheme), let hash = rest.firstIndex(of: "#") {
            rest = String(rest[..<hash])
        }
        var queryString = ""
        if let question = rest.firstIndex(of: "?") {
            queryString = String(rest[rest.index(after: question)...])
            rest = String(rest[..<question])
        } else if smsSchemes.contains(scheme) || scheme == "mailto", let ampersand = rest.firstIndex(of: "&") {
            // Older sms: links put the body after an ampersand instead of a question mark.
            queryString = String(rest[rest.index(after: ampersand)...])
            rest = String(rest[..<ampersand])
        }
        var host = ""
        if rest.hasPrefix("//") {
            let afterSlashes = rest.dropFirst(2)
            if let slash = afterSlashes.firstIndex(of: "/") {
                host = String(afterSlashes[..<slash]).lowercased()
            } else {
                host = String(afterSlashes).lowercased()
            }
        }
        // Web and geo queries write spaces as plus signs; mailto and sms do not.
        let plusIsSpace = scheme == "http" || scheme == "https" || scheme == "geo"
        var query: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = percentDecode(String(parts[0]), plusIsSpace: plusIsSpace).lowercased()
            let value = parts.count > 1 ? percentDecode(String(parts[1]), plusIsSpace: plusIsSpace) : ""
            if query[key] == nil { query[key] = value }
        }
        return ParsedURI(scheme: scheme, host: host, path: percentDecode(rest, plusIsSpace: false), query: query)
    }

    static func coordinates(in s: String) -> Coordinates? {
        let parts = s.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let latText = parts[0].trimmingCharacters(in: .whitespaces)
        let lonText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let lat = Double(latText), let lon = Double(lonText),
              (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }
        return Coordinates(latitude: lat, longitude: lon, latitudeText: latText, longitudeText: lonText)
    }

    static func geoCoordinates(in parts: ParsedURI) -> (coordinates: Coordinates, format: String)? {
        if parts.scheme == "geo" {
            // Parameters such as ;u=35 follow the coordinates.
            let coordinateText = parts.path.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? parts.path
            guard let found = coordinates(in: coordinateText) else { return nil }
            // geo:0,0?q=... is an address search, not a location.
            if found.latitude == 0, found.longitude == 0, parts.query["q"] != nil { return nil }
            return (found, "geo")
        }
        let format = parts.host.contains("google") ? "google" : "apple"
        for key in ["ll", "query", "q", "sll", "center", "daddr", "destination"] {
            if let value = parts.query[key], let found = coordinates(in: value) {
                return (found, format)
            }
        }
        if let at = parts.path.firstIndex(of: "@") {
            let after = String(parts.path[parts.path.index(after: at)...])
            if let found = coordinates(in: after) { return (found, format) }
        }
        return nil
    }

    static func addressText(in parts: ParsedURI) -> (text: String, format: String)? {
        if parts.scheme == "geo" {
            if let q = parts.query["q"], !q.isEmpty { return (q, "geo") }
            return nil
        }
        let format = parts.host.contains("google") ? "google" : "apple"
        for key in ["q", "query", "address", "daddr", "destination"] {
            if let value = parts.query[key], !value.isEmpty { return (value, format) }
        }
        // Google Maps also names a place in the path: /maps/place/Name+Here/...
        let segments = parts.path.split(separator: "/").map(String.init)
        if format == "google", let placeIndex = segments.firstIndex(of: "place"), placeIndex + 1 < segments.count {
            let name = segments[placeIndex + 1].replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return (name, format) }
        }
        return nil
    }

    static func isDisplayableText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        guard let text = String(data: data, encoding: .utf8) else { return false }
        for scalar in text.unicodeScalars {
            if scalar.value == 0x7F { return false }
            if scalar.value < 0x20, scalar != "\n", scalar != "\r", scalar != "\t" { return false }
        }
        return true
    }

    static func payloadFields(for payload: Data) -> [String: String] {
        if isDisplayableText(payload) {
            return [
                DraftKey.payloadIsHex: "false",
                DraftKey.payloadText: String(decoding: payload, as: UTF8.self),
                DraftKey.payloadHex: "",
            ]
        }
        return [
            DraftKey.payloadIsHex: "true",
            DraftKey.payloadText: "",
            DraftKey.payloadHex: payload.hexString(separator: " "),
        ]
    }

    static func uriString(of record: NDEFRecord) -> String {
        if let uri = RecordParsers.uri(record) { return uri }
        if record.tnf == .absoluteURI { return record.typeString }
        if record.isURI, let code = record.payload.first {
            let rest = String(decoding: record.payload.dropFirst(), as: UTF8.self)
            return URIPrefixes.expand(code: code, rest: rest)
        }
        return String(decoding: record.payload, as: UTF8.self)
    }

    static func uriDraft(_ uri: String) -> RecordDraft {
        let scheme = RecordDraft.scheme(of: uri)
        let isWeb = scheme == nil || scheme == "http" || scheme == "https"
        return RecordDraft(kind: isWeb ? .url : .customURI, fields: [DraftKey.url: uri])
    }

    static func mimeDraft(_ record: NDEFRecord) -> RecordDraft {
        var fields = payloadFields(for: record.payload)
        fields[DraftKey.mime] = record.typeString
        return RecordDraft(kind: .customMIME, fields: fields)
    }

    static func rawDraft(_ record: NDEFRecord) -> RecordDraft {
        RecordDraft(kind: .raw, fields: [
            DraftKey.tnf: String(record.tnf.rawValue),
            DraftKey.type: record.type.hexString(separator: " "),
            DraftKey.identifier: record.identifier.hexString(separator: " "),
            DraftKey.payloadHex: record.payload.hexString(separator: " "),
            DraftKey.payloadIsHex: "true",
        ])
    }
}
