import Foundation
import CoreNFC

var failures = 0
var passes = 0
func check(_ cond: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if cond { passes += 1 } else { failures += 1; print("FAIL: \(name) (line \(line))") }
}
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, line: Int = #line) {
    if a == b { passes += 1 } else { failures += 1; print("FAIL: \(name) (line \(line)): \(a) != \(b)") }
}
func hex(_ s: String) -> Data { Data(hexString: s)! }

// MARK: HexUtils
checkEqual(hex("04 58 3a").hexString(separator: ":"), "04:58:3A", "hexString separator")
checkEqual(hex("0x0458").hexString(), "0458", "hexString no separator")
check(Data(hexString: "123") == nil, "odd hex rejected")
check(Data(hexString: "zz") == nil, "non hex rejected")
checkEqual(UInt8(4).hex, "04", "UInt8.hex")
checkEqual(UInt16(0x44).hex, "0044", "UInt16.hex")
checkEqual(hex("0044").uint16BE, UInt16(0x0044), "uint16BE")
checkEqual("0x04:58-3a ".normalizedHex, "04583A", "normalizedHex")
check("04 58".isValidHex, "isValidHex true")
check(!"".isValidHex, "isValidHex empty false")
checkEqual(hex("41 42 00").asciiPreview, "AB.", "asciiPreview")

// MARK: URI prefixes
checkEqual(URIPrefixes.table.count, 36, "URI prefix table has 36 entries")
checkEqual(URIPrefixes.table[0x02], "https://www.", "prefix 0x02")
checkEqual(URIPrefixes.table[0x23], "urn:nfc:", "prefix 0x23")
let abbr = URIPrefixes.abbreviate("https://www.example.com")
checkEqual(Int(abbr.code), 0x02, "abbreviate picks https://www.")
checkEqual(abbr.rest, "example.com", "abbreviate rest")
checkEqual(URIPrefixes.expand(code: 0x05, rest: "+14165551234"), "tel:+14165551234", "expand tel")
checkEqual(URIPrefixes.expand(code: 0x00, rest: "geo:1,2"), "geo:1,2", "expand code 0")
checkEqual(Int(URIPrefixes.abbreviate("geo:1,2").code), 0, "geo has no prefix")

// MARK: Record builders and codec byte vectors
let uriRecord = RecordBuilders.uri("https://www.example.com")
checkEqual(NDEFMessageCodec.encode([uriRecord]), hex("D1010C55026578616D706C652E636F6D"), "URI record bytes")
let textRecord = RecordBuilders.text("Hello", language: "en")
checkEqual(NDEFMessageCodec.encode([textRecord]), hex("D101085402656E48656C6C6F"), "Text record bytes")
checkEqual(textRecord.encodedSize, 12, "text encodedSize")
checkEqual(NDEFMessageCodec.byteCount([uriRecord, textRecord]), 16 + 12, "byteCount of two records")
// Two records: MB on first, ME on last
let two = NDEFMessageCodec.encode([uriRecord, textRecord])
checkEqual(two[0], 0x91, "first record header MB|SR|TNF1")
checkEqual(two[16], 0x51, "second record header ME|SR|TNF1")
// Long payload uses 4-byte length
let big = RecordBuilders.text(String(repeating: "a", count: 300), language: "en")
let bigBytes = NDEFMessageCodec.encode([big])
checkEqual(bigBytes[0], 0xC1, "long record header has no SR")
checkEqual(Int(bigBytes[2]) << 24 | Int(bigBytes[3]) << 16 | Int(bigBytes[4]) << 8 | Int(bigBytes[5]), 303, "4-byte payload length")
checkEqual(big.encodedSize, bigBytes.count, "encodedSize matches long encoding")
// Round trips
do {
    let decoded = try NDEFMessageCodec.decode(two)
    checkEqual(decoded.count, 2, "decode two records")
    checkEqual(decoded[0].payload, uriRecord.payload, "decode uri payload")
    checkEqual(decoded[1].typeString, "T", "decode text type")
    let decodedBig = try NDEFMessageCodec.decode(bigBytes)
    checkEqual(decodedBig.first?.payload.count, 303, "decode long payload")
    // record with id
    let withID = NDEFRecord(tnf: .media, type: Data("text/plain".utf8), identifier: Data("id1".utf8), payload: Data("x".utf8))
    let idBytes = NDEFMessageCodec.encode([withID])
    checkEqual(idBytes[0], 0xDA, "IL flag set")
    let back = try NDEFMessageCodec.decode(idBytes)
    checkEqual(back.first?.identifier, Data("id1".utf8), "id round trip")
    // empty message
    let emptyBytes = NDEFMessageCodec.encode([])
    checkEqual(emptyBytes, hex("D00000"), "empty message encodes as empty record")
    let emptyDecoded = try NDEFMessageCodec.decode(hex("D00000"))
    checkEqual(emptyDecoded.first?.tnf, TypeNameFormat.empty, "empty record decodes")
} catch {
    check(false, "decode threw \(error)")
}
check((try? NDEFMessageCodec.decode(hex("D1 01"))) == nil, "truncated rejected")

