import Foundation

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case text, url, email, contact, phone, sms, geo, address, wifi, bluetooth, social, app
    case customURI, customMIME, external, raw, empty, smartPoster, unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL / URI"
        case .email: return "Email"
        case .contact: return "Contact"
        case .phone: return "Phone number"
        case .sms: return "SMS"
        case .geo: return "Location"
        case .address: return "Address"
        case .wifi: return "Wi-Fi network"
        case .bluetooth: return "Bluetooth"
        case .social: return "Social"
        case .app: return "Application"
        case .customURI: return "Custom URI"
        case .customMIME: return "Custom MIME"
        case .external: return "External type"
        case .raw: return "Raw record"
        case .empty: return "Empty"
        case .smartPoster: return "Smart poster"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .email: return "envelope"
        case .contact: return "person.crop.rectangle"
        case .phone: return "phone"
        case .sms: return "message"
        case .geo: return "location"
        case .address: return "map"
        case .wifi: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .social: return "at"
        case .app: return "app.badge"
        case .customURI: return "link.badge.plus"
        case .customMIME: return "doc"
        case .external: return "shippingbox"
        case .raw: return "number"
        case .empty: return "circle.dashed"
        case .smartPoster: return "doc.richtext"
        case .unknown: return "questionmark.circle"
        }
    }

    static let writable: [RecordKind] = [
        .text, .url, .email, .contact, .phone, .sms, .geo, .address, .wifi, .bluetooth,
        .social, .app, .customURI, .customMIME, .external, .raw, .empty
    ]
}

enum SocialPlatform: String, Codable, CaseIterable, Identifiable {
    case x, instagram, facebook, linkedin, tiktok, youtube, whatsapp, snapchat, threads, github, telegram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .x: return "X"
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .linkedin: return "LinkedIn"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .whatsapp: return "WhatsApp"
        case .snapchat: return "Snapchat"
        case .threads: return "Threads"
        case .github: return "GitHub"
        case .telegram: return "Telegram"
        }
    }

    func url(handle: String) -> String {
        let cleaned = SocialPlatform.cleanHandle(handle)
        switch self {
        case .x: return "https://x.com/\(cleaned)"
        case .instagram: return "https://www.instagram.com/\(cleaned)"
        case .facebook: return "https://www.facebook.com/\(cleaned)"
        case .linkedin: return "https://www.linkedin.com/in/\(cleaned)"
        case .tiktok: return "https://www.tiktok.com/@\(cleaned)"
        case .youtube: return "https://www.youtube.com/@\(cleaned)"
        case .whatsapp: return "https://wa.me/\(SocialPlatform.digits(handle))"
        case .snapchat: return "https://www.snapchat.com/add/\(cleaned)"
        case .threads: return "https://www.threads.net/@\(cleaned)"
        case .github: return "https://github.com/\(cleaned)"
        case .telegram: return "https://t.me/\(cleaned)"
        }
    }

    static func detect(url: String) -> (SocialPlatform, String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let rawHost = components.host?.lowercased() else {
            return nil
        }
        var host = rawHost
        for prefix in ["www.", "mobile.", "m."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }

        let segments = components.path
            .split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
            .filter { !$0.isEmpty }

        func single() -> String? {
            guard segments.count == 1 else { return nil }
            var handle = segments[0]
            while handle.hasPrefix("@") { handle.removeFirst() }
            guard !handle.isEmpty, !reservedPaths.contains(handle.lowercased()) else { return nil }
            return handle
        }

        func withAt() -> String? {
            guard segments.count == 1, segments[0].hasPrefix("@") else { return nil }
            let handle = String(segments[0].dropFirst())
            return handle.isEmpty ? nil : handle
        }

        func second(after first: String) -> String? {
            guard segments.count == 2, segments[0].lowercased() == first, !segments[1].isEmpty else { return nil }
            return segments[1]
        }

        switch host {
        case "x.com", "twitter.com":
            if let handle = single() { return (SocialPlatform.x, handle) }
        case "instagram.com":
            if let handle = single() { return (SocialPlatform.instagram, handle) }
        case "facebook.com", "fb.com":
            if let handle = single() { return (SocialPlatform.facebook, handle) }
        case "linkedin.com":
            if let handle = second(after: "in") { return (SocialPlatform.linkedin, handle) }
        case "tiktok.com":
            if let handle = withAt() { return (SocialPlatform.tiktok, handle) }
        case "youtube.com":
            if let handle = withAt() { return (SocialPlatform.youtube, handle) }
            if let handle = second(after: "c") ?? second(after: "user") { return (SocialPlatform.youtube, handle) }
        case "wa.me":
            if segments.count == 1 {
                let number = digits(segments[0])
                if !number.isEmpty { return (SocialPlatform.whatsapp, number) }
            }
        case "api.whatsapp.com", "whatsapp.com":
            if let phone = components.queryItems?.first(where: { $0.name.lowercased() == "phone" })?.value {
                let number = digits(phone)
                if !number.isEmpty { return (SocialPlatform.whatsapp, number) }
            }
        case "snapchat.com":
            if let handle = second(after: "add") { return (SocialPlatform.snapchat, handle) }
        case "threads.net", "threads.com":
            if let handle = withAt() { return (SocialPlatform.threads, handle) }
        case "github.com":
            if let handle = single() { return (SocialPlatform.github, handle) }
        case "t.me", "telegram.me":
            if let handle = single(), !handle.hasPrefix("+"), handle.lowercased() != "joinchat" {
                return (SocialPlatform.telegram, handle)
            }
        default:
            break
        }
        return nil
    }

    private static let reservedPaths: Set<String> = [
        "home", "explore", "login", "signup", "share", "search", "settings", "about", "help",
        "privacy", "terms", "i", "intent", "hashtag", "p", "reel", "reels", "stories", "accounts",
        "groups", "events", "marketplace", "pages", "watch", "feed", "notifications", "messages",
        "topics", "features", "pricing", "sharer", "profile.php", "direct", "compose"
    ]

    private static func cleanHandle(_ handle: String) -> String {
        var value = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("@") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func digits(_ value: String) -> String {
        value.filter { ("0"..."9").contains($0) }
    }
}
