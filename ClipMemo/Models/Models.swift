import SwiftUI
import Combine
import CoreData
import UniformTypeIdentifiers
import Vision

// MARK: - Types

enum ContentType: String, Codable {
    case text
    case code
    case image
    case file
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: ContentType = .text
    var text: String?                 // plain text or code source
    var rtfData: Data?                // rich text payload (RTF)
    var imageName: String?            // legacy JSON import only
    var fileName: String?             // display name for image / file records
    var fileKind: String?             // e.g. "PNG Image", "PDF Document"
    var fileSize: Int64?              // bytes
    var fileURLPath: String?          // original path (file records)
    var sourceBundleID: String?       // app the clip was copied from
    var sourceAppName: String?
    var ocrText: String?              // text recognized in images (Vision)
    var isPinned: Bool = false
    var createdAt: Date = Date()
}

// MARK: - Helpers

extension ClipboardItem {

    var titleLine: String {
        let l = L10n.shared
        switch type {
        case .image:
            return fileName ?? l.t("Image")
        case .file:
            return fileName ?? l.t("Unknown File")
        case .text, .code:
            return text?.firstNonEmptyLine ?? l.t("Text")
        }
    }

    var subtitleLine: String {
        let l = L10n.shared
        switch type {
        case .image:
            // A snippet of the recognized text doubles as a searchability cue.
            if let line = ocrText?.firstNonEmptyLine, !line.isEmpty {
                return String(line.prefix(60))
            }
            return "\(l.t(fileKind ?? "Image")) · \(formattedSize)"
        case .file:
            return "\(l.t(fileKind ?? "File")) · \(formattedSize)"
        case .text:
            if let second = text?.secondNonEmptyLine, !second.isEmpty { return second }
            return String(format: l.t("Text · %d characters"), text?.count ?? 0)
        case .code:
            if let second = text?.secondNonEmptyLine, !second.isEmpty { return second }
            return String(format: l.t("Code · %d lines"), text?.lineCount ?? 0)
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize ?? 0, countStyle: .file)
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.locale = L10n.shared.locale
        return f.string(from: createdAt)
    }

    /// A plain-text payload used for search, sharing and fallback copy.
    var searchText: String {
        [text, fileName, fileKind, fileURLPath, sourceAppName, ocrText]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}

extension String {
    var nonEmptyLines: [String] {
        components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var firstNonEmptyLine: String {
        nonEmptyLines.first ?? ""
    }

    var secondNonEmptyLine: String {
        let lines = nonEmptyLines
        return lines.count > 1 ? lines[1] : ""
    }

    var lineCount: Int {
        components(separatedBy: .newlines).count
    }
}

// MARK: - Date grouping

enum DateGroup {
    static let order = ["Pinned", "Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Earlier"]

    static func group(for item: ClipboardItem) -> String {
        if item.isPinned { return "Pinned" }
        return name(for: item.createdAt)
    }

    static func name(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let seven = cal.date(byAdding: .day, value: -7, to: Date()), date > seven { return "Previous 7 Days" }
        if let thirty = cal.date(byAdding: .day, value: -30, to: Date()), date > thirty { return "Previous 30 Days" }
        return "Earlier"
    }
}

// MARK: - Store (Core Data backed, optionally CloudKit-mirrored)

final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var iCloudSyncActive = false
    @Published private(set) var iCloudSyncError: String?
    @Published private(set) var iCloudAccountAvailable = FileManager.default.ubiquityIdentityToken != nil

    private let persistence = PersistenceController.shared
    private var refetchTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Sync can only engage when the build carries the iCloud entitlement AND
    /// the user is signed in to iCloud.
    var iCloudSyncAvailable: Bool {
        PersistenceController.hasCloudKitEntitlement && iCloudAccountAvailable
    }

    var entitlementMissing: Bool {
        !PersistenceController.hasCloudKitEntitlement
    }

    var viewContext: NSManagedObjectContext { persistence.viewContext }

