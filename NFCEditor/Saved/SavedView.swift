import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Saved tab: tags kept from scans and profiles ready to write again.
@MainActor
struct SavedView: View {
    @Environment(AppState.self) private var app
    @State private var path = NavigationPath()
    @State private var selectedKind: SavedItem.Kind = .tag
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var alert: AlertItem?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                kindPicker
                content
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Saved")
            .navigationDestination(for: UUID.self) { id in
                SavedItemDetailView(itemID: id)
            }
            .searchable(text: $searchText, prompt: "Search by name or serial")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        createProfile()
                    } label: {
                        Label("New profile", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alertItem($alert)
        }
    }

    // MARK: Layout

    private var kindPicker: some View {
        Picker("Show", selection: $selectedKind) {
            Text("Tags").tag(SavedItem.Kind.tag)
            Text("Profiles").tag(SavedItem.Kind.profile)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if filteredItems.isEmpty {
            if searchQuery.isEmpty {
                emptyState
            } else {
                ContentUnavailableView.search(text: searchQuery)
            }
        } else {
            List {
                ForEach(filteredItems) { item in
                    NavigationLink(value: item.id) {
                        SavedItemRow(item: item)
                    }
                }
                .onDelete { offsets in
                    app.store.delete(at: offsets, in: filteredItems)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        let isTags = selectedKind == .tag
        let title: String = isTags ? "No saved tags" : "No profiles"
        let symbol: String = isTags ? "tag" : "doc.text"
        let message: String = isTags
            ? "Scan a tag, then choose Save tag to keep it here."
            : "Save the records in the Write tab as a profile, or tap New profile to start one."
        return ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }

    // MARK: Filtering

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [SavedItem] {
        let ofKind = app.store.items.filter { $0.kind == selectedKind }
        let query = searchQuery
        guard !query.isEmpty else { return ofKind }
        return ofKind.filter { item in
            if item.name.localizedCaseInsensitiveContains(query) { return true }
            if item.subtitle.localizedCaseInsensitiveContains(query) { return true }
            if let serial = item.tagInfo?.serialLine, serial.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    // MARK: Actions

    private func createProfile() {
        let item = SavedItem.profile(name: "New profile", drafts: [])
        app.store.add(item)
        selectedKind = .profile
        searchText = ""
        Haptics.tap()
        path.append(item.id)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let count = try app.store.importItems(from: url)
                if count == 0 {
                    showSoon(AlertItem(error: NFCEditorError.invalidInput("The file does not contain any saved items.")))
                    return
                }
                Haptics.success()
                showSoon(AlertItem.success(count == 1 ? "Imported 1 item." : "Imported \(count) items."))
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                showSoon(AlertItem(error: error))
            }
        case .failure(let error):
            if NFCEditorError.map(error).isCancellation { return }
            showSoon(AlertItem(error: error))
        }
    }

    /// The file picker is still animating away when its result arrives, so the alert waits a moment.
    private func showSoon(_ item: AlertItem) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            alert = item
        }
    }
}

// MARK: - Rows

/// One saved item: icon, name, what it holds and when it last changed.
private struct SavedItemRow: View {
    let item: SavedItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.body)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: item.kind == .tag ? "tag" : "doc.text")
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 8)
            Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return item.kind == .tag ? "Untitled tag" : "Untitled profile"
        }
        return trimmed
    }
}
