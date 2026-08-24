import SwiftUI

enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, images, files
    var id: String { rawValue }

    var sidebarTitle: String {
        L10n.shared.t(sidebarTitleKey)
    }

    var sidebarTitleKey: String {
        switch self {
        case .all: return "All Items"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        }
    }

    var sidebarIcon: String {
        switch self {
        case .all: return "tray.full"
        case .text: return "doc.plaintext"
        case .images: return "photo"
        case .files: return "doc"
        }
    }

    var segmentTitle: String {
        switch self {
        case .all: return L10n.shared.t("All")
        default: return sidebarTitle
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text || item.type == .code
        case .images: return item.type == .image
        case .files: return item.type == .file
        }
    }
}

struct SidebarView: View {
    @Binding var selection: ClipFilter
    let counts: [ClipFilter: Int]
    var isToolboxActive: Bool = false
    var onToolbox: () -> Void = {}
    /// Fired on every category tap (even a re-tap of the selected one) so the
    /// owner can leave modes like the toolbox — a plain binding change can't
    /// express "clicked the already-selected row".
    var onCategoryPick: () -> Void = {}
    var onSettings: () -> Void

    @State private var settingsHover = false
    @State private var toolboxHover = false

    var body: some View {
        VStack(spacing: 0) {
            // Space for the overlaid traffic lights.
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Circle().fill(Color.yellow).frame(width: 12, height: 12)
                Circle().fill(Color.green).frame(width: 12, height: 12)
            }
            .opacity(0) // hidden stand-ins; real traffic lights render on top
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // App identity
            VStack(spacing: 8) {
                ZStack {
                    Image("ClipMemoMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("ClipMemo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)

            // Categories
            VStack(spacing: 2) {
                ForEach(ClipFilter.allCases) { filter in
                    SidebarRow(filter: filter,
                               count: counts[filter] ?? 0,
                               isSelected: selection == filter && !isToolboxActive) {
                        selection = filter
                        onCategoryPick()
                    }
                }
            }
            .padding(.horizontal, 8)

            // Toolbox entry
            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                Image(systemName: "toolbox")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22)
                Text(L10n.shared.t("Toolbox"))
                    .font(.system(size: 12, weight: isToolboxActive ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
            }
            .foregroundStyle(isToolboxActive ? Color.blue : Color.primary.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isToolboxActive ? Color.blue.opacity(0.13) : (toolboxHover ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
            .onTapGesture { onToolbox() }
            .onHover { toolboxHover = $0 }
            .padding(.horizontal, 8)

            Spacer()

            // Settings at the bottom
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.shared.t("Settings"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(settingsHover ? Color.primary.opacity(0.05) : .clear)
            )
            .onHover { settingsHover = $0 }
            .onTapGesture { onSettings() }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .frame(width: 150)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Rectangle()
                .fill(Color.primary.opacity(0.03))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 0.5)
                }
        )
    }
}

private struct SidebarRow: View {
    let filter: ClipFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: filter.sidebarIcon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22)
            Text(filter.sidebarTitle)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
        }
        .foregroundStyle(isSelected ? Color.blue : Color.primary.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.blue.opacity(0.13) : (hover ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hover = $0 }
    }
}
