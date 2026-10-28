#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-}"

if [ -z "$TARGET_DIR" ]; then
    DEFAULT_DIR="$HOME/Games/SWG-Uprising/drive_c/users/$USER/AppData/Local/Uprising/Client"
    read -rp "Enter destination Client directory [$DEFAULT_DIR]: " TARGET_DIR
    TARGET_DIR="${TARGET_DIR:-$DEFAULT_DIR}"
fi

mkdir -p "$TARGET_DIR"
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH:-}"

# 1. Resolve 7-Zip
SEVENZIP=""
for z in 7z 7za 7zz "$HOME/.local/bin/7zz"; do
    if command -v "$z" >/dev/null 2>&1; then
        SEVENZIP="$(command -v "$z")"
        break
    fi
done

if [ -z "$SEVENZIP" ]; then
    echo "==> 7-Zip not detected."
    IS_STEAMOS=false
    [ -f /etc/os-release ] && grep -qi "steamos" /etc/os-release && IS_STEAMOS=true

    if [ "$IS_STEAMOS" = true ]; then
        echo "==> SteamOS: Fetching static 7zz binary to ~/.local/bin..."
        curl -L -o /tmp/7z.tar.xz "https://www.7-zip.org/a/7z2408-linux-x64.tar.xz"
        tar -xf /tmp/7z.tar.xz -C "$HOME/.local/bin" 7zz
        rm -f /tmp/7z.tar.xz
        chmod +x "$HOME/.local/bin/7zz"
        SEVENZIP="$HOME/.local/bin/7zz"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm p7zip
        SEVENZIP="$(command -v 7z || command -v 7za)"
    else
        echo "Error: Please install p7zip."
        exit 1
    fi
fi

# 2. Resolve Unshield & OpenSSL 1.1
UNSHIELD_BIN=""
if [ -x "$HOME/.local/bin/unshield" ]; then
    UNSHIELD_BIN="$HOME/.local/bin/unshield"
elif command -v unshield >/dev/null 2>&1; then
    UNSHIELD_BIN="$(command -v unshield)"
fi

IS_STEAMOS=false
[ -f /etc/os-release ] && grep -qi "steamos" /etc/os-release && IS_STEAMOS=true

if [ "$IS_STEAMOS" = true ]; then
    if [ ! -f "$HOME/.local/lib/libcrypto.so.1.1" ]; then
        echo "==> SteamOS: Fetching libcrypto.so.1.1 into ~/.local/lib..."
        SSL_PKG="/tmp/openssl-1.1.pkg.tar.zst"
        curl -L -o "$SSL_PKG" "https://archive.archlinux.org/packages/o/openssl-1.1/openssl-1.1-1.1.1.w-1-x86_64.pkg.tar.zst"
        "$SEVENZIP" x -y -so "$SSL_PKG" 2>/dev/null | tar -xf - -C /tmp
        cp -u /tmp/usr/lib/libcrypto.so.1.1* "$HOME/.local/lib/"
        rm -rf /tmp/usr "$SSL_PKG"
    fi

    if [ -z "$UNSHIELD_BIN" ]; then
        echo "==> SteamOS: Fetching unshield into ~/.local/bin..."
        ARCH_PKG="/tmp/unshield.pkg.tar.zst"
        curl -L -o "$ARCH_PKG" "https://archive.archlinux.org/packages/u/unshield/unshield-1.5.1-1-x86_64.pkg.tar.zst"
        "$SEVENZIP" x -y -so "$ARCH_PKG" 2>/dev/null | tar -xf - -C /tmp
        cp -u /tmp/usr/bin/unshield "$HOME/.local/bin/unshield"
        chmod +x "$HOME/.local/bin/unshield"
        cp -u /tmp/usr/lib/libunshield* "$HOME/.local/lib/" 2>/dev/null || true
        rm -rf /tmp/usr "$ARCH_PKG"
        UNSHIELD_BIN="$HOME/.local/bin/unshield"
    fi
else
    if [ -z "$UNSHIELD_BIN" ]; then
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm unshield
            UNSHIELD_BIN="$(command -v unshield)"
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y unshield
            UNSHIELD_BIN="$(command -v unshield)"
        fi
    fi
fi

echo "Using 7-Zip:    $SEVENZIP"
echo "Using Unshield: $UNSHIELD_BIN"

