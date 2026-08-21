import AppKit

/// Resolves source-app metadata (icon / display name) for bundle IDs.
/// Lookups hit the disk the first time, so results are cached.
enum SourceApps {

    private static let nameCache = NSCache<NSString, NSString>()
    private static let iconCache = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        iconCache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    static func displayName(for bundleID: String) -> String? {
        if let cached = nameCache.object(forKey: bundleID as NSString) {
            return cached as String
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        else { return nil }
        nameCache.setObject(name as NSString, forKey: bundleID as NSString)
        return name
    }
}

/// Apps whose clipboard content is never recorded. Coping from a password
/// manager or banking app is almost always a secret, so a few are pre-seeded
/// on first launch; the user manages the rest in Settings.
enum ExclusionList {

    private static let key = "excludedAppBundleIDs"

    private static let seededDefaults = [
        "com.1password.1password",       // 1Password 8
        "com.agilebits.onepassword-osx", // 1Password 7
        "com.bitwarden.desktop"          // Bitwarden
    ]

    static var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Adds the default password managers the first time the app runs.
    static func seedIfNeeded() {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(seededDefaults, forKey: key)
    }

    static func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return all.contains(bundleID)
    }

    static func add(_ bundleID: String) {
        var list = all
        guard !list.contains(bundleID) else { return }
        list.append(bundleID)
        all = list
    }

    static func remove(_ bundleID: String) {
        all = all.filter { $0 != bundleID }
    }
}
