# NFC Editor

A native iOS app for reading, writing and editing NFC tags. It covers what the usual tag apps do, including the parts they charge for, and it stays free. Core NFC only. No accounts, no analytics, nothing leaves the phone.

## What it does

Read. Hold a tag to the top of the phone and you get the chip type (NTAG213, NTAG216, Ultralight EV1, DESFire, ICODE, ST25TV, FeliCa), the serial number, the memory layout, the NDEF records, a full page by page memory dump, whether a password is set, the scan counter and the NXP signature.

Write. Text, link, email, phone, SMS, contact card, location, street address, Wi-Fi network, Bluetooth device, social profile, Android app link, custom URI, custom MIME, external type, raw record, empty record. Several records on one tag, reorderable. The app shows the byte count before you tap, reads the tag back after the write to confirm it, and can lock the tag afterwards if you ask it to.

Tools. Erase, copy tag to tag, lock, memory editor (edit one page at a time), format, set or remove an NTAG password, send raw commands (MIFARE native, ISO 7816 APDU, ISO 15693 custom, FeliCa), write a saved dump back to a tag, read and toggle the NTAG counter, read the signature.

Saved. Scanned tags and write profiles, searchable, exported and imported as JSON. Memory dumps export as .bin.

## Build

1. Open `NFCEditor.xcodeproj` in Xcode 16 or newer.
2. Select the NFCEditor target, then Signing & Capabilities, and pick your team. Change the bundle identifier if `ca.katsuma.nfceditor` is taken on your account.
3. Plug in an iPhone 7 or newer running iOS 17 or newer. NFC does not run in the simulator, so the Read button is disabled there.
4. Run.

The entitlements file already asks for Near Field Communication Tag Reading (NDEF and TAG formats) and Hotspot Configuration. Xcode registers both on the App ID when you pick a team. If it complains, add the two capabilities by hand under Signing & Capabilities and it will stop.

There is no package dependency and no build script. Every source file under `NFCEditor/` is in the target through Xcode 16's synchronized folder, so adding a file to the folder adds it to the build.

## Layout

```
NFCEditor/
  NDEF/      NDEF message codec, record builders and parsers, vCard, Wi-Fi, Bluetooth. Foundation only.
  NFC/       Core NFC session wrapper, chip identification, NTAG and ISO 15693 commands, tag operations.
  Read/      Scan screen, tag details, record details.
  Write/     Record queue, editors for every record kind, write options.
  Tools/     One screen per tool.
  Saved/     JSON store for saved tags and profiles.
  Settings/  Settings and About.
  Shared/    Small shared views and helpers.
docs/        App Store listing, privacy policy, review notes, release checklist, architecture.
```

`docs/ARCHITECTURE.md` explains how a scan flows through the layers.

## Limits

iOS gives apps no way to read MIFARE Classic data blocks or to emulate a tag, so NFC Editor does not do either. It reports a Classic tag's serial number and stops there. Ultralight C 3DES authentication and DESFire authenticated commands are not implemented; DESFire NDEF reads work.

## License

MIT. See `LICENSE`.
