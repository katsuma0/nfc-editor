import Foundation
import SwiftUI
import CoreNFC

/// Shows the static and dynamic lock bits of an NTAG or Ultralight tag and locks chosen pages for good.
@MainActor
struct LockPagesToolView: View {
    @Environment(AppState.self) private var app
    @State private var state: LockStateResult?
    @State private var selected: Set<Int> = []
    @State private var password = Data()
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                ScanButton("Read lock state", systemImage: "magnifyingglass") {
                    readState()
                }
            } footer: {
                Text("Reads the lock bits of an NTAG or MIFARE Ultralight tag. Each lock bit covers one page or a group of pages, and once set it can never be cleared.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let state {
                summarySection(state)
                groupsSection(state)
                passwordSection
                lockSection
            }
        }
        .navigationTitle("Lock pages")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmationTitle, isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Lock pages", role: .destructive) {
                lockSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alertItem($alert)
    }

    // MARK: Sections

    private func summarySection(_ state: LockStateResult) -> some View {
        Section {
            LabeledContent("Chip", value: state.chipName)
            LabeledContent("Serial number") {
                Text(state.uid.hexString(separator: ":"))
                    .font(.body.monospaced())
            }
            LabeledContent("Locked groups", value: "\(state.groups.filter { $0.locked }.count) of \(state.groups.count)")
        } header: {
            Text("Tag")
        } footer: {
            Text("Read at \(state.readAt.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private func groupsSection(_ state: LockStateResult) -> some View {
        Section {
            ForEach(state.groups) { group in
                groupRow(group)
            }
            if !lockableIDs(state).isEmpty {
                Button(selectAllTitle(state)) {
                    toggleSelectAll(state)
                }
            }
        } header: {
            Text("Pages")
        } footer: {
            Text("Switch on the groups you want to lock. Page 3 holds the capability container; pages 4 and up hold your records.")
        }
    }

    @ViewBuilder
    private func groupRow(_ group: PageLock) -> some View {
        if group.locked {
            LabeledContent {
                Label("Locked", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            } label: {
                pagesLabel(group)
            }
        } else if group.lockable {
            Toggle(isOn: selectionBinding(for: group)) {
                pagesLabel(group)
            }
            .tint(.red)
        } else {
            LabeledContent {
                Text("Cannot be locked")
                    .foregroundStyle(.secondary)
            } label: {
                pagesLabel(group)
            }
        }
    }

    private func pagesLabel(_ group: PageLock) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LockPagesToolView.title(for: group.pages))
            Text(LockPagesToolView.hexRange(group.pages))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var passwordSection: some View {
        Section {
            DisclosureGroup("Password") {
                HexTextField("Password", data: $password, byteCount: 4)
            }
        } footer: {
            Text("Only needed when the tag is password protected.")
        }
    }

    private var lockSection: some View {
        Section {
            ScanButton("Lock selected pages", systemImage: "lock.fill", role: .destructive) {
                confirmLock()
            }
            .disabled(selected.isEmpty)
        } footer: {
            Text("Locking is permanent. Locked pages can never be written again, by this app or any other, and the lock bits can never be cleared. Hold the same tag you read.")
                .foregroundStyle(.red)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived values

    private var selectedGroups: [PageLock] {
        guard let state else { return [] }
        return state.groups.filter { selected.contains($0.id) && !$0.locked && $0.lockable }
    }

    private var selectedPageCount: Int {
        selectedGroups.reduce(0) { $0 + $1.pages.count }
    }

    private var confirmationTitle: String {
        selectedPageCount == 1 ? "Lock 1 page for good?" : "Lock \(selectedPageCount) pages for good?"
    }

    private var confirmationMessage: String {
        let list = selectedGroups.map { LockPagesToolView.shortTitle(for: $0.pages) }.joined(separator: ", ")
        return "Locks \(list). These pages become read only forever. This cannot be undone."
    }

    private func selectAllTitle(_ state: LockStateResult) -> String {
        selected.count == lockableIDs(state).count ? "Clear selection" : "Select every unlocked group"
    }

    private func lockableIDs(_ state: LockStateResult) -> Set<Int> {
        Set(state.groups.filter { !$0.locked && $0.lockable }.map { $0.id })
    }

    private func selectionBinding(for group: PageLock) -> Binding<Bool> {
        Binding(
            get: { selected.contains(group.id) },
            set: { isOn in
                if isOn {
                    selected.insert(group.id)
                } else {
                    selected.remove(group.id)
                }
            }
        )
    }

    private static func title(for pages: ClosedRange<Int>) -> String {
        if pages.count == 1 {
            return pages.lowerBound == 3 ? "Page 3, capability container" : "Page \(pages.lowerBound)"
        }
        return "Pages \(pages.lowerBound) to \(pages.upperBound)"
    }

    private static func shortTitle(for pages: ClosedRange<Int>) -> String {
        pages.count == 1 ? "page \(pages.lowerBound)" : "pages \(pages.lowerBound) to \(pages.upperBound)"
    }

    private static func hexRange(_ pages: ClosedRange<Int>) -> String {
        if pages.count == 1 {
            return hexPage(pages.lowerBound)
        }
        return hexPage(pages.lowerBound) + " to " + hexPage(pages.upperBound)
    }

    private static func hexPage(_ page: Int) -> String {
        let raw = String(max(page, 0), radix: 16, uppercase: true)
        return "0x" + (raw.count >= 2 ? raw : "0" + raw)
    }

    // MARK: Actions

    private func toggleSelectAll(_ state: LockStateResult) {
        let all = lockableIDs(state)
        if selected.count == all.count {
            selected.removeAll()
        } else {
            selected = all
        }
        Haptics.tap()
    }

    private func readState() {
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Lock state read."
                ) { session, tag -> LockStateResult in
                    let (spec, uid) = try await TagOperations.identify(session, tag)
                    let groups = try await TagOperations.lockState(session, tag)
                    return LockStateResult(chipName: spec.name, uid: uid, groups: groups, readAt: Date())
                }
                state = result
                selected = []
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func confirmLock() {
        guard !selectedGroups.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Choose at least one group of pages to lock."))
            return
        }
        guard password.isEmpty || password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        showingConfirmation = true
    }

    private func lockSelected() {
        guard let state else { return }
        let groups = selectedGroups.map { group -> PageLock in
            var marked = group
            marked.locked = true
            return marked
        }
        guard !groups.isEmpty else { return }
        let expectedUID = state.uid
        let key: Data? = password.count == 4 ? password : nil
        let lockedIDs = Set(groups.map { $0.id })
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the same tag.",
                    successMessage: "Pages locked."
                ) { session, tag -> Void in
                    // Lock bits are permanent, so they only go to the tag whose state the user just reviewed.
                    let (_, uid) = try await TagOperations.identify(session, tag)
                    guard uid == expectedUID else {
                        throw NFCEditorError.invalidInput("This is a different tag. Read its lock state first.")
                    }
                    try await TagOperations.lockPages(session, tag, groups: groups, password: key)
                }
                if var current = self.state {
                    for index in current.groups.indices where lockedIDs.contains(current.groups[index].id) {
                        current.groups[index].locked = true
                    }
                    self.state = current
                }
                selected = []
                Haptics.success()
                alert = AlertItem.success("The pages are locked. Read the lock state again to check.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

private struct LockStateResult: Hashable, Sendable {
    var chipName: String
    var uid: Data
    var groups: [PageLock]
    var readAt: Date
}
