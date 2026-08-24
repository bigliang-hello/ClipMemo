//
//  ClipMemoApp.swift
//  ClipMemo
//
//  Created by bigliang on 2026/8/21.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Lets non-view code (hotkey, menu bar) reopen the main SwiftUI window.
@MainActor
enum WindowOpener {
    static var openMain: (() -> Void)?
    static var show: (() -> Void)?

    static func showMainWindow() {
        // Come back to the Dock when a window is about to appear again.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: never run alongside another copy (e.g. a
        // Debug build from DerivedData plus the installed Release app) —
        // they would share one sandbox container and fight over the store.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first {
                other.activate()
                NSApp.terminate(nil)
                return
            }
        }

        ExclusionList.seedIfNeeded()
        if HistoryStore.shared.purgeExpired() {
            HistoryStore.shared.refetch()
        }
        ClipboardMonitorHolder.monitor.start()

        HotKeyManager.shared.register(id: 1, keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) {
            QuickPasteController.shared.togglePanel()
        }
        HotKeyManager.shared.register(id: 2, keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey) {
            WindowOpener.showMainWindow()
            // Give a freshly (re)created window a moment to subscribe first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .showClipMemoToolbox, object: nil)
            }
        }

        // Menu-bar-resident behavior: once the last real window closes, drop
        // the Dock icon (accessory policy) and keep only the status-bar item.
        // Showing a window again (WindowOpener) flips back to regular.
        // Filter by canBecomeMain: NSStatusBarWindow (the menu-bar item) and
        // the quick-paste NSPanel are always around and must not count.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, !(window is NSPanel) else { return }
        DispatchQueue.main.async {
            let others = NSApp.windows.filter {
                $0 !== window && $0.canBecomeMain && $0.isVisible
            }
            guard others.isEmpty, NSApp.activationPolicy() == .regular else { return }
            // Switching policy while we're still the frontmost app is flaky —
            // give the close/deactivation a beat to settle first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.showMainWindow() }
        return true
    }
}

/// Owns the monitor instance for the whole app.
@MainActor
enum ClipboardMonitorHolder {
    static let monitor = ClipboardMonitor(store: HistoryStore.shared)
}

@main
struct ClipMemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var l10n = L10n.shared
    // Scene/Commands don't reliably re-evaluate on ObservableObject changes,
    // but they do on @AppStorage — reading it re-runs App.body (incl. the
    // main-menu commands) whenever the language pref is written.
    @AppStorage("appLanguage") private var appLanguage = "system"

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(HistoryStore.shared)
                .environmentObject(ClipboardMonitorHolder.monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Group {
                    Button(l10n.t("Quick Paste")) {
                        QuickPasteController.shared.togglePanel()
                    }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    Button(l10n.t("Show ClipMemo")) {
                        WindowOpener.showMainWindow()
                    }
                    Button(l10n.t("Open Toolbox")) {
                        WindowOpener.showMainWindow()
                        NotificationCenter.default.post(name: .showClipMemoToolbox, object: nil)
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }
                .id(appLanguage) // rebuild menu items when the language changes
            }
            CommandMenu(l10n.t("History")) {
                Button(l10n.t("Copy Latest Item")) {
                    if let latest = HistoryStore.shared.items.first {
                        ClipboardMonitorHolder.monitor.copyAndIgnore(latest)
                    }
                }
                .disabled(HistoryStore.shared.items.isEmpty)
                Button(l10n.t("Clear History…"), role: .destructive) {
                    if ConfirmDialog.clearHistory() {
                        HistoryStore.shared.clearAll(keepPinned: false)
                    }
                }
                .disabled(HistoryStore.shared.items.isEmpty)
            }
        }

        MenuBarExtra {
            MenuBarMenu()
        } label: {
            Image(systemName: "clipboard")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .accessibilityLabel("ClipMemo")
        }
    }
}

private struct MenuBarMenu: View {
    @ObservedObject var monitor = ClipboardMonitorHolder.monitor
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(l10n.t("Show ClipMemo")) { WindowOpener.showMainWindow() }
        Button(l10n.t("Quick Paste")) { QuickPasteController.shared.togglePanel() }
        Button(l10n.t("Open Toolbox")) {
            WindowOpener.showMainWindow()
            NotificationCenter.default.post(name: .showClipMemoToolbox, object: nil)
        }
        Divider()
        Button(monitor.isPaused ? l10n.t("Resume Monitoring") : l10n.t("Pause Monitoring (Privacy Mode)")) {
            monitor.isPaused.toggle()
        }
        Button(l10n.t("Clear History")) {
            if ConfirmDialog.clearHistory() {
                HistoryStore.shared.clearAll(keepPinned: false)
            }
        }
        Divider()
        Button(l10n.t("Settings…")) {
            WindowOpener.showMainWindow()
            NotificationCenter.default.post(name: .showClipMemoSettings, object: nil)
        }
        Button(l10n.t("Quit ClipMemo")) {
            NSApplication.shared.terminate(nil)
        }
    }
}
