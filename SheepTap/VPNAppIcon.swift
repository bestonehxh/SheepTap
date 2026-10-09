import AppKit

/// The icon of the app behind a VPN tunnel — FortiClient's, Tailscale's —
/// taken from the copy installed on this Mac rather than shipped logos.
///
/// Tried in order, each only accepted when it leads to a real `.app`:
/// 1. The tunnel's own Network Extension bundle ID. An app extension is
///    registered inside its host app, so walking up to the outermost `.app`
///    finds the client. A system extension lives in /Library/SystemExtensions
///    with no host around it and is skipped.
/// 2. The vendor's client, if it is running.
/// 3. The vendor's known app bundle IDs.
enum VPNAppIcon {
    private struct Entry {
        let image: NSImage?
        let date: Date
    }

    private static var cache: [String: Entry] = [:]
    /// A miss is retried after this long, so a client launched or installed
    /// while SheepTap runs still gets its icon.
    private static let missLifetime: TimeInterval = 30

    static func image(provider: String?, bundleID: String?) -> NSImage? {
        guard provider != nil || bundleID != nil else { return nil }
        let key = "\(bundleID ?? "")|\(provider ?? "")"
        if let entry = cache[key],
           entry.image != nil || Date().timeIntervalSince(entry.date) < missLifetime {
            return entry.image
        }
        let image = appURL(provider: provider, bundleID: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[key] = Entry(image: image, date: Date())
        return image
    }

    private static func appURL(provider: String?, bundleID: String?) -> URL? {
        let workspace = NSWorkspace.shared

        if let bundleID,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID),
           let app = outermostApp(containing: url) {
            return app
        }

        guard let provider, let vendor = VPNProvider.vendor(called: provider) else { return nil }

        let running = workspace.runningApplications.first { app in
            guard let id = app.bundleIdentifier else { return false }
            return VPNProvider.vendor(bundleID: id)?.name == vendor.name
        }
        if let url = running?.bundleURL, let app = outermostApp(containing: url) {
            return app
        }

        for id in vendor.apps {
            if let url = workspace.urlForApplication(withBundleIdentifier: id),
               let app = outermostApp(containing: url) {
                return app
            }
        }
        return nil
    }

    /// `/Applications/FortiClient.app/Contents/PlugIns/X.appex` →
    /// `/Applications/FortiClient.app`. The outermost bundle, because a
    /// helper app nested inside the client carries a generic icon.
    nonisolated static func outermostApp(containing url: URL) -> URL? {
        var app = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            app.appendPathComponent(component)
            if component.hasSuffix(".app") { return app }
        }
        return nil
    }
}
