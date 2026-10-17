# What an iPhone can do to an NFC chip, and what this app does about it

Core NFC is the only way an app touches NFC on an iPhone. It works on iPhone 7 and newer, in the foreground, with the system sheet showing, for up to 60 seconds per session. Everything below follows from that. iPad, Apple Watch and Mac have no third party NFC reading at all.

The table is the whole list. "Have" means it shipped in the first version, "Added" means this change, "No" means iOS does not allow it and no app can do it.

## Any tag

| Capability | Status | Notes |
| --- | --- | --- |
| Read NDEF records (Type 2, 3, 4, 5) | Have | Text, URL, email, phone, SMS, location, address, Wi-Fi, Bluetooth, vCard, social, Android app, MIME, external, raw, smart poster |
| Write NDEF records | Have | Several records per tag, reordered, byte count shown before the tap, verified after |
| Write the same records to many tags in one session | Added | "Write to several tags" keeps the sheet open and counts tags until you cancel or the 60 s limit |
| Make a tag read only (lock bits) | Have | Permanent |
| Set only the NDEF read only flag (CC byte 3) | Added | Phones treat the tag as read only, raw page writes still work, cannot be undone either |
| Erase, format, copy tag to tag | Have | |
| Full memory dump, page editor, write a dump back | Have | |
| Write a dump including the serial number pages | Added | Only "magic" clone chips accept it; real chips refuse pages 0 and 1 |
| Save tags and profiles, export and import JSON, export .bin | Have | |
| Export the scan log as CSV | Added | Serial numbers, chips and times from the Read tab |
| Smart poster record (URL plus title) | Added | |
| Bluetooth pairing record wrapped in a Handover Select | Added | What Android expects for tap to pair |
| Shortcuts and Siri | Added | "Read NFC tag" and "Write profile to tag" App Intents; the app opens, the system sheet runs |
| Automations on tag scan | No, use Shortcuts | iOS runs automations from the Shortcuts app's own NFC trigger, apps cannot register one; the About screen explains the setup |
| Read tags in the background | No, iOS does it | iPhone XS and newer open https links from tags on their own; no app code involved |
| Tag emulation, card emulation | No | Core NFC has no emulation. Apple's NFC and SE platform is only for approved partners |
| MIFARE Classic data | No | iOS never exposes the Classic command set. The app shows the serial number and says so |
| Type 1 (Topaz) tags | No | Not in Core NFC's tag reader session |
| Passports, bank cards | Not included | Possible with ISO 7816 and a lot of crypto; it is a different app |

## NTAG and MIFARE Ultralight (ISO 14443-3A, Type 2)

| Capability | Status | Notes |
| --- | --- | --- |
| Identify the chip, memory layout, config pages | Have | NTAG 203, 210, 212, 213, 213F, 213TT, 215, 216, 216F, I2C; Ultralight, C, EV1 |
| Raw commands (GET_VERSION, READ, FAST_READ, WRITE, PWD_AUTH, READ_SIG, READ_CNT) | Have | Advanced commands tool with presets |
| Password: set, remove, read protected pages, attempt limit | Have | NTAG21x, NTAG 210 and 212, Ultralight EV1 |
| Lock the configuration pages for good (CFGLCK) | Added | In the Password tool, behind two confirmations |
| NFC counter: read, enable, disable | Have | |
| Counter only readable with the password (NFC_CNT_PWD_PROT) | Added | |
| UID mirror and counter mirror into a URL | Added | Mirror tool writes a URL with placeholders and sets MIRROR, MIRROR_PAGE and MIRROR_BYTE so the tag fills in its serial number and scan count on every read |
| Lock single pages or page groups (static and dynamic lock bits) | Added | Lock pages tool shows every page's lock state and lets you lock chosen ones, permanently |
| Originality signature: read | Have | |
| Originality signature: verify against NXP's public key | Added | ECDSA on secp128r1 in the app, no network; says genuine, not genuine or no key for this chip |
| NTAG 213TT tamper status | Added | Shown in tag details when the chip is a TT |
| Ultralight C 3DES authentication, set key, protect pages, remove protection | Added | The old 16 byte key tags; the default key BREAKMEIFYOUCAN! is offered |
| Ultralight EV1 three counters | Have | |

## MIFARE DESFire and NTAG DNA (ISO 14443-4, Type 4)

| Capability | Status | Notes |
| --- | --- | --- |
| Identify the chip and version | Have | DESFire D40, EV1, EV2, EV3, Light; NTAG 413 and 424 DNA |
| Read and write NDEF through the ISO file system | Have | |
| Send any APDU | Have | Advanced commands, APDU transport |
| List applications, free memory, file IDs, key settings | Added | Without authentication where the card allows it |
| Authenticate with a DES key (legacy D40 authentication) | Added | Default key is all zeros on a new card |
| Format the card (FormatPICC) | Added | Erases every application, needs the master key |
| Create the NDEF application on a blank card | Added | Application 000001 with ISO name D2760000850101, CC file E103 and NDEF file E104, so a blank DESFire becomes a normal NDEF tag |
| AES authentication, change keys, DNA secure messaging (SUN) | Not included | Needs AES EV2 secure messaging; the key management alone is a project of its own |

## ISO 15693 (ICODE, ST25TV, Tag-it; Type 5)

| Capability | Status | Notes |
| --- | --- | --- |
| Read and write blocks, memory editor, system info | Have | |
| Blocks above 255 (ST25TV16K, 64K) | Added | Extended commands |
| Lock single blocks, see which blocks are locked | Added | Block security status in the memory editor |
| AFI and DSFID: write and lock | Added | Type 5 settings tool |
| ICODE SLIX, SLIX2: passwords, privacy mode, EAS, destroy | Added | Type 5 settings tool and Advanced presets; privacy mode hides the tag until the password is presented |
| ST25TV: present and write passwords | Added | |
| Custom commands with any code A0 to DF | Have | |

## FeliCa (ISO 18092, Type 3)

| Capability | Status | Notes |
| --- | --- | --- |
| Identify, IDm, PMm, system codes | Have | |
| Read and write NDEF (FeliCa Lite-S) | Have | |
| Read and write blocks of a service without encryption | Added | FeliCa tool: service code and block list |
| Any raw FeliCa command | Have | |

## What stays out on purpose

Reading payment cards and passports is possible with Core NFC and deliberately not in this app. Both read other people's documents as easily as your own, and neither is tag editing.
