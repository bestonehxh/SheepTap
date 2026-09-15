<p align="center">
  <img src=".github/icon.png?v=3" width="128" alt="SheepTap app icon">
</p>

# 🐑 SheepTap

**A macOS menu-bar utility that shows your active network interfaces at a glance — with one-click copy of any value.**

SheepTap lives quietly in the menu bar (no Dock icon). Click it and you get one card per
active interface — Wi-Fi, Ethernet, VPN — each showing **IP, subnet mask, gateway, DNS
servers, and MAC address**. Click any value to copy it to the clipboard.

## ⬇️ Download

[![Download SheepTap for macOS](https://img.shields.io/badge/Download-SheepTap_9_for_macOS-2ea44f?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/bestonehxh/SheepTap/releases/latest)

**[Get the latest release →](https://github.com/bestonehxh/SheepTap/releases/latest)** — download the `.zip`, unzip, and drag **SheepTap.app** into `Applications`.

> The build is unsigned (not notarized), so macOS will warn on first launch —
> right-click the app and choose **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/SheepTap.app`
>
> Requires macOS 26.4 (Tahoe) or later, Apple Silicon.

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

## The Sheep family 🐑

SheepTap is one of six small native macOS apps that share the same sheep icon set:

|  | App | What it does |
|---|---|---|
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepDrop/main/.github/icon.png?v=3" width="44" alt=""> | [SheepDrop](https://github.com/bestonehxh/SheepDrop) | SFTP / SCP / FTP / TFTP file transfer — client and built-in server |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTerm/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTerm](https://github.com/bestonehxh/SheepTerm) | SSH / Serial / local-shell terminal for network engineers |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTap/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTap](https://github.com/bestonehxh/SheepTap) | Menu-bar viewer for your Mac's network interfaces with click-to-copy |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepPing/main/.github/icon.png?v=3" width="44" alt=""> | [SheepPing](https://github.com/bestonehxh/SheepPing) | Continuous multi-host ping monitor with per-host logs and CSV export |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepText/main/.github/icon.png?v=3" width="44" alt=""> | [SheepText](https://github.com/bestonehxh/SheepText) | Fast text editor with tree-sitter highlighting and a JavaScript plugin system |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepArt/main/.github/icon.png?v=3" width="44" alt=""> | [SheepArt](https://github.com/bestonehxh/SheepArt) | Screenshot annotation — draw, crop, layers, one-key background removal |

## License

[MIT](LICENSE) © 2026 bestonehxh