# 3. Locate Disc ISOs
echo "==> Searching for SWG installation ISOs..."
prompt_iso() {
    local num="$1"
    local found
    found=$(find . "$HOME/Downloads" -maxdepth 2 \( -iname "*galaxies*$num*.iso" -o -iname "*disc*$num*.iso" \) 2>/dev/null | head -n 1)
    if [ -z "$found" ] || [ ! -f "$found" ]; then
        read -rp "Enter path to Disc $num ISO: " found
    fi
    if [ ! -f "$found" ]; then
        echo "Error: File not found: $found"
        exit 1
    fi
    echo "$found"
}

DISC1=$(prompt_iso 1)
DISC2=$(prompt_iso 2)
DISC3=$(prompt_iso 3)

# Stage on disk (/home partition) to avoid RAM tmpfs quotas
TMP_STAGE="$TARGET_DIR/.swg_stage_tmp"
rm -rf "$TMP_STAGE"
mkdir -p "$TMP_STAGE/cabs" "$TMP_STAGE/unpacked"
trap 'rm -rf "$TMP_STAGE"' EXIT

echo "==> Extracting cabinet archives from ISOs to disk storage..."
"$SEVENZIP" e -y -o"$TMP_STAGE/cabs" "$DISC1" "data*.cab" "data*.hdr" "DATA*.CAB" "DATA*.HDR" >/dev/null 2>&1 || true
"$SEVENZIP" e -y -o"$TMP_STAGE/cabs" "$DISC2" "data*.cab" "data*.hdr" "DATA*.CAB" "DATA*.HDR" >/dev/null 2>&1 || true
"$SEVENZIP" e -y -o"$TMP_STAGE/cabs" "$DISC3" "data*.cab" "data*.hdr" "DATA*.CAB" "DATA*.HDR" >/dev/null 2>&1 || true

# Normalize all filenames to lowercase
(
    cd "$TMP_STAGE/cabs"
    for f in *; do
        lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
        if [ "$f" != "$lower" ]; then
            mv -n "$f" "$lower" 2>/dev/null || true
        fi
    done
)

echo "==> Extracting game archives directly from cabinets..."
(
    cd "$TMP_STAGE/cabs"
    # data4.cab houses the complete SWG Files catalog across all discs
    if [ -f "data4.cab" ]; then
        "$UNSHIELD_BIN" -d "$TMP_STAGE/unpacked" -g "SWG Files" x data4.cab >/dev/null 2>&1 || \
        "$UNSHIELD_BIN" -d "$TMP_STAGE/unpacked" x data4.cab >/dev/null 2>&1 || true
    fi
    # Fallback to data1.hdr if any remaining files are cataloged separately
    if [ -f "data1.hdr" ]; then
        "$UNSHIELD_BIN" -d "$TMP_STAGE/unpacked" -g "SWG Files" x data1.hdr >/dev/null 2>&1 || true
    fi
)

echo "==> Deploying .tre archives to $TARGET_DIR..."
found_tre=0
while IFS= read -r file; do
    fname=$(basename "$file")
    lower_fname=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
    dest_file="$TARGET_DIR/$lower_fname"

    # Avoid attempting to copy file onto itself
    if [ -f "$dest_file" ] && [ "$(realpath "$file")" = "$(realpath "$dest_file")" ]; then
        continue
    fi

    cp -u "$file" "$dest_file"
    found_tre=$((found_tre + 1))
    echo "  -> Deployed: $lower_fname"
done < <(find "$TMP_STAGE/unpacked" -type f -iname "*.tre" 2>/dev/null)

if [ "$found_tre" -eq 0 ]; then
    echo "Error: No .tre archives were extracted."
    exit 1
fi

echo "Successfully extracted $found_tre .tre archives."

# Provide base configuration if missing
CFG_FILE="$TARGET_DIR/swg_client.cfg"
if [ ! -f "$CFG_FILE" ]; then
    echo "==> Generating base swg_client.cfg..."
    cat << 'EOF' > "$CFG_FILE"
[SharedFile]
    searchPath01=.

[ClientGame]
    autoPlayerAcceptedEula=1
    preApprovedServer=1

[ClientGraphics]
    useHardwareMouseCursor=1
EOF
fi

echo ""
echo "=========================================================="
echo "Extraction complete! Files placed in: $TARGET_DIR"
echo "=========================================================="
