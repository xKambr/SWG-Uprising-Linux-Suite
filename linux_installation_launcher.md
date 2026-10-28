# Star Wars Galaxies: Uprising — Linux Client Setup & Launcher

A lightweight, native Linux setup and launcher suite for **Star Wars Galaxies: Uprising**[cite: 9]. 

This toolset bypasses the official Windows Electron installer and launcher entirely to eliminate common Wine friction points: Wine UDP socket stalls during login handshakes, broken background NSIS update loops, and crashing `powershell.exe`/JSON sub-processes[cite: 9].

---

## Included Components

| File | Purpose |
| :--- | :--- |
| `setup_uprising.sh` | Automated environment installer: builds the isolated Wine prefix, applies registry overrides, provisions DXVK, and registers desktop application shortcuts. |
| `swg_setup.sh` | Direct asset extractor: natively pulls the base `.tre` game archives from retail ISOs (`GALAXIES1.iso`–`3`) by parsing InstallShield cabinets directly. |
| `launch_uprising.py` | Standalone Python client: runs differential HTTPS manifest updates, performs the SOE UDP login handshake natively, and starts `SWGEmu.exe` synchronously in Wine. |

---

## Prerequisites

Before starting, ensure you have:
1. **Linux Distribution:** Arch / CachyOS, SteamOS (Steam Deck), Bazzite, Fedora, Ubuntu/Debian, or openSUSE.
2. **System Packages:**
   * `python3`
   * `wine` (on standard mutable distributions; SteamOS utilizes an automated user-space runner)
   * `p7zip` (only required if extracting retail ISOs with `swg_setup.sh`)
   * A terminal emulator (`alacritty`, `kitty`, `foot`, `konsole`, `gnome-terminal`, or `xfce4-terminal`)
3. **SWG Base Game Files:**
   * Either original retail installation media (`GALAXIES1.iso`, `GALAXIES2.iso`, `GALAXIES3.iso`) or pre-extracted retail TRE files (`bottom.tre`, `data_sku0_00.tre` through `data_sku0_14.tre`).
   * A clean `SWGEmu.exe` executable.

> **Note:** `setup_uprising.sh` will automatically detect your package manager (`pacman`, `apt`, `dnf`) on desktop distributions and prompt to install missing core packages if permitted. On SteamOS, it operates fully in user-space without modifying read-only root filesystems.

---

## Installation & Execution

### Step 1: Clone the Repository & Set Permissions

```bash
git clone [https://github.com/xKambr/swg-uprising-linux.git](https://github.com/xKambr/swg-uprising-linux.git)
cd swg-uprising-linux
chmod +x setup_uprising.sh swg_setup.sh launch_uprising.py
