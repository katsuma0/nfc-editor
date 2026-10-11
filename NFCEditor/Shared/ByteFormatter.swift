import Foundation

enum ByteFormatter {
    /// "181 bytes". Tags are small, so this never switches to KB.
    static func bytes(_ n: Int) -> String {
        let count = max(n, 0)
        return count == 1 ? "1 byte" : "\(count) bytes"
    }

    /// One line per page: "04: 03 0B D1 01  ...." with the page index in hex, the bytes, then printable ASCII.
    static func hexDump(_ data: Data, pageSize: Int, startIndex: Int = 0) -> String {
        let size = max(pageSize, 1)
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return "" }

        let pageCount = (bytes.count + size - 1) / size
        let lastIndex = max(startIndex + pageCount - 1, 0)
        let width = max(2, String(lastIndex, radix: 16).count)

        var lines: [String] = []
        lines.reserveCapacity(pageCount)
        var offset = 0
        var index = startIndex
        while offset < bytes.count {
            let end = min(offset + size, bytes.count)
            let chunk = Array(bytes[offset..<end])
            var hex = chunk.map { $0.hex }.joined(separator: " ")
            if chunk.count < size {
                hex += String(repeating: "   ", count: size - chunk.count)
            }
            let ascii = Data(chunk).asciiPreview
            lines.append("\(label(index, width: width)): \(hex)  \(ascii)")
            offset = end
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    /// "2%"
    static func percent(_ used: Int, of capacity: Int) -> String {
        guard capacity > 0 else { return "0%" }
        let ratio = Double(max(used, 0)) / Double(capacity) * 100
        let rounded = Int(ratio.rounded())
        return "\(min(max(rounded, 0), 100))%"
    }

    private static func label(_ index: Int, width: Int) -> String {
        let raw = String(max(index, 0), radix: 16, uppercase: true)
        if raw.count >= width {
            return raw
        }
        return String(repeating: "0", count: width - raw.count) + raw
    }
}
