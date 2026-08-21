//
//  ClipMemoApp.swift
//  ClipMemo
//
//  Created by bigliang on 2026/8/21.
//

import SwiftUI
import AppKit

/// Lets non-view code (hotkey, menu bar) reopen the main SwiftUI window.
@MainActor
enum WindowOpener {
    static var openMain: (() -> Void)?
    static var show: (() -> Void)?

    static func showMainWindow() {
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
        HistoryStore.shared.seedIfNeeded()
        if HistoryStore.shared.purgeExpired() {
            HistoryStore.shared.refetch()
        }
        ClipboardMonitorHolder.monitor.start()

        HotKeyManager.shared.register {
            QuickPasteController.shared.togglePanel()
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
