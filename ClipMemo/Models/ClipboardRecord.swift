import CoreData

/// Core Data entity backing one clipboard record. Hand-written (no codegen) so it
/// stays in sync with the MainActor-default project settings.
@objc(ClipboardRecord)
final class ClipboardRecord: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var type: String?
    @NSManaged var text: String?
    @NSManaged var rtfData: Data?
    @NSManaged var imageData: Data?
    @NSManaged var fileName: String?
    @NSManaged var fileKind: String?
    @NSManaged var fileSize: Int64
    @NSManaged var fileURLPath: String?
    @NSManaged var isPinned: Bool
    @NSManaged var createdAt: Date?

    @nonobjc static func fetchRequest() -> NSFetchRequest<ClipboardRecord> {
        NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
    }
}

extension ClipboardRecord {

    /// Converts the managed object into the value type used by the UI layer.
    var item: ClipboardItem {
        ClipboardItem(
            id: id ?? UUID(),
            type: ContentType(rawValue: type ?? "") ?? .text,
            text: text,
            rtfData: rtfData,
            imageName: nil,
            fileName: fileName,
            fileKind: fileKind,
            fileSize: fileSize,
            fileURLPath: fileURLPath,
            isPinned: isPinned,
            createdAt: createdAt ?? Date()
        )
    }

    /// Writes the value type's fields into this managed object.
    func apply(_ item: ClipboardItem, imageBytes: Data?) {
        id = item.id
        type = item.type.rawValue
        text = item.text
        rtfData = item.rtfData
        if let imageBytes { imageData = imageBytes }
        fileName = item.fileName
        fileKind = item.fileKind
        fileSize = item.fileSize ?? 0
        fileURLPath = item.fileURLPath
        isPinned = item.isPinned
        createdAt = item.createdAt
    }
}
