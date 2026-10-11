import Foundation

enum URIPrefixes {
    /// NFC Forum URI Record Type Definition, identifier codes 0x00 through 0x23.
    static let table: [String] = [
        "",                             // 0x00
        "http://www.",                  // 0x01
        "https://www.",                 // 0x02
        "http://",                      // 0x03
        "https://",                     // 0x04
        "tel:",                         // 0x05
        "mailto:",                      // 0x06
        "ftp://anonymous:anonymous@",   // 0x07
        "ftp://ftp.",                   // 0x08
        "ftps://",                      // 0x09
        "sftp://",                      // 0x0A
        "smb://",                       // 0x0B
        "nfs://",                       // 0x0C
        "ftp://",                       // 0x0D
        "dav://",                       // 0x0E
        "news:",                        // 0x0F
        "telnet://",                    // 0x10
        "imap:",                        // 0x11
        "rtsp://",                      // 0x12
        "urn:",                         // 0x13
        "pop:",                         // 0x14
        "sip:",                         // 0x15
        "sips:",                        // 0x16
        "tftp:",                        // 0x17
        "btspp://",                     // 0x18
        "btl2cap://",                   // 0x19
        "btgoep://",                    // 0x1A
        "tcpobex://",                   // 0x1B
        "irdaobex://",                  // 0x1C
        "file://",                      // 0x1D
        "urn:epc:id:",                  // 0x1E
        "urn:epc:tag:",                 // 0x1F
        "urn:epc:pat:",                 // 0x20
        "urn:epc:raw:",                 // 0x21
        "urn:epc:",                     // 0x22
        "urn:nfc:"                      // 0x23
    ]

    static func abbreviate(_ uri: String) -> (code: UInt8, rest: String) {
        let uriBytes = Array(uri.utf8)
        var best: (code: UInt8, rest: String) = (0, uri)
        var bestLength = 0
        for (index, prefix) in table.enumerated() where index > 0 {
            let prefixBytes = Array(prefix.utf8)
            guard prefixBytes.count > bestLength, uriBytes.count >= prefixBytes.count else { continue }
            if uriBytes.starts(with: prefixBytes) {
                bestLength = prefixBytes.count
                best = (UInt8(index), String(decoding: uriBytes[prefixBytes.count...], as: UTF8.self))
            }
        }
        return best
    }

    static func expand(code: UInt8, rest: String) -> String {
        let index = Int(code)
        guard index < table.count else { return rest }
        return table[index] + rest
    }
}
