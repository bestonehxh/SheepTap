import Foundation
import SystemConfiguration
import Network
import Darwin

nonisolated struct NetworkInterface: Identifiable, Equatable, Sendable {
    /// The BSD name, which is unique per fetch and stable across refreshes.
    ///
    /// This used to be a fresh `UUID()`, so every refresh handed SwiftUI a new
    /// identity for every row and the whole list was torn down and rebuilt even
    /// when nothing had changed.
    var id: String { name }
    let name: String
    let type: InterfaceType
    let ipAddress: String
    let subnetMask: String
    let gateway: String
    let dns: [String]
    let macAddress: String
    /// The System Configuration service ID (a UUID) behind this interface, when
    /// the interface belongs to a configured network service. Tunnels created
    /// by Network Extension VPNs have none.
    var serviceID: String? = nil

    enum InterfaceType: Equatable, Sendable {
        case wifi(ssid: String?)
        case ethernet
        case vpn
        case other
    }

    var icon: String {
        switch type {
        case .wifi: return "wifi"
        case .ethernet: return "point.3.connected.trianglepath.dotted"
        case .vpn: return "lock.shield"
        case .other: return "network"
        }
    }

    var typeLabel: String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn: return "VPN"
        case .other: return "Network"
        }
    }

    var ssid: String? {
        if case .wifi(let s) = type { return s }
        return nil
    }

    /// The System Settings location that manages this interface.
    ///
    /// The query after `?` is handed verbatim to the pane's `revealElement`.
    /// Wi-Fi's `General_Details` key opens the Details sheet of the network
    /// currently joined, so a connected Wi-Fi lands on its own SSID. It is used
    /// regardless of whether `ssid` is known: reading the SSID needs Location
    /// permission, so it is usually nil even while joined, and an interface only
    /// reaches this list once it holds an IP address.
    ///
    /// The Network pane accepts a bare service UUID as the key and pushes that
    /// service's own page (verified on macOS 26; its named anchors such as
    /// `?Ethernet` only reveal the first service of a kind). Interfaces with no
    /// service fall back to the pane's list. VPN has a pane of its own.
    var systemSettingsURL: URL {
        let target: String
        switch type {
        case .wifi:
            target = "com.apple.wifi-settings-extension?General_Details"
        case .vpn:
            target = "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"
        case .ethernet, .other:
            if let serviceID {
                target = "com.apple.Network-Settings.extension?\(serviceID)"
            } else {
                target = "com.apple.Network-Settings.extension"
            }
        }
        return URL(string: "x-apple.systempreferences:\(target)")!
    }

    /// Presentation order. Kept as a plain rank so the sort predicate is a total
    /// order: the previous hand-written `switch` returned `true` for both
    /// `(a, b)` and `(b, a)` when two interfaces were both Wi-Fi, which is not a
    /// valid strict weak ordering and reversed rows for anyone running a second
    /// Wi-Fi adapter.
    var sortRank: Int {
        switch type {
        case .wifi: return 0
        case .ethernet: return 1
        case .vpn: return 2
        case .other: return 3
        }
    }
}

/// The parts of the System Configuration graph that only change when hardware
/// or a network service is added or removed.
///
/// Loading this costs the bulk of a refresh (`SCNetworkInterfaceCopyAll` plus a
/// full `SCPreferences` open), while the events that actually fire often — DHCP
/// renewals, DNS changes, SSID changes — never invalidate it. `InterfaceFetcher`
/// caches it and drops it only when `NWPathMonitor` reports a path change.
nonisolated struct InterfaceTopology: Sendable {
    var wifiNames: Set<String> = []
    var ethernetNames: Set<String> = []
    var macAddresses: [String: String] = [:]
    var bsdToServiceID: [String: String] = [:]

    static func load() -> InterfaceTopology {
        var topology = InterfaceTopology()

        let scIfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for scIface in scIfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(scIface) as String? else { continue }

            if let mac = SCNetworkInterfaceGetHardwareAddressString(scIface) as String? {
                topology.macAddresses[bsd] = mac
            }

            guard let type = SCNetworkInterfaceGetInterfaceType(scIface) as String? else { continue }
            if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                topology.wifiNames.insert(bsd)
            } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
                topology.ethernetNames.insert(bsd)
            }
        }

        // BSD-name → service-ID via SCPreferences (authoritative, not dynamic store)
        if let prefs = SCPreferencesCreate(nil, "SheepTap" as CFString, nil),
           let allServices = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] {
            for svc in allServices {
                guard let iface = SCNetworkServiceGetInterface(svc),
                      let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
                if let sid = SCNetworkServiceGetServiceID(svc) as String? {
                    topology.bsdToServiceID[bsd] = sid
                }
            }
        }

        return topology
    }
}

