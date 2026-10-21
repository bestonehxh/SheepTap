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
        AppUpdater.startUnlessTesting()
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

/// What the menu-bar item draws, chosen under ☰ → Symbol in the status menu.
enum StatusIconStyle: String, CaseIterable {
    case ring
    case ip

    private static let defaultsKey = "SheepTap.statusIconStyle"

    static var current: StatusIconStyle {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .ring
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var menuTitle: String {
        switch self {
        case .ring: "Ring"
        case .ip: "iP"
        }
    }

    var image: NSImage {
        switch self {
        case .ring: .ringStatusIcon
        case .ip: .ipStatusIcon
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
    private var symbolItems: [NSMenuItem] = []
    private var moreItem: NSMenuItem?

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

        // SwiftUI reports its height as part of its own layout, so the frame
        // and the content change in the same display frame. The measured
        // fallback below still covers anything that path misses.
        hostingView.rootView.onHeightChange = { [weak self] height in
            self?.applyContentHeight(height)
        }
        monitor.onInterfacesChanged = { [weak self] in
            self?.scheduleContentResize()
        }
        configureStatusItem()
        configureMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = 24
        button.image = StatusIconStyle.current.image
        button.imagePosition = .imageOnly
        statusItem.menu = menu
    }

    @objc private func selectStatusIcon(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String,
              let selected = StatusIconStyle(rawValue: style) else { return }
        StatusIconStyle.current = selected
        statusItem.button?.image = selected.image
        for item in symbolItems {
            item.state = (item.representedObject as? String) == selected.rawValue ? .on : .off
        }
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

        // One ☰ row holds the app's own controls, so the panel ends with the
        // network details instead of a list of settings. SheepTap has no app menu
        // or Settings window (it is a menu-bar accessory), so they live here.
        menu.addItem(.separator())
        let moreMenu = NSMenu()
        moreMenu.autoenablesItems = false

        // Symbol: which mark the menu-bar item shows. Remembered in UserDefaults,
        // so a relaunch comes back with the same one.
        let symbolMenu = NSMenu()
        symbolMenu.autoenablesItems = false
        for style in StatusIconStyle.allCases {
            let item = NSMenuItem(
                title: style.menuTitle,
                action: #selector(selectStatusIcon(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = style.image
            item.representedObject = style.rawValue
            item.state = style == StatusIconStyle.current ? .on : .off
            symbolMenu.addItem(item)
            symbolItems.append(item)
        }
        let symbolItem = NSMenuItem(title: "Symbol", action: nil, keyEquivalent: "")
        symbolItem.submenu = symbolMenu
        moreMenu.addItem(symbolItem)

        moreMenu.addItem(.separator())
        let checkItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkItem.target = self
        moreMenu.addItem(checkItem)

        // The app runs as an accessory (no Dock icon), so without this there was
        // no way to quit it short of Activity Monitor. It lives under ☰ too, so
        // the panel itself ends with the ☰ row.
        moreMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        // macOS gives an item with no image of its own an automatic symbol, and
        // the one it picks for terminate: draws as a missing-glyph box. A
        // transparent image claims the slot without drawing anything.
        quitItem.image = .menuIconPlaceholder
        quitItem.target = NSApp
        quitItem.isEnabled = true
        moreMenu.addItem(quitItem)

        // Just the three lines, in the place Quit used to have. They are drawn as
        // the title (an image attachment), not as `image`: AppKit draws nothing
        // for an item whose title is empty, image included.
        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        moreItem.attributedTitle = .menuHamburger(highlighted: false)
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)
        self.moreItem = moreItem

        resizeContent()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        AppUpdater.shared.checkNow()
    }

    /// AppKit leaves an image inside a title untinted (a template one too), so
    /// the ☰ is drawn in an explicit colour and swapped for white while its row
    /// is highlighted, the way the menu recolours title text.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let moreItem, menu === moreItem.menu else { return }
        moreItem.attributedTitle = .menuHamburger(highlighted: item === moreItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Rebuilt per opening so the colour follows a light/dark switch.
        moreItem?.attributedTitle = .menuHamburger(highlighted: false)
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
        applyContentHeight(hostingView.fittingSize.height)
    }

    /// Sets the item view's frame from a content height. A no-op when the
    /// height already matches: the Wi-Fi poll publishes new RSSI figures every
    /// two seconds, and re-applying an unchanged frame plus `menu.update()`
    /// each time made the open menu re-lay itself out for nothing.
    private func applyContentHeight(_ contentHeight: CGFloat) {
        let height = max(ceil(contentHeight), MenuMetrics.minHeight)
        guard hostingView.frame.height != height else { return }
        hostingView.frame.size = NSSize(width: MenuMetrics.width, height: height)
        menu.update()
    }

    func menuDidClose(_ menu: NSMenu) {
        monitor.isVisible = false
    }
}

private extension NSAttributedString {
    /// The ☰ as menu-item text. Drawn by hand rather than with the
    /// `line.3.horizontal` symbol, whose bars sit too close together at menu
    /// size. Drawn in the menu's text colour, or white on the highlighted row
    /// (see `menu(_:willHighlight:)`).
    static func menuHamburger(highlighted: Bool) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let barWidth: CGFloat = 14, barHeight: CGFloat = 1.6, gap: CGFloat = 3.4
        let size = NSSize(width: barWidth, height: barHeight * 3 + gap * 2)
        let image = NSImage(size: size, flipped: false) { rect in
            (highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor).set()
            for i in 0..<3 {
                let y = CGFloat(i) * (barHeight + gap)
                NSBezierPath(
                    roundedRect: NSRect(x: 0, y: y, width: rect.width, height: barHeight),
                    xRadius: barHeight / 2, yRadius: barHeight / 2
                ).fill()
            }
            return true
        }
        image.accessibilityDescription = "More"
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centred on the cap height, where a title's letters sit.
        attachment.bounds = NSRect(
            x: 0, y: ((font.capHeight - size.height) / 2).rounded(),
            width: size.width, height: size.height
        )
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
        return text
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
    static var ringStatusIcon: NSImage {
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

    /// The original "iP" lettering, restored as the alternative under Symbol.
    /// Drawn through `NSImage(size:flipped:drawingHandler:)` so AppKit re-renders
    /// it per backing scale factor; `lockFocus` baked in whichever scale happened
    /// to be current when the status item was created.
    static var ipStatusIcon: NSImage {
        let size = NSSize(width: 21, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let text = "iP" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 15.0, weight: .heavy),
                .foregroundColor: NSColor.black,
                .kern: -1.4
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: size.width / 2.0 - textSize.width / 2.0,
                    y: size.height / 2.0 - textSize.height / 2.0 - 1.2
                ),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SheepTap IP"
        return image
    }
}
