import Foundation
import SwiftUI
import CoreNFC

/// ISO 15693 (NFC Forum Type 5) settings: AFI, DSFID and block locks for any tag, plus the
/// password, privacy, EAS and destroy features of ICODE SLIX chips and the ST25TV passwords.
@MainActor
struct Type5ToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case slix = "ICODE SLIX"
        case st = "ST25TV"

        var id: String { rawValue }
    }

    private enum Confirmation: Hashable, Identifiable {
        case lockAFI, lockDSFID, lockBlocks, slixPassword, privacyOn, destroy, stPassword

        var id: Self { self }
    }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .settings
    @State private var reading: Type5Reading?

    @State private var afi = Data()
    @State private var lockAFI = false
    @State private var dsfid = Data()
    @State private var lockDSFID = false
    @State private var lockFrom = 0
    @State private var lockTo = 0

    @State private var slixIdentifier: SLIXPassword = .read
    @State private var slixCurrent = Data()
    @State private var slixNew = Data()
    @State private var privacyOn = true
    @State private var privacyPassword = Data()
    @State private var easOn = true
    @State private var easPassword = Data()
    @State private var destroyPassword = Data()

    @State private var stNumber = 0
    @State private var stCurrent = Data()
    @State private var stNew = Data()

    @State private var confirmation: Confirmation?
    @State private var showingDestroyFinal = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Picker("Chip", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(modeFooter)
            }

            switch mode {
            case .settings:
                settingsSections
            case .slix:
                slixSections
            case .st:
                stSections
            }
        }
        .navigationTitle("Type 5 settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lockFrom) { _, newValue in
            if lockTo < newValue {
                lockTo = newValue
            }
        }
        .onChange(of: lockTo) { _, newValue in
            if lockFrom > newValue {
                lockFrom = newValue
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible, presenting: confirmation) { item in
            Button(actionTitle(for: item), role: actionRole(for: item)) {
                perform(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(confirmationMessage(for: item))
        }
        .alert("Destroy the tag for good?", isPresented: $showingDestroyFinal) {
            Button("Destroy tag", role: .destructive) {
                destroyTag()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the last question. The tag you scan next stops answering every reader, forever.")
        }
        .alertItem($alert)
    }

    private var modeFooter: String {
        switch mode {
        case .settings:
            return "AFI, DSFID and block locks work on every ISO 15693 tag."
        case .slix:
            return "For NXP ICODE SLIX, SLIX2 and DNA tags. Other chips refuse these commands."
        case .st:
            return "For ST25TV tags from STMicroelectronics. Other chips refuse these commands."
        }
    }

    // MARK: Settings

    @ViewBuilder
    private var settingsSections: some View {
        Section {
            ScanButton("Read settings", systemImage: "magnifyingglass") {
                readSettings()
            }
        } footer: {
            Text("Reads the DSFID, the AFI, the memory size and which blocks are locked.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        if let reading {
            readingSection(reading)
        }

        Section {
            HexTextField("AFI", data: $afi, byteCount: 1)
            Toggle("Lock the AFI", isOn: $lockAFI)
                .tint(.red)
        } header: {
            Text("AFI")
        } footer: {
            Text("The application family identifier tells readers what kind of item the tag is on. 00 means any. Locking makes the value permanent.")
        }
        Section {
            ScanButton("Write AFI", systemImage: "square.and.pencil") {
                requestWriteAFI()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            HexTextField("DSFID", data: $dsfid, byteCount: 1)
            Toggle("Lock the DSFID", isOn: $lockDSFID)
                .tint(.red)
        } header: {
            Text("DSFID")
        } footer: {
            Text("The data storage format identifier is one byte that says how the memory is organized. Most readers ignore it. Locking makes the value permanent.")
        }
        Section {
            ScanButton("Write DSFID", systemImage: "square.and.pencil") {
                requestWriteDSFID()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            Stepper("From block \(lockFrom)", value: $lockFrom, in: 0...maxBlock)
            Stepper("To block \(lockTo)", value: $lockTo, in: 0...maxBlock)
        } header: {
            Text("Lock blocks")
        } footer: {
            Text("Locked blocks can never be written again, by any reader. Block 0 holds the capability container. Read the settings first so the steppers match the tag's size.")
                .foregroundStyle(.red)
        }
        Section {
            ScanButton(lockBlocksTitle, systemImage: "lock.fill", role: .destructive) {
                requestLockBlocks()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func readingSection(_ reading: Type5Reading) -> some View {
        let settings = reading.settings
        let lockedCount = settings.lockedBlocks.filter { $0 }.count
        return Section {
            LabeledContent("DSFID", value: Type5ToolView.byteLabel(settings.dsfid))
            LabeledContent("AFI", value: Type5ToolView.byteLabel(settings.afi))
            LabeledContent("Block size", value: ByteFormatter.bytes(settings.blockSize))
            LabeledContent("Blocks", value: "\(settings.totalBlocks)")
            LabeledContent("Memory", value: ByteFormatter.bytes(settings.blockSize * settings.totalBlocks))
            if settings.lockedBlocks.isEmpty {
                LabeledContent("Locked blocks", value: "Not reported")
            } else {
                LabeledContent("Locked blocks", value: "\(lockedCount)")
                if lockedCount > 0 {
                    Text("Locked: blocks " + Type5ToolView.lockedRanges(settings.lockedBlocks))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if settings.isSLIX {
                Label("ICODE SLIX family. Its passwords, privacy and EAS are under ICODE SLIX above.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if settings.isST {
                Label("ST25TV chip. Its passwords are under ST25TV above.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tag")
        } footer: {
            Text(readingFooter(reading))
        }
    }

    private func readingFooter(_ reading: Type5Reading) -> String {
        var text = "Read at \(reading.readAt.formatted(date: .omitted, time: .shortened))."
        let settings = reading.settings
        if !settings.lockedBlocks.isEmpty && settings.lockedBlocks.count < settings.totalBlocks {
            text += " Lock state shown for the first \(settings.lockedBlocks.count) blocks."
        }
        return text
    }

    private var maxBlock: Int {
        guard let reading, reading.settings.totalBlocks > 0 else { return 255 }
        return reading.settings.totalBlocks - 1
    }

    private var lockBlocksTitle: String {
        lockFrom == lockTo ? "Lock block \(lockFrom)" : "Lock blocks \(lockFrom) to \(lockTo)"
    }

    // MARK: ICODE SLIX

    @ViewBuilder
    private var slixSections: some View {
        Section {
            Picker("Password", selection: $slixIdentifier) {
                ForEach(SLIXPassword.allCases, id: \.self) { item in
                    Text(Type5ToolView.title(for: item)).tag(item)
                }
            }
            HexTextField("Current password", data: $slixCurrent, byteCount: 4)
            HexTextField("New password", data: $slixNew, byteCount: 4)
        } header: {
            Text("Passwords")
        } footer: {
            Text("Each SLIX password is 4 bytes and guards one feature: reading, writing, privacy mode, destroy, or EAS and AFI. Changing a password needs the current one. Check the tag's datasheet for its default passwords.")
        }
        Section {
            ScanButton("Set password", systemImage: "key") {
                requestSLIXPassword()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        Section {
            ScanButton("Present password", systemImage: "checkmark.shield") {
                presentSLIXPassword()
            }
        } footer: {
            Text("Present password sends the current password and tells you whether the tag accepts it. The tag stays unlocked only while it has power, which ends with the scan.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            Toggle("Privacy mode", isOn: $privacyOn)
            HexTextField("Privacy password", data: $privacyPassword, byteCount: 4)
        } header: {
            Text("Privacy")
        } footer: {
            Text("In privacy mode the tag hides its memory and serial number until the privacy password is presented. Leaving privacy mode only lasts until the tag next loses power, so it hides again once it leaves the field.")
        }
        Section {
            ScanButton(privacyOn ? "Turn privacy on" : "Leave privacy mode", systemImage: privacyOn ? "eye.slash" : "eye") {
                requestPrivacy()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            Toggle("EAS alarm", isOn: $easOn)
            DisclosureGroup("EAS and AFI password") {
                HexTextField("Password", data: $easPassword, byteCount: 4)
            }
        } header: {
            Text("EAS")
        } footer: {
            Text("EAS is the shop anti-theft bit: with it on, security gates sound for the tag. Enter the EAS and AFI password only if the tag protects EAS with one.")
        }
        Section {
            ScanButton(easOn ? "Turn EAS on" : "Turn EAS off", systemImage: "bell") {
                setEAS()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        Section {
            ScanButton("Test EAS alarm", systemImage: "bell.badge") {
                testEAS()
            }
        } footer: {
            Text("Asks the tag for its EAS alarm answer. Only a tag with EAS on replies.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            HexTextField("Destroy password", data: $destroyPassword, byteCount: 4)
        } header: {
            Text("Destroy")
        } footer: {
            Text("Destroy switches the tag off forever. It never answers any reader again and nothing can bring it back.")
                .foregroundStyle(.red)
        }
        Section {
            ScanButton("Destroy tag", systemImage: "xmark.octagon", role: .destructive) {
                requestDestroy()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: ST25TV

    @ViewBuilder
    private var stSections: some View {
        Section {
            Picker("Password", selection: $stNumber) {
                ForEach(0..<4, id: \.self) { number in
                    Text(Type5ToolView.stTitle(for: number)).tag(number)
                }
            }
            HexTextField("Current password", data: $stCurrent, byteCount: 8)
        } header: {
            Text("Password")
        } footer: {
            Text("ST25TV passwords are 8 bytes. New chips use 8 zero bytes. Check the chip's datasheet for what each password guards.")
        }
        Section {
            ScanButton("Present password", systemImage: "checkmark.shield") {
                presentSTPassword()
            }
        } footer: {
            Text("Tells you whether the tag accepts the password. The tag stays unlocked only while it has power, which ends with the scan.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            HexTextField("New password", data: $stNew, byteCount: 8)
        } header: {
            Text("New password")
        } footer: {
            Text("The tag only takes a new password right after the current one, so both are sent in the same scan. Write the new password down first.")
        }
        Section {
            ScanButton("Write password", systemImage: "key") {
                requestSTPassword()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Labels

    private static func byteLabel(_ value: Int?) -> String {
        guard let value else { return "Not reported" }
        return "0x" + UInt8(truncatingIfNeeded: value).hex
    }

    /// "0 to 3, 7, 10 to 12" from one flag per block.
    private static func lockedRanges(_ locked: [Bool]) -> String {
        var parts: [String] = []
        var start: Int?
        for (index, isLocked) in locked.enumerated() {
            if isLocked {
                if start == nil {
                    start = index
                }
            } else if let first = start {
                parts.append(rangeLabel(first, index - 1))
                start = nil
            }
        }
        if let first = start {
            parts.append(rangeLabel(first, locked.count - 1))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    private static func rangeLabel(_ first: Int, _ last: Int) -> String {
        first == last ? "\(first)" : "\(first) to \(last)"
    }

    private static func title(for password: SLIXPassword) -> String {
        switch password {
        case .read: return "Read"
        case .write: return "Write"
        case .privacy: return "Privacy"
        case .destroy: return "Destroy"
        case .easAFI: return "EAS and AFI"
        }
    }

    /// The password's name inside a sentence, "the read password".
    private static func passwordName(for password: SLIXPassword) -> String {
        switch password {
        case .read: return "read"
        case .write: return "write"
        case .privacy: return "privacy"
        case .destroy: return "destroy"
        case .easAFI: return "EAS and AFI"
        }
    }

    private static func stTitle(for number: Int) -> String {
        switch number {
        case 0: return "0, configuration"
        case 1: return "1, area 1"
        case 2: return "2, area 2"
        default: return "\(number)"
        }
    }

    // MARK: Confirmations

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { isPresented in
                if !isPresented {
                    confirmation = nil
                }
            }
        )
    }

    private var confirmationTitle: String {
        guard let confirmation else { return "" }
        switch confirmation {
        case .lockAFI: return "Write and lock the AFI?"
        case .lockDSFID: return "Write and lock the DSFID?"
        case .lockBlocks: return lockFrom == lockTo ? "Lock block \(lockFrom) for good?" : "Lock blocks \(lockFrom) to \(lockTo) for good?"
        case .slixPassword: return "Change the \(Type5ToolView.passwordName(for: slixIdentifier)) password?"
        case .privacyOn: return "Turn privacy mode on?"
        case .destroy: return "Destroy this tag?"
        case .stPassword: return "Change password \(stNumber)?"
        }
    }

    private func confirmationMessage(for item: Confirmation) -> String {
        switch item {
        case .lockAFI:
            return "The AFI becomes \(afi.hexString()) forever. It can never be changed again."
        case .lockDSFID:
            return "The DSFID becomes \(dsfid.hexString()) forever. It can never be changed again."
        case .lockBlocks:
            return lockFrom == lockTo
                ? "This block becomes read only forever. This cannot be undone."
                : "These blocks become read only forever. This cannot be undone."
        case .slixPassword:
            return "The tag will answer to \(slixNew.hexString(separator: " ")) from now on. Write it down first; it cannot be read back."
        case .privacyOn:
            return "The tag hides until the privacy password \(privacyPassword.hexString(separator: " ")) is presented. Without that password you cannot use the tag again."
        case .destroy:
            return "Destroy is permanent. The tag never answers any reader again."
        case .stPassword:
            return "Password \(stNumber) becomes \(stNew.hexString(separator: " ")). Write it down first; it cannot be read back."
        }
    }

    private func actionTitle(for item: Confirmation) -> String {
        switch item {
        case .lockAFI: return "Write and lock"
        case .lockDSFID: return "Write and lock"
        case .lockBlocks: return lockFrom == lockTo ? "Lock block" : "Lock blocks"
        case .slixPassword: return "Set password"
        case .privacyOn: return "Turn privacy on"
        case .destroy: return "Continue"
        case .stPassword: return "Write password"
        }
    }

    private func actionRole(for item: Confirmation) -> ButtonRole? {
        switch item {
        case .slixPassword, .stPassword: return nil
        default: return .destructive
        }
    }

    private func perform(_ item: Confirmation) {
        switch item {
        case .lockAFI: writeAFI()
        case .lockDSFID: writeDSFID()
        case .lockBlocks: lockBlocks()
        case .slixPassword: setSLIXPassword()
        case .privacyOn: setPrivacy()
        case .destroy: askFinalDestroyConfirmation()
        case .stPassword: writeSTPassword()
        }
    }

    // MARK: Actions

    /// Every write here follows the same pattern: one scan, a success alert, and silence when the user cancels.
    private func runOperation(
        successMessage: String,
        doneMessage: String,
        onSuccess: @escaping @MainActor () -> Void = {},
        body: @escaping @Sendable (NFCTagReaderSession, NFCTag) async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: successMessage,
                    body: body
                )
                onSuccess()
                Haptics.success()
                alert = AlertItem.success(doneMessage)
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func invalid(_ message: String) {
        alert = AlertItem(error: NFCEditorError.invalidInput(message))
    }

    private func readSettings() {
        Task { @MainActor in
            do {
                let settings = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Settings read."
                ) { session, tag in
                    try await TagOperations.type5Settings(session, tag)
                }
                reading = Type5Reading(settings: settings, readAt: Date())
                if let value = settings.afi {
                    afi = Data([UInt8(truncatingIfNeeded: value)])
                }
                if let value = settings.dsfid {
                    dsfid = Data([UInt8(truncatingIfNeeded: value)])
                }
                let last = max(settings.totalBlocks - 1, 0)
                lockFrom = min(lockFrom, last)
                lockTo = min(lockTo, last)
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func requestWriteAFI() {
        guard afi.count == 1 else {
            invalid("Enter the AFI as one byte, for example 00.")
            return
        }
        if lockAFI {
            confirmation = .lockAFI
        } else {
            writeAFI()
        }
    }

    private func writeAFI() {
        guard let value = afi.first else { return }
        let lock = lockAFI
        runOperation(
            successMessage: lock ? "AFI written and locked." : "AFI written.",
            doneMessage: lock ? "The AFI is now 0x\(value.hex) and locked." : "The AFI is now 0x\(value.hex).",
            onSuccess: {
                lockAFI = false
                updateReading { $0.afi = Int(value) }
            }
        ) { session, tag in
            try await TagOperations.type5WriteAFI(session, tag, afi: value, lock: lock)
        }
    }

    private func requestWriteDSFID() {
        guard dsfid.count == 1 else {
            invalid("Enter the DSFID as one byte, for example 00.")
            return
        }
        if lockDSFID {
            confirmation = .lockDSFID
        } else {
            writeDSFID()
        }
    }

    private func writeDSFID() {
        guard let value = dsfid.first else { return }
        let lock = lockDSFID
        runOperation(
            successMessage: lock ? "DSFID written and locked." : "DSFID written.",
            doneMessage: lock ? "The DSFID is now 0x\(value.hex) and locked." : "The DSFID is now 0x\(value.hex).",
            onSuccess: {
                lockDSFID = false
                updateReading { $0.dsfid = Int(value) }
            }
        ) { session, tag in
            try await TagOperations.type5WriteDSFID(session, tag, dsfid: value, lock: lock)
        }
    }

    private func requestLockBlocks() {
        guard lockFrom <= lockTo else {
            invalid("The first block must not be after the last one.")
            return
        }
        confirmation = .lockBlocks
    }

    private func lockBlocks() {
        guard lockFrom <= lockTo else { return }
        let blocks = Array(lockFrom...lockTo)
        let count = blocks.count
        runOperation(
            successMessage: count == 1 ? "Block locked." : "Blocks locked.",
            doneMessage: count == 1 ? "Block \(blocks[0]) is now read only." : "\(count) blocks are now read only.",
            onSuccess: {
                updateReading { settings in
                    for block in blocks where block < settings.lockedBlocks.count {
                        settings.lockedBlocks[block] = true
                    }
                }
            }
        ) { session, tag in
            try await TagOperations.type5LockBlocks(session, tag, blocks: blocks)
        }
    }

    private func updateReading(_ change: (inout Type5Settings) -> Void) {
        guard var current = reading else { return }
        change(&current.settings)
        reading = current
    }

    private func requestSLIXPassword() {
        // WRITE PASSWORD is refused unless the same password was presented with SET PASSWORD first.
        guard slixCurrent.count == 4 else {
            invalid("Enter the current 4-byte password. The tag only takes a new one after the current one.")
            return
        }
        guard slixNew.count == 4 else {
            invalid("Enter a new 4-byte password.")
            return
        }
        confirmation = .slixPassword
    }

    private func setSLIXPassword() {
        let identifier = slixIdentifier
        guard slixCurrent.count == 4 else { return }
        let current = slixCurrent
        let newPassword = slixNew
        let name = Type5ToolView.passwordName(for: identifier)
        runOperation(
            successMessage: "Password set.",
            doneMessage: "The \(name) password is now \(newPassword.hexString(separator: " ")). Keep it somewhere safe.",
            onSuccess: {
                slixCurrent = newPassword
                slixNew = Data()
            }
        ) { session, tag in
            try await TagOperations.slixSetPassword(session, tag, identifier: identifier, currentPassword: current, newPassword: newPassword)
        }
    }

    private func presentSLIXPassword() {
        guard slixCurrent.count == 4 else {
            invalid("Enter the current 4-byte password.")
            return
        }
        let identifier = slixIdentifier
        let password = slixCurrent
        runOperation(
            successMessage: "Password accepted.",
            doneMessage: "The tag accepted the \(Type5ToolView.passwordName(for: identifier)) password."
        ) { session, tag in
            try await TagOperations.slixPresentPassword(session, tag, identifier: identifier, password: password)
        }
    }

    private func requestPrivacy() {
        guard privacyPassword.count == 4 else {
            invalid("Enter the 4-byte privacy password.")
            return
        }
        if privacyOn {
            confirmation = .privacyOn
        } else {
            setPrivacy()
        }
    }

    private func setPrivacy() {
        let enabled = privacyOn
        let password = privacyPassword
        runOperation(
            successMessage: enabled ? "Privacy mode on." : "Privacy mode left.",
            doneMessage: enabled
                ? "The tag is in privacy mode. Present the privacy password to use it again."
                : "The tag left privacy mode until it next loses power. Once it leaves the field it hides again."
        ) { session, tag in
            try await TagOperations.slixSetPrivacy(session, tag, enabled: enabled, password: password)
        }
    }

    private func setEAS() {
        guard easPassword.isEmpty || easPassword.count == 4 else {
            invalid("The EAS and AFI password must be 4 bytes. Leave it empty if EAS is not protected.")
            return
        }
        let enabled = easOn
        let password: Data? = easPassword.count == 4 ? easPassword : nil
        runOperation(
            successMessage: enabled ? "EAS on." : "EAS off.",
            doneMessage: enabled ? "EAS is on. Security gates now sound for this tag." : "EAS is off."
        ) { session, tag in
            if let password {
                try await TagOperations.slixPresentPassword(session, tag, identifier: .easAFI, password: password)
            }
            try await TagOperations.slixSetEAS(session, tag, enabled: enabled)
        }
    }

    private func testEAS() {
        Task { @MainActor in
            do {
                let sounding = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "EAS checked."
                ) { session, tag in
                    try await TagOperations.slixEASAlarm(session, tag)
                }
                Haptics.success()
                alert = AlertItem(
                    title: sounding ? "EAS is on" : "EAS is off",
                    message: sounding
                        ? "The tag answered the EAS alarm. Security gates would sound."
                        : "The tag did not answer the EAS alarm."
                )
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func requestDestroy() {
        guard destroyPassword.count == 4 else {
            invalid("Enter the 4-byte destroy password.")
            return
        }
        confirmation = .destroy
    }

    /// The second question waits for the first dialog to finish closing, or UIKit drops it.
    private func askFinalDestroyConfirmation() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            showingDestroyFinal = true
        }
    }

    private func destroyTag() {
        guard destroyPassword.count == 4 else {
            invalid("Enter the 4-byte destroy password.")
            return
        }
        let password = destroyPassword
        runOperation(
            successMessage: "Tag destroyed.",
            doneMessage: "The tag is destroyed and will not answer again.",
            onSuccess: {
                destroyPassword = Data()
            }
        ) { session, tag in
            try await TagOperations.slixDestroy(session, tag, password: password)
        }
    }

    private func presentSTPassword() {
        guard stCurrent.count == 8 else {
            invalid("Enter the current 8-byte password.")
            return
        }
        let number = UInt8(stNumber)
        let password = stCurrent
        runOperation(
            successMessage: "Password accepted.",
            doneMessage: "The tag accepted password \(number)."
        ) { session, tag in
            try await TagOperations.stPresentPassword(session, tag, number: number, password: password)
        }
    }

    private func requestSTPassword() {
        guard stCurrent.count == 8 else {
            invalid("Enter the current 8-byte password. New chips use 8 zero bytes.")
            return
        }
        guard stNew.count == 8 else {
            invalid("Enter a new 8-byte password.")
            return
        }
        confirmation = .stPassword
    }

    private func writeSTPassword() {
        let number = UInt8(stNumber)
        let current = stCurrent
        let newPassword = stNew
        runOperation(
            successMessage: "Password written.",
            doneMessage: "Password \(number) is now \(newPassword.hexString(separator: " ")). Keep it somewhere safe.",
            onSuccess: {
                stCurrent = newPassword
                stNew = Data()
            }
        ) { session, tag in
            try await TagOperations.stPresentPassword(session, tag, number: number, password: current)
            try await TagOperations.stWritePassword(session, tag, number: number, password: newPassword)
        }
    }
}

private struct Type5Reading: Hashable {
    var settings: Type5Settings
    var readAt: Date
}
