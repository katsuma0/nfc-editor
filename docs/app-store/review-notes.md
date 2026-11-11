# Notes for App Review

Paste everything below the line into the Notes field under App Review Information, and into the reply to App Review. Attach the screen recording to the reply.

---

1. Screen recording

Attached. Recorded on an iPhone running the latest iOS. It starts from the Home Screen, launches the app, scans an NTAG215 sticker, writes a link to it, reads it back, then shows the Tools and Settings screens. The app has no accounts, no user-generated content and no paid content, so there is nothing else to show.

2. Purpose and audience

NFC Editor reads, writes and edits NFC tags: the small stickers, cards and key fobs used for links, contact cards, Wi-Fi details and access badges. It is for anyone who buys blank NFC tags and wants to put something on them, and for people who need to see what is on a tag they already have, such as makers, small businesses handing out tap-to-open business cards, and hobbyists. It shows the chip type, serial number, memory and every record, lets you write links, contacts, Wi-Fi networks and other records, and has tools to erase, copy, lock, format and password-protect a tag. Tools other NFC apps charge for, such as the memory editor and raw commands, are free here.

3. How to test

You need one physical NFC tag. Any NTAG213, NTAG215 or NTAG216 sticker works. There is no login.

- Read: open the Read tab, tap Scan tag for details, hold the tag to the top edge of the iPhone. The details screen lists the chip, serial number, memory and records.
- Write: open the Write tab, tap Add a record, pick URL, type any address, tap Write to tag, hold the tag. Scan it again on the Read tab to see the link.
- Tools: the everyday tools are listed first. Tap Show advanced tools for the memory editor, raw commands and chip-specific tools. Lock tag is permanent and asks twice before it does anything.
- Settings: the gear button on the Read or Tools tab. Appearance switches between System, Light and Dark.

4. External services

None. The app has no server, no account system, no analytics, no ads, no payments and no AI service. Everything runs on the iPhone with Apple's Core NFC framework. The app uses NEHotspotConfiguration only when the user taps Join on a Wi-Fi record read from a tag; it never joins a network on its own.

5. Regional differences

None. The app works the same in every region.

6. Regulated industry or third-party material

Not applicable. The app is a general NFC tag utility and does not read payment cards, passports or other identity documents. MIFARE, NTAG and ICODE are named only to identify chip types and are credited as trademarks of NXP B.V. in the About screen.
