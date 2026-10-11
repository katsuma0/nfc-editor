# Release checklist

1. Open the project in Xcode 16 or newer. Pick your team under Signing & Capabilities. If the bundle identifier is taken, change it in both build configurations of the NFCEditor target.
2. Run on a real iPhone. Scan an NTAG tag, write a URL, read it back, open the memory editor, set and remove a password on a tag you do not care about. Everything in Tools touches real hardware and none of it can be tested in the simulator.
3. Replace the app icon if you want. It is the single 1024 x 1024 PNG in `NFCEditor/Assets.xcassets/AppIcon.appiconset/`. Xcode makes every size from it.
4. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the target build settings for each upload.
5. Product, Archive. Distribute App, App Store Connect, Upload.
6. In App Store Connect, create the app with the bundle identifier, then paste in `listing.md`. Screenshots: 6.9 inch display is the only required set (iPhone 16 Pro Max or 17 Pro Max). Take them from the Read details screen, the Write screen with three records, the memory editor, and the Tools list. Six is plenty.
7. App Privacy: Data Not Collected. Age rating: 4+. Privacy policy URL: the hosted copy of `privacy-policy.md`.
8. Paste `review-notes.md` into App Review Information.
9. Submit. First reviews of NFC apps usually take two to four days because the reviewer has to find a tag.

If the build is rejected under 2.5.1 for the Hotspot Configuration entitlement, reply that it is used only for the Join button on Wi-Fi records read from a tag, and point at `Shared/WiFiJoiner.swift`.
