import AppKit

/// One entry in the switcher.
struct SwitchItem {
    /// nil when the app is pinned in the Dock but not running.
    let app: NSRunningApplication?
    let bundleURL: URL?
    let name: String
    let icon: NSImage
    /// Finder or kept in the Dock (left of the Dock's divider).
    let isPinned: Bool
}

/// Builds the switcher list in the same order the Dock shows it:
/// Finder, then the apps kept in the Dock (in their Dock order),
/// then the other running apps in the order they were opened.
enum DockOrder {
    struct PinnedApp {
        let bundleId: String?
        let url: URL?
    }

    /// The apps kept in the Dock, read from the Dock's own preferences.
    /// The Dock updates these as soon as you drag an icon, so the list is always current.
    static func pinnedApps() -> [PinnedApp] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] else {
            return []
        }
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any] else { return nil } // spacers have no tile-data
            let bundleId = data["bundle-identifier"] as? String
            let urlString = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String
            let url = urlString.flatMap { URL(string: $0) }
            if bundleId == nil && url == nil { return nil }
            return PinnedApp(bundleId: bundleId, url: url)
        }
    }

    static func items(includeNotRunning: Bool) -> [SwitchItem] {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        var remaining = NSWorkspace.shared.runningApplications.enumerated()
            .filter { $0.element.activationPolicy == .regular && !$0.element.isTerminated && $0.element.processIdentifier != ownPid }
            .sorted { lhs, rhs in
                let l = lhs.element.launchDate ?? .distantPast
                let r = rhs.element.launchDate ?? .distantPast
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)

        func take(_ matches: (NSRunningApplication) -> Bool) -> [NSRunningApplication] {
            let taken = remaining.filter(matches)
            remaining.removeAll(where: matches)
            return taken
        }

        var result: [SwitchItem] = []

        // Finder is always the first icon in the Dock.
        result += take { $0.bundleIdentifier == "com.apple.finder" }.map { item(for: $0, pinned: true) }

        for pinned in pinnedApps() {
            let running = take { app in
                if let id = pinned.bundleId, id == app.bundleIdentifier { return true }
                if let url = pinned.url, let appURL = app.bundleURL, samePath(url, appURL) { return true }
                return false
            }
            if !running.isEmpty {
                result += running.map { item(for: $0, pinned: true) }
            } else if includeNotRunning, let notRunning = item(forNotRunning: pinned) {
                result.append(notRunning)
            }
        }

        result += remaining.map { item(for: $0, pinned: false) }
        return result
    }

    private static func item(for app: NSRunningApplication, pinned: Bool) -> SwitchItem {
        let icon = app.icon ?? app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
        let name = app.localizedName ?? app.bundleURL.map { displayName(of: $0) } ?? "App"
        return SwitchItem(app: app, bundleURL: app.bundleURL, name: name, icon: icon, isPinned: pinned)
    }

    private static func item(forNotRunning pinned: PinnedApp) -> SwitchItem? {
        let fm = FileManager.default
        var url = pinned.bundleId.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if url == nil, let pinnedURL = pinned.url, fm.fileExists(atPath: pinnedURL.path) { url = pinnedURL }
        guard let url else { return nil }
        return SwitchItem(app: nil, bundleURL: url, name: displayName(of: url),
                          icon: NSWorkspace.shared.icon(forFile: url.path), isPinned: true)
    }

    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func samePath(_ a: URL, _ b: URL) -> Bool {
        func normalized(_ url: URL) -> String {
            var path = url.resolvingSymlinksInPath().path
            while path.hasSuffix("/") && path.count > 1 { path.removeLast() }
            return path
        }
        return normalized(a) == normalized(b)
    }
}
