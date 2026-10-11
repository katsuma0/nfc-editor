import Foundation

enum TypeNameFormat: UInt8, Codable, CaseIterable {
    case empty = 0
    case wellKnown = 1
    case media = 2
    case absoluteURI = 3
    case external = 4
    case unknown = 5
    case unchanged = 6

    var label: String {
        switch self {
        case .empty: return "Empty"
        case .wellKnown: return "Well known"
        case .media: return "MIME media"
        case .absoluteURI: return "Absolute URI"
        case .external: return "External"
        case .unknown: return "Unknown"
        case .unchanged: return "Unchanged"
        }
    }
}

struct NDEFRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var tnf: TypeNameFormat
    var type: Data
    var identifier: Data
    var payload: Data

    init(tnf: TypeNameFormat, type: Data, identifier: Data = Data(), payload: Data) {
        self.id = UUID()
        self.tnf = tnf
        self.type = type
        self.identifier = identifier
        self.payload = payload
    }

    init(tnf: TypeNameFormat, typeString: String, payload: Data) {
        self.init(tnf: tnf, type: Data(typeString.utf8), identifier: Data(), payload: payload)
    }

    static let empty = NDEFRecord(tnf: .empty, type: Data(), identifier: Data(), payload: Data())

    var typeString: String {
        String(decoding: type, as: UTF8.self)
    }

    var isText: Bool {
        tnf == .wellKnown && typeString == "T"
    }

    var isURI: Bool {
        tnf == .wellKnown && typeString == "U"
    }

    var isSmartPoster: Bool {
        tnf == .wellKnown && typeString == "Sp"
    }

    /// Matches NDEFMessageCodec.encode byte for byte: an empty TNF record always encodes with zero lengths.
    var encodedSize: Int {
        if tnf == .empty { return 3 }
        let typeCount = min(type.count, 255)
        let identifierCount = min(identifier.count, 255)
        var size = 2
        size += payload.count < 256 ? 1 : 4
        if identifierCount > 0 { size += 1 }
        size += typeCount + identifierCount + payload.count
        return size
    }
}
