import SwiftUI

// MARK: - Thumbnail cache

enum ImageCache {
    static let shared = NSCache<NSString, NSImage>()

    static func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = shared.object(forKey: key) { return cached }
        guard let loaded = HistoryStore.shared.imageNSImage(for: item) else { return nil }
        shared.setObject(loaded, forKey: key)
        return loaded
    }
}

// MARK: - Lightweight syntax highlighting

enum SyntaxHighlight {

    private static let keywords: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "import", "return", "if", "else",
        "for", "while", "switch", "case", "break", "continue", "public", "private", "static",
        "extension", "protocol", "guard", "defer", "throw", "try", "catch", "in", "self",
        "func", "def", "lambda", "None", "True", "False", "nil", "true", "false", "new", "async", "await"
    ]

    static func highlighted(_ line: String) -> Text {
        guard !line.isEmpty else { return Text(" ") }
        let pattern = "\"[^\"]*\"|//.*|\\b[A-Za-z_][A-Za-z0-9_]*\\b|\\b[0-9][0-9_]*(?:\\.[0-9]+)?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(line)
        }
        var result = AttributedString()
        var cursor = line.startIndex
        for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let r = Range(match.range, in: line) else { continue }
            if cursor < r.lowerBound {
                result += AttributedString(String(line[cursor..<r.lowerBound]))
            }
            result += token(String(line[r]))
            cursor = r.upperBound
        }
        if cursor < line.endIndex {
            result += AttributedString(String(line[cursor..<line.endIndex]))
        }
        return Text(result)
    }

    private static func token(_ token: String) -> AttributedString {
        var run = AttributedString(token)
        if token.hasPrefix("//") {
            run.foregroundColor = .secondary
        } else if token.hasPrefix("\"") {
            run.foregroundColor = .orange
        } else if token.first?.isNumber == true {
            run.foregroundColor = .purple
        } else if keywords.contains(token) {
            run.foregroundColor = .pink
        }
        return run
    }
}

// MARK: - Record card

struct RecordCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    var onSelect: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onPreview: () -> Void
    var onTogglePin: () -> Void

    @State private var hover = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.blue :
                        (hover ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05)),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onCopy() }
            .onTapGesture(count: 1) { onSelect() }
            .onHover { hover = $0 }
            .contextMenu {
                Button(L10n.shared.t("Copy")) { onCopy() }
                Button(L10n.shared.t(item.isPinned ? "Unpin" : "Pin")) { onTogglePin() }
                Button(L10n.shared.t("Preview")) { onPreview() }
                Divider()
                Button(L10n.shared.t("Delete"), role: .destructive) { onDelete() }
            }
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingPreview
            centerPreview
            Spacer(minLength: 8)
            trailingControls
        }
    }

    // MARK: Leading badge / thumbnail

    @ViewBuilder
    private var leadingPreview: some View {
        switch item.type {
        case .text:
            badge(color: .blue) {
                Text("T").font(.system(size: 20, weight: .bold, design: .rounded))
            }
        case .code:
            badge(color: .green) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
        case .file:
            badge(color: .purple) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 17, weight: .medium))
            }
        case .image:
            if let nsImage = ImageCache.image(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                badge(color: .gray) {
                    Image(systemName: "photo").font(.system(size: 16))
                }
            }
        }
    }

    private func badge<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(color.opacity(0.13))
            content().foregroundColor(color)
        }
        .frame(width: 52, height: 52)
    }

    // MARK: Center text

    @ViewBuilder
    private var centerPreview: some View {
        switch item.type {
        case .code:
            VStack(alignment: .leading, spacing: 2) {
                codeLine(item.titleLine)
                codeLine(item.subtitleLine)
            }
        default:
            VStack(alignment: .leading, spacing: 3) {
                Text(item.titleLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func codeLine(_ line: String) -> some View {
        SyntaxHighlight.highlighted(line)
            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Trailing controls

    private var trailingControls: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 8) {
                Text(item.formattedTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(item.isPinned ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(item.isPinned || hover ? 1 : 0.35)
            }
            actionButtons
                .opacity(hover ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hover)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let l = L10n.shared
        HStack(spacing: 4) {
            actionIcon("doc.on.doc", help: l.t("Copy")) { onCopy() }
            actionIcon("eye", help: l.t("Preview")) { onPreview() }
            shareButton
            actionIcon("trash", help: l.t("Delete"), color: .red) { onDelete() }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        switch item.type {
        case .text, .code:
            if let text = item.text {
                ShareLink(item: text) { shareLabel }
                    .buttonStyle(.plain)
            }
        case .image:
            if let url = HistoryStore.shared.imageFileURL(for: item) {
                ShareLink(item: url) { shareLabel }
                    .buttonStyle(.plain)
            }
        case .file:
            if let path = item.fileURLPath {
                ShareLink(item: URL(fileURLWithPath: path)) { shareLabel }
                    .buttonStyle(.plain)
            }
        }
    }

    private var shareLabel: some View {
        actionLabel("square.and.arrow.up", help: L10n.shared.t("Share"))
    }

    private func actionIcon(_ systemName: String, help: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(systemName, help: help).foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ systemName: String, help: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .medium))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .help(help)
    }

    // MARK: Card background

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(isSelected ? 0.07 : 0))
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.07),
                radius: hover || isSelected ? 4 : 1.5, y: hover || isSelected ? 2 : 1)
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}
