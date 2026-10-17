import Foundation

// Vectors copied from Tests/Vectors/vectors.json ("ultralightC").
func checkNTAG() {
    // MARK: Ultralight C authentication exchange
    let ulcKey = hex("425245414B4D454946594F5543414E21")
    let piccStep1 = hex("AFD5ADBD5A1C4A8BD1")
    let rndA = hex("A0B1C2D3E4F50617")
    check(UltralightC.defaultKey == ulcKey, "Ultralight C default key is BREAKMEIFYOUCAN!")
    if let exchange = UltralightC.computeExchange(key: ulcKey, piccStep1: piccStep1, rndA: rndA) {
        checkEqual(exchange.pcdStep2, hex("AF7273043815B93F01872053C9A200E333"), "Ultralight C pcd step 2")
        checkEqual(exchange.expectedPiccStep3, hex("002A647F504AE4BCDA"), "Ultralight C picc step 3")
    } else {
        check(false, "Ultralight C computeExchange returned nil")
    }
    check(UltralightC.computeExchange(key: Data(repeating: 0, count: 8), piccStep1: piccStep1, rndA: rndA) == nil, "Ultralight C rejects a short key")
    check(UltralightC.computeExchange(key: ulcKey, piccStep1: hex("D5ADBD5A1C4A8BD1"), rndA: rndA) == nil, "Ultralight C rejects a step 1 without AF")

    // Key stored across pages 2C..2F, each 8-byte half most significant byte first.
    var keyPagesFlat = Data()
    for page in UltralightC.keyPages(ulcKey) { keyPagesFlat.append(page) }
    checkEqual(keyPagesFlat, hex("49454D4B41455242214E4143554F5946"), "Ultralight C key page layout 2C..2F")

    // MARK: NTAG mirror arithmetic
    checkEqual(NTAGMirror.location(ofOffsetInUserMemory: 0).page, 4, "mirror offset 0 is page 4")
    checkEqual(NTAGMirror.location(ofOffsetInUserMemory: 0).byte, 0, "mirror offset 0 byte 0")
    let loc = NTAGMirror.location(ofOffsetInUserMemory: 23)
    checkEqual(loc.page, 9, "mirror location page")
    checkEqual(loc.byte, 3, "mirror location byte")

    // For https://example.com/t?u= with a UID mirror the placeholder is appended after the URL.
    let mirror = NTAGMirror.mirroredURL(url: "https://example.com/t?u=", kind: .uid)
    checkEqual(mirror.fullURL, "https://example.com/t?u=00000000000000", "mirror full URL")
    checkEqual(mirror.placeholderIndex, 24, "mirror placeholder index")
    // Datasheet layout worked by hand on an NTAG216:
    //   TLV header 03 len                                         -> 2 bytes (offsets 0..1)
    //   record header D1, type len 01, payload len, 'U' 55, prefix 04 -> 5 bytes (offsets 2..6)
    //   the URL rest starts at offset 7; the placeholder is 16 bytes into it (24 minus "https://" = 8)
    //   placeholder offset = 2 + 5 + (24 - 8) = 23 -> page 4 + 23/4 = 9, byte 23 % 4 = 3
    let prefixLength = "https://".utf8.count
    let placeholderOffset = 2 + 5 + (mirror.placeholderIndex - prefixLength)
    checkEqual(placeholderOffset, 23, "mirror placeholder byte offset")
    let placeholderLocation = NTAGMirror.location(ofOffsetInUserMemory: placeholderOffset)
    checkEqual(placeholderLocation.page, 9, "mirror placeholder page")
    checkEqual(placeholderLocation.byte, 3, "mirror placeholder byte")
    // The 14-byte UID mirror ends at offset 36 -> page 13, which fits an NTAG216.
    checkEqual(NTAGMirror.location(ofOffsetInUserMemory: placeholderOffset + MirrorKind.uid.length - 1).page, 13, "last UID mirror byte page")

    checkEqual(MirrorKind.uid.length, 14, "UID mirror length")
    checkEqual(MirrorKind.counter.length, 6, "counter mirror length")
    checkEqual(MirrorKind.both.length, 21, "both mirror length")

    let tokenMirror = NTAGMirror.mirroredURL(url: "https://ex.com/{mirror}/x", kind: .counter)
    checkEqual(tokenMirror.fullURL, "https://ex.com/000000/x", "mirror token replaced")
    checkEqual(tokenMirror.placeholderIndex, "https://ex.com/".utf8.count, "mirror token index")

    // MARK: Lock bit groups
    let ntag213 = ChipIdentifier.ntag213
    let ntag215 = ChipIdentifier.ntag215
    let ntag216 = ChipIdentifier.ntag216
    let zeroStatic = hex("0000")
    let zeroDynamic = hex("000000")

    let g213 = LockBits.groups(chip: ntag213, staticLock: zeroStatic, dynamicLock: zeroDynamic)
    // 13 static single pages (3..15) then 12 two-page dynamic groups (16..39).
    checkEqual(g213.count, 25, "NTAG213 group count")
    checkEqual(g213.first?.pages, 3...3, "NTAG213 first group is page 3")
    checkEqual(g213[12].pages, 15...15, "NTAG213 last static group is page 15")
    checkEqual(g213[13].pages, 16...17, "NTAG213 first dynamic group")
    checkEqual(g213[24].pages, 38...39, "NTAG213 last dynamic group")

    let g216 = LockBits.groups(chip: ntag216, staticLock: zeroStatic, dynamicLock: zeroDynamic)
    // 13 static then 14 sixteen-page dynamic groups from 16, the last clamped to 224..225.
    checkEqual(g216.count, 27, "NTAG216 group count")
    checkEqual(g216[13].pages, 16...31, "NTAG216 first dynamic group")
    checkEqual(g216[26].pages, 224...225, "NTAG216 last dynamic group clamped")

    if let layout = LockBits.dynamicLayout(chip: ntag213) {
        checkEqual(layout.pagesPerBit, 2, "NTAG213 pages per bit")
        checkEqual(layout.firstPage, 16, "NTAG213 dynamic first page")
        checkEqual(layout.bitCount, 12, "NTAG213 dynamic bit count")
    } else {
        check(false, "NTAG213 has a dynamic layout")
    }
    if let layout = LockBits.dynamicLayout(chip: ntag216) {
        checkEqual(layout.pagesPerBit, 16, "NTAG216 pages per bit")
        checkEqual(layout.bitCount, 14, "NTAG216 dynamic bit count")
    } else {
        check(false, "NTAG216 has a dynamic layout")
    }
    if let layout = LockBits.dynamicLayout(chip: ntag215) {
        checkEqual(layout.pagesPerBit, 16, "NTAG215 pages per bit")
        checkEqual(layout.bitCount, 8, "NTAG215 dynamic bit count")
    } else {
        check(false, "NTAG215 has a dynamic layout")
    }

    // MARK: bytesToLock sets the right bits and never clears
    var toLock = g213
    func markLocked(_ page: Int) {
        for index in toLock.indices where toLock[index].pages.lowerBound == page { toLock[index].locked = true }
    }
    markLocked(3)  // static byte 0 bit 3
    markLocked(4)  // static byte 0 bit 4
    markLocked(8)  // static byte 1 bit 0
    markLocked(16) // dynamic group 0 -> byte 0 bit 0
    markLocked(38) // dynamic group 11 -> byte 1 bit 3
    let result = LockBits.bytesToLock(groups: toLock, chip: ntag213, staticLock: zeroStatic, dynamicLock: zeroDynamic)
    checkEqual(result.page2LockBytes, hex("1801"), "NTAG213 static lock bytes")
    checkEqual(result.dynamic, hex("010800"), "NTAG213 dynamic lock bytes")

    // Nothing marked: the existing bits are kept unchanged.
    let preset = LockBits.bytesToLock(groups: g213, chip: ntag213, staticLock: hex("0402"), dynamicLock: hex("800000"))
    checkEqual(preset.page2LockBytes, hex("0402"), "bytesToLock keeps existing static bits")
    checkEqual(preset.dynamic, hex("800000"), "bytesToLock keeps existing dynamic bits")

    // A chip without a dynamic lock page has static groups only and no dynamic bytes.
    let ulev1 = ChipIdentifier.ultralightEV1_11
    check(LockBits.dynamicLayout(chip: ulev1) == nil, "MF0UL11 has no dynamic layout")
    let gUL = LockBits.groups(chip: ulev1, staticLock: zeroStatic, dynamicLock: nil)
    checkEqual(gUL.count, 13, "MF0UL11 has only static groups")
    check(LockBits.bytesToLock(groups: gUL, chip: ulev1, staticLock: zeroStatic, dynamicLock: nil).dynamic == nil, "MF0UL11 bytesToLock has no dynamic bytes")
}
