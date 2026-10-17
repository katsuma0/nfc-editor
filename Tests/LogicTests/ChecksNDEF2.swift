import Foundation

// Handover Select, buildAll and smart poster drafts. Expected bytes follow the NFC Forum Connection Handover 1.3
// and Smart Poster layouts; vectors.json has no NDEF entries, so the literals are worked out by hand here.
func checkNDEF2() {
    // MARK: Handover Select builder
    let select = RecordBuilders.handoverSelect()
    checkEqual(select.tnf, TypeNameFormat.wellKnown, "Hs tnf")
    checkEqual(select.typeString, "Hs", "Hs type")
    checkEqual(select.payload.first, 0x13, "Hs payload starts with version 1.3")
    checkEqual(select.payload, hex("13 D1 02 04 61 63 01 01 30 00"), "Hs payload bytes")
    checkEqual(NDEFMessageCodec.encode([select]), hex("D1 02 0A 48 73 13 D1 02 04 61 63 01 01 30 00"), "Hs record bytes")
    do {
        let inner = try NDEFMessageCodec.decode(Data(select.payload.dropFirst()))
        checkEqual(inner.count, 1, "Hs wraps one record")
        checkEqual(inner.first?.tnf, TypeNameFormat.wellKnown, "Hs inner record is well known")
        checkEqual(inner.first?.typeString, "ac", "Hs inner record is an alternative carrier")
        checkEqual(inner.first?.payload, hex("01 01 30 00"), "ac payload: active, reference 0, no auxiliary data")
    } catch {
        check(false, "Hs inner message did not decode: \(error)")
    }
    checkEqual(RecordBuilders.handoverSelect(carrierID: "bt").payload, hex("13 D1 02 05 61 63 01 02 62 74 00"), "Hs with a longer carrier ID")

    // MARK: Handover Select parsing
    if let parsed = RecordParsers.handoverSelect(select) {
        checkEqual(parsed.version, 0x13, "Hs parsed version")
        checkEqual(parsed.carriers.count, 1, "Hs parsed carrier count")
        checkEqual(parsed.carriers.first?.reference, "0", "Hs parsed carrier reference")
        checkEqual(parsed.carriers.first?.powerState, 1, "Hs parsed power state")
    } else {
        check(false, "Hs did not parse")
    }
    let selectSummary = RecordParsers.parse(select)
    checkEqual(selectSummary.kind, RecordKind.handover, "Hs kind")
    checkEqual(selectSummary.title, "Handover select", "Hs title")
    checkEqual(selectSummary.detail, "Bluetooth pairing", "Hs detail")
    check(selectSummary.actions.isEmpty, "Hs has no actions")
    checkEqual(selectSummary.systemImage, "arrow.triangle.2.circlepath", "Hs icon")
    check(selectSummary.fields.contains(TagField(label: "Version", value: "1.3", systemImage: "number")), "Hs version field")
    let noCarriers = NDEFRecord(tnf: .wellKnown, typeString: "Hs", payload: hex("13"))
    checkEqual(RecordParsers.handoverSelect(noCarriers)?.carriers.count, 0, "Hs without carriers parses")
    checkEqual(RecordParsers.parse(noCarriers).detail, "Handover", "Hs without carriers detail")
    let broken = NDEFRecord(tnf: .wellKnown, typeString: "Hs", payload: hex("13 D1 02 09 61 63"))
    check(RecordParsers.handoverSelect(broken) == nil, "malformed Hs rejected")
    checkEqual(RecordParsers.parse(broken).kind, RecordKind.handover, "malformed Hs still classed as handover")
    checkEqual(RecordParsers.parse(broken).detail, "Handover", "malformed Hs detail")
    checkEqual(RecordDraft.from(record: select).kind, RecordKind.raw, "Hs comes back as a raw draft")
    check(!RecordKind.writable.contains(.handover), "handover not writable")
    checkEqual(RecordKind.handover.displayName, "Handover select", "handover display name")

    // MARK: buildAll
    let bluetoothFields = [DraftKey.mac: "AA:BB:CC:DD:EE:FF", DraftKey.name: "Speaker"]
    checkEqual(RecordDraft(kind: .bluetooth)[DraftKey.handover], "false", "handover defaults to false")
    do {
        let plain = try RecordDraft.buildAll(RecordDraft(kind: .bluetooth, fields: bluetoothFields))
        checkEqual(plain.count, 1, "buildAll without handover gives one record")
        checkEqual(plain.first?.identifier, Data(), "plain bluetooth record has no ID")

        var paired = RecordDraft(kind: .bluetooth, fields: bluetoothFields)
        paired[DraftKey.handover] = "true"
        let records = try RecordDraft.buildAll(paired)
        checkEqual(records.count, 2, "buildAll with handover gives two records")
        checkEqual(records.first?.typeString, "Hs", "first record is the Handover Select")
        checkEqual(records.last?.typeString, BluetoothOOB.mimeType, "second record is the Bluetooth OOB")
        checkEqual(records.last?.identifier, Data("0".utf8), "second record has ID 0")
        checkEqual(records.last?.payload, plain.first?.payload, "handover keeps the OOB payload")
        let message = NDEFMessageCodec.encode(records)
        checkEqual(message, hex("91020A487313D102046163010130005A2011016170706C69636174696F6E2F766E642E626C7565746F6F74682E65702E6F6F62301100FFEEDDCCBBAA0809537065616B6572"), "handover message bytes")
        checkEqual(paired.encodedSize, message.count, "handover encodedSize counts both records")
        checkEqual(try RecordDraft.buildAll(RecordDraft(kind: .text, fields: [DraftKey.text: "Hi"])).count, 1, "buildAll of text gives one record")

        let back = RecordDraft.from(records: try NDEFMessageCodec.decode(message))
        checkEqual(back.count, 1, "Hs and its carrier come back as one draft")
        checkEqual(back.first?.kind, RecordKind.bluetooth, "collapsed draft is bluetooth")
        checkEqual(back.first?[DraftKey.handover], "true", "collapsed draft keeps handover on")
        if let first = back.first {
            checkEqual(NDEFMessageCodec.encode(try RecordDraft.buildAll(first)), message, "collapsed draft rebuilds the same bytes")
        }
        let separate = RecordDraft.from(records: [select, plain[0]])
        checkEqual(separate.count, 2, "Hs without a matching carrier ID stays separate")
        let mixed = RecordDraft.from(records: [RecordBuilders.text("Hi", language: "en")] + records)
        checkEqual(mixed.map(\.kind), [RecordKind.text, RecordKind.bluetooth], "pair after another record collapses")
    } catch {
        check(false, "buildAll threw \(error)")
    }
    var invalid = RecordDraft(kind: .bluetooth, fields: [DraftKey.mac: "nope"])
    invalid[DraftKey.handover] = "true"
    check((try? RecordDraft.buildAll(invalid)) == nil, "buildAll of an invalid draft throws")
    checkEqual(invalid.encodedSize, 0, "invalid handover draft size is zero")

    // MARK: Smart poster drafts
    check(RecordKind.writable.contains(.smartPoster), "smart poster writable")
    checkEqual(RecordKind.writable.last, RecordKind.smartPoster, "smart poster listed after empty")
    let poster = RecordDraft(kind: .smartPoster, fields: [DraftKey.url: "example.com/shop", DraftKey.text: "Shop", DraftKey.language: "en"])
    check(poster.validate() == nil, "smart poster draft valid")
    do {
        let record = try poster.build()
        checkEqual(NDEFMessageCodec.encode([record]), hex("D10220537091011155046578616D706C652E636F6D2F73686F705101075402656E53686F70"), "smart poster bytes")
        let summary = RecordParsers.parse(record)
        checkEqual(summary.kind, RecordKind.smartPoster, "smart poster parses as smart poster")
        checkEqual(summary.detail, "https://example.com/shop", "smart poster detail")
        checkEqual(RecordParsers.smartPoster(record)?.title, "Shop", "smart poster parsed title")
        let back = RecordDraft.from(record: record)
        checkEqual(back.kind, RecordKind.smartPoster, "smart poster draft from record")
        checkEqual(back[DraftKey.text], "Shop", "smart poster title field")
        checkEqual(back[DraftKey.language], "en", "smart poster language field")
        checkEqual(NDEFMessageCodec.encode([try back.build()]), NDEFMessageCodec.encode([record]), "smart poster round trip bytes")
        checkEqual(try RecordDraft.buildAll(poster).count, 1, "smart poster buildAll gives one record")
        checkEqual(poster.encodedSize, record.encodedSize, "smart poster encodedSize")
    } catch {
        check(false, "smart poster build threw \(error)")
    }
    let untitled = RecordDraft(kind: .smartPoster, fields: [DraftKey.url: "https://example.com"])
    if let record = try? untitled.build(), let parsed = RecordParsers.smartPoster(record) {
        checkEqual(parsed.uri, "https://example.com", "smart poster without title keeps the URL")
        check(parsed.title == nil, "smart poster without title has no title record")
    } else {
        check(false, "smart poster without title did not build")
    }
    check(RecordDraft(kind: .smartPoster, fields: [DraftKey.url: ""]).validate() != nil, "smart poster needs a URL")
    check(RecordDraft(kind: .smartPoster, fields: [DraftKey.url: "https://example.com", DraftKey.text: "Shop", DraftKey.language: "e n"]).validate() != nil, "smart poster rejects a bad language")
}
