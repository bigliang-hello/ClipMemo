import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: HistoryStore
    @EnvironmentObject var monitor: ClipboardMonitor

    @State private var activeFilter: ClipFilter = .all
    @State private var sourceFilter: String?
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var showToolbox = false
    @State private var previewItem: ClipboardItem?
    @FocusState private var searchFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("mainLayout") private var mainLayout = "list"

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $activeFilter, counts: counts,
                        isToolboxActive: showToolbox,
                        onToolbox: { showToolbox = true },
                        onCategoryPick: { showToolbox = false }) {
                showSettings = true
            }
            if showToolbox {
                ToolboxView()
                    .id(l10n.language)
            } else {
                mainArea
            }
        }
        .id(l10n.language) // rebuild the tree when the in-app language changes
        .environment(\.locale, l10n.locale)
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $previewItem) { item in
            DetailPreviewView(item: item, onCopy: { copy(item) }) { newText in
                store.updateText(item.id, to: newText)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .showClipMemoToolbox)) { _ in
            showToolbox = true
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
                    if let bid = sourceFilter {
                        sourceFilterChip(bid)
                    }
                    Spacer()
                    privacyBadge
                    layoutToggleButton
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
                            if mainLayout == "grid" {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                                          spacing: 12) {
                                    ForEach(sectionItems) { item in
                                        gridCell(for: item)
                                    }
                                }
                            } else {
                                ForEach(sectionItems) { item in
                                    card(for: item)
                                }
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

    private func gridCell(for item: ClipboardItem) -> some View {
        MainGridCell(
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
            onTogglePin: { store.togglePin(item.id) },
            onSourceFilter: { bid in
                sourceFilter = sourceFilter == bid ? nil : bid
            }
        )
    }

    /// Removable capsule shown while a source-app filter is active.
    private func sourceFilterChip(_ bundleID: String) -> some View {
        let name = store.items.first { $0.sourceBundleID == bundleID }?.sourceAppName
            ?? SourceApps.displayName(for: bundleID)
            ?? bundleID
        return HStack(spacing: 5) {
            if let icon = SourceApps.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(String(format: L10n.shared.t("From %@"), name))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .fixedSize()
            Button {
                sourceFilter = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.blue.opacity(0.10)))
        .help(L10n.shared.t("Clear filter"))
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

    /// List ⇄ grid switch for the main history area.
    private var layoutToggleButton: some View {
        Button {
            mainLayout = mainLayout == "grid" ? "list" : "grid"
        } label: {
            Image(systemName: mainLayout == "grid" ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(L10n.shared.t(mainLayout == "grid" ? "List View" : "Grid View"))
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
            if let sourceFilter, item.sourceBundleID != sourceFilter { return false }
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

/// Grid-layout tile for the main window: images get a large preview (the
/// point of the grid), text/code a multi-line snippet, files a document
/// badge. Single tap selects, double tap copies — and hover reveals the same
/// actions the record card shows (copy / preview / share / delete / pin).
private struct MainGridCell: View {
    let item: ClipboardItem
    let isSelected: Bool
    var onSelect: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onPreview: () -> Void
    var onTogglePin: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .overlay(alignment: .bottomTrailing) {
                    if hover {
                        hoverActions
                            .transition(.opacity)
                    }
                }
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.blue.opacity(0.10) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.blue.opacity(0.65) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCopy() }
        .onTapGesture(count: 1) { onSelect() }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu {
            Button(L10n.shared.t("Copy")) { onCopy() }
            Button(L10n.shared.t(item.isPinned ? "Unpin" : "Pin")) { onTogglePin() }
            Button(L10n.shared.t("Preview")) { onPreview() }
            if let bid = item.sourceBundleID, let name = item.sourceAppName {
                Divider()
                Button(String(format: L10n.shared.t("Exclude %@"), name)) {
                    ExclusionList.add(bid)
                }
            }
            Divider()
            Button(L10n.shared.t("Delete"), role: .destructive) { onDelete() }
        }
    }

    /// Compact action bar fading in over the thumbnail — the grid counterpart
    /// of the record card's trailing buttons.
    private var hoverActions: some View {
        let l = L10n.shared
        return HStack(spacing: 3) {
            actionIcon("doc.on.doc", help: l.t("Copy")) { onCopy() }
            actionIcon("eye", help: l.t("Preview")) { onPreview() }
            shareButton
            actionIcon("trash", help: l.t("Delete"), color: .red) { onDelete() }
        }
        .padding(3)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let nsImage = ImageCache.image(for: item) {
                // Shape-driven footprint with the image drawn on top and
                // cropped — keeps wide images inside the grid track.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                typePlaceholder("photo", color: .gray)
            }
        case .file:
            typePlaceholder("doc.fill", color: .purple)
        case .code:
            snippet(monospaced: true)
        case .text:
            snippet(monospaced: false)
        }
    }

    /// Multi-line text preview keeping every tile in a row the same height.
    private func snippet(monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: monospaced ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(typeColor)
                Text(monospaced ? L10n.shared.t("Code") : L10n.shared.t("Text"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(monospaced ? "{ }" : "Aa")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(typeColor.opacity(0.75))
            }
            Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? item.titleLine)
                .font(.system(size: monospaced ? 10.5 : 11.5,
                              design: monospaced ? .monospaced : .default))
                .lineLimit(5)
                .lineSpacing(2)
                .truncationMode(.tail)
                .foregroundStyle(.primary.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(typeColor.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(typeColor.opacity(0.16), lineWidth: 0.7)
        )
    }

    private func typePlaceholder(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.10))
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(height: 118)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: typeIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(typeColor)
            Text(footerTitle)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(item.isPinned ? .blue : .secondary)
                    .opacity(item.isPinned || hover ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .help(L10n.shared.t(item.isPinned ? "Unpin" : "Pin"))
        }
    }

    private var footerTitle: String {
        switch item.type {
        case .image, .file:
            return item.titleLine
        case .text, .code:
            return item.sourceAppName ?? (item.type == .code ? L10n.shared.t("Code") : L10n.shared.t("Text"))
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        switch item.type {
        case .text, .code:
            if let text = item.text {
                ShareLink(item: text) { actionLabel("square.and.arrow.up", help: L10n.shared.t("Share")) }
                    .buttonStyle(.plain)
            }
        case .image:
            if let url = HistoryStore.shared.imageFileURL(for: item) {
                ShareLink(item: url) { actionLabel("square.and.arrow.up", help: L10n.shared.t("Share")) }
                    .buttonStyle(.plain)
            }
        case .file:
            if let path = item.fileURLPath {
                ShareLink(item: URL(fileURLWithPath: path)) { actionLabel("square.and.arrow.up", help: L10n.shared.t("Share")) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func actionIcon(_ systemName: String, help: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(systemName, help: help).foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    /// Material-backed so the icons stay readable over any thumbnail.
    private func actionLabel(_ systemName: String, help: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .medium))
            .frame(width: 22, height: 22)
            .background(Circle().fill(.regularMaterial))
            .help(help)
    }

    private var typeIcon: String {
        switch item.type {
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var typeColor: Color {
        switch item.type {
        case .text: return .blue
        case .code: return .green
        case .image: return .orange
        case .file: return .purple
        }
    }
}

extension Notification.Name {
    static let showClipMemoSettings = Notification.Name("showClipMemoSettings")
    static let showClipMemoWindow = Notification.Name("showClipMemoWindow")
    static let showClipMemoToolbox = Notification.Name("showClipMemoToolbox")
}
