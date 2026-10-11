import Foundation

enum NDEFCodecError: LocalizedError, Equatable {
    case truncated
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .truncated:
            return "The NDEF message is incomplete."
        case .malformed(let reason):
            return "The NDEF message is malformed. \(reason)"
        }
    }
}

enum NDEFMessageCodec {
    private static let flagMessageBegin: UInt8 = 0x80
    private static let flagMessageEnd: UInt8 = 0x40
    private static let flagChunk: UInt8 = 0x20
    private static let flagShortRecord: UInt8 = 0x10
    private static let flagIDLength: UInt8 = 0x08

    static func encode(_ records: [NDEFRecord]) -> Data {
        let list = records.isEmpty ? [NDEFRecord.empty] : records
        var out = Data()
        for (index, record) in list.enumerated() {
            let isEmpty = record.tnf == .empty
            let typeBytes = isEmpty ? Data() : record.type.prefix(255)
            let idBytes = isEmpty ? Data() : record.identifier.prefix(255)
            let payload = isEmpty ? Data() : record.payload
            let short = payload.count < 256

            var flags: UInt8 = record.tnf.rawValue & 0x07
            if index == 0 { flags |= flagMessageBegin }
            if index == list.count - 1 { flags |= flagMessageEnd }
            if short { flags |= flagShortRecord }
            if !idBytes.isEmpty { flags |= flagIDLength }

            out.append(flags)
            out.append(UInt8(typeBytes.count))
            if short {
                out.append(UInt8(payload.count))
            } else {
                let count = UInt32(truncatingIfNeeded: payload.count)
                out.append(UInt8(truncatingIfNeeded: count >> 24))
                out.append(UInt8(truncatingIfNeeded: count >> 16))
                out.append(UInt8(truncatingIfNeeded: count >> 8))
                out.append(UInt8(truncatingIfNeeded: count))
            }
            if !idBytes.isEmpty {
                out.append(UInt8(idBytes.count))
            }
            out.append(typeBytes)
            out.append(idBytes)
            out.append(payload)
        }
        return out
    }

    static func decode(_ data: Data) throws -> [NDEFRecord] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw NDEFCodecError.truncated }

        var records: [NDEFRecord] = []
        var offset = 0
        var sawEnd = false
        // A chunked record starts with CF set and continues in unchanged TNF chunks until CF clears.
        var pendingChunk: NDEFRecord?

        while offset < bytes.count {
            let flags = bytes[offset]
            offset += 1

            let messageBegin = flags & flagMessageBegin != 0
            let messageEnd = flags & flagMessageEnd != 0
            let chunk = flags & flagChunk != 0
            let short = flags & flagShortRecord != 0
            let hasID = flags & flagIDLength != 0
            let isFirst = records.isEmpty && pendingChunk == nil

            if isFirst && !messageBegin {
                throw NDEFCodecError.malformed("The first record does not start a message.")
            }
            if !isFirst && messageBegin {
                throw NDEFCodecError.malformed("A second message begin flag was found.")
            }
            if chunk && messageEnd {
                throw NDEFCodecError.malformed("A record chunk cannot end the message.")
            }
            guard let tnf = TypeNameFormat(rawValue: flags & 0x07) else {
                throw NDEFCodecError.malformed("Reserved type name format 7 was found.")
            }

            guard offset < bytes.count else { throw NDEFCodecError.truncated }
            let typeLength = Int(bytes[offset])
            offset += 1

            let payloadLength: Int
            if short {
                guard offset < bytes.count else { throw NDEFCodecError.truncated }
                payloadLength = Int(bytes[offset])
                offset += 1
            } else {
                guard offset + 4 <= bytes.count else { throw NDEFCodecError.truncated }
                payloadLength = Int(bytes[offset]) << 24
                    | Int(bytes[offset + 1]) << 16
                    | Int(bytes[offset + 2]) << 8
                    | Int(bytes[offset + 3])
                offset += 4
            }

            var idLength = 0
            if hasID {
                guard offset < bytes.count else { throw NDEFCodecError.truncated }
                idLength = Int(bytes[offset])
                offset += 1
            }

            guard offset + typeLength + idLength + payloadLength <= bytes.count else {
                throw NDEFCodecError.truncated
            }

            let type = Data(bytes[offset..<offset + typeLength])
            offset += typeLength
            let identifier = Data(bytes[offset..<offset + idLength])
            offset += idLength
            let payload = Data(bytes[offset..<offset + payloadLength])
            offset += payloadLength

            if var pending = pendingChunk {
                guard tnf == .unchanged, typeLength == 0, idLength == 0 else {
                    throw NDEFCodecError.malformed("A record chunk continuation must use the unchanged type name format.")
                }
                pending.payload.append(payload)
                if chunk {
                    pendingChunk = pending
                } else {
                    pendingChunk = nil
                    records.append(pending)
                }
            } else {
                guard tnf != .unchanged else {
                    throw NDEFCodecError.malformed("The unchanged type name format is only valid inside a chunked record.")
                }
                let record = NDEFRecord(tnf: tnf, type: type, identifier: identifier, payload: payload)
                if chunk {
                    pendingChunk = record
                } else {
                    records.append(record)
                }
            }

            if messageEnd {
                sawEnd = true
                break
            }
        }

        guard pendingChunk == nil else {
            throw NDEFCodecError.truncated
        }
        guard sawEnd else {
            throw NDEFCodecError.malformed("The message end flag is missing.")
        }
        return records
    }

    static func byteCount(_ records: [NDEFRecord]) -> Int {
        encode(records).count
    }

    static func tlv(message: Data) -> Data {
        var out = Data([0x03])
        if message.count < 0xFF {
            out.append(UInt8(message.count))
        } else {
            let count = min(message.count, 0xFFFF)
            out.append(0xFF)
            out.append(UInt8((count >> 8) & 0xFF))
            out.append(UInt8(count & 0xFF))
        }
        out.append(message)
        out.append(0xFE)
        return out
    }

    static func messageFromTLV(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let tag = bytes[offset]
            offset += 1

            // NULL TLVs are a single byte and the terminator ends the area.
            if tag == 0x00 { continue }
            if tag == 0xFE { return nil }

            guard offset < bytes.count else { return nil }
            var length = Int(bytes[offset])
            offset += 1
            if length == 0xFF {
                guard offset + 2 <= bytes.count else { return nil }
                length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                offset += 2
            }

            if tag == 0x03 {
                // A partially read memory image yields a short message; the decoder reports it as truncated.
                let end = min(offset + length, bytes.count)
                return Data(bytes[offset..<end])
            }

            offset += length
        }
        return nil
    }
}
