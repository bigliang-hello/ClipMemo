import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

// MARK: - Tool registry

enum ToolboxTool: String, CaseIterable, Identifiable {
    case color, translate, qr, codec, timestamp

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .color: return "Color Converter"
        case .translate: return "Translate Text"
        case .qr: return "QR Code"
        case .codec: return "Encode / Decode"
        case .timestamp: return "Timestamp"
        }
    }

    var subtitleKey: String {
        switch self {
        case .color: return "Convert between HEX, RGB, HSL and more."
        case .translate: return "Google Translate by default, or DeepL."
        case .qr: return "Turn text or links into a scannable code."
        case .codec: return "Base64, URL, Unicode escape and hashes."
        case .timestamp: return "Convert Unix timestamps to readable dates."
        }
    }

    var icon: String {
        switch self {
        case .color: return "paintpalette"
        case .translate: return "character.book.closed"
        case .qr: return "qrcode"
        case .codec: return "curlybraces"
        case .timestamp: return "clock"
        }
    }

    var tint: Color {
        switch self {
        case .color: return .pink
        case .translate: return .blue
        case .qr: return .indigo
        case .codec: return .green
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
        case .codec: CodecTool()
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

private extension View {
    /// Shared input-box chrome: subtle fill + hairline border, so every tool
    /// field reads as an actual text field instead of a bare colored patch.
    func toolFieldStyle() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
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
            .toolFieldStyle()

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
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Translate (Google gtx / DeepL)

private enum TranslationEngine: String, CaseIterable, Identifiable {
    case google, deepl
    var id: String { rawValue }
}

private enum TranslateTarget: String, CaseIterable, Identifiable {
    case app, zh, en, ja, ko, fr, de, es, ru, pt, ar

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .app: return L10n.shared.t("Follow App Language")
        case .zh: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .ru: return "Русский"
        case .pt: return "Português"
        case .ar: return "العربية"
        }
    }

    var googleCode: String {
        self == .zh ? "zh-CN" : rawValue
    }

    var deeplCode: String {
        self == .pt ? "PT-BR" : rawValue.uppercased()
    }

    /// Resolves "follow app language" to a concrete target.
    static func resolve(_ pick: TranslateTarget) -> TranslateTarget {
        guard pick == .app else { return pick }
        let code: String
        switch L10n.shared.language {
        case .chinese: code = "zh"
        case .english: code = "en"
        case .system: code = Locale.current.language.languageCode?.identifier ?? "en"
        }
        return TranslateTarget(rawValue: code) ?? .en
    }
}

/// Minimal generic-password wrapper so the DeepL key doesn't sit in
/// UserDefaults (which is plain text inside the app container).
private enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "ClipMemo"

    static func set(_ value: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct TranslateTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""
    @State private var output = ""
    @State private var failed = false
    @State private var missingKey = false
    @State private var busy = false
    @State private var engine: TranslationEngine =
        TranslationEngine(rawValue: UserDefaults.standard.string(forKey: "translateEngine") ?? "") ?? .google
    @State private var target: TranslateTarget =
        TranslateTarget(rawValue: UserDefaults.standard.string(forKey: "translateTarget") ?? "") ?? .app
    @State private var deeplKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("", selection: $engine) {
                    Text("Google").tag(TranslationEngine.google)
                    Text("DeepL").tag(TranslationEngine.deepl)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Picker("", selection: $target) {
                    ForEach(TranslateTarget.allCases) { target in
                        Text(target.nativeName).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
            }
            .onChange(of: engine) { _, e in
                UserDefaults.standard.set(e.rawValue, forKey: "translateEngine")
            }
            .onChange(of: target) { _, t in
                UserDefaults.standard.set(t.rawValue, forKey: "translateTarget")
            }

            if engine == .deepl {
                HStack(spacing: 8) {
                    Image(systemName: "key")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    SecureField(l10n.t("API Key"), text: $deeplKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: deeplKey) { _, k in
                            KeychainStore.set(k, forKey: "deeplAPIKey")
                        }
                    Text(l10n.t("Free API key at deepl.com"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .toolFieldStyle()
            }

            ToolFieldHeader(titleKey: "Text to translate") {
                pasteFromClipboard()
            }

            TextEditor(text: $input)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .toolFieldStyle()

            Button {
                translate()
            } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                    Text(busy ? l10n.t("Translating…") : l10n.t("Translate"))
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if failed {
                Text(l10n.t("Translation failed"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if missingKey {
                Text(l10n.t("DeepL requires an API key."))
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
                .toolFieldStyle()
            }

            Text(l10n.t("Text is sent to the selected translation service."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { deeplKey = KeychainStore.get("deeplAPIKey") ?? "" }
    }

    // MARK: Engines

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        failed = false
        missingKey = false
        let key = deeplKey.trimmingCharacters(in: .whitespaces)
        if engine == .deepl && key.isEmpty {
            missingKey = true
            return
        }
        let lang = TranslateTarget.resolve(target)
        let engine = engine
        busy = true
        Task {
            do {
                output = try await Self.run(engine: engine, text: text, target: lang, deeplKey: key)
            } catch {
                output = ""
                failed = true
            }
            busy = false
        }
    }

    private static func run(engine: TranslationEngine, text: String,
                            target: TranslateTarget, deeplKey: String) async throws -> String {
        switch engine {
        case .google: return try await google(text: text, target: target)
        case .deepl: return try await deepl(text: text, target: target, key: deeplKey)
        }
    }

    /// Google's public gtx endpoint — no key, auto source detection.
    /// Response: [[["translated","source",…],…], …] (nested JSON arrays).
    private static func google(text: String, target: TranslateTarget) async throws -> String {
        guard let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&dt=t&tl=\(target.googleCode)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "q", value: text)]
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONSerialization.jsonObject(with: data) as? [Any]
        guard let segments = payload?.first as? [[Any]] else { throw URLError(.cannotParseResponse) }
        let translated = segments.compactMap { $0.first as? String }.joined()
        guard !translated.isEmpty else { throw URLError(.cannotParseResponse) }
        return translated
    }

    /// DeepL official API. Free keys end in ":fx" and use the api-free host.
    private static func deepl(text: String, target: TranslateTarget, key: String) async throws -> String {
        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: target.deeplCode),
        ]
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let translations = payload?["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return translated
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            input = text
        }
    }
}

// MARK: - QR code

private enum QRModuleStyle: String, CaseIterable, Identifiable {
    case square, dot, rounded
    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .square: return "Square"
        case .dot: return "Dots"
        case .rounded: return "Rounded"
        }
    }
}

private enum QRCorrection: String, CaseIterable, Identifiable {
    case l = "L", m = "M", q = "Q", h = "H"
    var id: String { rawValue }

    /// Letter plus the data-recovery capacity it can survive, e.g. "H · 30%".
    var label: String {
        switch self {
        case .l: return "L · 7%"
        case .m: return "M · 15%"
        case .q: return "Q · 25%"
        case .h: return "H · 30%"
        }
    }
}

private struct QRTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var content = ""
    @State private var copied = false
    @State private var fgColor: Color = .black
    @State private var bgColor: Color = .white
    @State private var logo: NSImage?
    @State private var pickingLogo = false
    // Structural choices persist across launches; colors stay session-only.
    @AppStorage("qrModuleStyle") private var styleRaw = QRModuleStyle.square.rawValue
    @AppStorage("qrCorrection") private var correctionRaw = QRCorrection.m.rawValue

    private var style: QRModuleStyle { QRModuleStyle(rawValue: styleRaw) ?? .square }
    private var correction: QRCorrection { QRCorrection(rawValue: correctionRaw) ?? .m }

    private var qrImage: NSImage? {
        Self.render(content, fg: fgColor, bg: bgColor,
                    style: style, correction: correction, logo: logo)
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
                .toolFieldStyle()

            styleCard

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

            if lowContrast {
                Text(l10n.t("Low contrast — scanning may fail."))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if logo != nil, correction == .l || correction == .m {
                Text(l10n.t("Use Q or H correction when adding a logo."))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if qrImage != nil {
                Button {
                    guard let image = qrImage else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    // Write PNG bytes so other apps get a real image file payload.
                    if let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        pb.setData(png, forType: .png)
                    } else {
                        pb.writeObjects([image])
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(isPresented: $pickingLogo, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                logo = NSImage(contentsOf: url)
            }
        }
    }

    /// Colors, module shape, error correction and the center logo.
    private var styleCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(l10n.t("Foreground"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ColorPicker("", selection: $fgColor, supportsOpacity: false)
                        .labelsHidden()
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text(l10n.t("Background"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ColorPicker("", selection: $bgColor, supportsOpacity: true)
                        .labelsHidden()
                        .fixedSize()
                }
                Spacer()
                Text(l10n.t("Error Correction"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $correctionRaw) {
                    ForEach(QRCorrection.allCases) { level in
                        Text(level.label).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 10) {
                Picker("", selection: $styleRaw) {
                    ForEach(QRModuleStyle.allCases) { shape in
                        Text(l10n.t(shape.labelKey)).tag(shape.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                Spacer()
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Button(l10n.t("Choose Image…")) { pickingLogo = true }
                    .controlSize(.small)
                if logo != nil {
                    Button {
                        self.logo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t("Remove Logo"))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    /// Rough luminance check — QR scanners need a strong fg/bg contrast.
    private var lowContrast: Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let fg = NSColor(fgColor).usingColorSpace(.sRGB) ?? .black
        let bg = NSColor(bgColor).usingColorSpace(.sRGB) ?? .white
        guard bg.alphaComponent > 0.6 else { return false } // translucent bg: real backdrop unknown
        func luminance(_ c: NSColor) -> Double {
            0.2126 * Double(c.redComponent)
                + 0.7152 * Double(c.greenComponent)
                + 0.0722 * Double(c.blueComponent)
        }
        return abs(luminance(fg) - luminance(bg)) < 0.35
    }

    /// Builds the styled QR: the filter's raw black/white grid is read back
    /// pixel by pixel, then redrawn in Core Graphics so module shape, colors,
    /// quiet zone and logo are fully custom.
    private static func render(_ text: String, fg: Color, bg: Color,
                               style: QRModuleStyle, correction: QRCorrection,
                               logo: NSImage?) -> NSImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(trimmed.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let base = CIContext().createCGImage(output, from: output.extent) else { return nil }

        let rep = NSBitmapImageRep(cgImage: base)
        let cols = rep.pixelsWide, rows = rep.pixelsHigh

        let scale: CGFloat = 12
        let quiet: CGFloat = 4 * scale // standard 4-module quiet zone
        let width = Int(CGFloat(cols) * scale + quiet * 2)
        let height = Int(CGFloat(rows) * scale + quiet * 2)
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let fgColor = NSColor(fg).usingColorSpace(.sRGB) ?? .black
        let bgColor = NSColor(bg).usingColorSpace(.sRGB) ?? .white
        if bgColor.alphaComponent > 0.01 {
            ctx.setFillColor(bgColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        ctx.setFillColor(fgColor.cgColor)
        for row in 0..<rows {
            for col in 0..<cols {
                guard isDark(rep, col, row) else { continue }
                // Bitmap rows run top-down; Core Graphics is bottom-up.
                let rect = CGRect(x: quiet + CGFloat(col) * scale,
                                  y: quiet + CGFloat(rows - 1 - row) * scale,
                                  width: scale, height: scale)
                switch style {
                case .square:
                    ctx.fill(rect)
                case .rounded:
                    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                       cornerWidth: scale * 0.32, cornerHeight: scale * 0.32,
                                       transform: nil))
                    ctx.fillPath()
                case .dot:
                    let d = scale * 0.78
                    ctx.addPath(CGPath(ellipseIn: CGRect(x: rect.midX - d / 2,
                                                         y: rect.midY - d / 2,
                                                         width: d, height: d),
                                       transform: nil))
                    ctx.fillPath()
                }
            }
        }

        // Center logo on a rounded plate punched over the modules.
        if let logo, let logoCG = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let side = min(CGFloat(width), CGFloat(height)) * 0.2
            let inner = CGRect(x: (CGFloat(width) - side) / 2,
                               y: (CGFloat(height) - side) / 2,
                               width: side, height: side)
            let plate = inner.insetBy(dx: -side * 0.12, dy: -side * 0.12)
            ctx.setFillColor((bgColor.alphaComponent > 0.5 ? bgColor : .white).cgColor)
            ctx.addPath(CGPath(roundedRect: plate,
                               cornerWidth: side * 0.15, cornerHeight: side * 0.15,
                               transform: nil))
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: inner,
                               cornerWidth: side * 0.1, cornerHeight: side * 0.1,
                               transform: nil))
            ctx.clip()
            // Aspect-fill: scale to cover, centered.
            let coverScale = max(side / CGFloat(logoCG.width), side / CGFloat(logoCG.height))
            let dw = CGFloat(logoCG.width) * coverScale
            let dh = CGFloat(logoCG.height) * coverScale
            ctx.draw(logoCG, in: CGRect(x: inner.midX - dw / 2, y: inner.midY - dh / 2,
                                        width: dw, height: dh))
            ctx.restoreGState()
        }

        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: width, height: height))
    }

    private static func isDark(_ rep: NSBitmapImageRep, _ col: Int, _ row: Int) -> Bool {
        guard let c = rep.colorAt(x: col, y: row) else { return false }
        let srgb = c.usingColorSpace(.sRGB) ?? c
        return srgb.alphaComponent > 0.5
            && (srgb.redComponent + srgb.greenComponent + srgb.blueComponent) / 3 < 0.5
    }
}

// MARK: - Codec (Base64 / URL / Unicode escape, hashes)

private enum CodecOp: String, CaseIterable, Identifiable {
    case encode, decode, hash
    var id: String { rawValue }
}

private enum CodecFormat: String, CaseIterable, Identifiable {
    case base64, url, unicode
    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .base64: return "Base64"
        case .url: return "URL"
        case .unicode: return "Unicode"
        }
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private struct CodecTool: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var input = ""
    @State private var op: CodecOp = .encode
    @State private var format: CodecFormat = .base64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("", selection: $op) {
                    Text(l10n.t("Encode")).tag(CodecOp.encode)
                    Text(l10n.t("Decode")).tag(CodecOp.decode)
                    Text(l10n.t("Hash")).tag(CodecOp.hash)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                if op != .hash {
                    Picker("", selection: $format) {
                        ForEach(CodecFormat.allCases) { f in
                            Text(l10n.t(f.labelKey)).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Spacer()
            }

            ToolFieldHeader(titleKey: "Input") {
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    input = text
                }
            }

            TextEditor(text: $input)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .toolFieldStyle()

            if result.failed {
                Text(l10n.t("Invalid input"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if op == .hash {
                if !input.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(hashRows, id: \.0) { algo, hex in
                            CopyRow(label: algo, value: hex)
                        }
                    }
                }
            } else if let text = result.text, !text.isEmpty {
                ToolFieldHeader(titleKey: "Output") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
                ScrollView {
                    Text(text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .toolFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Conversion (live)

    private var result: (text: String?, failed: Bool) {
        let text = input
        guard !text.isEmpty else { return (nil, false) }
        switch (op, format) {
        case (.encode, .base64):
            return (Data(text.utf8).base64EncodedString(), false)
        case (.decode, .base64):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: " ", with: "")
            if let data = Data(base64Encoded: cleaned),
               let decoded = String(data: data, encoding: .utf8) {
                return (decoded, false)
            }
            return (nil, true)
        case (.encode, .url):
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return (text.addingPercentEncoding(withAllowedCharacters: allowed), false)
        case (.decode, .url):
            if let decoded = text.removingPercentEncoding {
                return (decoded, false)
            }
            return (nil, true)
        case (.encode, .unicode):
            return (Self.escapeUnicode(text), false)
        case (.decode, .unicode):
            return (Self.unescapeUnicode(text), false)
        case (.hash, _):
            return (nil, false) // hashes render as rows below
        }
    }

    private var hashRows: [(String, String)] {
        let data = Data(input.utf8)
        return [
            ("MD5", Insecure.MD5.hash(data: data).hexString),
            ("SHA-1", Insecure.SHA1.hash(data: data).hexString),
            ("SHA-256", SHA256.hash(data: data).hexString),
            ("SHA-512", SHA512.hash(data: data).hexString),
        ]
    }

    /// Non-ASCII → `\uXXXX`; astral planes → JSON-style surrogate pairs.
    private static func escapeUnicode(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar.value < 0x80 {
                out.unicodeScalars.append(scalar)
            } else if scalar.value <= 0xFFFF {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                let v = scalar.value - 0x10000
                out += String(format: "\\u%04x\\u%04x",
                              0xD800 + (v >> 10),
                              0xDC00 + (v & 0x3FF))
            }
        }
        return out
    }

    /// `\uXXXX` / `\UXXXXXXXX` → text, combining adjacent surrogate pairs.
    private static func unescapeUnicode(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\\\(u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8})") else {
            return s
        }
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        var out = ""
        var cursor = s.startIndex
        var index = 0

        func value(_ match: NSTextCheckingResult) -> UInt32? {
            guard let r = Range(match.range, in: s) else { return nil }
            let body = s[s.index(r.lowerBound, offsetBy: 2)..<r.upperBound]
            return UInt32(body, radix: 16)
        }
        func appendLiteral(_ match: NSTextCheckingResult) {
            guard let r = Range(match.range, in: s) else { return }
            out += String(s[r])
        }

        while index < matches.count {
            // Copy the text between matches.
            if let r = Range(matches[index].range, in: s), cursor < r.lowerBound {
                out += s[cursor..<r.lowerBound]
                cursor = r.lowerBound
            }
            let adjacent = index + 1 < matches.count
                && matches[index + 1].range.location == matches[index].range.location + matches[index].range.length
            if let hi = value(matches[index]), (0xD800...0xDBFF).contains(hi),
               adjacent, let lo = value(matches[index + 1]), (0xDC00...0xDFFF).contains(lo) {
                let combined = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                if let scalar = Unicode.Scalar(combined) {
                    out.unicodeScalars.append(scalar)
                    cursor = Range(matches[index + 1].range, in: s)!.upperBound
                    index += 2
                    continue
                }
            }
            if let v = value(matches[index]), let scalar = Unicode.Scalar(v) {
                out.unicodeScalars.append(scalar)
            } else {
                appendLiteral(matches[index]) // unpaired surrogate or invalid — keep as written
            }
            if let r = Range(matches[index].range, in: s), cursor < r.upperBound {
                cursor = r.upperBound
            }
            index += 1
        }
        if cursor < s.endIndex {
            out += s[cursor...]
        }
        return out
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
            .toolFieldStyle()

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
