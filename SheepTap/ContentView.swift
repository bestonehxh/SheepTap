import SwiftUI
import AppKit

/// Shared between the SwiftUI content and the AppKit hosting view that measures
/// it — they used to hard-code 240 independently in two files.
enum MenuMetrics {
    static let width: CGFloat = 240
    static let minHeight: CGFloat = 100
}

// MARK: – Root view

struct ContentView: View {
    let monitor: NetworkMonitor
    /// Closes the status menu after a tap opens System Settings. A custom view
    /// inside an `NSMenuItem` does not end menu tracking on its own.
    var dismissMenu: () -> Void = {}
    /// Reports the laid-out height so the AppKit hosting view can match it in
    /// the same layout pass. Measuring from AppKit a run-loop turn later left
    /// one displayed frame with the new content centred in the old frame,
    /// which showed as a flash every time the Wi-Fi details toggled.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if monitor.interfaces.isEmpty {
                NoConnectionView()
            } else {
                ForEach(Array(monitor.interfaces.enumerated()), id: \.element.id) { idx, iface in
                    if idx > 0 {
                        Divider()
                            .background(Color.primary.opacity(0.12))
                            .padding(.horizontal, 20)
                    }
                    InterfaceCard(
                        interface: iface,
                        wifi: monitor.wifiDetails[iface.name],
                        showWiFiDetails: monitor.showWiFiDetails,
                        isFirst: idx == 0,
                        toggleWiFiDetails: { monitor.setShowWiFiDetails(!monitor.showWiFiDetails) },
                        dismissMenu: dismissMenu
                    )
                }
            }
        }
        .frame(width: MenuMetrics.width)
        .padding(.vertical, 4)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            onHeightChange(height)
        }
    }
}

// MARK: – No connection

private struct NoConnectionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.65))
            Text("No Active Interface")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: – Interface card

struct InterfaceCard: View {
    let interface: NetworkInterface
    var wifi: WiFiDetails? = nil
    var showWiFiDetails = false
    var isFirst = false
    var toggleWiFiDetails: () -> Void = {}
    var dismissMenu: () -> Void = {}

    @State private var iconHovered = false

    private var isWiFi: Bool {
        if case .wifi = interface.type { return true }
        return false
    }

    /// The SSID when it is known and non-empty. The AirPort store key carries
    /// an empty `SSID_STR` while joined but without Location permission.
    private var displaySSID: String? {
        for candidate in [wifi?.ssid, interface.ssid] {
            if let ssid = candidate, !ssid.isEmpty { return ssid }
        }
        return nil
    }

    /// SSID and Wi-Fi generation share the line under the interface name.
    private var hasSubtitle: Bool { displaySSID != nil || wifi?.generation != nil }

