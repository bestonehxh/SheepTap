<p align="center">
  <img src=".github/icon.png?v=3" width="128" alt="SheepTap app icon">
</p>

# 🐑 SheepTap

**A macOS menu-bar utility that shows your active network interfaces at a glance — with one-click copy of any value.**

SheepTap lives quietly in the menu bar (no Dock icon). Click it and you get one card per
active interface — Wi-Fi, Ethernet, VPN — each showing **IP, subnet mask, gateway, DNS
servers, and MAC address**. Click any value to copy it to the clipboard.

## ⬇️ Download

[![Download SheepTap for macOS](https://img.shields.io/badge/Download-SheepTap_13_for_macOS-2ea44f?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/bestonehxh/SheepTap/releases/latest)

**[Get the latest release →](https://github.com/bestonehxh/SheepTap/releases/latest)** — download the `.zip`, unzip, and drag **SheepTap.app** into `Applications`.

> The build is unsigned (not notarized), so macOS will warn on first launch —
> right-click the app and choose **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/SheepTap.app`
>
> Requires macOS 26.4 (Tahoe) or later, Apple Silicon.

## The Sheep family 🐑

SheepTap is one of a few small native macOS apps for network engineers:

|  | App | What it does |
|---|---|---|
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTerm/main/.github/icon.png?v=3" width="48" height="48" alt="SheepTerm"> | **[SheepTerm](https://github.com/bestonehxh/SheepTerm)**<br>[⬇️ Download](https://github.com/bestonehxh/SheepTerm/releases/latest) | SSH / Serial / local-shell terminal for network engineers |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepText/main/.github/icon.png?v=3" width="48" height="48" alt="SheepText"> | **[SheepText](https://github.com/bestonehxh/SheepText)**<br>[⬇️ Download](https://github.com/bestonehxh/SheepText/releases/latest) | Fast text editor with tree-sitter highlighting and a JavaScript plugin system |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepDrop/main/.github/icon.png?v=3" width="48" height="48" alt="SheepDrop"> | **[SheepDrop](https://github.com/bestonehxh/SheepDrop)**<br>[⬇️ Download](https://github.com/bestonehxh/SheepDrop/releases/latest) | SFTP / SCP / FTP / TFTP file transfer — client and built-in server |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTap/main/.github/icon.png?v=3" width="48" height="48" alt="SheepTap"> | **[SheepTap](https://github.com/bestonehxh/SheepTap)**<br>[⬇️ Download](https://github.com/bestonehxh/SheepTap/releases/latest) | Menu-bar viewer for your Mac's network interfaces with click-to-copy |
| <img src="https://raw.githubusercontent.com/bestonehxh/LabDC/main/.github/icon.png" width="48" height="48" alt="LabDC"> | **[LabDC](https://github.com/bestonehxh/LabDC)**<br>[⬇️ Download](https://github.com/bestonehxh/LabDC/releases/latest) | Active Directory–compatible domain controller with RADIUS for 802.1X and a lab CA |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepLog/main/.github/icon.png?v=2" width="48" height="48" alt="UncleSpy"> | **[UncleSpy](https://github.com/bestonehxh/SheepLog)**<br>[⬇️ Download](https://github.com/bestonehxh/SheepLog/releases/latest) | Syslog viewer, SNMP tester and packet capture with TCP and 802.1X ladder diagrams — and a Troubleshoot page that reads all three |
| <img src="https://raw.githubusercontent.com/bestonehxh/Paddock/main/.github/icon.png" width="48" height="48" alt="Paddock"> | **[Paddock](https://github.com/bestonehxh/Paddock)**<br>[⬇️ Download](https://github.com/bestonehxh/Paddock/releases/latest) | VM control and console for standalone ESXi hosts — power, snapshots, guest files and scripts, no vCenter |

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

## License

[MIT](LICENSE) © 2026 bestonehxh
