import Foundation

/// One lockable group of pages. Static lock bits each cover a single page; dynamic lock bits
/// cover a fixed stride of pages.
struct PageLock: Hashable, Identifiable {
    var pages: ClosedRange<Int>
    var locked: Bool
    var lockable: Bool
    var id: Int { pages.lowerBound }
}

enum LockBits {
    /// Builds the lock groups for a chip from its current static and dynamic lock bytes.
    /// staticLock is page 2 bytes 2 and 3; dynamicLock is the first 3 bytes of the dynamic lock page.
    static func groups(chip: ChipSpec, staticLock: Data, dynamicLock: Data?) -> [PageLock] {
        var result: [PageLock] = []
        let lock0 = staticLock[safe: 0] ?? 0
        let lock1 = staticLock[safe: 1] ?? 0

        // Byte 2 bit 3 locks page 3; bits 4..7 lock pages 4..7. Bits 0..2 are block locking bits.
        result.append(PageLock(pages: 3...3, locked: bit(lock0, 3), lockable: true))
        for page in 4...7 {
            result.append(PageLock(pages: page...page, locked: bit(lock0, page), lockable: true))
        }
        // Byte 3 bit n locks page 8 + n.
        for page in 8...15 {
            result.append(PageLock(pages: page...page, locked: bit(lock1, page - 8), lockable: true))
        }

        if let layout = dynamicLayout(chip: chip), let userRange = chip.userPageRange {
            let dyn = (dynamicLock ?? Data()).bytes
            for index in 0..<layout.bitCount {
                let start = layout.firstPage + index * layout.pagesPerBit
                if start > userRange.upperBound { break }
                let end = min(start + layout.pagesPerBit - 1, userRange.upperBound)
                let byteIndex = index / 8
                let bitIndex = index % 8
                let locked = byteIndex < dyn.count ? bit(dyn[byteIndex], bitIndex) : false
                result.append(PageLock(pages: start...end, locked: locked, lockable: true))
            }
        }

        return result
    }

    /// ORs the lock bits for every group marked locked into the current lock bytes. It never clears a bit.
    static func bytesToLock(groups: [PageLock], chip: ChipSpec, staticLock: Data, dynamicLock: Data?) -> (page2LockBytes: Data, dynamic: Data?) {
        var lock0 = staticLock[safe: 0] ?? 0
        var lock1 = staticLock[safe: 1] ?? 0
        var dyn = (dynamicLock ?? Data()).bytes
        let layout = dynamicLayout(chip: chip)
        while dyn.count < 3 { dyn.append(0) }

        for group in groups where group.locked {
            let page = group.pages.lowerBound
            if group.pages.count == 1 && (3...15).contains(page) {
                if page == 3 {
                    lock0 |= UInt8(1 << 3)
                } else if page <= 7 {
                    lock0 |= UInt8(1 << page)
                } else {
                    lock1 |= UInt8(1 << (page - 8))
                }
            } else if let layout = layout, page >= layout.firstPage {
                let bitIndex = (page - layout.firstPage) / layout.pagesPerBit
                let byteIndex = bitIndex / 8
                if byteIndex < dyn.count {
                    dyn[byteIndex] |= UInt8(1 << (bitIndex % 8))
                }
            }
        }

        let dynamicOut: Data? = layout != nil ? Data(dyn.prefix(3)) : nil
        return (page2LockBytes: Data([lock0, lock1]), dynamic: dynamicOut)
    }

    /// The dynamic lock stride for a chip, or nil when it has no dynamic lock page.
    /// NTAG215 and NTAG216 lock 16 pages per bit; the smaller chips lock 2.
    static func dynamicLayout(chip: ChipSpec) -> (pagesPerBit: Int, firstPage: Int, bitCount: Int)? {
        guard chip.dynamicLockPage != nil, let userRange = chip.userPageRange, userRange.upperBound >= 16 else {
            return nil
        }
        let pagesPerBit = (chip.name.contains("NTAG215") || chip.name.contains("NTAG216")) ? 16 : 2
        let span = userRange.upperBound - 15
        let bitCount = (span + pagesPerBit - 1) / pagesPerBit
        return (pagesPerBit, 16, bitCount)
    }

    private static func bit(_ byte: UInt8, _ index: Int) -> Bool {
        (byte >> UInt8(index)) & 1 == 1
    }
}