    var accentColor: Color {
        switch interface.type {
        case .wifi:     return Color(red: 0.35, green: 0.78, blue: 1.0)
        case .ethernet: return Color(red: 0.45, green: 0.92, blue: 0.62)
        case .vpn:      return Color(red: 0.68, green: 0.55, blue: 1.0)
        case .other:    return Color(red: 0.72, green: 0.72, blue: 0.76)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Centered icon + label ──────────────────────────────────
            VStack(spacing: 3) {
                // Tapping the icon opens the matching System Settings pane.
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(iconHovered ? 0.3 : 0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: interface.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                .contentShape(Circle())
                // `pointerStyle` restores the arrow itself when the menu closes
                // under the pointer. A manual `NSCursor` push/pop pair depended
                // on an exit event that a closing menu never delivers, leaving
                // the stack unbalanced.
                .pointerStyle(.link)
                .onHover { iconHovered = $0 }
                .onTapGesture { openSystemSettings() }
                .help("Open \(interface.typeLabel) settings")
                .animation(.easeOut(duration: 0.12), value: iconHovered)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(interface.typeLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(interface.name)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Fixed-height slot — shows the SSID for Wi-Fi, an equally tall
                // gap otherwise. An invisible placeholder sizes the slot to the
                // font's real line height; the old 8-point frame let a 12-point
                // label spill over the interface name above it.
                HStack(spacing: 5) {
                    // The blank placeholder is only for sizing an empty slot;
                    // beside a lone badge it would push the badge off-centre.
                    if displaySSID != nil || wifi?.generation == nil {
                        Text(displaySSID ?? " ")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let generation = wifi?.generation {
                        GenerationBadge(text: generation, tint: accentColor)
                    }
                }
                .opacity(hasSubtitle ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, isFirst ? 0 : 12)

            // ── Detail rows ───────────────────────────────────────────
            VStack(spacing: 0) {
                InfoRow(label: "IP",      value: interface.ipAddress)
                InfoRow(label: "Subnet",  value: interface.subnetMask)
                InfoRow(label: "Gateway", value: interface.gateway)
                DNSRows(servers: interface.dns)
                InfoRow(label: "MAC", value: interface.macAddress)

                if isWiFi, let wifi {
                    MoreToggle(expanded: showWiFiDetails, action: toggleWiFiDetails)
                    if showWiFiDetails {
                        WiFiDetailRows(wifi: wifi)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    private func openSystemSettings() {
        // The menu closes underneath the pointer, so no exit event will clear
        // the highlight before the next open.
        iconHovered = false
        dismissMenu()
        NSWorkspace.shared.open(interface.systemSettingsURL)
    }
}

// MARK: – Wi-Fi extras

/// "Wi-Fi 6E" capsule beside the SSID.
private struct GenerationBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.15)))
            .fixedSize()
    }
}

/// The "More" / "Less" disclosure under a Wi-Fi card's address rows.
private struct MoreToggle: View {
    let expanded: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 3) {
            Text(expanded ? "Less" : "More")
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .regular))
                .rotationEffect(.degrees(expanded ? 90 : 0))
            Spacer()
        }
        .font(.system(size: 11.5, weight: .regular))
        .foregroundStyle(hovered ? .primary : .secondary)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .help(expanded ? "Hide Wi-Fi details" : "Show Wi-Fi details")
    }
}

/// The Option-click Wi-Fi menu's diagnostic block. Rows whose value macOS will
/// not give out (BSSID and country code before Location is granted) are left
/// out rather than shown as "N/A".
private struct WiFiDetailRows: View {
    let wifi: WiFiDetails

    var body: some View {
        VStack(spacing: 0) {
            optional("Security", wifi.security)
            optional("BSSID",    wifi.bssid)
            optional("Channel",  wifi.channelLabel)
            optional("Country",  wifi.countryCode)
            optional("RSSI",     wifi.rssi.map { "\($0) dBm" })
            optional("Noise",    wifi.noise.map { "\($0) dBm" })
            optional("Tx Rate",  wifi.txRate.map { "\(Int($0.rounded())) Mbps" })
            optional("PHY",      phy)
            optional("MCS",      wifi.mcsIndex.map(String.init))
            optional("NSS",      wifi.spatialStreams.map(String.init))
        }
    }

    /// "802.11ax (Wi-Fi 6E)", or just the IEEE name for pre-802.11n links.
    private var phy: String? {
        guard let label = wifi.phyLabel else { return nil }
        guard let generation = wifi.generation else { return label }
        return "\(label) (\(generation))"
    }

    @ViewBuilder
    private func optional(_ label: String, _ value: String?) -> some View {
        if let value {
            InfoRow(label: label, value: value)
        }
    }
}

// MARK: – Detail rows

private struct RowLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 62, alignment: .leading)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RowLabel(text: label)
            CopyableText(value: value)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}

private struct DNSRows: View {
    let servers: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RowLabel(text: "DNS")
            VStack(alignment: .leading, spacing: 2) {
                // Keyed by position: a manual DNS list can repeat a server, and
                // duplicate `\.self` ids make SwiftUI's diffing undefined.
                ForEach(Array(servers.prefix(3).enumerated()), id: \.offset) { _, s in
                    CopyableText(value: s)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}

/// A tappable value that copies itself and flashes "Copied".
///
/// `InfoRow` and the DNS rows used to carry byte-identical copies of this, each
/// with a `DispatchQueue.main.asyncAfter` that could not be cancelled — tapping
/// twice queued two timers and the first one cleared the badge early.
private struct CopyableText: View {
    let value: String

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .onTapGesture { copy() }
                .help("Copy")

            if copied {
                Text("Copied")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .onDisappear { resetTask?.cancel() }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        resetTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            copied = true
        }
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copied = false
            }
        }
    }
}

#Preview {
    ContentView(monitor: NetworkMonitor())
}
