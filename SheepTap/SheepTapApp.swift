import SwiftUI
import AppKit
import ServiceManagement

@main
struct SheepTapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once, the first time the app ever launches. Without it the app
    /// re-registered itself on every launch, so turning "Open at Login" off in
    /// System Settings (which puts the service back to `.notRegistered`) was
    /// silently undone the next time the app started.
    private static let didConfigureLoginItemKey = "SheepTap.didConfigureLoginItem"
    /// The bundle path the login item was registered from. The system's record
    /// keeps whatever path `register()` was called from, so if the app later
    /// moves (first run from Xcode's DerivedData, then installed to
    /// /Applications) the item stays enabled but points at a bundle that no
    /// longer exists — and nothing launches at login.
    private static let registeredLoginItemPathKey = "SheepTap.registeredLoginItemPath"

    private let monitor = NetworkMonitor()
    private var statusController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureLoginItem()
        statusController = StatusMenuController(monitor: monitor)
    }

    private func configureLoginItem() {
        let defaults = UserDefaults.standard
        let bundlePath = Bundle.main.bundlePath
        // A registration made from a build directory or the Trash dies as soon
        // as that copy is cleaned out, so never register from there.
        let isStableLocation = !bundlePath.contains("/DerivedData/")
            && !bundlePath.contains("/.Trash/")

        guard defaults.bool(forKey: Self.didConfigureLoginItemKey) else {
            // Decide only from a stable location. Consuming the one-shot flag
            // on a DerivedData launch left the later /Applications install
            // unregistered for good: the repair path below only acts on an
            // item that is already `.enabled`.
            guard isStableLocation else { return }
            defaults.set(true, forKey: Self.didConfigureLoginItemKey)
            guard SMAppService.mainApp.status == .notRegistered else { return }
            if (try? SMAppService.mainApp.register()) != nil {
                defaults.set(bundlePath, forKey: Self.registeredLoginItemPathKey)
            }
            return
        }

        // Repair a registration left behind at an old location. Only while the
        // item is `.enabled`: `.notRegistered` means the user turned it off,
        // and that choice stays theirs.
        guard isStableLocation,
              SMAppService.mainApp.status == .enabled,
              defaults.string(forKey: Self.registeredLoginItemPathKey) != bundlePath
        else { return }

        try? SMAppService.mainApp.unregister()
        if (try? SMAppService.mainApp.register()) != nil {
            defaults.set(bundlePath, forKey: Self.registeredLoginItemPathKey)
        }
    }
}

private final class StatusMenuController: NSObject, NSMenuDelegate {
    private let monitor: NetworkMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu: NSMenu
    // Concrete root view rather than `AnyView`: type-erasing the root defeats
    // SwiftUI's structural diffing, so every interface update tore down and
    // rebuilt the whole subtree instead of updating the rows that changed.
    private let hostingView: NSHostingView<ContentView>

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
        // A local so the closure can capture the menu before `self` is fully
        // initialised; the menu owns the view, so `weak` keeps it from cycling.
        let menu = NSMenu()
        self.menu = menu
        hostingView = NSHostingView(rootView: ContentView(monitor: monitor) { [weak menu] in
            menu?.cancelTracking()
        })

        super.init()

        monitor.onInterfacesChanged = { [weak self] in
            self?.scheduleContentResize()
        }
        configureStatusItem()
        configureMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = 24
        button.image = NSImage.ipStatusIcon
        button.imagePosition = .imageOnly
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        hostingView.frame = NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 120)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentItem = NSMenuItem()
        contentItem.view = hostingView
        menu.addItem(contentItem)

        // The app runs as an accessory (no Dock icon), so without this there was
        // no way to quit it short of Activity Monitor.
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        // macOS gives an item with no image of its own an automatic symbol in the
        // leading icon column, and the one it picks for a terminate: action draws
        // as a missing-glyph box here. An explicit transparent image claims the
        // slot without drawing anything. This is unrelated to the trailing "⌘Q",
        // which renders fine and is kept.
        quitItem.image = .menuIconPlaceholder
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        resizeContent()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Tells the monitor the panel is on screen, so it starts honouring
        // network events again and picks up anything that changed while closed.
        monitor.isVisible = true
        resizeContent()
    }

    private func scheduleContentResize() {
        Task { @MainActor [weak self] in
            // Give SwiftUI one turn to consume the update before asking AppKit
            // for the new fitting size.
            await Task.yield()
            self?.resizeContent()
        }
    }

    private func resizeContent() {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = NSSize(
            width: MenuMetrics.width,
            height: max(fittingSize.height, MenuMetrics.minHeight)
        )
        menu.update()
    }

    func menuDidClose(_ menu: NSMenu) {
        monitor.isVisible = false
    }
}

private extension NSImage {
    /// A fully transparent 1-point image. See the Quit item for why.
    static var menuIconPlaceholder: NSImage {
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        image.isTemplate = true
        return image
    }

    /// The pulse-ring motif from the app icon (ring + centre dot), drawn on its
    /// own at menu-bar size. A template image, so the system tints it for the
    /// menu bar's light/dark appearance and the highlighted state. Wrapped in
    /// `NSImage(size:flipped:drawingHandler:)` so AppKit re-renders it per
    /// backing scale factor instead of caching one rasterisation.
    ///
    /// Proportions follow the artwork: ring thickness ≈ 0.3 of the outer
    /// radius, dot diameter ≈ 0.39 of the outer diameter.
    static var ipStatusIcon: NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()

            let outer = rect.insetBy(dx: 0.75, dy: 0.75)   // outer ⌀ 16.5
            let ringWidth: CGFloat = 2.5
            let ring = NSBezierPath(ovalIn: outer.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            ring.lineWidth = ringWidth
            ring.stroke()

            let dotDiameter: CGFloat = 5.4
            let dotInset = (outer.width - dotDiameter) / 2
            NSBezierPath(ovalIn: outer.insetBy(dx: dotInset, dy: dotInset)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SheepTap"
        return image
    }
}