// MARK: TLV
let tlvShort = NDEFMessageCodec.tlv(message: two)
checkEqual(tlvShort[0], 0x03, "tlv type")
checkEqual(Int(tlvShort[1]), two.count, "tlv short length")
checkEqual(tlvShort.last, 0xFE, "tlv terminator")
let tlvLong = NDEFMessageCodec.tlv(message: bigBytes)
checkEqual(tlvLong[1], 0xFF, "tlv long marker")
checkEqual(Int(tlvLong[2]) << 8 | Int(tlvLong[3]), bigBytes.count, "tlv long length")
checkEqual(NDEFMessageCodec.messageFromTLV(tlvShort), two, "messageFromTLV short")
checkEqual(NDEFMessageCodec.messageFromTLV(tlvLong), bigBytes, "messageFromTLV long")
var withLockControl = hex("0103A00C34") // lock control TLV, 3 bytes
withLockControl.append(hex("00"))        // NULL TLV
withLockControl.append(tlvShort)
checkEqual(NDEFMessageCodec.messageFromTLV(withLockControl), two, "messageFromTLV skips lock control and null TLVs")
check(NDEFMessageCodec.messageFromTLV(hex("00000000")) == nil, "no TLV -> nil")

// MARK: Text parsing
let parsedText = RecordParsers.text(textRecord)
checkEqual(parsedText?.text, "Hello", "text parse")
checkEqual(parsedText?.language, "en", "text language")
checkEqual(RecordParsers.uri(uriRecord), "https://www.example.com", "uri parse")
checkEqual(RecordParsers.parse(uriRecord).kind, RecordKind.url, "uri kind")
checkEqual(RecordParsers.parse(textRecord).kind, RecordKind.text, "text kind")
checkEqual(RecordParsers.parse(textRecord).detail, "Hello", "text detail")

// MARK: Wi-Fi
let wifi = WiFiCredential(ssid: "Shop", password: "sashiko123", auth: .wpa2PSK, encryption: .aes, hidden: false)
let wifiData = wifi.encode()
checkEqual(wifiData.prefix(2), hex("100E"), "WSC credential attribute id")
checkEqual(Int(wifiData[2]) << 8 | Int(wifiData[3]), wifiData.count - 4, "WSC credential length covers the rest")
let wifiBack = WiFiCredential.decode(wifiData)
checkEqual(wifiBack?.ssid, "Shop", "wifi ssid round trip")
checkEqual(wifiBack?.password, "sashiko123", "wifi password round trip")
checkEqual(wifiBack?.auth, WiFiCredential.Auth.wpa2PSK, "wifi auth round trip")
checkEqual(wifiBack?.encryption, WiFiCredential.Encryption.aes, "wifi encryption round trip")
let wifiRecord = RecordBuilders.wifi(wifi)
checkEqual(wifiRecord.typeString, "application/vnd.wfa.wsc", "wifi mime")
checkEqual(RecordParsers.parse(wifiRecord).kind, RecordKind.wifi, "wifi kind")
checkEqual(RecordParsers.parse(wifiRecord).detail, "Shop", "wifi detail is SSID")
check(RecordParsers.parse(wifiRecord).actions.contains(.joinWiFi(wifi)), "wifi join action")

