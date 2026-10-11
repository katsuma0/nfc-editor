import Foundation
import CoreNFC

enum FeliCaCommands {
    struct Info {
        var idm: Data
        var pmm: Data?
        var systemCode: Data
        var systemCodes: [Data]
    }

    private static let wildcardSystemCode = Data([0xFF, 0xFF])

    static func info(_ tag: NFCFeliCaTag) async throws -> Info {
        let idm = Data(tag.currentIDm)
        let current = Data(tag.currentSystemCode)
        let systemCode = current.count == 2 ? current : wildcardSystemCode

        var pmm: Data?
        // Core NFC refuses the wildcard system code in polling, so the PMm is only asked for when a real one is known.
        if systemCode != wildcardSystemCode {
            do {
                let (manufacturerParameter, _) = try await tag.polling(
                    systemCode: systemCode,
                    requestCode: NFCFeliCaPollingRequestCode.systemCode,
                    timeSlot: NFCFeliCaPollingTimeSlot.max1
                )
                if !manufacturerParameter.isEmpty {
                    pmm = Data(manufacturerParameter)
                }
            } catch {
                let mapped = NFCEditorError.map(error)
                if isSessionError(mapped) { throw mapped }
            }
        }

        var codes: [Data] = []
        do {
            codes = try await tag.requestSystemCode().map { Data($0) }
        } catch {
            let mapped = NFCEditorError.map(error)
            if isSessionError(mapped) { throw mapped }
        }
        if codes.isEmpty, systemCode != wildcardSystemCode {
            codes = [systemCode]
        }

        return Info(idm: idm, pmm: pmm, systemCode: systemCode, systemCodes: codes)
    }

    static func raw(_ tag: NFCFeliCaTag, packet: Data) async throws -> Data {
        guard !packet.isEmpty else {
            throw NFCEditorError.invalidInput("Enter a command.")
        }
        do {
            let response = try await tag.sendFeliCaCommand(commandPacket: packet)
            return Data(response)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    private static func isSessionError(_ error: NFCEditorError) -> Bool {
        switch error {
        case .cancelled, .timeout, .tagLost, .nfcUnavailable, .multipleTags:
            return true
        default:
            return false
        }
    }
}