    var historyLimit: Int {
        guard UserDefaults.standard.object(forKey: "historyLimit") != nil else { return 500 }
        let raw = UserDefaults.standard.integer(forKey: "historyLimit")
        return raw <= 0 ? Int.max : raw
    }

    init() {
        importLegacyJSONIfNeeded()
        refetch()

        // Local edits already refetch directly; watch remote (CloudKit) imports
        // and container rebuilds from the toggle in Settings.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefetch() })
        observers.append(NotificationCenter.default.addObserver(
            forName: .clipMemoStoreDidRebuild, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshSyncState(); self?.refetch() })
        refreshSyncState()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func refreshSyncState() {
        iCloudSyncActive = persistence.syncActive
        iCloudSyncError = persistence.syncError
        iCloudAccountAvailable = persistence.iCloudAccountAvailable
    }

    private func scheduleRefetch() {
        refetchTask?.cancel()
        refetchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            self?.refetch()
        }
    }

    // MARK: Fetching

    func refetch() {
        let request = ClipboardRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let records = (try? viewContext.fetch(request)) ?? []
        items = records.map(\.item)
        refreshSyncState()
    }

    private func record(for id: UUID) -> ClipboardRecord? {
        let request = ClipboardRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    // MARK: Mutations

    /// Adds a record; `imageBytes` carries image payloads (also used for image files).
    func add(_ item: ClipboardItem, imageBytes: Data? = nil) {
        if isDuplicate(of: item, imageBytes: imageBytes) { return }
        let record = ClipboardRecord(context: viewContext)
        record.apply(item, imageBytes: imageBytes)
        try? viewContext.save()
        trimToLimit()
        purgeExpired()
        refetch()
    }

    private func isDuplicate(of item: ClipboardItem, imageBytes: Data?) -> Bool {
        guard let newest = items.first,
              newest.type == item.type,
              newest.text == item.text,
              newest.rtfData == item.rtfData,
              newest.fileName == item.fileName,
              newest.fileURLPath == item.fileURLPath else { return false }
        guard item.type == .image, let bytes = imageBytes else { return true }
        return record(for: newest.id)?.imageData == bytes
    }

    private func trimToLimit() {
        let request = ClipboardRecord.fetchRequest()
        request.predicate = NSPredicate(format: "isPinned == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let unpinned = try? viewContext.fetch(request), unpinned.count > historyLimit else { return }
        for doomed in unpinned[historyLimit...] {
            viewContext.delete(doomed)
        }
        try? viewContext.save()
    }

    /// Removes unpinned records older than the "Auto-delete after" setting
    /// (0 = never). Called on launch and whenever a new record is added.
    @discardableResult
    func purgeExpired() -> Bool {
        let days = UserDefaults.standard.integer(forKey: "autoExpireDays")
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return false
        }
        let request = ClipboardRecord.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt < %@ AND isPinned == NO", cutoff as NSDate)
        guard let doomed = try? viewContext.fetch(request), !doomed.isEmpty else { return false }
        doomed.forEach(viewContext.delete)
        try? viewContext.save()
        return true
    }

    func remove(_ id: UUID) {
        guard let record = record(for: id) else { return }
        viewContext.delete(record)
        try? viewContext.save()
        refetch()
    }

    func togglePin(_ id: UUID) {
        guard let record = record(for: id) else { return }
        record.isPinned.toggle()
        try? viewContext.save()
        refetch()
    }

    /// Edits a text/code record in place; the rich-text payload no longer
    /// matches the edited text, so it is dropped.
    func updateText(_ id: UUID, to newText: String) {
        guard let record = record(for: id) else { return }
        record.text = newText
        record.rtfData = nil
        try? viewContext.save()
        refetch()
    }

    func clearAll(keepPinned: Bool = false) {
        let request = ClipboardRecord.fetchRequest()
        if keepPinned {
            request.predicate = NSPredicate(format: "isPinned == NO")
        }
        for record in (try? viewContext.fetch(request)) ?? [] {
            viewContext.delete(record)
        }
        try? viewContext.save()
        refetch()
    }

    /// Replaces the whole history (used by first-launch seeding).
    func replaceAll(with newItems: [ClipboardItem], imageBytesByID: [UUID: Data] = [:]) {
        clearAll()
        for item in newItems {
            let record = ClipboardRecord(context: viewContext)
            record.apply(item, imageBytes: imageBytesByID[item.id])
        }
        try? viewContext.save()
        refetch()
    }

    // MARK: Images

    func imageData(for item: ClipboardItem) -> Data? {
        record(for: item.id)?.imageData
    }

    func imageNSImage(for item: ClipboardItem) -> NSImage? {
        guard let data = imageData(for: item) else { return nil }
        return NSImage(data: data)
    }

    /// Materializes the image into a temp file (for sharing).
    func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let data = imageData(for: item) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(item.id.uuidString)
            .appendingPathExtension("png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: OCR (Vision)

    /// Settings toggle — on by default.
    var ocrEnabled: Bool {
        UserDefaults.standard.object(forKey: "ocrEnabled") == nil
            || UserDefaults.standard.bool(forKey: "ocrEnabled")
    }

    /// Runs Vision text recognition on a freshly captured image in the
    /// background and stores the result so the record becomes searchable.
    func performOCR(for item: ClipboardItem) {
        guard ocrEnabled, item.type == .image,
              let data = record(for: item.id)?.imageData else { return }
        let id = item.id
        Task.detached(priority: .utility) { [weak self] in
            let text = Self.recognizeText(in: data)
            await self?.storeOCRText(text, for: id)
        }
    }

    private func storeOCRText(_ text: String, for id: UUID) {
        guard let record = record(for: id) else { return } // deleted meanwhile
        record.ocrText = text.isEmpty ? nil : text
        try? viewContext.save()
        refetch()
    }

    /// Pure Vision call — runs entirely off the main actor, fully offline.
    nonisolated private static func recognizeText(in data: Data) -> String {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        var recognized = ""
        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            recognized = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"] // Chinese + English mixed
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return recognized
    }

    // MARK: iCloud toggle (Settings)

    func setSyncEnabled(_ enabled: Bool) {
        persistence.setSyncEnabled(enabled)
        refreshSyncState()
        scheduleRefetch() // rebuild posts too, but keep state snappy
    }

    // MARK: Copy back to the system pasteboard

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem, plainText: Bool = false) -> Bool {
        let pb = NSPasteboard.general
        pb.declareTypes([], owner: nil)
        if plainText, let text = item.text {
            // ⌥⏎ paste: strip formatting, only the plain string goes out.
            pb.setString(text, forType: .string)
            return true
        }
        switch item.type {
        case .image:
            guard let data = imageData(for: item),
                  let image = NSImage(data: data) else { return false }
            pb.writeObjects([image])
        case .file:
            guard let path = item.fileURLPath else { return false }
            pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
        case .text, .code:
            if let rtf = item.rtfData,
               let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                pb.writeObjects([attr])
            } else if let text = item.text {
                pb.setString(text, forType: .string)
            } else {
                return false
            }
        }
        return true
    }

    // MARK: Legacy JSON migration

    private func importLegacyJSONIfNeeded() {
        guard UserDefaults.standard.object(forKey: "didImportLegacyHistory") == nil else { return }
        UserDefaults.standard.set(true, forKey: "didImportLegacyHistory")

        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipMemo", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("history.json")
        let imagesDir = dir.appendingPathComponent("Images", isDirectory: true)

        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode([ClipboardItem].self, from: data), !legacy.isEmpty else { return }

        for item in legacy {
            let record = ClipboardRecord(context: viewContext)
            var bytes: Data? = nil
            if let name = item.imageName {
                bytes = try? Data(contentsOf: imagesDir.appendingPathComponent(name))
            }
            record.apply(item, imageBytes: bytes)
        }
        try? viewContext.save()
    }
}