// MARK: Bluetooth
check(BluetoothOOB.isValidAddress("AA:BB:CC:DD:EE:FF"), "bt address colon")
check(BluetoothOOB.isValidAddress("aabbccddeeff"), "bt address plain")
check(!BluetoothOOB.isValidAddress("AA:BB"), "bt address short rejected")
let bt = BluetoothOOB(address: "AA:BB:CC:DD:EE:FF", name: "Speaker")
let btData = bt.encode()
checkEqual(Int(btData[0]) | Int(btData[1]) << 8, btData.count, "bt OOB total length little endian")
checkEqual(Data(btData[2..<8]), hex("FFEEDDCCBBAA"), "bt address little endian")
let btBack = BluetoothOOB.decode(btData)
checkEqual(btBack?.address, "AA:BB:CC:DD:EE:FF", "bt address round trip")
checkEqual(btBack?.name, "Speaker", "bt name round trip")
checkEqual(RecordParsers.parse(RecordBuilders.bluetooth(bt)).kind, RecordKind.bluetooth, "bt kind")

// MARK: vCard
var card = VCard()
card.firstName = "Katsuma"; card.lastName = "Onishi"; card.organization = "Denim; Goods"; card.phone = "+1 905 555 0100"; card.email = "hi@example.com"; card.website = "https://example.com"; card.note = "Line one\nLine two, with comma"
let vcf = card.encode()
check(vcf.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0"), "vcard header")
check(vcf.contains("N:Onishi;Katsuma;;;"), "vcard N line")
check(vcf.contains("FN:Katsuma Onishi"), "vcard FN")
check(vcf.contains("ORG:Denim\\; Goods"), "vcard escapes semicolon")
check(vcf.contains("NOTE:Line one\\nLine two\\, with comma"), "vcard escapes newline and comma")
check(vcf.hasSuffix("END:VCARD\r\n") || vcf.hasSuffix("END:VCARD"), "vcard footer")
let cardBack = VCard.decode(vcf)
checkEqual(cardBack?.firstName, "Katsuma", "vcard first name round trip")
checkEqual(cardBack?.lastName, "Onishi", "vcard last name round trip")
checkEqual(cardBack?.organization, "Denim; Goods", "vcard org unescape")
checkEqual(cardBack?.note, "Line one\nLine two, with comma", "vcard note unescape")
checkEqual(cardBack?.phone, "+1 905 555 0100", "vcard phone")
let folded = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Some Very Long Name That\r\n  Continues Here\r\nTEL;TYPE=CELL:123\r\nEND:VCARD\r\n"
checkEqual(VCard.decode(folded)?.phone, "123", "vcard folded line parse")
checkEqual(RecordParsers.parse(RecordBuilders.vcard(card)).kind, RecordKind.contact, "vcard kind")
checkEqual(RecordParsers.parse(RecordBuilders.vcard(card)).detail, "Katsuma Onishi", "vcard detail")

// MARK: Other builders and parser classification
checkEqual(RecordParsers.parse(RecordBuilders.email(to: "a@b.com", subject: "Hi there", body: "x&y")).kind, RecordKind.email, "email kind")
checkEqual(RecordParsers.uri(RecordBuilders.email(to: "a@b.com", subject: "Hi there", body: "x&y")), "mailto:a@b.com?subject=Hi%20there&body=x%26y", "mailto encoding")
checkEqual(RecordParsers.parse(RecordBuilders.phone("+1 905 555 0100")).kind, RecordKind.phone, "phone kind")
checkEqual(RecordParsers.parse(RecordBuilders.sms(number: "+19055550100", body: "hello world")).kind, RecordKind.sms, "sms kind")
checkEqual(RecordParsers.parse(RecordBuilders.geo(latitude: 43.8561, longitude: -79.3370, format: "geo")).kind, RecordKind.geo, "geo kind")
checkEqual(RecordParsers.uri(RecordBuilders.geo(latitude: 43.8561, longitude: -79.3370, format: "geo")), "geo:43.8561,-79.337", "geo uri")
checkEqual(RecordParsers.parse(RecordBuilders.address("1 Main St, Markham", format: "apple")).kind, RecordKind.address, "address kind")
checkEqual(RecordParsers.parse(RecordBuilders.social(.instagram, handle: "@katsuma")).kind, RecordKind.social, "social kind")
checkEqual(RecordParsers.uri(RecordBuilders.social(.instagram, handle: "@katsuma")), "https://www.instagram.com/katsuma", "instagram url")
checkEqual(SocialPlatform.detect(url: "https://www.instagram.com/katsuma")?.0, SocialPlatform.instagram, "social detect")
checkEqual(RecordParsers.parse(RecordBuilders.androidApp(package: "com.example.app")).kind, RecordKind.app, "aar kind")
checkEqual(RecordBuilders.androidApp(package: "com.example.app").typeString, "android.com:pkg", "aar type")
checkEqual(RecordParsers.parse(RecordBuilders.mime(type: "application/octet-stream", payload: hex("0102"))).kind, RecordKind.customMIME, "mime kind")
checkEqual(RecordParsers.parse(RecordBuilders.external(domain: "example.com", type: "thing", payload: hex("01"))).kind, RecordKind.external, "external kind")
checkEqual(RecordBuilders.external(domain: "example.com", type: "thing", payload: hex("01")).typeString, "example.com:thing", "external type string")
checkEqual(RecordParsers.parse(NDEFRecord.empty).kind, RecordKind.empty, "empty kind")
checkEqual(RecordParsers.parse(RecordBuilders.smartPoster(uri: "https://example.com", title: "Shop", language: "en")).kind, RecordKind.smartPoster, "smart poster kind")
checkEqual(RecordParsers.smartPoster(RecordBuilders.smartPoster(uri: "https://example.com", title: "Shop", language: "en"))?.uri, "https://example.com", "smart poster uri")
checkEqual(RecordParsers.smartPoster(RecordBuilders.smartPoster(uri: "https://example.com", title: "Shop", language: "en"))?.title, "Shop", "smart poster title")
checkEqual(RecordBuilders.percentEncode("a b&c/d"), "a%20b%26c%2Fd", "percentEncode")

// MARK: RecordDraft round trips
func roundTrip(_ kind: RecordKind, _ fields: [String: String], line: Int = #line) {
    let draft = RecordDraft(kind: kind, fields: fields)
    if let message = draft.validate() { check(false, "\(kind) draft invalid: \(message)", line: line); return }
    do {
        let record = try draft.build()
        let parsedKind = RecordParsers.parse(record).kind
        let back = RecordDraft.from(record: record)
        let rebuilt = try back.build()
        checkEqual(NDEFMessageCodec.encode([rebuilt]), NDEFMessageCodec.encode([record]), "\(kind) draft round trip bytes (parsed as \(parsedKind), back kind \(back.kind))", line: line)
        checkEqual(draft.encodedSize, record.encodedSize, "\(kind) encodedSize", line: line)
        check(!draft.summary.isEmpty, "\(kind) summary not empty", line: line)
    } catch {
        check(false, "\(kind) build threw \(error)", line: line)
    }
}
roundTrip(.text, [DraftKey.text: "Hello there", DraftKey.language: "en"])
roundTrip(.url, [DraftKey.url: "https://example.com/path?q=1"])
roundTrip(.email, [DraftKey.email: "a@b.com", DraftKey.subject: "Sub", DraftKey.body: "Body text"])
roundTrip(.contact, [DraftKey.firstName: "K", DraftKey.lastName: "O", DraftKey.phone: "+1905", DraftKey.email: "k@o.ca"])
roundTrip(.phone, [DraftKey.phone: "+19055550100"])
roundTrip(.sms, [DraftKey.phone: "+19055550100", DraftKey.body: "hi there"])
roundTrip(.geo, [DraftKey.latitude: "43.85", DraftKey.longitude: "-79.33", DraftKey.geoFormat: "geo"])
roundTrip(.geo, [DraftKey.latitude: "43.85", DraftKey.longitude: "-79.33", DraftKey.geoFormat: "apple"])
roundTrip(.address, [DraftKey.address: "1 Main St", DraftKey.addressFormat: "apple"])
roundTrip(.address, [DraftKey.address: "1 Main St", DraftKey.addressFormat: "geo"])
roundTrip(.wifi, [DraftKey.ssid: "Shop", DraftKey.password: "pw12345678", DraftKey.auth: WiFiCredential.Auth.wpa2PSK.rawValue, DraftKey.encryption: WiFiCredential.Encryption.aes.rawValue, DraftKey.hidden: "false"])
roundTrip(.bluetooth, [DraftKey.mac: "AA:BB:CC:DD:EE:FF", DraftKey.name: "Speaker"])
roundTrip(.social, [DraftKey.platform: "x", DraftKey.handle: "katsuma"])
roundTrip(.app, [DraftKey.package: "com.example.app"])
roundTrip(.customURI, [DraftKey.url: "myapp://open?id=1"])
roundTrip(.customMIME, [DraftKey.mime: "text/csv", DraftKey.payloadText: "a,b", DraftKey.payloadIsHex: "false"])
roundTrip(.customMIME, [DraftKey.mime: "application/octet-stream", DraftKey.payloadHex: "01 02 03", DraftKey.payloadIsHex: "true"])
roundTrip(.external, [DraftKey.domain: "example.com", DraftKey.externalType: "thing", DraftKey.payloadText: "x", DraftKey.payloadIsHex: "false"])
roundTrip(.raw, [DraftKey.tnf: "1", DraftKey.type: "54", DraftKey.payloadHex: "02 65 6E 48 69", DraftKey.payloadIsHex: "true"])
roundTrip(.empty, [:])
// Validation
check(RecordDraft(kind: .url, fields: [DraftKey.url: ""]).validate() != nil, "empty url invalid")
check(RecordDraft(kind: .geo, fields: [DraftKey.latitude: "abc", DraftKey.longitude: "1"]).validate() != nil, "bad latitude invalid")
check(RecordDraft(kind: .bluetooth, fields: [DraftKey.mac: "nope"]).validate() != nil, "bad mac invalid")
check(RecordDraft(kind: .wifi, fields: [DraftKey.ssid: ""]).validate() != nil, "empty ssid invalid")
check(RecordDraft(kind: .raw, fields: [DraftKey.payloadHex: "0", DraftKey.payloadIsHex: "true"]).validate() != nil, "odd hex invalid")
check(RecordDraft(kind: .empty).validate() == nil, "empty draft valid")
check(RecordKind.writable.count >= 15, "writable kinds listed")
check(!RecordKind.writable.contains(.unknown) && !RecordKind.writable.contains(.smartPoster), "writable excludes unknown and smart poster")
// Draft from a read record of each kind keeps the kind
checkEqual(RecordDraft.from(record: textRecord).kind, RecordKind.text, "from text")
checkEqual(RecordDraft.from(record: textRecord)[DraftKey.text], "Hello", "from text field")
checkEqual(RecordDraft.from(record: uriRecord).kind, RecordKind.url, "from url")
checkEqual(RecordDraft.from(record: wifiRecord).kind, RecordKind.wifi, "from wifi")
checkEqual(RecordDraft.from(record: wifiRecord)[DraftKey.password], "sashiko123", "from wifi password")
checkEqual(RecordDraft.from(record: RecordBuilders.vcard(card)).kind, RecordKind.contact, "from vcard")
checkEqual(RecordDraft.from(record: RecordBuilders.vcard(card))[DraftKey.organization], "Denim; Goods", "from vcard org")

// MARK: Chip identification
let ntag216 = ChipIdentifier.fromGetVersion(hex("0004040201001303"))
checkEqual(ntag216?.name, "NTAG216", "NTAG216 from GET_VERSION")
checkEqual(ntag216?.totalPages, 231, "NTAG216 pages")
checkEqual(ntag216?.userPageRange, 4...225, "NTAG216 user range")
checkEqual(ntag216?.configPage, 0xE3, "NTAG216 cfg page")
checkEqual(ntag216?.pwdPage, 0xE5, "NTAG216 pwd page")
checkEqual(ntag216?.packPage, 0xE6, "NTAG216 pack page")
checkEqual(ntag216?.dynamicLockPage, 0xE2, "NTAG216 dyn lock")
checkEqual(ntag216?.totalMemoryBytes, 924, "NTAG216 total bytes")
checkEqual(ntag216?.capabilityContainer, hex("E1106D00"), "NTAG216 CC")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004040201000F03"))?.name, "NTAG213", "NTAG213")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004040201000F03"))?.configPage, 0x29, "NTAG213 cfg")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004040201001103"))?.name, "NTAG215", "NTAG215")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004040201001103"))?.configPage, 0x83, "NTAG215 cfg")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004040401000F03"))?.name, "NTAG213F", "NTAG213F")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004030101000B03"))?.family, ChipFamily.ultralightEV1, "UL EV1 11")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004030101000B03"))?.configPage, 0x10, "UL11 cfg")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004030101000E03"))?.configPage, 0x25, "UL21 cfg")
checkEqual(ChipIdentifier.fromGetVersion(hex("0004030101000E03"))?.counterCount, 3, "UL21 counters")
check(ChipIdentifier.fromGetVersion(hex("00050402")) == nil, "short version rejected")
checkEqual(ChipIdentifier.legacyType2(canReadPage16: false, canReadPage42: false).totalPages, 16, "Ultralight 16 pages")
checkEqual(ChipIdentifier.legacyType2(canReadPage16: true, canReadPage42: false).name, "NTAG203", "NTAG203")
checkEqual(ChipIdentifier.legacyType2(canReadPage16: true, canReadPage42: true).family, ChipFamily.ultralightC, "UL C")
let ev1 = ChipIdentifier.fromDESFireVersion(hardware: hex("04010101001805"))
checkEqual(ev1?.name, "MIFARE DESFire EV1 4K", "DESFire EV1 4K")
checkEqual(ev1?.nfcForumType, 4, "DESFire type 4")
checkEqual(ChipIdentifier.fromDESFireVersion(hardware: hex("04010112001A05"))?.name, "MIFARE DESFire EV2 8K", "DESFire EV2 8K")
checkEqual(ChipIdentifier.fromDESFireVersion(hardware: hex("04040230001105"))?.name, "NTAG 424 DNA", "NTAG 424 DNA")
let slix = ChipIdentifier.iso15693(uid: hex("E004010012345678"), icManufacturerCode: 4, icReference: 1, blockSize: 4, totalBlocks: 28)
checkEqual(slix.name, "ICODE SLIX", "ICODE SLIX")
checkEqual(slix.userMemoryBytes, 112, "SLIX user bytes")
checkEqual(slix.nfcForumType, 5, "SLIX type 5")
checkEqual(ChipIdentifier.iso15693(uid: hex("E004010012345678"), icManufacturerCode: 4, icReference: 1, blockSize: 4, totalBlocks: 80).name, "ICODE SLIX2", "ICODE SLIX2")
checkEqual(ChipIdentifier.iso15693(uid: hex("E002230012345678"), icManufacturerCode: 2, icReference: nil, blockSize: 4, totalBlocks: 64).name, "ST25TV02K", "ST25TV02K")
checkEqual(ChipIdentifier.feliCa(systemCode: hex("12FC")).nfcForumType, 3, "FeliCa type 3")

