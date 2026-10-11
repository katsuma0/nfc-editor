import Foundation
import CoreNFC

extension NDEFRecord {
    init(payload: NFCNDEFPayload) {
        let tnf = TypeNameFormat(rawValue: payload.typeNameFormat.rawValue) ?? .unknown
        self.init(tnf: tnf, type: payload.type, identifier: payload.identifier, payload: payload.payload)
    }

    var nfcPayload: NFCNDEFPayload {
        let format = NFCTypeNameFormat(rawValue: tnf.rawValue) ?? .unknown
        return NFCNDEFPayload(format: format, type: type, identifier: identifier, payload: payload)
    }
}

extension Array where Element == NDEFRecord {
    var nfcMessage: NFCNDEFMessage {
        NFCNDEFMessage(records: map { $0.nfcPayload })
    }

    init(message: NFCNDEFMessage) {
        self = message.records.map { NDEFRecord(payload: $0) }
    }
}
