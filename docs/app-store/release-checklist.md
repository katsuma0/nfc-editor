# Release checklist

Everything here happens on the Mac, in Xcode and in App Store Connect. Budget an hour for the first upload, most of it waiting.

## 1. Build on the iPhone

1. `cd` into the project folder, then `git checkout main && git pull`, then `open NFCEditor.xcodeproj`.
2. Signing & Capabilities on the NFCEditor target: pick your team, leave Automatically manage signing on. Xcode registers `ca.katsuma.nfceditor` with the NFC Tag Reading and Hotspot Configuration capabilities on its own.
3. Pick the iPhone in the device menu, Cmd+Shift+K, Cmd+R.
4. Scan a tag, write a URL, read it back, set and remove a password on a spare tag, switch Appearance between Light and Dark in Settings. None of the NFC parts work in the simulator.

## 2. Create the app in App Store Connect

appstoreconnect.apple.com, Apps, the plus button, New App.

- Platform: iOS
- Name: NFC Editor (runner up if taken: Tag Editor: NFC Read & Write)
- Primary language: English (Canada)
- Bundle ID: ca.katsuma.nfceditor
- SKU: nfceditor-001
- User access: Full Access

## 3. Archive and upload

1. In Xcode's device menu pick Any iOS Device (arm64), not the phone.
2. Product, Archive. The Organizer opens when it is done.
3. Distribute App, App Store Connect, Upload. Keep every default.
4. Processing takes 10 to 30 minutes. Apple emails when the build is ready.

For each later upload, raise the Build number (CURRENT_PROJECT_VERSION) by one, and the Version (MARKETING_VERSION) when the change is worth a new version.

## 4. Fill in the listing

On the 1.0 version page, paste from `listing.md`: promotional text, description, keywords, support URL, copyright. Under App Information set the subtitle, Utilities as the primary category, Developer Tools as the secondary.

## 5. Screenshots

Only the 6.9 inch set is required (1320 x 2868). Run the app on the iPhone 17 Pro Max simulator and press Cmd+S on each screen; the files land on the Desktop. Six is plenty:

1. Read tab with a few recent scans (scan real tags on the phone first, or use the Saved tab).
2. Write tab with three records queued.
3. The Add a record list.
4. Tools with advanced tools shown.
5. Memory editor.
6. Settings in Dark appearance.

## 6. Privacy, age, price

- App Privacy: Data Not Collected. Privacy policy URL: https://katsuma.ca/nfc-editor/privacy.html. Publish.
- Age rating: No to every question, 4+.
- Pricing and Availability: Free. All countries, or Canada only to start.

## 7. App Review

- Build: pick the one you uploaded.
- Sign-in required: off.
- Contact: your name, phone and email.
- Notes: paste `review-notes.md`.
- Export compliance does not come up; Info.plist already declares no non-exempt encryption. The 3DES and ECDSA code only authenticates to tags, which is exempt.

## 8. Submit

Add for Review, then Submit to App Review. NFC apps usually take one to four days because the reviewer has to find a tag.

If the build is rejected under 2.5.1 for the Hotspot Configuration entitlement, reply that it is used only for the Join button on Wi-Fi records read from a tag, and point at `Shared/WiFiJoiner.swift`.