// MARK: TagInfo display
var info = TagInfo(technology: .iso14443A, chip: ntag216!, uid: hex("04583A629567 81"))
info.ndefStatus = .readWrite
info.ndefCapacity = 868
info.ndefUsedBytes = 15
checkEqual(info.typeLine, "ISO 14443-3A (NFC Forum Type 2)", "typeLine")
checkEqual(info.chipLine, "NXP NTAG216", "chipLine")
checkEqual(info.serialLine, "04:58:3A:62:95:67:81", "serialLine")
checkEqual(info.memoryLine, "924 bytes : 231 pages (4 bytes each)", "memoryLine")
checkEqual(info.sizeLine, "15 / 868 bytes (2%)", "sizeLine")
checkEqual(info.atqaLine, "0x0044", "atqaLine")
checkEqual(info.sakLine, "0x00", "sakLine")
checkEqual(info.writableLine, "Yes", "writableLine")

// MARK: MemoryDump
let dump = MemoryDump(flatBytes: hex("00010203 04050607 08"), pageSize: 4, chip: nil)
checkEqual(dump.pages.count, 3, "flat bytes -> 3 pages (last padded or partial)")
checkEqual(dump.pages[1].bytes, hex("04050607"), "page 1 bytes")
checkEqual(dump.flatBytes.prefix(8), hex("0001020304050607"), "flatBytes round trip")

