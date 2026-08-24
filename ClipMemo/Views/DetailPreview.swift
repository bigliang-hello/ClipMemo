import SwiftUI

/// A lightweight Quick-Look-style sheet for inspecting a record.
struct DetailPreviewView: View {
    let item: ClipboardItem
    var onCopy: () -> Void
    var onUpdateText: (String) -> Void = { _ in }

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editMode = false
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                payload
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
            Text(item.titleLine)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if item.type == .text || item.type == .code {
                Button {
                    draftText = item.text ?? ""
                    editMode = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.t("Edit"))
                .disabled(editMode)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            if editMode {
                Button(l10n.t("Cancel")) { editMode = false }
                Button(l10n.t("Save")) {
                    onUpdateText(draftText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(l10n.t("Copy")) { onCopy(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footerText: String {
        let l = L10n.shared
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = l.locale
        var parts = [f.string(from: item.createdAt)]
        if item.fileSize != nil { parts.append(item.formattedSize) }
        if item.type == .text || item.type == .code {
            parts.append(String(format: l.t("Text · %d characters"), item.text?.count ?? 0))
        }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch item.type {
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    @ViewBuilder
    private var payload: some View {
        if editMode {
            TextEditor(text: $draftText)
                .font(.system(size: 12.5,
                              design: item.type == .code ? .monospaced : .default))
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        } else {
            payloadView
        }
    }

    @ViewBuilder
    private var payloadView: some View {
        switch item.type {
        case .image:
            VStack(alignment: .leading, spacing: 12) {
                if let image = ImageCache.image(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                } else {
                    Text(L10n.shared.t("Image unavailable")).foregroundStyle(.secondary)
                }
                if let ocr = item.ocrText, !ocr.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.shared.t("Recognized Text"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(ocr)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((item.text ?? "").components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    SyntaxHighlight.highlighted(line)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        case .text:
            if let attr = attributedRichText {
                Text(AttributedString(attr))
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            } else {
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
        case .file:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "doc.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.purple)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fileName ?? item.titleLine).font(.system(size: 14, weight: .semibold))
                        Text("\(L10n.shared.t(item.fileKind ?? "File")) · \(item.formattedSize)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if let path = item.fileURLPath {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var attributedRichText: NSAttributedString? {
        guard let rtf = item.rtfData else { return nil }
        return NSAttributedString(rtf: rtf, documentAttributes: nil)
    }
}
