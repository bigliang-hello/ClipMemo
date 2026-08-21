import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: HistoryStore
    @EnvironmentObject var monitor: ClipboardMonitor

    @State private var activeFilter: ClipFilter = .all
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var previewItem: ClipboardItem?
    @FocusState private var searchFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $activeFilter, counts: counts) {
                showSettings = true
            }
            mainArea
        }
        .id(l10n.language) // rebuild the tree when the in-app language changes
        .environment(\.locale, l10n.locale)
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $previewItem) { item in
            DetailPreviewView(item: item) { copy(item) }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .background(
            // ⌘K focuses search (hidden button so it works regardless of focus)
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .onReceive(NotificationCenter.default.publisher(for: .showClipMemoSettings)) { _ in
            showSettings = true
        }
        .onAppear { WindowOpener.openMain = { openWindow(id: "main") } }
    }

    // MARK: Main area

    private var mainArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                SearchBarView(text: $searchText, focus: $searchFocused)
                HStack {
                    SegmentedFilterBar(selection: $activeFilter, counts: counts)
                    Spacer()
                    privacyBadge
                    clearButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if filteredGroups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredGroups, id: \.0) { section, sectionItems in
                            sectionHeader(section)
                            ForEach(sectionItems) { item in
                                card(for: item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(L10n.shared.t(title))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func card(for item: ClipboardItem) -> some View {
        RecordCard(
            item: item,
            isSelected: selectedID == item.id,
            onSelect: { selectedID = item.id },
            onCopy: { copy(item) },
            onDelete: {
                guard ConfirmDialog.deleteRecord() else { return }
                if selectedID == item.id { selectedID = nil }
                store.remove(item.id)
            },
            onPreview: { previewItem = item },
            onTogglePin: { store.togglePin(item.id) }
        )
    }

    @ViewBuilder
    private var privacyBadge: some View {
        if monitor.isPaused {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n.shared.t("Paused"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
            .help(L10n.shared.t("Privacy mode is on — clipboard monitoring is paused. Click to resume."))
            .onTapGesture { monitor.isPaused = false }
        }
    }

    private var clearButton: some View {
        Button {
            guard ConfirmDialog.clearHistory() else { return }
            store.clearAll(keepPinned: false)
            selectedID = nil
            showToast(L10n.shared.t("History cleared"))
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(L10n.shared.t("Clear all history"))
    }

    private var emptyState: some View {
        let l = L10n.shared
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 64, height: 64)
                Image(systemName: "clipboard")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
            }
            Text(searchText.isEmpty
                 ? l.t("No clipboard items yet")
                 : String(format: l.t("No results for “%@”"), searchText))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty
                 ? l.t("Copy something and it will appear here automatically.")
                 : l.t("Try a different search term or filter."))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data shaping

    private var counts: [ClipFilter: Int] {
        var result: [ClipFilter: Int] = [:]
        for filter in ClipFilter.allCases {
            result[filter] = store.items.filter(filter.matches).count
        }
        return result
    }

    private var filteredGroups: [(String, [ClipboardItem])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = store.items.filter { item in
            guard activeFilter.matches(item) else { return false }
            guard !query.isEmpty else { return true }
            return item.searchText.contains(query)
        }
        return DateGroup.order.compactMap { section in
            let items = filtered.filter { DateGroup.group(for: $0) == section }
            return items.isEmpty ? nil : (section, items)
        }
    }

    // MARK: Actions

    private func copy(_ item: ClipboardItem) {
        monitor.copyAndIgnore(item)
        selectedID = item.id
        showToast(L10n.shared.t("Copied to clipboard"))
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.25)) { toastMessage = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            ToastView(message: message)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension Notification.Name {
    static let showClipMemoSettings = Notification.Name("showClipMemoSettings")
    static let showClipMemoWindow = Notification.Name("showClipMemoWindow")
}
