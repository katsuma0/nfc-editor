import Foundation

// Checks for the pure Swift crypto: DES and Triple DES against the classic FIPS test key,
// and secp128r1 ECDSA originality signature verification. Hex vectors are copied from
// Tests/Vectors/vectors.json so this file is self contained.
func checkCrypto() {
    // MARK: DES and Triple DES
    let desKey = hex("0123456789ABCDEF")
    let ecbPlain = hex("4E6F772069732074")
    let ecbCipher = hex("3FA40E8A984D4815")
    checkEqual(DES.encryptBlock(ecbPlain, key: desKey), ecbCipher, "DES ECB encrypt")
    checkEqual(DES.decryptBlock(ecbCipher, key: desKey), ecbPlain, "DES ECB decrypt")

    let zeroIV = hex("0000000000000000")
    let cbcPlain = hex("4E6F77206973207468652074696D6520")
    let cbcCipher = hex("3FA40E8A984D48150B2E73F88DC5856A")
    checkEqual(DES.cbcEncrypt(cbcPlain, key: desKey, iv: zeroIV), cbcCipher, "DES CBC encrypt")
    checkEqual(DES.cbcDecrypt(cbcCipher, key: desKey, iv: zeroIV), cbcPlain, "DES CBC decrypt")

    let tdeaKey = hex("0123456789ABCDEFFEDCBA9876543210")
    let tdeaEcbCipher = hex("D80A0D8B2BAE5E4E")
    let tdeaCbcCipher = hex("D80A0D8B2BAE5E4E319E5E68C3E8891B")
    checkEqual(DES.tdeaEncryptBlock(ecbPlain, key: tdeaKey), tdeaEcbCipher, "TDEA ECB encrypt")
    checkEqual(DES.tdeaDecryptBlock(tdeaEcbCipher, key: tdeaKey), ecbPlain, "TDEA ECB decrypt")
    checkEqual(DES.cbcEncrypt(cbcPlain, key: tdeaKey, iv: zeroIV), tdeaCbcCipher, "TDEA CBC encrypt")
    checkEqual(DES.cbcDecrypt(tdeaCbcCipher, key: tdeaKey, iv: zeroIV), cbcPlain, "TDEA CBC decrypt")

    checkEqual(DES.xor(hex("0102"), hex("0203")), hex("0301"), "DES xor")
    checkEqual(DES.rotateLeft(hex("01020304")), hex("02030401"), "DES rotateLeft")

    // MARK: secp128r1 ECDSA verification
    let publicKey = hex("04A17ACAADC4CB5B56CE86EE64BD4D3628AA4A94C85805C1C1C476A5748012C8A2")
    // uid, signature, expected validity. The second of each pair flips one signature nibble.
    let vectors: [(uid: String, signature: String, valid: Bool)] = [
        ("04583A62956781", "4C83E7F38AB05999EBD7120A617E4C240B277BA8E5AA500FEA514820CEA923D1", true),
        ("04583A62956781", "4C83E7F38AB15999EBD7120A617E4C240B277BA8E5AA500FEA514820CEA923D1", false),
        ("04A1B2C3D4E5F6", "079612154E6F5FAB6FE25FB711529A8C2A6EBEE639D9472EC709C1DB76C4B720", true),
        ("04A1B2C3D4E5F6", "079612154E6E5FAB6FE25FB711529A8C2A6EBEE639D9472EC709C1DB76C4B720", false),
        ("04C0FFEE010203", "C5FB9A1122F850782267092A412F62A772BDD17D8DB412D741301B31B22E567A", true),
        ("04C0FFEE010203", "C5FB9A1122F950782267092A412F62A772BDD17D8DB412D741301B31B22E567A", false)
    ]
    for (index, vector) in vectors.enumerated() {
        let result = OriginalitySignature.verify(
            signature: hex(vector.signature), uid: hex(vector.uid), publicKey: publicKey
        )
        checkEqual(result, vector.valid, "secp128r1 vector \(index)")
    }

    // The factory public keys match NXP's published values.
    checkEqual(
        OriginalitySignature.ntag21xPublicKey,
        hex("04494E1A386D3D3CFE3DC10E5DE68A499B1C202DB5B132393E89ED19FE5BE8BC61"),
        "NTAG21x public key"
    )
    checkEqual(
        OriginalitySignature.ultralightEV1PublicKey,
        hex("0490933BDCD6E99B4E255E3DA55389A827564E11718E017292FAF23226A96614B8"),
        "Ultralight EV1 public key"
    )

    // Verdict by chip: an NTAG213 maps to the NTAG key, a DESFire card has no key.
    let ntag213 = ChipIdentifier.fromGetVersion(hex("0004040201000F03"))!
    checkEqual(OriginalitySignature.publicKey(for: ntag213), OriginalitySignature.ntag21xPublicKey, "NTAG213 public key lookup")
    let desfire = ChipIdentifier.fromDESFireVersion(hardware: hex("04010101001805"))!
    checkEqual(
        OriginalitySignature.verify(signature: Data(repeating: 0, count: 32), uid: hex("04583A62956781"), chip: desfire),
        SignatureVerdict.noKey,
        "DESFire has no signature key"
    )
}