/// Serialises the (synchronous, ~milliseconds) System Configuration queries onto
/// a single background executor and owns the topology cache.
///
/// This replaces a `Task.detached` per refresh. Detached tasks do not inherit
/// cancellation, so cancelling `refreshTask` left the previous fetch running to
/// completion; overlapping events could also run two fetches concurrently.
actor InterfaceFetcher {
    static let shared = InterfaceFetcher()

    private var cachedTopology: InterfaceTopology?

    /// Called when `NWPathMonitor` reports a change — an adapter may have been
    /// plugged in or a service added, so the cached topology is no longer trusted.
    func invalidateTopology() {
        cachedTopology = nil
    }

    func fetch() -> [NetworkInterface] {
        NetworkMonitor.fetchInterfaces {
            if let cachedTopology { return cachedTopology }
            let loaded = InterfaceTopology.load()
            cachedTopology = loaded
            return loaded
        }
    }

    func wifiDetails(for names: [String]) -> [String: WiFiDetails] {
        NetworkMonitor.loadWiFiDetails(for: names)
    }
}

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var interfaces: [NetworkInterface] = []
    /// Live radio figures per Wi-Fi BSD name. Polled only while the menu is
    /// open — nothing announces an RSSI or rate change.
    private(set) var wifiDetails: [String: WiFiDetails] = [:]

    private static let showWiFiDetailsKey = "SheepTap.showWiFiDetails"
    /// The "More" disclosure under a Wi-Fi card. Remembered across launches so
    /// someone who always wants the radio figures does not re-open it each time.
    private(set) var showWiFiDetails = UserDefaults.standard.bool(forKey: showWiFiDetailsKey)

    @ObservationIgnored private let locationGate = LocationGate()
    @ObservationIgnored private var wifiPollTask: Task<Void, Never>?

    @ObservationIgnored private var notifyStore: SCDynamicStore?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// While the menu is closed nothing is on screen, so events only mark the
    /// data stale instead of paying for a fetch. Set by the status-menu
    /// controller around the menu's lifetime.
    @ObservationIgnored var isVisible = false {
        didSet {
            if isVisible && needsRefresh { refresh() }
            if isVisible { startWiFiPolling() } else { stopWiFiPolling() }
        }
    }
    @ObservationIgnored private var needsRefresh = true

    /// Lets the menu update its AppKit frame after SwiftUI's content changes.
    /// NSMenu does not automatically remeasure a custom view while it is open.
    @ObservationIgnored var onInterfacesChanged: (() -> Void)?

    init() {
        // Seed the first menu synchronously. The old asynchronous first fetch
        // left the hosting view at its 120-point placeholder height, causing
        // the actual rows to be clipped/reordered when the menu opened quickly.
        interfaces = Self.fetchInterfaces { .load() }
        needsRefresh = false
        startSCNotifications()
        startPathMonitor()
        // Granting Location unlocks the SSID/BSSID in both CoreWLAN and the
        // dynamic store, and neither posts a change notification for it.
        locationGate.onChange = { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.isVisible { self.startWiFiPolling() }
        }
    }

    func setShowWiFiDetails(_ show: Bool) {
        showWiFiDetails = show
        UserDefaults.standard.set(show, forKey: Self.showWiFiDetailsKey)
        if show { locationGate.requestIfNeeded() }
        onInterfacesChanged?()
    }

    // ── Wi-Fi radio polling (menu open only) ──────────────────────────────

    private var wifiNames: [String] {
        interfaces.compactMap { if case .wifi = $0.type { $0.name } else { nil } }
    }

    private func startWiFiPolling() {
        // The first sample is taken synchronously so the menu opens at its
        // final height instead of growing a frame later. CoreWLAN answers from
        // airportd's cache in a few milliseconds.
        applyWiFiDetails(Self.loadWiFiDetails(for: wifiNames))

        wifiPollTask?.cancel()
        wifiPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let names = self?.wifiNames else { return }
                let fetched = await InterfaceFetcher.shared.wifiDetails(for: names)
                guard !Task.isCancelled else { return }
                self?.applyWiFiDetails(fetched)
            }
        }
    }

    private func stopWiFiPolling() {
        wifiPollTask?.cancel()
        wifiPollTask = nil
    }

    private func applyWiFiDetails(_ fetched: [String: WiFiDetails]) {
        guard wifiDetails != fetched else { return }
        wifiDetails = fetched
        // A field turning up or vanishing (BSSID once Location is granted)
        // changes the number of rows, so the menu has to remeasure.
        onInterfacesChanged?()
    }

    nonisolated static func loadWiFiDetails(for names: [String]) -> [String: WiFiDetails] {
        var result: [String: WiFiDetails] = [:]
        for name in names {
            result[name] = WiFiDetails.load(interfaceName: name)
        }
        return result
    }

    // Isolated to the main actor so it can touch the main-actor state it owns.
    // The previous nonisolated `deinit` could only see `Sendable` stored
    // properties, which is why `runLoopSource` needed `nonisolated(unsafe)`.
    isolated deinit {
        pathMonitor.cancel()
        debounceTask?.cancel()
        refreshTask?.cancel()
        wifiPollTask?.cancel()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        if let notifyStore {
            // Stop the store from calling back into a pointer that is about to
            // dangle: the callback context holds `self` unretained.
            SCDynamicStoreSetNotificationKeys(notifyStore, nil, nil)
        }
    }

    func refresh() {
        // One in flight at a time. Without this, overlapping refreshes could
        // finish out of order and an older snapshot could overwrite a newer one.
        refreshTask?.cancel()
        needsRefresh = false
        refreshTask = Task { [weak self] in
            let fetched = await InterfaceFetcher.shared.fetch()
            guard !Task.isCancelled, let self else { return }
            // Most events (a DHCP renewal that returns the same lease, a link
            // flap) produce byte-identical data. Assigning anyway would publish
            // a change and re-render for nothing.
            if self.interfaces != fetched {
                self.interfaces = fetched
                self.onInterfacesChanged?()
                // A Wi-Fi interface that joined while the menu was closed would
                // otherwise wait a full poll interval for its radio figures.
                if self.isVisible { self.startWiFiPolling() }
            }
        }
    }

    // Debounce rapid-fire events (e.g. DHCP sends several store updates in sequence)
    func scheduleRefresh(after nanoseconds: UInt64 = 800_000_000) {
        guard isVisible else {
            // Menu is closed — remember that the data is stale and fetch when it
            // is next shown. This is a menu-bar app: refreshing while nothing is
            // on screen costs milliseconds per event and shows the user nothing.
            needsRefresh = true
            return
        }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    // ── NWPathMonitor: fires on interface up/down, WiFi join/leave ────────
    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { _ in
            Task { @MainActor [weak self] in
                // A path change is the only event that can add or remove an
                // adapter, so it is also the only one that invalidates the cache.
                await InterfaceFetcher.shared.invalidateTopology()
                self?.scheduleRefresh()
            }
        }
        pathMonitor.start(queue: .global(qos: .background))
    }

    // ── SCDynamicStore: fires on IP renewal, gateway/DNS change, SSID ────
    private func startSCNotifications() {
        // The callback must be a non-capturing closure so it converts to a C pointer.
        // Context passes `self` as an unretained raw pointer (safe: the monitor is
        // owned by AppDelegate and lives for the app's lifetime; `deinit` also
        // clears the notification keys before the pointer can dangle).
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var ctx = SCDynamicStoreContext(version: 0, info: selfPtr,
                                        retain: nil, release: nil,
                                        copyDescription: nil)

        let cb: SCDynamicStoreCallBack = { _, _, ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.scheduleRefresh() }
        }

        guard let store = SCDynamicStoreCreate(nil, "SheepTapNotify" as CFString, cb, &ctx)
        else { return }
        notifyStore = store

        let patterns = [
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/DNS",
            "State:/Network/Global/IPv4",
            "State:/Network/Global/DNS",
            "State:/Network/Interface/.*/AirPort",
            "State:/Network/Interface/.*/Link"
        ] as CFArray

        SCDynamicStoreSetNotificationKeys(store, nil, patterns)

        if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = src
        }
    }

    // ── Data fetching (runs on InterfaceFetcher's background executor) ─────

    private nonisolated struct LocalAddresses {
        var ipData: [String: (ip: String, subnet: String)] = [:]
        var macAddresses: [String: String] = [:]
    }

    /// `topology` is a closure so the cheap `getifaddrs` pass can bail out before
    /// paying for the expensive System Configuration load when nothing is up.
    nonisolated static func fetchInterfaces(topology: () -> InterfaceTopology) -> [NetworkInterface] {
        let local = collectLocalAddresses()
        guard !local.ipData.isEmpty else { return [] }
        let topology = topology()

        let store = SCDynamicStoreCreate(nil, "SheepTap" as CFString, nil, nil)

        var wifiSSIDs: [String: String] = [:]
        if let store {
            for name in topology.wifiNames {
                let key = "State:/Network/Interface/\(name)/AirPort" as CFString
                if let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                   let ssid = dict["SSID_STR"] as? String {
                    wifiSSIDs[name] = ssid
                }
            }
        }

        var primaryInterface: String?
        var primaryGateway: String?
        if let store {
            let globalKey = "State:/Network/Global/IPv4" as CFString
            if let dict = SCDynamicStoreCopyValue(store, globalKey) as? [String: Any] {
                primaryInterface = dict["PrimaryInterface"] as? String
                primaryGateway = dict["Router"] as? String
            }
        }

        var result: [NetworkInterface] = []
        result.reserveCapacity(local.ipData.count)

        for (name, data) in local.ipData {
            let isWiFi = topology.wifiNames.contains(name)
            let ifType = interfaceType(
                name: name,
                wifiSSID: isWiFi ? wifiSSIDs[name] : nil,
                isWiFi: isWiFi,
                isEthernet: topology.ethernetNames.contains(name)
            )

            var gateway = "N/A"
            var dns: [String] = []

            if let store {
                // The DHCP/manual router lives on the service-level State key.
                // The interface-level key only carries addresses/masks, so a
                // non-primary interface (e.g. Wi-Fi while Ethernet is primary)
                // showed "N/A" when we read only that one.
                if let sid = topology.bsdToServiceID[name] {
                    let svcKey = "State:/Network/Service/\(sid)/IPv4" as CFString
                    if let dict = SCDynamicStoreCopyValue(store, svcKey) as? [String: Any],
                       let gw = dict["Router"] as? String, !gw.isEmpty { gateway = gw }
                }
                if gateway == "N/A" {
                    let ifKey = "State:/Network/Interface/\(name)/IPv4" as CFString
                    if let dict = SCDynamicStoreCopyValue(store, ifKey) as? [String: Any],
                       let gw = dict["Router"] as? String, !gw.isEmpty { gateway = gw }
                }

                // The global router belongs only to the primary interface.
                // Assigning it to VPN/tunnel interfaces reported a false gateway.
                if gateway == "N/A", primaryInterface == name, let primaryGateway {
                    gateway = primaryGateway
                }

                // DNS: service-level State key (effective DNS = DHCP or manual override)
                if let sid = topology.bsdToServiceID[name] {
                    let stateKey = "State:/Network/Service/\(sid)/DNS" as CFString
                    if let dict = SCDynamicStoreCopyValue(store, stateKey) as? [String: Any],
                       let srv = dict["ServerAddresses"] as? [String], !srv.isEmpty { dns = srv }

                    // Manual DNS lives in Setup: — takes priority if set
                    let setupKey = "Setup:/Network/Service/\(sid)/DNS" as CFString
                    if let dict = SCDynamicStoreCopyValue(store, setupKey) as? [String: Any],
                       let srv = dict["ServerAddresses"] as? [String], !srv.isEmpty { dns = srv }
                }
                // Last resort: interface-level key
                if dns.isEmpty {
                    let ifDNS = "State:/Network/Interface/\(name)/DNS" as CFString
                    if let dict = SCDynamicStoreCopyValue(store, ifDNS) as? [String: Any],
                       let srv = dict["ServerAddresses"] as? [String] { dns = srv }
                }
            }

            result.append(NetworkInterface(
                name: name,
                type: ifType,
                ipAddress: data.ip,
                subnetMask: data.subnet,
                gateway: gateway,
                dns: dns.isEmpty ? ["N/A"] : dns,
                macAddress: local.macAddresses[name] ?? topology.macAddresses[name] ?? "N/A",
                serviceID: topology.bsdToServiceID[name]
            ))
        }

        // A total order, so the result is independent of the (unordered)
        // dictionary iteration above. An unstable order here would make the
        // `interfaces != fetched` check in `refresh()` fire on identical data.
        result.sort { ($0.sortRank, $0.name) < ($1.sortRank, $1.name) }
        return result
    }

    /// IPv4 addresses, netmasks and link-layer MACs via `getifaddrs` — cheap
    /// enough to run on every refresh.
    nonisolated private static func collectLocalAddresses() -> LocalAddresses {
        var result = LocalAddresses()

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return result }
        defer { freeifaddrs(ifaddrPtr) }

        // IPv4 presentation form is at most 15 characters, so NI_MAXHOST (1025)
        // was two kilobyte-sized allocations per interface per refresh.
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var subnetBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            let name = String(cString: cur.pointee.ifa_name)

            if let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let mac = macAddress(from: addr) {
                result.macAddresses[name] = mac
                continue
            }

            guard (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_UP) != 0,
                  let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            ipBuf[0] = 0
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST)
            let ip = Self.string(from: ipBuf)
            guard !ip.isEmpty, ip != "0.0.0.0" else { continue }

            subnetBuf[0] = 0
            if let netmask = cur.pointee.ifa_netmask {
                getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                            &subnetBuf, socklen_t(subnetBuf.count), nil, 0, NI_NUMERICHOST)
            }
            let subnet = Self.string(from: subnetBuf)
            // `getifaddrs` lists an interface's primary address before its
            // aliases; overwriting on every entry showed the last alias instead.
            if result.ipData[name] == nil {
                result.ipData[name] = (ip: ip, subnet: subnet.isEmpty ? "N/A" : subnet)
            }
        }

        return result
    }

    /// Reads a NUL-terminated C string out of a fixed-size buffer. The
    /// `String(cString:)` array overload is deprecated in Swift 6; the pointer
    /// overload is not, and avoids the intermediate `prefix`/`map` copies.
    nonisolated private static func string(from buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
    }

    nonisolated static func interfaceType(
        name: String,
        wifiSSID: String?,
        isWiFi: Bool,
        isEthernet: Bool
    ) -> NetworkInterface.InterfaceType {
        if isWiFi { return .wifi(ssid: wifiSSID) }
        if isEthernet { return .ethernet }

        let vpnPrefixes = ["utun", "tun", "tap", "ppp", "ipsec"]
        if vpnPrefixes.contains(where: name.hasPrefix) { return .vpn }
        return .other
    }

    nonisolated private static func macAddress(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        // `sockaddr_dl` is variable-length: `sdl_data` holds the interface name
        // followed by the link address, and together they routinely overrun the
        // struct's nominal 12-byte `sdl_data` field (e.g. "bridge100" + 6 MAC
        // bytes = 15). Copying the struct by value truncated that tail, so the
        // MAC bytes must be read from the original buffer, bounded by `sdl_len`.
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdlPtr in
            let sdl = sdlPtr.pointee
            guard sdl.sdl_alen == 6 else { return nil }

            let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
            let macOffset = dataOffset + Int(sdl.sdl_nlen)
            guard macOffset + Int(sdl.sdl_alen) <= Int(sdl.sdl_len) else { return nil }

            let raw = UnsafeRawPointer(sdlPtr)
            let bytes = (0..<Int(sdl.sdl_alen)).map {
                raw.load(fromByteOffset: macOffset + $0, as: UInt8.self)
            }
            return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
    }
}
