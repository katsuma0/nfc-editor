import Foundation

// Vectors copied from Tests/Vectors/vectors.json ("desfireLegacy").
func checkDESFire() {
    // MARK: DESFire legacy (D40) authentication arithmetic
    let key = hex("0000000000000000")
    let rndA = hex("F0E1D2C3B4A59687")
    let piccStep1 = hex("AF70C7F6D7AFAC450C")
    if let auth = DESFireCommands.computeLegacyAuth(key: key, piccStep1: piccStep1, rndA: rndA) {
        checkEqual(auth.pcdStep2, hex("AF1D1BF70DFA0C8B662E9F2CB89851B507"), "DESFire legacy pcd step 2")
        checkEqual(auth.expectedPiccStep3, hex("0070329A1A9A93B73B"), "DESFire legacy picc step 3")
        checkEqual(auth.sessionKey, hex("F0E1D2C30A1B2C3DF0E1D2C30A1B2C3D"), "DESFire legacy session key")
    } else {
        check(false, "DESFire computeLegacyAuth returned nil")
    }
    check(DESFireCommands.computeLegacyAuth(key: hex("00"), piccStep1: piccStep1, rndA: rndA) == nil, "DESFire rejects a short key")
    check(DESFireCommands.computeLegacyAuth(key: key, piccStep1: hex("70C7F6D7AFAC450C"), rndA: rndA) == nil, "DESFire rejects a step 1 without AF")
    check(DESFireCommands.computeLegacyAuth(key: key, piccStep1: piccStep1, rndA: hex("F0E1D2C3")) == nil, "DESFire rejects a short RndA")

    // MARK: CRC_A
    checkEqual(DESFireCommands.crc16(hex("00010203")), hex("F70D"), "DESFire CRC_A of 00 01 02 03")
    checkEqual(DESFireCommands.crc16(Data()), hex("6363"), "DESFire CRC_A of nothing is the seed")

    // MARK: Status names
    checkEqual(DESFireCommands.statusName(0xAE), "Authentication error", "DESFire status 0xAE")
    checkEqual(DESFireCommands.statusName(0x00), "OK", "DESFire status 0x00")
    checkEqual(DESFireCommands.statusName(0xF0), "File not found", "DESFire status 0xF0")
    checkEqual(DESFireCommands.statusName(0x1C), "Illegal command", "DESFire status 0x1C")
    checkEqual(DESFireCommands.statusName(0x55), "Status 0x55", "DESFire unknown status")
}
