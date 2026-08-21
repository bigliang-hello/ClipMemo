import SwiftUI

// MARK: - Search bar

struct SearchBarView: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L10n.shared.t("Search clipboard"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘K")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(focus.wrappedValue ? Color.blue.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - Segmented filter (capsule style: selected = white card + soft shadow)

struct SegmentedFilterBar: View {
    @Binding var selection: ClipFilter
    let counts: [ClipFilter: Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipFilter.allCases) { filter in
                SegmentButton(title: filter.segmentTitle,
                              count: counts[filter] ?? 0,
                              isSelected: selection == filter) {
                    selection = filter
                }
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Color.primary.opacity(0.07))
        )
    }
}

private struct SegmentButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: isSelected ? 2 : 0, y: 1)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.primary.opacity(0.08) : .clear, lineWidth: 0.5)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.65))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in hover = inside }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Destructive-action confirmation

/// Native modal confirmation for destructive actions — a single path that
/// works from any entry point (window buttons, command menu, menu bar),
/// since NSAlert doesn't need to attach to a particular SwiftUI view.
enum ConfirmDialog {

    @discardableResult
    private static func ask(title: String, message: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: L10n.shared.t("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Before removing a single record.
    static func deleteRecord() -> Bool {
        ask(title: L10n.shared.t("Delete Record?"),
            message: L10n.shared.t("This record will be removed from your history. This cannot be undone."),
            confirm: L10n.shared.t("Delete"))
    }

    /// Before clearing everything.
    static func clearHistory() -> Bool {
        ask(title: L10n.shared.t("Clear All History?"),
            message: L10n.shared.t("All clipboard history will be removed. This cannot be undone."),
            confirm: L10n.shared.t("Clear History"))
    }
}
