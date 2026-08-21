import AppKit
import Combine
import UniformTypeIdentifiers

/// Polls the system pasteboard and turns new content into history records.
final class ClipboardMonitor: ObservableObject {

    private let store: HistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int
    /// changeCount produced by our own "copy back" writes — must be ignored.
    private var ignoredChangeCount: Int?

    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: "privacyMode") }
    }

    private let maxTextLength = 200_000
    private let maxDataLength = 8_000_000

    init(store: HistoryStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.isPaused = UserDefaults.standard.bool(forKey: "privacyMode")
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Copy an item back and mark the resulting changeCount as ours.
    func copyAndIgnore(_ item: ClipboardItem) {
        if store.copyToPasteboard(item) {
            ignoredChangeCount = NSPasteboard.general.changeCount
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if let ignored = ignoredChangeCount, ignored == pb.changeCount {
            ignoredChangeCount = nil
            return
        }
        guard !isPaused else { return }
        capture(from: pb)
    }

    // MARK: Capture

    private func capture(from pb: NSPasteboard) {
        let types = pb.types ?? []

        // 1. Files (file URLs, excluding plain URL strings from browsers)
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            captureFile(url: url, urls: urls, pasteboard: pb)
            return
        }

        // 2. Images
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if types.contains(where: imageTypes.contains) {
            if let type = imageTypes.first(where: { types.contains($0) }),
               let data = pb.data(forType: type) {
                captureImage(data: data, pb: pb)
                return
            }
        }
        if let data = pb.data(forType: NSPasteboard.PasteboardType(UTType.image.identifier)),
           NSBitmapImageRep(data: data) != nil {
            captureImage(data: data, pb: pb)
            return
        }

        // 3. Text (rich text kept alongside the plain string)
        if let text = pb.string(forType: .string), !text.isEmpty {
            let rtf = types.contains(.rtf) ? pb.data(forType: .rtf) : nil
            captureText(text: text, rtf: rtf)
            return
        }
    }

    private func captureText(text: String, rtf: Data?) {
        let trimmed = String(text.prefix(maxTextLength))
        let cleanRTF = (rtf?.count ?? 0) <= maxDataLength ? rtf : nil
        var item = ClipboardItem(
            type: Self.looksLikeCode(trimmed) ? .code : .text,
            text: trimmed,
            rtfData: cleanRTF
        )
        item.text = trimmed
        store.add(item)
    }

    private func captureImage(data: Data, pb: NSPasteboard) {
        guard data.count <= maxDataLength else { return }
        let png: Data?
        if let rep = NSBitmapImageRep(data: data) {
            png = rep.representation(using: .png, properties: [:]) ?? data
        } else {
            png = data
        }
        guard let pngData = png else { return }

        // Best-effort display name: pasted images sometimes carry a title/URL.
        var title: String? = nil
        if let url = pb.string(forType: .URL), !url.isEmpty {
            title = URL(string: url)?.lastPathComponent
        }
        if title == nil, let described = pb.string(forType: NSPasteboard.PasteboardType("public.url-name")), !described.isEmpty {
            title = described
        }

        let item = ClipboardItem(
            type: .image,
            fileName: title,
            fileKind: "PNG Image",
            fileSize: Int64(pngData.count)
        )
        store.add(item, imageBytes: pngData)
    }

    private func captureFile(url: URL, urls: [URL], pasteboard pb: NSPasteboard) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey, .localizedTypeDescriptionKey, .isRegularFileKey])
        let size = Int64(values?.fileSize ?? 0)
        let kind = values?.localizedTypeDescription
            ?? UTType(filenameExtension: url.pathExtension)?.localizedDescription
            ?? url.pathExtension.uppercased() + " File"

        // If it's a single readable image file, store it as an image record with thumbnail.
        let isImage = (values?.typeIdentifier).flatMap { UTType($0)?.conforms(to: .image) } ?? false
        if urls.count == 1, isImage, let data = try? Data(contentsOf: url), data.count <= maxDataLength {
            var item = ClipboardItem(
                type: .image,
                fileName: url.lastPathComponent,
                fileKind: kind,
                fileSize: size > 0 ? size : Int64(data.count)
            )
            item.fileURLPath = url.path
            store.add(item, imageBytes: data)
            return
        }

        var item = ClipboardItem(
            type: .file,
            fileName: url.lastPathComponent,
            fileKind: kind,
            fileSize: size,
            fileURLPath: url.path
        )
        if urls.count > 1 {
            item.text = urls.map(\.lastPathComponent).joined(separator: ", ")
        }
        store.add(item)
    }

    // MARK: Code heuristic

    private static func looksLikeCode(_ text: String) -> Bool {
        let indicators = ["func ", "var ", "let ", "import ", "class ", "def ", "return ", "public ", "private ",
                          "if (", "for (", "while (", "=>", "-> {", "{\n", "};", " #include", "npm ", "git "]
        let hits = indicators.filter { text.contains($0) }.count
        if hits >= 2 { return true }
        let lines = text.components(separatedBy: .newlines)
        let codeLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return false }
            return t.hasSuffix(";") || t.hasSuffix("{") || t.hasSuffix("}") || t.hasPrefix("//") || t.contains(" = ")
        }.count
        return lines.count >= 3 && Double(codeLines) / Double(max(lines.count, 1)) > 0.6
    }
}
