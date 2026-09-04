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
                    InterfaceCard(interface: iface, isFirst: idx == 0, dismissMenu: dismissMenu)
                }
            }
        }
        .frame(width: MenuMetrics.width)
        .padding(.vertical, 4)
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
    var isFirst = false
    var dismissMenu: () -> Void = {}

    @State private var iconHovered = false

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
                .onHover { hovering in
                    // Keep push/pop balanced: `openSystemSettings` may already
                    // have cleared the hover before the exit event arrives.
                    guard hovering != iconHovered else { return }
                    iconHovered = hovering
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
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

                // Fixed-height slot — shows SSID for WiFi, empty gap for Ethernet
                Group {
                    if let ssid = interface.ssid, !ssid.isEmpty {
                        Text(ssid)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, isFirst ? 0 : 12)
            .padding(.bottom, 4)

            // ── Detail rows ───────────────────────────────────────────
            VStack(spacing: 0) {
                InfoRow(label: "IP",      value: interface.ipAddress)
                InfoRow(label: "Subnet",  value: interface.subnetMask)
                InfoRow(label: "Gateway", value: interface.gateway)
                DNSRows(servers: interface.dns)
                InfoRow(label: "MAC", value: interface.macAddress)
            }
            .padding(.bottom, 10)
        }
    }

    private func openSystemSettings() {
        // Pop the hover cursor first: the menu closes underneath the pointer,
        // so `onHover(false)` never fires and the hand would stick.
        if iconHovered {
            iconHovered = false
            NSCursor.pop()
        }
        dismissMenu()
        NSWorkspace.shared.open(interface.systemSettingsURL)
    }
}

// MARK: – Detail rows

private struct RowLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 56, alignment: .leading)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 0) {
            RowLabel(text: label)
            CopyableText(value: value)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

private struct DNSRows: View {
    let servers: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RowLabel(text: "DNS")
            VStack(alignment: .leading, spacing: 3) {
                ForEach(servers.prefix(3), id: \.self) { s in
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
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .onTapGesture { copy() }
                .help("Copy")

            if copied {
                Text("Copied")
                    .font(.system(size: 10, weight: .medium))
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
