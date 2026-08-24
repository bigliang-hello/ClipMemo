import SwiftUI
import Translation

// MARK: - Tool registry

enum ToolboxTool: String, CaseIterable, Identifiable {
    case color, translate, qr, base64, timestamp

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .color: return "Color Converter"
        case .translate: return "Translate Text"
        case .qr: return "QR Code"
        case .base64: return "Base64"
        case .timestamp: return "Timestamp"
        }
    }

    var subtitleKey: String {
        switch self {
        case .color: return "Convert between HEX, RGB, HSL and more."
        case .translate: return "Translate with the system translation engine."
        case .qr: return "Turn text or links into a scannable code."
        case .base64: return "Encode or decode Base64 text."
        case .timestamp: return "Convert Unix timestamps to readable dates."
        }
    }

    var icon: String {
        switch self {
        case .color: return "paintpalette"
        case .translate: return "character.book.closed"
        case .qr: return "qrcode"
        case .base64: return "curlybraces"
        case .timestamp: return "clock"
        }
    }

    var tint: Color {
        switch self {
        case .color: return .pink
        case .translate: return .blue
        case .qr: return .indigo
        case .base64: return .green
        case .timestamp: return .orange
        }
    }
}

// MARK: - Toolbox shell (grid + detail)

struct ToolboxView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedTool: ToolboxTool?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let tool = selectedTool {
                ScrollView {
                    toolContent(tool)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(tool)
            } else {
                grid
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let tool = selectedTool {
                Button {
                    selectedTool = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(l10n.t("Back"))
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(selectedTool.map { l10n.t($0.titleKey) } ?? l10n.t("Toolbox"))
                .font(.system(size: 14, weight: .semibold))
            if selectedTool == nil {
                Text(l10n.t("Small utilities for clipboard content."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(ToolboxTool.allCases) { tool in
                    ToolCard(tool: tool) { selectedTool = tool }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func toolContent(_ tool: ToolboxTool) -> some View {
        switch tool {
        case .color: ColorTool()
        case .translate: TranslateTool()
        case .qr: QRTool()
        case .base64: Base64Tool()
        case .timestamp: TimestampTool()
        }
    }
}

private struct ToolCard: View {
    let tool: ToolboxTool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tool.tint.opacity(0.13))
                    .frame(width: 38, height: 38)
                Image(systemName: tool.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tool.tint)
            }
            Text(L10n.shared.t(tool.titleKey))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(L10n.shared.t(tool.subtitleKey))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.055 : 0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hover = $0 }
    }
}

// MARK: - Shared row: label + value + copy

private struct CopyRow: View {
    let label: String
    let value: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
    }
}

// MARK: - Color converter

private struct ParsedColor: Equatable {
    var r, g, b, a: Double // components in 0...1

    var hex: String {
        a < 0.999
            ? String(format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
            : String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    var rgb: String {
        a < 0.999
            ? String(format: "rgba(%.0f, %.0f, %.0f, %.2f)", r * 255, g * 255, b * 255, a)
            : String(format: "rgb(%.0f, %.0f, %.0f)", r * 255, g * 255, b * 255)
    }

    var hsl: String {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        let d = mx - mn
        var h = 0.0, s = 0.0
        if d > 1e-9 {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
        }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h, s * 100, l * 100)
    }

    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }

    var swiftCode: String {
        a < 0.999
            ? String(format: "Color(red: %.3f, green: %.3f, blue: %.3f, opacity: %.3f)", r, g, b, a)
            : String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)
    }

    private func byte(_ v: Double) -> Int {
        max(0, min(255, Int((v * 255).rounded())))
    }

    /// Accepts `#RGB`, `#RRGGBB(BB)`, `0x…`, `rgb()/rgba()` and plain `r, g, b[, a]`.
    static func parse(_ raw: String) -> ParsedColor? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty, s.count <= 32 else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        else if s.hasPrefix("0x") { s.removeFirst(2) }
        if s.contains("(") {
            let inner = s.split(separator: "(").last?.split(separator: ")").first
            s = inner.map(String.init) ?? ""
        }

        // Comma / space separated numbers in 0–255 (with optional alpha).
        let tokens = s.split { ",; \t".contains($0) }
        if (3...4).contains(tokens.count),
           let nums = tokens.wholeNumbers, nums.count == tokens.count,
           nums.allSatisfy({ (0...255).contains($0) }) {
            return ParsedColor(r: nums[0] / 255, g: nums[1] / 255, b: nums[2] / 255,
                               a: nums.count == 4 ? nums[3] / 255 : 1)
        }

        // Pure hex digits, 3 / 6 / 8 long (shorthand expanded).
        let hex = s.filter { $0.isHexDigit }
        guard hex.count == s.count, hex.count == 3 || hex.count == 6 || hex.count == 8 else { return nil }
        let chars = Array(hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex)
        var vals: [Double] = []
        for i in stride(from: 0, to: 6, by: 2) {
            guard let v = Int(String(chars[i]) + String(chars[i + 1]), radix: 16) else { return nil }
            vals.append(Double(v) / 255)
        }
        if chars.count == 8 {
            guard let v = Int(String(chars[6]) + String(chars[7]), radix: 16) else { return nil }
            vals.append(Double(v) / 255)
        }
        return ParsedColor(r: vals[0], g: vals[1], b: vals[2], a: vals.count == 4 ? vals[3] : 1)
    }
}

private extension Array where Element == Substring {
    /// All tokens parse as whole numbers, or nil.
    var wholeNumbers: [Double]? {
        var result: [Double] = []
        for token in self {
            guard let d = Double(token), d == d.rounded() else { return nil }
            result.append(d)
        }
        return result
    }
}

