import Foundation

// Checks for the chip identification, the signature verdict wiring and the new TagInfo fields
// that the full coverage round adds. These exercise ChipSpec, TagInfo and Type5Settings.
func checkTagInfo() {
    // MARK: GET_VERSION identification
    // Bytes: 00, vendor 04, product type 04 (NTAG), subtype, major, minor, storage 0F, protocol.
    let tt = ChipIdentifier.fromGetVersion(hex("0004040301000F03"))
    check(tt?.name == "NTAG213TT", "NTAG213TT is identified")
    checkEqual(tt?.family, ChipFamily.ntag21x, "NTAG213TT family is ntag21x")
    checkEqual(tt?.configPage, 0x29, "NTAG213TT keeps the NTAG213 config page")
    check(tt?.userPageRange == 4...39, "NTAG213TT keeps the NTAG213 user pages")

    let plain = ChipIdentifier.fromGetVersion(hex("0004040201000F03"))
    check(plain?.name == "NTAG213", "NTAG213 is still identified")
    checkEqual(plain?.family, ChipFamily.ntag21x, "NTAG213 family is ntag21x")

    let fVariant = ChipIdentifier.fromGetVersion(hex("0004040401000F03"))
    check(fVariant?.name == "NTAG213F", "NTAG213F is still identified")
    checkEqual(fVariant?.family, ChipFamily.ntag21xF, "NTAG213F family is ntag21xF")

    // MARK: Signature verdict wiring through the chip family
    check(OriginalitySignature.publicKey(for: ChipIdentifier.ntag213) == OriginalitySignature.ntag21xPublicKey, "NTAG213 maps to the NTAG public key")
    check(OriginalitySignature.publicKey(for: ChipIdentifier.ultralightEV1_11) == OriginalitySignature.ultralightEV1PublicKey, "Ultralight EV1 maps to the UL public key")
    check(OriginalitySignature.publicKey(for: ChipIdentifier.iso7816Generic()) == nil, "A Type 4 chip has no originality key")
    checkEqual(OriginalitySignature.verify(signature: Data(repeating: 0, count: 32), uid: hex("04583A62956781"), chip: ChipIdentifier.iso7816Generic()), SignatureVerdict.noKey, "No key gives the noKey verdict")

    // MARK: Type5Settings
    let settings = Type5Settings(dsfid: 0, afi: 0, blockSize: 4, totalBlocks: 28, lockedBlocks: [true, false, false], isSLIX: true, isST: false)
    checkEqual(settings.lockedBlocks.filter { $0 }.count, 1, "Type5Settings counts a locked block")
    check(settings == settings, "Type5Settings is Hashable")

    // MARK: TagInfo codable with the new fields
    var info = TagInfo(technology: .iso14443A, chip: ChipIdentifier.ntag213, uid: hex("04583A62956781"))
    info.signature = Data(repeating: 0xAB, count: 32)
    info.signatureVerdict = .genuine
    info.tamperStatus = hex("0100000000")
    do {
        let data = try JSONEncoder().encode(info)
        let back = try JSONDecoder().decode(TagInfo.self, from: data)
        checkEqual(back.signatureVerdict, SignatureVerdict.genuine, "TagInfo keeps the signature verdict")
        checkEqual(back.tamperStatus, hex("0100000000"), "TagInfo keeps the tamper status")
    } catch {
        check(false, "TagInfo codable threw \(error)")
    }
}
