# 🐑 SheepTap

**A macOS menu-bar utility that shows your active network interfaces at a glance — with one-click copy of any value.**

SheepTap lives quietly in the menu bar (no Dock icon). Click it and you get one card per
active interface — Wi-Fi, Ethernet, VPN — each showing **IP, subnet mask, gateway, DNS
servers, and MAC address**. Click any value to copy it to the clipboard.

## Features

- One card per active IPv4 interface, sorted Wi-Fi → Ethernet → VPN → Other
- Wi-Fi cards show the current **SSID**
- **Click-to-copy** every value (IP, subnet, gateway, each DNS server, MAC) with a
  "Copied" flash so you know it worked
- Gateway is attributed only to the actual primary interface — VPN/tunnel interfaces
  don't report a false gateway
- DNS shown per interface, respecting manual overrides in System Settings
- Live updates via `NWPathMonitor` + SystemConfiguration notifications, debounced and
  refreshed lazily — near-zero CPU while the menu is closed
- **Launch at login** registered automatically on first run (and self-repairs if you
  move the app), while respecting it if you later turn it off in System Settings
- Fully sandboxed; reads only local system APIs — **no network requests, no analytics**
- No third-party dependencies — Apple frameworks only

## Requirements

- macOS 26.4 (Tahoe) or later, Apple Silicon

## Building

```bash
xcodebuild -project SheepTap.xcodeproj -target SheepTap -configuration Release build
```

(or just open `SheepTap.xcodeproj` in Xcode 26+ and hit Run)

## Download

Prebuilt (unsigned) builds are on the
[Releases](https://github.com/bestonehxh/SheepTap-app/releases) page.
Because they are not notarized, macOS will warn on first launch — right-click the app
and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/SheepTap.app
```

## The Sheep family 🐑

SheepTap is one of four small native macOS apps that share the same sheep icon set:

| App | What it does |
|---|---|
| 🖥️ [SheepTerm](https://github.com/bestonehxh/SheepTerm-app) | SSH / Serial / local-shell terminal for network engineers |
| 📋 [SheepTap](https://github.com/bestonehxh/SheepTap-app) | Menu-bar viewer for your Mac's network interfaces with click-to-copy |
| 📡 [SheepPing](https://github.com/bestonehxh/SheepPing-app) | Continuous multi-host ping monitor with per-host logs and CSV export |
| 📝 [SheepText](https://github.com/bestonehxh/SheepText-app) | Fast text editor with tree-sitter highlighting and a JavaScript plugin system |

## License

[MIT](LICENSE) © 2026 bestonehxh