private struct ColorTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""

    private var parsed: ParsedColor? { ParsedColor.parse(input) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(l10n.t("Enter a color (HEX, rgb()…)"), text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                Button {
                    pickFromScreen()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 10))
                        Text(l10n.t("Pick Color from Screen"))
                            .font(.system(size: 11))
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            if !input.isEmpty && parsed == nil {
                Text(l10n.t("Invalid color"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if let c = parsed {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(c.swiftUIColor)
                    .frame(height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )

                VStack(spacing: 4) {
                    CopyRow(label: "HEX", value: c.hex)
                    CopyRow(label: "RGB", value: c.rgb)
                    CopyRow(label: "HSL", value: c.hsl)
                    CopyRow(label: "Swift", value: c.swiftCode)
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func pickFromScreen() {
        let sampler = NSColorSampler()
        sampler.show { color in
            guard let color else { return }
            let converted = color.usingColorSpace(.deviceRGB) ?? color
            input = String(format: "#%02X%02X%02X",
                           Int(converted.redComponent * 255),
                           Int(converted.greenComponent * 255),
                           Int(converted.blueComponent * 255))
        }
    }
}

// MARK: - Translate (system Translation framework)

private struct TranslateTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""
    @State private var output = ""
    @State private var failed = false
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolFieldHeader(titleKey: "Text to translate") {
                pasteFromClipboard()
            }

            TextEditor(text: $input)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            Button {
                failed = false
                config = .init() // presents the system translation sheet
            } label: {
                Label(l10n.t("Translate"), systemImage: "character.book.closed")
                    .font(.system(size: 12, weight: .medium))
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if failed {
                Text(l10n.t("Translation failed"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if !output.isEmpty {
                ToolFieldHeader(titleKey: "Translated text") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(output, forType: .string)
                }
                ScrollView {
                    Text(output)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .translationTask(config) { session in
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            do {
                let response = try await session.translate(text)
                output = response.targetText
                failed = false
            } catch {
                failed = true
            }
        }
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            input = text
        }
    }
}

// MARK: - QR code

private struct QRTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var content = ""
    @State private var copied = false

    private var qrImage: NSImage? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let image = NSImage(size: scaled.extent.size)
        image.addRepresentation(NSCIImageRep(ciImage: scaled))
        return image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolFieldHeader(titleKey: "Content") {
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    content = text
                }
            }

            TextEditor(text: $content)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 70)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                if let image = qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 26))
                        Text(l10n.t("Text or URL to encode"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 220, height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            if qrImage != nil {
                Button {
                    guard let image = qrImage else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { copied = false }
                } label: {
                    Label(copied ? l10n.t("Copied") : l10n.t("Copy Image"),
                          systemImage: copied ? "checkmark" : "photo.on.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

// MARK: - Base64

private struct Base64Tool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""
    @State private var output = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolFieldHeader(titleKey: "Input") {
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    input = text
                }
            }

            TextEditor(text: $input)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            HStack(spacing: 10) {
                Button(l10n.t("Encode")) { run(encode: true) }
                Button(l10n.t("Decode")) { run(encode: false) }
            }
            .controlSize(.regular)

            if invalid {
                Text(l10n.t("Invalid Base64 input"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if !output.isEmpty {
                ToolFieldHeader(titleKey: "Output") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(output, forType: .string)
                }
                ScrollView {
                    Text(output)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func run(encode: Bool) {
        invalid = false
        output = ""
        let text = input
        if encode {
            output = Data(text.utf8).base64EncodedString()
        } else {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let data = Data(base64Encoded: cleaned),
                  let decoded = String(data: data, encoding: .utf8) else {
                invalid = true
                return
            }
            output = decoded
        }
    }
}

// MARK: - Timestamp

private struct TimestampTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""

    private struct Converted {
        var seconds: Int
        var date: Date
    }

    private var converted: Converted? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Epoch number — auto-detect seconds vs milliseconds.
        if let n = Double(trimmed), trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            let ms = abs(n) >= 1e11 // anything this large must be milliseconds
            return Converted(seconds: ms ? Int(n / 1000) : Int(n), date: Date(timeIntervalSince1970: ms ? n / 1000 : n))
        }
        // Date strings: ISO 8601 first, then "yyyy-MM-dd HH:mm:ss".
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: trimmed) ?? isoWithFraction.date(from: trimmed) {
            return Converted(seconds: Int(d.timeIntervalSince1970), date: d)
        }
        if let d = customFormatter.date(from: trimmed) {
            return Converted(seconds: Int(d.timeIntervalSince1970), date: d)
        }
        return nil
    }

    private var isoWithFraction: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private var customFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }

    private var localFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = l10n.locale
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }

    private var utcFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(l10n.t("Unix Timestamp"), text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                Button(l10n.t("Now")) {
                    input = String(Int(Date().timeIntervalSince1970))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            Text(l10n.t("Auto-detects seconds or milliseconds"))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            if !input.isEmpty && converted == nil {
                Text(l10n.t("Invalid timestamp or date"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if let c = converted {
                VStack(spacing: 4) {
                    CopyRow(label: l10n.t("Seconds"), value: "\(c.seconds)")
                    CopyRow(label: l10n.t("Milliseconds"), value: "\(c.seconds * 1000)")
                    CopyRow(label: l10n.t("Local Time"), value: localFormatter.string(from: c.date))
                    CopyRow(label: "UTC", value: utcFormatter.string(from: c.date))
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

// MARK: - Small shared header for editable fields

private struct ToolFieldHeader: View {
    @ObservedObject private var l10n = L10n.shared
    let titleKey: String
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(l10n.t(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button {
                    action()
                } label: {
                    Label(l10n.t("Paste"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .controlSize(.mini)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    init(titleKey: String, action: (() -> Void)? = nil) {
        self.titleKey = titleKey
        self.action = action
    }
}
