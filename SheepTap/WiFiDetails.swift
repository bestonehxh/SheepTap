import Foundation
import CoreWLAN
import CoreLocation

/// The live link figures behind the Wi-Fi menu's Option-click panel.
///
/// Kept apart from `NetworkInterface` on purpose: RSSI, noise and the transmit
/// rate move every second, and folding them into the interface list would make
/// `NetworkMonitor.refresh()`'s equality check fail on every poll and republish
/// the whole list.
nonisolated struct WiFiDetails: Equatable, Sendable {
    var ssid: String?
    /// Needs Location authorization; CoreWLAN returns nil without it.
    var bssid: String?
    var security: String?
    var channel: Int?
    var band: String?
    var width: String?
    /// Needs Location authorization, like `bssid`.
    var countryCode: String?
    var rssi: Int?
    var noise: Int?
    var txRate: Double?
    var phyMode: CWPHYMode = .modeNone
    var is6GHz = false
    var mcsIndex: Int?
    var spatialStreams: Int?

    /// "Wi-Fi 6E" and friends — the Wi-Fi Alliance generation name for the
    /// negotiated PHY. 802.11ax only earns the "E" on the 6 GHz band; a/b/g
    /// predate the numbering and are shown by their IEEE name instead.
    var generation: String? {
        switch phyMode {
        case .mode11be: return "Wi-Fi 7"
        case .mode11ax: return is6GHz ? "Wi-Fi 6E" : "Wi-Fi 6"
        case .mode11ac: return "Wi-Fi 5"
        case .mode11n:  return "Wi-Fi 4"
        default:        return nil
        }
    }

    var phyLabel: String? {
        switch phyMode {
        case .mode11a:  return "802.11a"
        case .mode11b:  return "802.11b"
        case .mode11g:  return "802.11g"
        case .mode11n:  return "802.11n"
        case .mode11ac: return "802.11ac"
        case .mode11ax: return "802.11ax"
        case .mode11be: return "802.11be"
        default:        return nil
        }
    }

    /// "157 (5 GHz, 40 MHz)", matching the Wi-Fi menu's wording.
    var channelLabel: String? {
        guard let channel else { return nil }
        let extras = [band, width].compactMap { $0 }
        return extras.isEmpty ? "\(channel)" : "\(channel) (\(extras.joined(separator: ", ")))"
    }

    static func load(interfaceName: String) -> WiFiDetails? {
        guard let iface = CWWiFiClient.shared().interface(withName: interfaceName),
              iface.powerOn() else { return nil }

        var d = WiFiDetails()
        d.ssid = iface.ssid()
        d.bssid = iface.bssid()
        d.security = securityLabel(iface.security())
        d.countryCode = iface.countryCode()
        d.phyMode = iface.activePHYMode()

        if let ch = iface.wlanChannel() {
            d.channel = ch.channelNumber
            switch ch.channelBand {
            case .band2GHz: d.band = "2.4 GHz"
            case .band5GHz: d.band = "5 GHz"
            case .band6GHz: d.band = "6 GHz"; d.is6GHz = true
            default: break
            }
            switch ch.channelWidth {
            case .width20MHz:  d.width = "20 MHz"
            case .width40MHz:  d.width = "40 MHz"
            case .width80MHz:  d.width = "80 MHz"
            case .width160MHz: d.width = "160 MHz"
            // 320 MHz (Wi-Fi 7) has no constant in the SDK; an unknown width
            // is left off rather than guessed.
            default: break
            }
        }

        // A disassociated interface reports zeros rather than nil.
        let rssi = iface.rssiValue()
        if rssi != 0 { d.rssi = rssi }
        let noise = iface.noiseMeasurement()
        if noise != 0 { d.noise = noise }
        let rate = iface.transmitRate()
        if rate > 0 { d.txRate = rate }

        // MCS and spatial-stream count are not public API. The Wi-Fi menu reads
        // them from these CWInterface properties; probe before asking so a
        // future macOS that drops them only hides the rows instead of crashing.
        d.mcsIndex = privateInt(iface, "mcsIndex")
        d.spatialStreams = privateInt(iface, "numberOfSpatialStreams")
        if d.spatialStreams == 0 { d.spatialStreams = nil }
        return d
    }

    private static func privateInt(_ iface: CWInterface, _ key: String) -> Int? {
        guard iface.responds(to: NSSelectorFromString(key)) else { return nil }
        return (iface.value(forKey: key) as? NSNumber)?.intValue
    }

    private static func securityLabel(_ s: CWSecurity) -> String? {
        switch s {
        case .none:                 return "None"
        case .WEP:                  return "WEP"
        case .wpaPersonal:          return "WPA Personal"
        case .wpaPersonalMixed:     return "WPA/WPA2 Personal"
        case .wpa2Personal:         return "WPA2 Personal"
        case .personal:             return "Personal"
        case .dynamicWEP:           return "Dynamic WEP"
        case .wpaEnterprise:        return "WPA Enterprise"
        case .wpaEnterpriseMixed:   return "WPA/WPA2 Enterprise"
        case .wpa2Enterprise:       return "WPA2 Enterprise"
        case .enterprise:           return "Enterprise"
        case .wpa3Personal:         return "WPA3 Personal"
        case .wpa3Enterprise:       return "WPA3 Enterprise"
        case .wpa3Transition:       return "WPA2/WPA3 Personal"
        case .OWE:                  return "Enhanced Open"
        case .oweTransition:        return "Enhanced Open Transition"
        default:                    return nil
        }
    }
}

/// Asks for Location access, which macOS requires before CoreWLAN (and the
/// System Configuration store) will hand out the SSID, BSSID or country code.
///
/// Requested only when the user opens the Wi-Fi details, never at launch — a
/// menu-bar utility that prompts for location before it is asked to show
/// anything location-like reads as suspicious.
@MainActor
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onChange?() }
    }
}
