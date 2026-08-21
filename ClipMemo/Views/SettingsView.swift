import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var monitor: ClipboardMonitor
    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var l10n = L10n.shared

    @AppStorage("historyLimit") private var historyLimit = 500
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var iCloudSync = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
    @State private var language = L10n.shared.language

    private let limits: [Int] = [50, 100, 200, 500, 1000, 0]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    card("General") {
                        toggleRow(l10n.t("Launch at login"), isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                        if let loginError { footnote(loginError) }
                    }
                    card("Language") {
                        HStack {
                            Text(l10n.t("Language")).font(.system(size: 12))
                            Spacer()
                            Picker(l10n.t("Language"), selection: $language) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang == .chinese ? lang.displayNameKey : l10n.t(lang.displayNameKey))
                                        .tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: language) { _, new in L10n.shared.language = new }
                        }
                    }
                    card("History") {
                        HStack {
                            Text(l10n.t("Number of items to keep")).font(.system(size: 12))
                            Spacer()
                            Picker(l10n.t("Number of items to keep"), selection: $historyLimit) {
                                ForEach(limits, id: \.self) { limit in
                                    Text(limit == 0 ? l10n.t("Unlimited") : "\(limit)").tag(limit)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                        footnote(l10n.t("The oldest unpinned records are removed first. Pinned records are always kept."))
                    }
                    card("Privacy") {
                        toggleRow(l10n.t("Privacy mode (pause monitoring)"), isOn: $monitor.isPaused)
                        footnote(l10n.t("While enabled, ClipMemo ignores clipboard changes completely."))
                    }
                    card(nil) {
                        toggleRow(l10n.t("Sync history via iCloud"), isOn: $iCloudSync)
                            .disabled(!store.iCloudSyncAvailable)
                            .onChange(of: iCloudSync) { _, on in store.setSyncEnabled(on) }
                        if let error = store.iCloudSyncError {
                            footnote(error, color: .orange)
                        } else if !store.iCloudSyncAvailable {
                            footnote(store.entitlementMissing
                                     ? l10n.t("iCloud sync needs a build signed with the iCloud capability (paid Apple Developer team).")
                                     : l10n.t("Sign in to iCloud in System Settings to enable sync."))
                        } else if store.iCloudSyncActive {
                            Label(l10n.t("Syncing privately through your iCloud account."),
                                  systemImage: "checkmark.icloud.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        } else {
                            footnote(l10n.t("Off — history stays only on this Mac. Turning it on keeps this Mac’s history in sync with your other devices."))
                        }
                    }
                    card("Storage") {
                        footnote(store.iCloudSyncActive
                                 ? l10n.t("Records are stored on this Mac and in your private iCloud database.")
                                 : l10n.t("All records are stored locally on this Mac. Nothing is ever uploaded."))
                        Button(l10n.t("Clear All History"), role: .destructive) {
                            store.clearAll(keepPinned: false)
                            dismiss()
                        }
                        .controlSize(.small)
                    }
                    card("Shortcut") {
                        HStack {
                            Text(l10n.t("Quick Paste")).font(.system(size: 12))
                            Spacer()
                            Text("⌘⇧V")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(l10n.language) // refresh every label when the language changes
        .environment(\.locale, l10n.locale)
        .frame(width: 440, height: 660)
    }

    // MARK: Building blocks

    private func card(_ titleKey: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let titleKey {
                Text(L10n.shared.t(titleKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
            )
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 12))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func footnote(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.blue.opacity(0.13))
                    .frame(width: 26, height: 26)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
            Text(L10n.shared.t("Settings"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("ClipMemo 1.0")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            launchAtLogin.toggle()
            loginError = "Could not change login item: \(error.localizedDescription)"
        }
    }
}
