import SwiftUI
import Combine
import ApplicationServices

/// Accessibility (TCC) permission can never be granted programmatically — the
/// user must flip the switch in System Settings. The official prompt below at
/// least pre-lists ClipMemo in Privacy & Security → Accessibility, so the
/// "+"-button/Finder-browse dance is unnecessary.
enum AccessibilityPermission {

    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Once per launch — don't nag after the user has seen the dialog.
    static var hasRequestedThisLaunch = false

    /// Activates the app (the system dialog won't surface from a background
    /// app — the quick panel is non-activating), shows the official prompt
    /// (pre-lists ClipMemo in the Accessibility pane), and opens the pane
    /// directly as a guaranteed visible response.
    static func request() {
        hasRequestedThisLaunch = true
        NSApp.activate(ignoringOtherApps: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// Floating quick-paste palette summoned by the global hotkey while typing in
/// any app: search, pick a row, and it is pasted straight into the field that
/// had focus (via a synthetic ⌘V — needs Accessibility permission; without it
/// the item is only copied). Esc closes, ⌘⏎ opens the full window instead.
@MainActor
final class QuickPasteController: NSObject, ObservableObject, NSWindowDelegate {

    static let shared = QuickPasteController()

    @Published var query = ""
    @Published var selectionIndex = 0
    @Published private(set) var panelVisible = false

    private var panel: QuickPanel?
    private var previousApp: NSRunningApplication?

    /// Rows shown in the palette (search over title/subtitle/body, newest first).
    var filteredItems: [ClipboardItem] {
        let all = HistoryStore.shared.items
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(all.prefix(50)) }
        let matched = all.filter { item in
            let haystack = [item.titleLine, item.subtitleLine, item.text ?? ""]
                .joined(separator: "\n")
            return haystack.localizedCaseInsensitiveContains(q)
        }
        return Array(matched.prefix(50))
    }

    /// ⏎ pastes directly only when we may synthesize keystrokes.
    var canAutoPaste: Bool { AccessibilityPermission.isGranted }

    func togglePanel() { panelVisible ? hidePanel() : showPanel() }

    func showPanel() {
        let p = panel ?? makePanel()
        previousApp = NSWorkspace.shared.frontmostApplication
        query = ""
        selectionIndex = 0
        position(p)
        p.orderFrontRegardless()
        p.makeKey()
        panelVisible = true
    }

    func hidePanel() {
        panel?.orderOut(nil)
        panelVisible = false
    }

    func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectionIndex = ((selectionIndex + delta) % count + count) % count
    }

    /// Copy the selected row and paste it into the app that was frontmost.
    /// `openFullWindow` (⌘⏎) just opens the main window instead; `plainText`
    /// (⌥⏎) strips formatting so only the plain string is pasted.
    func confirmSelection(openFullWindow: Bool = false, plainText: Bool = false) {
        hidePanel()
        if openFullWindow {
            WindowOpener.showMainWindow()
            return
        }
        let items = filteredItems
        guard items.indices.contains(selectionIndex) || !items.isEmpty else { return }
        let item = items.indices.contains(selectionIndex) ? items[selectionIndex] : items[0]

        let target = previousApp
        let ownBundle = Bundle.main.bundleIdentifier
        let shouldAutoPaste = canAutoPaste
            && target != nil
            && target?.bundleIdentifier != ownBundle   // don't ⌘V into our own window
        let pid = target?.processIdentifier

        ClipboardMonitorHolder.monitor.copyAndIgnore(item, plainText: plainText && item.text != nil)
        if shouldAutoPaste, let pid {
            // Give the panel time to close so the previous app has key focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Self.postCommandV(to: pid)
            }
        } else if !AccessibilityPermission.isGranted && !AccessibilityPermission.hasRequestedThisLaunch
                    && target?.bundleIdentifier != ownBundle {
            // The ⏎ didn't land in the field as expected — surface the official
            // grant dialog once so the user can fix it in two clicks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AccessibilityPermission.request()
            }
        }
    }

    // MARK: Panel plumbing

    private func position(_ p: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = p.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY + visible.height * 0.15 - size.height / 2 // slightly above centre
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func makePanel() -> QuickPanel {
        let p = QuickPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 380)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.contentView = NSHostingView(rootView: QuickPasteView(controller: self))
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.delegate = self
        p.onNavigate = { [weak self] delta in
            MainActor.assumeIsolated { self?.moveSelection(delta) }
        }
        p.onConfirm = { [weak self] openFull, plainText in
            MainActor.assumeIsolated {
                self?.confirmSelection(openFullWindow: openFull, plainText: plainText)
            }
        }
        p.onCancel = { [weak self] in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
        panel = p
        return p
    }

    nonisolated private static func postCommandV(to pid: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
    }

    /// Click anywhere else closes the palette.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { self.hidePanel() }
    }
}

/// Borderless panel that intercepts navigation keys before SwiftUI sees them.
nonisolated final class QuickPanel: NSPanel {

    var onNavigate: ((Int) -> Void)?
    var onConfirm: ((Bool, Bool) -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 125: onNavigate?(1); return   // down arrow
            case 126: onNavigate?(-1); return  // up arrow
            case 53: onCancel?(); return       // escape
            case 36, 76:                       // return / enter
                onConfirm?(event.modifierFlags.contains(.command),
                          event.modifierFlags.contains(.option))
                return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

// MARK: SwiftUI content

private struct QuickPasteView: View {
    @ObservedObject var controller: QuickPasteController
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = HistoryStore.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = controller.filteredItems
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(l10n.t("Search clipboard"), text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onChange(of: controller.query) { _, _ in
                        controller.selectionIndex = 0
                    }
                Text("esc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if items.isEmpty {
                            Text(l10n.t("Try a different search term or filter."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 28)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            QuickRow(item: item, isSelected: index == controller.selectionIndex)
                                .id(item.id)
                                .onTapGesture {
                                    controller.selectionIndex = index
                                    controller.confirmSelection()
                                }
                                .onHover { hover in
                                    if hover { controller.selectionIndex = index }
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: controller.selectionIndex) { _, newIndex in
                    if items.indices.contains(newIndex) {
                        proxy.scrollTo(items[newIndex].id, anchor: .center)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                if controller.canAutoPaste {
                    Text(l10n.t("Type to search, ↑↓ to select, ⏎ paste, ⌥⏎ plain text"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(l10n.t("No Accessibility permission — items are only copied; press ⌘V to paste."))
                        .foregroundStyle(.orange)
                    Button(l10n.t("Open System Settings")) {
                        AccessibilityPermission.request()
                    }
                    .controlSize(.mini)
                }
                Spacer()
                Button(l10n.t("Full History…")) {
                    controller.confirmSelection(openFullWindow: true)
                }
                .controlSize(.small)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 400, height: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { searchFocused = true }
    }
}

private struct QuickRow: View {
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(badgeColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(badgeColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.titleLine)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(item.subtitleLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
            }
            Text(item.formattedTime)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.blue.opacity(0.13) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch item.type {
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var badgeColor: Color {
        switch item.type {
        case .text: return .blue
        case .code: return .green
        case .image: return .orange
        case .file: return .purple
        }
    }
}
