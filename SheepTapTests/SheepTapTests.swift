//
//  SheepTapTests.swift
//  SheepTapTests
//
//  Created by Bestchaan on 10/5/2569 BE.
//

import Testing
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

    private func iface(_ type: NetworkInterface.InterfaceType) -> NetworkInterface {
        NetworkInterface(name: "x", type: type, ipAddress: "", subnetMask: "",
                         gateway: "", dns: [], macAddress: "")
    }
}
