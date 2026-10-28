# SWG Uprising - Unified Linux Setup & Launcher

A self-contained, rootless setup and launch suite for **Star Wars Galaxies: Uprising**, engineered specifically for **CachyOS / Arch Linux** and **SteamOS (Steam Deck)**.

## Highlights
- **Immutable Root Friendly**: Requires no root access or partition unlocks on SteamOS. Uses persistent user-space Wine runners (`~/.local/share/wine-runners`) and user-space binaries (`~/.local/bin/`).
- **Direct Cabinet Extraction**: Automatically unpacks retail ISOs by targeting the localized `SWG Files` catalog directly inside `data4.cab`, bypassing legacy InstallShield multi-volume 2 GB overflow bugs.
- **Physical Disk Staging**: Stages temporary unpacking files to user storage to avoid running out of RAM disk space on `/tmp`.
- **Display Server & DXVK Native**: Bundles DXVK (Direct3D 9 over Vulkan) and launches via an auto-detected Wine virtual desktop (`explorer /desktop=...`) using `xrandr`. Prevents `ChangeDisplaySettings` crashes and dynamically scales between the Steam Deck's 800p internal screen and external 1080p+ monitors.
- **Clean Alt-Tabbing**: Running in an isolated desktop wrapper allows seamless minimizing and workspace switching without dropping the DirectX surface.

---

## Quick Start

### 1. Clone Repository
```bash
git clone [https://github.com/xKambr/swg-uprising-linux.git](https://github.com/xKambr/swg-uprising-linux.git)
cd swg-uprising-linux
chmod +x setup_uprising.sh swg_setup.sh launch_uprising.py
