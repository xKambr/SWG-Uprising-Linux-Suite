#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "      SWG Uprising - Unified Setup (Arch / SteamOS)       "
echo "=========================================================="

detect_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Determine if running on SteamOS
IS_STEAMOS=false
if [ -f /etc/os-release ]; then
    if grep -qi "steamos" /etc/os-release; then
        IS_STEAMOS=true
    fi
fi

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# 1. Dependency Checks: Python 3
if ! detect_cmd python3; then
    echo "Error: Python 3 is required."
    exit 1
fi

# 2. Dependency Checks: Wine Runner Resolution
WINE_BIN=""
WINEBOOT_BIN=""

if [ "$IS_STEAMOS" = true ]; then
    echo "==> SteamOS detected. Utilizing persistent user-space runner..."
    RUNNER_DIR="$HOME/.local/share/wine-runners"
    RUNNER_VER="wine-9.0-staging-amd64"
    WINE_BIN="$RUNNER_DIR/$RUNNER_VER/bin/wine"
    WINEBOOT_BIN="$RUNNER_DIR/$RUNNER_VER/bin/wineboot"

    if [ ! -f "$WINE_BIN" ]; then
        echo "==> Downloading portable Wine runner into $RUNNER_DIR..."
        mkdir -p "$RUNNER_DIR"
        TAR_DEST="/tmp/$RUNNER_VER.tar.xz"
        curl -L -o "$TAR_DEST" "https://github.com/Kron4ek/Wine-Builds/releases/download/9.0/wine-9.0-staging-amd64.tar.xz"
        tar -xf "$TAR_DEST" -C "$RUNNER_DIR"
        rm -f "$TAR_DEST"
    fi
else
    # Standard Linux (CachyOS, Arch, Fedora, etc.)
    if ! detect_cmd wine; then
        echo "Notice: Wine was not found."
        if detect_cmd pacman; then
            echo "Installing wine via pacman..."
            sudo pacman -S --needed --noconfirm wine wine-gecko wine-mono
        elif detect_cmd apt-get; then
            sudo apt-get update && sudo apt-get install -y wine
        elif detect_cmd dnf; then
            sudo dnf install -y wine
        else
            echo "Please install Wine manually and rerun this script."
            exit 1
        fi
    fi
    WINE_BIN="$(command -v wine)"
    WINEBOOT_BIN="$(command -v wineboot || echo "$WINE_BIN"boot)"
fi

echo "Using Wine runner: $WINE_BIN"

# 3. Directory Resolution
DEFAULT_DIR="$HOME/Games/SWG-Uprising"
echo ""
read -rp "Enter Wine prefix destination path [$DEFAULT_DIR]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"

WINE_PREFIX="$INSTALL_DIR"
CLIENT_DIR="$INSTALL_DIR/drive_c/users/$USER/AppData/Local/Uprising/Client"

mkdir -p "$CLIENT_DIR/.uprising/manifests"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/Desktop"

# Save runner path configuration for launch_uprising.py
cat << EOF > "$CLIENT_DIR/runner_config.json"
{
  "wine_bin": "$WINE_BIN",
  "is_steamos": $IS_STEAMOS
}
EOF

# 4. Wine Prefix Setup & Registry Overrides
echo "==> Initializing Wine prefix..."
WINEPREFIX="$WINE_PREFIX" "$WINEBOOT_BIN" -u >/dev/null 2>&1 || true

echo "==> Setting native DLL overrides (dinput8, d3d9)..."
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "dinput8" /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "d3d9" /d "native,builtin" /f >/dev/null 2>&1 || true

# 5. DXVK Direct3D 9 Provisioning
echo "==> Setting up DXVK Vulkan translation layer..."
DXVK_DEST="/tmp/dxvk.tar.gz"
curl -L -o "$DXVK_DEST" "https://github.com/doitsujin/dxvk/releases/download/v2.3/dxvk-2.3.tar.gz" 2>/dev/null
tar -xzf "$DXVK_DEST" -C /tmp/
cp -u /tmp/dxvk-2.3/x32/d3d9.dll "$CLIENT_DIR/" 2>/dev/null || true
cp -u /tmp/dxvk-2.3/x32/dxgi.dll "$CLIENT_DIR/" 2>/dev/null || true
rm -rf /tmp/dxvk*

cat << 'EOF' > "$CLIENT_DIR/dxvk.conf"
d3d9.forceWindowedMode = true
d3d9.disableModeSwitch = true
EOF

cat << 'EOF' > "$CLIENT_DIR/options.cfg"
[ClientGraphics]
	windowed=1
	borderlessWindow=1
	useHardwareMouseCursor=1
EOF

# 6. Optional Base Media Extraction
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/swg_setup.sh" ]; then
    echo ""
    read -rp "Do you want to extract retail ISOs using swg_setup.sh now? [y/N] " extract_choice
    if [[ "$extract_choice" =~ ^[Yy]$ ]]; then
        chmod +x "$SCRIPT_DIR/swg_setup.sh"
        "$SCRIPT_DIR/swg_setup.sh" "$CLIENT_DIR"
    fi
fi

# 7. Install Launcher Script
if [ ! -f "$SCRIPT_DIR/launch_uprising.py" ]; then
    echo "Error: launch_uprising.py was not found in $SCRIPT_DIR."
    exit 1
fi

echo "==> Installing launcher script to client directory..."
cp "$SCRIPT_DIR/launch_uprising.py" "$CLIENT_DIR/launch_uprising.py"
chmod +x "$CLIENT_DIR/launch_uprising.py"

# 8. Terminal Detection & Desktop Shortcuts
TERM_BIN=""
for t in alacritty kitty foot konsole gnome-terminal xfce4-terminal; do
    if detect_cmd "$t"; then
        TERM_BIN="$t"
        break
    fi
done

PYTHON_BIN="$(command -v python3)"

if [ -z "$TERM_BIN" ]; then
    EXEC_CMD="$PYTHON_BIN \"$CLIENT_DIR/launch_uprising.py\""
    TERMINAL_SETTING="true"
else
    case "$TERM_BIN" in
        konsole)
            EXEC_CMD="konsole -e $PYTHON_BIN \"$CLIENT_DIR/launch_uprising.py\""
            ;;
        *)
            EXEC_CMD="$TERM_BIN -e $PYTHON_BIN \"$CLIENT_DIR/launch_uprising.py\""
            ;;
    esac
    TERMINAL_SETTING="false"
fi

echo "==> Creating desktop shortcuts..."
DESKTOP_FILE="$HOME/.local/share/applications/swg-uprising.desktop"
cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=SWG Uprising
Comment=Star Wars Galaxies Uprising
Path=$CLIENT_DIR
Exec=$EXEC_CMD
Terminal=$TERMINAL_SETTING
Type=Application
Categories=Game;
EOF

chmod +x "$DESKTOP_FILE"
cp "$DESKTOP_FILE" "$HOME/Desktop/swg-uprising.desktop"
chmod +x "$HOME/Desktop/swg-uprising.desktop"

if detect_cmd update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
fi

echo ""
echo "=========================================================="
echo "Installation Finished!"
echo "Destination: $CLIENT_DIR"
echo "Launch via desktop shortcut or directly with:"
echo "python3 $CLIENT_DIR/launch_uprising.py"
echo "=========================================================="
