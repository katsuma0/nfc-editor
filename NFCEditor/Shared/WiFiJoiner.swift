import Foundation
import NetworkExtension

enum WiFiJoiner {
    /// Joins the network with NEHotspotConfiguration. Throws NFCEditorError.failed(message) on error. Requires the Hotspot Configuration entitlement.
    static func join(_ credential: WiFiCredential) async throws {
        let ssid = credential.ssid
        guard !ssid.isEmpty else {
            throw NFCEditorError.failed("The network has no name.")
        }
        guard ssid.utf8.count <= 32 else {
            throw NFCEditorError.failed("The network name is longer than 32 bytes.")
        }

        // NEHotspotConfiguration raises an uncatchable exception on a bad passphrase, so check it first.
        let secured = credential.auth != .open && !credential.password.isEmpty
        if secured {
            guard (8...63).contains(credential.password.count) else {
                throw NFCEditorError.failed("The Wi-Fi password must be 8 to 63 characters.")
            }
        }

        let configuration: NEHotspotConfiguration
        if secured {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: credential.password, isWEP: false)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid)
        }
        configuration.hidden = credential.hidden
        configuration.joinOnce = false

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NEHotspotConfigurationManager.shared.apply(configuration) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            if isAlreadyAssociated(error) {
                return
            }
            throw NFCEditorError.failed(message(for: error))
        }
    }

    private static func isAlreadyAssociated(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NEHotspotConfigurationErrorDomain
            && nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NEHotspotConfigurationErrorDomain else {
            return nsError.localizedDescription
        }
        switch nsError.code {
        case NEHotspotConfigurationError.userDenied.rawValue:
            return "You chose not to join the network."
        case NEHotspotConfigurationError.invalidSSID.rawValue,
             NEHotspotConfigurationError.invalidSSIDPrefix.rawValue:
            return "The network name is not valid."
        case NEHotspotConfigurationError.invalidWPAPassphrase.rawValue,
             NEHotspotConfigurationError.invalidWEPPassphrase.rawValue:
            return "The Wi-Fi password is not valid."
        case NEHotspotConfigurationError.applicationIsNotInForeground.rawValue:
            return "Bring NFC Editor to the front and try again."
        case NEHotspotConfigurationError.pending.rawValue:
            return "A previous Wi-Fi request is still in progress. Try again in a moment."
        case NEHotspotConfigurationError.systemConfiguration.rawValue:
            return "This network is managed by a configuration profile and cannot be changed."
        default:
            return "Could not join the network."
        }
    }
}
