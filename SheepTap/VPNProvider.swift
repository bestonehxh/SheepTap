import Foundation

/// Names the product behind a VPN tunnel ("FortiGate", "Tailscale", …).
///
/// macOS never says which app owns a `utun`: the kernel only hands out the
/// name, and the Network Extension configurations that would say are private
/// to the app that created them. So the name is inferred, strongest evidence
/// first:
///
/// 1. The network service the tunnel belongs to. A Network Extension VPN's
///    service carries the client's bundle ID (`io.tailscale.ipn.macsys`,
///    `com.fortinet.forticlient.macos.vpn`), which names the vendor outright.
///    Failing that, the service name: one that mentions a known vendor is
///    shown as that vendor, any other ("Office VPN") as is — except a bare
///    "VPN", which is FortiClient's default and says nothing.
/// 2. A signature of the tunnel itself — GlobalProtect's `gpd` interface,
///    Tailscale's MagicDNS resolver or its 100.64/10 address.
/// 3. The one VPN client that is running, when exactly one tunnel is left
///    unexplained. With two unexplained tunnels or two clients running it
///    would be a guess, so the tunnel stays a plain "VPN".
nonisolated enum VPNProvider {
    nonisolated struct Vendor: Sendable {
        let name: String
        /// Bundle IDs (or prefixes) of the vendor's client app. Kept specific
        /// where the vendor also ships non-VPN apps (Cisco's Webex).
        let bundleIDs: [String]
        /// Lower-case fragments that identify the vendor in a service name.
        let keywords: [String]
        /// Exact bundle IDs of the client app, for finding its icon when it
        /// is not running. Only IDs known for certain; the rest rely on the
        /// running app or the tunnel's own extension.
        var apps: [String] = []
    }

    nonisolated struct Tunnel: Sendable {
        let name: String
        let ipAddress: String
        let dns: [String]
        /// The name of the network service behind the tunnel, if one is found.
        var serviceName: String? = nil
        /// The client's bundle ID, for a Network Extension VPN service.
        var serviceBundleID: String? = nil
    }

    static let vendors: [Vendor] = [
        Vendor(name: "FortiGate", bundleIDs: ["com.fortinet."], keywords: ["forti"],
               apps: ["com.fortinet.FortiClient"]),
        Vendor(name: "Check Point", bundleIDs: ["com.checkpoint."], keywords: ["check point", "checkpoint"]),
        Vendor(name: "Tailscale", bundleIDs: ["io.tailscale."], keywords: ["tailscale"],
               apps: ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]),
        Vendor(name: "Cisco Secure Client",
               bundleIDs: ["com.cisco.anyconnect", "com.cisco.secureclient"],
               keywords: ["anyconnect", "cisco"]),
        Vendor(name: "GlobalProtect", bundleIDs: ["com.paloaltonetworks."], keywords: ["globalprotect"],
               apps: ["com.paloaltonetworks.GlobalProtect.client"]),
        Vendor(name: "Zscaler", bundleIDs: ["com.zscaler."], keywords: ["zscaler"]),
        Vendor(name: "Ivanti Secure Access",
               bundleIDs: ["net.pulsesecure.", "com.ivanti."],
               keywords: ["ivanti", "pulse secure"]),
        Vendor(name: "SonicWall", bundleIDs: ["com.sonicwall."], keywords: ["sonicwall", "netextender"]),
        Vendor(name: "WireGuard", bundleIDs: ["com.wireguard."], keywords: ["wireguard"],
               apps: ["com.wireguard.macos"]),
        Vendor(name: "OpenVPN", bundleIDs: ["net.openvpn."], keywords: ["openvpn"]),
        Vendor(name: "Cloudflare WARP", bundleIDs: ["com.cloudflare.1dot1dot1dot1"], keywords: ["cloudflare"]),
        Vendor(name: "NordVPN", bundleIDs: ["com.nordvpn."], keywords: ["nordvpn", "nordlynx"]),
        Vendor(name: "ExpressVPN", bundleIDs: ["com.expressvpn."], keywords: ["expressvpn"]),
        Vendor(name: "Proton VPN", bundleIDs: ["ch.protonvpn.", "ch.protonmail.vpn"], keywords: ["proton"]),
        Vendor(name: "Surfshark", bundleIDs: ["com.surfshark."], keywords: ["surfshark"]),
        Vendor(name: "Mullvad", bundleIDs: ["net.mullvad."], keywords: ["mullvad"]),
    ]

    /// Provider name per tunnel BSD name. Tunnels that cannot be told apart
    /// are left out.
    static func identify(_ tunnels: [Tunnel], runningBundleIDs: Set<String>) -> [String: String] {
        let running = vendors.filter { vendor in
            runningBundleIDs.contains { self.vendor(bundleID: $0)?.name == vendor.name }
        }

        var result: [String: String] = [:]
        var unexplained: [Tunnel] = []

        for tunnel in tunnels {
            if let bundleID = tunnel.serviceBundleID, let known = vendor(bundleID: bundleID) {
                result[tunnel.name] = known.name
            } else if let service = tunnel.serviceName?.trimmingCharacters(in: .whitespaces),
                      !service.isEmpty, service.lowercased() != "vpn" {
                result[tunnel.name] = vendor(named: service)?.name ?? service
            } else if let known = signature(of: tunnel, running: running) {
                result[tunnel.name] = known.name
            } else {
                unexplained.append(tunnel)
            }
        }

        // A client whose tunnel is already accounted for cannot also own the
        // leftover one.
        let claimed = Set(result.values)
        let candidates = running.filter { !claimed.contains($0.name) }
        if unexplained.count == 1, candidates.count == 1 {
            result[unexplained[0].name] = candidates[0].name
        }
        return result
    }

    static func vendor(bundleID: String) -> Vendor? {
        vendors.first { vendor in vendor.bundleIDs.contains(where: bundleID.hasPrefix) }
    }

    static func vendor(named serviceName: String) -> Vendor? {
        let lowered = serviceName.lowercased()
        return vendors.first { vendor in vendor.keywords.contains { lowered.contains($0) } }
    }

    private static func signature(of tunnel: Tunnel, running: [Vendor]) -> Vendor? {
        if tunnel.name.hasPrefix("gpd") { return vendor(called: "GlobalProtect") }
        // MagicDNS answers on this address and nowhere else.
        if tunnel.dns.contains("100.100.100.100") { return vendor(called: "Tailscale") }
        // Tailscale hands out addresses from the CGNAT range, but so do others
        // (Zscaler among them), so the range alone needs the app running too.
        if isCGNAT(tunnel.ipAddress), running.contains(where: { $0.name == "Tailscale" }) {
            return vendor(called: "Tailscale")
        }
        return nil
    }

    static func vendor(called name: String) -> Vendor? {
        vendors.first { $0.name == name }
    }

    /// 100.64.0.0/10 (RFC 6598).
    static func isCGNAT(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (octets[1] & 0xC0) == 64
    }
}
