import CoreData
import CloudKit
import Combine
import Security

/// Owns the Core Data stack. A single SQLite store: when iCloud sync is enabled
/// (and an iCloud account is signed in) it is opened with CloudKit mirroring;
/// otherwise it runs purely locally. The same file is used either way, so
/// toggling the setting never moves or loses data.
final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()
    static let cloudContainerID = "iCloud.cn.yiling.berry.health.ClipMemo"

    @Published private(set) var syncActive = false
    @Published private(set) var syncError: String?

    private(set) var container: NSPersistentCloudKitContainer

    static var isSyncWanted: Bool {
        UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
    }

    var iCloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// True when the running binary was signed with the iCloud entitlement
    /// (free personal teams can't sign it — see ClipMemo-iCloud.entitlements).
    static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
        return services?.contains("CloudKit") == true
    }

    init() {
        let cloudBacked = Self.isSyncWanted && Self.hasCloudKitEntitlement
                          && FileManager.default.ubiquityIdentityToken != nil
        container = Self.makeContainer(cloudBacked: cloudBacked)
        load(cloudBacked: cloudBacked)
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: Store lifecycle

    private static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipMemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    private static func makeContainer(cloudBacked: Bool) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "ClipMemo")
        let description = NSPersistentStoreDescription(url: storeURL())
        // Both options are required for CloudKit mirroring and remote-change posts.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if cloudBacked {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudContainerID)
        }
        container.persistentStoreDescriptions = [description]
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }

    private func load(cloudBacked: Bool) {
        container.loadPersistentStores { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    if cloudBacked {
                        // CloudKit unavailable (container not provisioned, network, …):
                        // fall back to a local-only store so history keeps working.
                        self.syncError = "iCloud sync couldn’t start: \(error.localizedDescription)"
                        self.rebuild(cloudBacked: false)
                    } else {
                        self.syncError = error.localizedDescription
                        self.syncActive = false
                    }
                } else {
                    self.syncError = nil
                    self.syncActive = cloudBacked
                }
            }
        }
    }

    /// Tears the current container down and loads the store again, with or
    /// without CloudKit mirroring.
    private func rebuild(cloudBacked: Bool) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        container = Self.makeContainer(cloudBacked: cloudBacked)
        load(cloudBacked: cloudBacked)
        NotificationCenter.default.post(name: .clipMemoStoreDidRebuild, object: nil)
    }

    // MARK: Public toggle

    func setSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "iCloudSyncEnabled")
        syncError = nil
        let cloudBacked = enabled && Self.hasCloudKitEntitlement && iCloudAccountAvailable
        if cloudBacked != syncActive {
            rebuild(cloudBacked: cloudBacked)
        }
        if enabled && !Self.hasCloudKitEntitlement {
            syncError = "This build doesn’t include the iCloud capability. Rebuild with the iCloud entitlements (requires a paid Apple Developer team)."
        } else if enabled && !iCloudAccountAvailable {
            syncError = "Sign in to iCloud in System Settings to enable sync."
        }
    }
}

extension Notification.Name {
    static let clipMemoStoreDidRebuild = Notification.Name("clipMemoStoreDidRebuild")
}
