//
//  SheepTapTests.swift
//  SheepTapTests
//
//  Created by Bestchaan on 10/5/2569 BE.
//

import Foundation
import Testing
import Security
@testable import SheepTap

struct SheepTapTests {

    @Test func classifiesCommonInterfaceKinds() {
        #expect(NetworkMonitor.interfaceType(
            name: "en0", wifiSSID: "Office", isWiFi: true, isEthernet: false
        ) == .wifi(ssid: "Office"))
        #expect(NetworkMonitor.interfaceType(
            name: "en5", wifiSSID: nil, isWiFi: false, isEthernet: true
        ) == .ethernet)
        #expect(NetworkMonitor.interfaceType(
            name: "utun8", wifiSSID: nil, isWiFi: false, isEthernet: false
        ) == .vpn)
        #expect(NetworkMonitor.interfaceType(
            name: "bridge0", wifiSSID: nil, isWiFi: false, isEthernet: false
        ) == .other)
    }

    /// Regression: the old hand-written comparator returned `true` for both
    /// `(a, b)` and `(b, a)` when both interfaces were Wi-Fi, so two Wi-Fi
    /// adapters came out in reverse order (and the predicate was not a valid
    /// strict weak ordering).
    @Test func sortsInterfacesByKindThenName() {
        func iface(_ name: String, _ type: NetworkInterface.InterfaceType) -> NetworkInterface {
            NetworkInterface(name: name, type: type, ipAddress: "", subnetMask: "",
                             gateway: "", dns: [], macAddress: "")
        }

        let unsorted = [
            iface("utun0", .vpn),
            iface("en1", .wifi(ssid: "B")),
            iface("bridge0", .other),
            iface("en0", .wifi(ssid: "A")),
            iface("en5", .ethernet)
        ]

        let sorted = unsorted.sorted { ($0.sortRank, $0.name) < ($1.sortRank, $1.name) }
        #expect(sorted.map(\.name) == ["en0", "en1", "en5", "utun0", "bridge0"])
    }

    @Test func sortRanksWiFiFirstAndOtherLast() {
        #expect(NetworkInterface.InterfaceType.wifi(ssid: nil) == .wifi(ssid: nil))
        let ranks = [
            iface(.wifi(ssid: nil)), iface(.ethernet), iface(.vpn), iface(.other)
        ].map(\.sortRank)
        #expect(ranks == [0, 1, 2, 3])
    }

    @Test func namesVPNFromItsServiceName() {
        let providers = VPNProvider.identify([
            .init(name: "utun4", ipAddress: "10.212.134.200", dns: [], serviceName: "FortiClient VPN"),
            .init(name: "utun5", ipAddress: "172.16.10.2", dns: [], serviceName: "Endpoint Security VPN - Check Point"),
            .init(name: "ipsec0", ipAddress: "10.0.0.9", dns: [], serviceName: "Office VPN")
        ], runningBundleIDs: [])
        #expect(providers == ["utun4": "FortiGate", "utun5": "Check Point", "ipsec0": "Office VPN"])
    }

    /// As `scutil --nc list` shows them: FortiClient's configuration is named
    /// just "VPN", so only its bundle ID says who it is.
    @Test func namesNetworkExtensionVPNFromItsBundleID() {
        let providers = VPNProvider.identify([
            .init(name: "utun4", ipAddress: "10.212.134.200", dns: [], serviceName: "VPN",
                  serviceBundleID: "com.fortinet.forticlient.macos.vpn"),
            .init(name: "utun5", ipAddress: "100.90.1.1", dns: [], serviceName: "Tailscale",
                  serviceBundleID: "io.tailscale.ipn.macsys")
        ], runningBundleIDs: [])
        #expect(providers == ["utun4": "FortiGate", "utun5": "Tailscale"])

        // A bare "VPN" name with nothing else to go on is not shown.
        #expect(VPNProvider.identify(
            [.init(name: "utun4", ipAddress: "10.1.1.1", dns: [], serviceName: "VPN")],
            runningBundleIDs: []).isEmpty)
    }

    @Test func namesTailscaleFromItsSignature() {
        let magicDNS = VPNProvider.identify(
            [.init(name: "utun6", ipAddress: "100.101.102.103", dns: ["100.100.100.100"])],
            runningBundleIDs: [])
        #expect(magicDNS == ["utun6": "Tailscale"])

        // The CGNAT range alone is shared with other products.
        let rangeOnly = VPNProvider.identify(
            [.init(name: "utun6", ipAddress: "100.64.1.2", dns: [])], runningBundleIDs: [])
        #expect(rangeOnly.isEmpty)

        let rangeAndApp = VPNProvider.identify(
            [.init(name: "utun6", ipAddress: "100.64.1.2", dns: [])],
            runningBundleIDs: ["io.tailscale.ipn.macsys"])
        #expect(rangeAndApp == ["utun6": "Tailscale"])
    }

    @Test func attributesLoneTunnelToLoneRunningClient() {
        let tunnel = VPNProvider.Tunnel(name: "utun7", ipAddress: "10.1.1.1", dns: [])
        #expect(VPNProvider.identify([tunnel], runningBundleIDs: ["com.fortinet.FortiClient"])
                == ["utun7": "FortiGate"])
        // Webex is a Cisco app but not a VPN client.
        #expect(VPNProvider.identify([tunnel], runningBundleIDs: ["com.cisco.webexmeetingsapp"]).isEmpty)
        // Two clients running: which one owns the tunnel is a guess.
        #expect(VPNProvider.identify(
            [tunnel], runningBundleIDs: ["com.fortinet.FortiClient", "com.checkpoint.eps.gui"]
        ).isEmpty)
        // Tailscale's tunnel is already explained, so FortiClient owns the other one.
        #expect(VPNProvider.identify(
            [tunnel, .init(name: "utun8", ipAddress: "100.90.1.1", dns: ["100.100.100.100"])],
            runningBundleIDs: ["com.fortinet.FortiClient", "io.tailscale.ipn.macos"]
        ) == ["utun7": "FortiGate", "utun8": "Tailscale"])
    }

    @Test func findsTheClientAppAroundAnExtension() {
        func app(_ path: String) -> String? {
            VPNAppIcon.outermostApp(containing: URL(fileURLWithPath: path))?.path
        }
        #expect(app("/Applications/FortiClient.app/Contents/PlugIns/vpn.appex") == "/Applications/FortiClient.app")
        // A helper nested in the client has a generic icon; the client is wanted.
        #expect(app("/Applications/Tailscale.app/Contents/Helpers/Helper.app") == "/Applications/Tailscale.app")
        // An installed system extension has no host app around it.
        #expect(app("/Library/SystemExtensions/ABC/com.fortinet.vpn.systemextension") == nil)
    }

    /// Inside the App Sandbox, CoreWLAN reports no interfaces at all unless the
    /// app holds the outgoing-network entitlement — the Wi-Fi details panel
    /// silently vanished in build 9 for exactly this reason. These tests run
    /// hosted in the app, so this reads the app's own signature.
    @Test func hostAppCanReachCoreWLANFromTheSandbox() {
        let task = SecTaskCreateFromSelf(nil)
        let key = "com.apple.security.network.client" as CFString
        let value = task.flatMap { SecTaskCopyValueForEntitlement($0, key, nil) }
        #expect((value as? Bool) == true)
    }

    /// Least privilege: SheepTap never opens a file, so it must not carry the
    /// user-selected-files entitlement it was created with.
    @Test func hostAppHasNoFileAccessEntitlement() {
        let task = SecTaskCreateFromSelf(nil)
        let key = "com.apple.security.files.user-selected.read-only" as CFString
        let value = task.flatMap { SecTaskCopyValueForEntitlement($0, key, nil) }
        #expect(value == nil)
    }

    /// The hardened runtime blocks code and dylib injection, and notarization
    /// requires it.
    @Test func hostAppIsSignedWithHardenedRuntime() {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else {
            Issue.record("Could not read the host app's signature")
            return
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        #expect(flags & SecCodeSignatureFlags.runtime.rawValue != 0)
    }

    private func iface(_ type: NetworkInterface.InterfaceType) -> NetworkInterface {
        NetworkInterface(name: "x", type: type, ipAddress: "", subnetMask: "",
                         gateway: "", dns: [], macAddress: "")
    }
}