// MARK: Error mapping
checkEqual(NFCEditorError.map(NFCReaderError(.readerSessionInvalidationErrorUserCanceled)), NFCEditorError.cancelled, "map cancel")
check(NFCEditorError.map(NFCReaderError(.readerSessionInvalidationErrorUserCanceled)).isCancellation, "isCancellation")
checkEqual(NFCEditorError.map(NFCReaderError(.readerSessionInvalidationErrorSessionTimeout)), NFCEditorError.timeout, "map timeout")
checkEqual(NFCEditorError.map(NFCReaderError(.readerTransceiveErrorTagConnectionLost)), NFCEditorError.tagLost, "map lost")
checkEqual(NFCEditorError.map(NFCReaderError(.readerTransceiveErrorTagResponseError)), NFCEditorError.nak(nil), "map nak")
checkEqual(NFCEditorError.map(NFCReaderError(.ndefReaderSessionErrorTagNotWritable)), NFCEditorError.readOnly, "map read only")
checkEqual(NFCEditorError.map(CancellationError()), NFCEditorError.cancelled, "map CancellationError")
checkEqual(NFCEditorError.map(NFCEditorError.readOnly), NFCEditorError.readOnly, "passthrough")
check(NFCEditorError.invalidInput("Enter a URL").errorDescription == "Enter a URL.", "sentence period")
check(NFCEditorError.nak(0x04).errorDescription?.contains("0x04") == true, "nak code in message")

// MARK: Codable
do {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    var full = info
    full.records = [uriRecord, textRecord]
    full.dump = dump
    let data = try enc.encode(full)
    let back = try dec.decode(TagInfo.self, from: data)
    checkEqual(back.records.count, 2, "TagInfo codable records")
    checkEqual(back.chip.name, "NTAG216", "TagInfo codable chip")
    checkEqual(back.dump?.pages.count, 3, "TagInfo codable dump")
    let draftData = try enc.encode(RecordDraft(kind: .wifi, fields: [DraftKey.ssid: "x"]))
    checkEqual(try dec.decode(RecordDraft.self, from: draftData).kind, RecordKind.wifi, "RecordDraft codable")
} catch {
    check(false, "codable threw \(error)")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
