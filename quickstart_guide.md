# SWG Uprising — Quick Start Guide

A concise guide to setting up and launching Star Wars Galaxies: Uprising on Linux (Arch, CachyOS, and SteamOS).

---

## Order of Operations

```
[1. Clone Repo] ➜ [2. Stage ISOs] ➜ [3. Run setup_uprising.sh] ➜ [4. Launch Game]
```

---

## Step-by-Step Instructions

### 1. Clone & Set Permissions
Open a terminal and clone the repository:
```bash
git clone https://github.com/xKambr/swg-uprising-linux.git
cd swg-uprising-linux
chmod +x setup_uprising.sh swg_setup.sh launch_uprising.py
```

### 2. Stage Base Media
Place your three retail SWG ISO images in `~/Downloads` or the repository folder:
* `GALAXIES1.iso`
* `GALAXIES2.iso`
* `GALAXIES3.iso`

*(Alternatively, if you already have the pre-extracted `.tre` files, place them directly into `~/Games/SWG-Uprising/drive_c/users/$USER/AppData/Local/Uprising/Client/`)*

### 3. Run Environment Setup
Execute the primary installer:
```bash
./setup_uprising.sh
```

**What this handles automatically:**
1. Installs or extracts a portable user-space Wine runner (no root access required on SteamOS).
2. Initializes the Wine prefix (`~/Games/SWG-Uprising`).
3. Sets native DLL overrides for `dinput8` and `d3d9`.
4. Provisions DXVK Direct3D 9 Vulkan translation libraries.
5. Invokes `swg_setup.sh` when prompted (`y`) to extract all 22 base game `.tre` archives directly from `data4.cab`.
6. Generates desktop launcher shortcuts (`swg-uprising.desktop`).

### 4. Launch the Game
Start the game from your application menu (**SWG Uprising**) or run the launcher directly in terminal:
```bash
python3 "$HOME/Games/SWG-Uprising/drive_c/users/$USER/AppData/Local/Uprising/Client/launch_uprising.py"
```

1. Enter your server **Username** and **Password**.
2. The launcher automatically syncs server patch manifests.
3. The game launches in an auto-scaled desktop wrapper matching your active display resolution (Steam Deck 800p or external 1080p+).