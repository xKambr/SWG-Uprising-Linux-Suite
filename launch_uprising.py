#!/usr/bin/env python3
import getpass
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import urllib.request
import zlib

SERVER_IP = "135.148.150.69"
SERVER_PORT = 44453
CLIENT_VERSION = "20050408-18:00"
LOGIN_CLIENT_ID = 1091772310
LOGIN_CLIENT_TOKEN = 2863830726
ERROR_MESSAGE = 3047946522

LIVE_CHANNEL_URL = "https://downloads.swguprising.com/live-channel.json"
HTTP_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "*/*",
}

# --- 1. Client Auto-Update Pipeline ---

def get_installed_state(client_dir: str) -> dict:
    state_file = os.path.join(client_dir, ".uprising", "installed-state.json")
    if os.path.exists(state_file):
        try:
            with open(state_file, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"releaseId": "none", "clientMode": "phase-b-dinput8"}

def update_installed_state(client_dir: str, release_id: str, manifest_sha: str):
    state_dir = os.path.join(client_dir, ".uprising")
    os.makedirs(state_dir, exist_ok=True)
    state_file = os.path.join(state_dir, "installed-state.json")
    
    state = {
        "releaseId": release_id,
        "manifestSha256": manifest_sha,
        "clientMode": "phase-b-dinput8",
    }
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)

def check_and_apply_updates(client_dir: str):
    print("Checking for game client updates...")
    req = urllib.request.Request(LIVE_CHANNEL_URL, headers=HTTP_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            channel_data = json.loads(resp.read().decode())
    except Exception as e:
        print(f"Warning: Could not check for updates ({e}). Proceeding with local client.")
        return

    remote_release = channel_data.get("releaseId")
    manifest_url = channel_data.get("manifestUrl")
    manifest_sha = channel_data.get("manifestSha256", "")

    installed_state = get_installed_state(client_dir)
    installed_release = installed_state.get("releaseId")

    if installed_release == remote_release:
        print(f"Client is up to date ({remote_release}).")
        return

    print(f"\nUpdate available! Installed: {installed_release} -> Remote: {remote_release}")
    print("Fetching manifest...")

    man_req = urllib.request.Request(manifest_url, headers=HTTP_HEADERS)
    with urllib.request.urlopen(man_req, timeout=10.0) as resp:
        manifest = json.loads(resp.read().decode())

    with open(os.path.join(client_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    files = manifest.get("files", [])
    total_files = len(files)
    downloaded = 0

    for idx, item in enumerate(files, 1):
        rel_path = item["path"]
        expected_sha = item["sha256"]
        url = item["url"]
        full_path = os.path.join(client_dir, rel_path)

        needs_download = True
        if os.path.exists(full_path):
            hasher = hashlib.sha256()
            with open(full_path, "rb") as fp:
                while chunk := fp.read(65536):
                    hasher.update(chunk)
            if hasher.hexdigest().lower() == expected_sha.lower():
                needs_download = False

        if needs_download:
            print(f"[{idx}/{total_files}] Downloading {rel_path}...")
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            dl_req = urllib.request.Request(url, headers=HTTP_HEADERS)
            with urllib.request.urlopen(dl_req, timeout=30.0) as resp, open(full_path, "wb") as out:
                out.write(resp.read())
            downloaded += 1

    update_installed_state(client_dir, remote_release, manifest_sha)
    print(f"Update complete! ({downloaded} files updated)\n")

# --- 2. SOE Protocol & Authentication ---

def make_crc_table():
    table = [0] * 256
    for i in range(256):
        val = i
        for _ in range(8):
            val = 3988292384 ^ (val >> 1) if (val & 1) else (val >> 1)
        table[i] = val & 0xFFFFFFFF
    return table

CRC_TABLE = make_crc_table()

def generate_soe_crc(data: bytes, seed: int) -> int:
    crc = (CRC_TABLE[(~seed) & 0xFF] ^ 0xFFFFFF) & 0xFFFFFFFF
    for shift in (8, 16, 24):
        idx = ((seed >> shift) ^ crc) & 0xFF
        crc = ((crc >> 8) & 0xFFFFFF) ^ CRC_TABLE[idx]
    for b in data:
        crc = ((crc >> 8) & 0xFFFFFF) ^ CRC_TABLE[(b ^ crc) & 0xFF]
    return (~crc) & 0xFFFFFFFF

def append_crc(packet: bytearray, seed: int):
    crc = generate_soe_crc(packet[:-2], seed)
    struct.pack_into(">H", packet, len(packet) - 2, crc & 0xFFFF)

def validate_crc(packet: bytes, seed: int) -> bool:
    if len(packet) < 2:
        return False
    expected = struct.unpack(">H", packet[-2:])[0]
    calculated = generate_soe_crc(packet[:-2], seed) & 0xFFFF
    return expected == calculated

def crypt_soe_packet(packet: bytearray, seed: int, decrypt: bool):
    offset = 2 if packet[0] == 0 else 1
    crypt_len = len(packet) - (4 if packet[0] == 0 else 3)
    pos = offset
    num_blocks = crypt_len // 4
    for _ in range(num_blocks):
        orig = struct.unpack_from("<I", packet, pos)[0]
        struct.pack_into("<I", packet, pos, (orig ^ seed) & 0xFFFFFFFF)
        seed = orig if decrypt else struct.unpack_from("<I", packet, pos)[0]
        pos += 4
    for _ in range(crypt_len % 4):
        packet[pos] ^= (seed & 0xFF)
        pos += 1

def encode_ascii(text: str) -> bytes:
    raw = text.encode("utf-8")
    return struct.pack("<H", len(raw)) + raw

def build_data_packet(payload: bytes, seed: int, seq: int = 0) -> bytes:
    pkt = bytearray(len(payload) + 7)
    struct.pack_into("<H", pkt, 0, 2304)
    struct.pack_into(">H", pkt, 2, seq)
    pkt[4:4 + len(payload)] = payload
    pkt[-3] = 0
    struct.pack_into(">H", pkt, len(pkt) - 2, 0)
    crypt_soe_packet(pkt, seed, False)
    append_crc(pkt, seed)
    return bytes(pkt)

def build_ack_packet(seq: int, seed: int) -> bytes:
    pkt = bytearray(7)
    struct.pack_into("<H", pkt, 0, 5376)
    struct.pack_into(">H", pkt, 2, seq)
    crypt_soe_packet(pkt, seed, False)
    append_crc(pkt, seed)
    return bytes(pkt)

def read_ascii(msg: bytes, offset: int):
    if offset + 2 > len(msg):
        return "", offset
    length = struct.unpack_from("<H", msg, offset)[0]
    offset += 2
    val = msg[offset:offset + length].decode("utf-8", errors="replace")
    return val, offset + length

def parse_application(message: bytes):
    if len(message) < 6 or struct.unpack_from("<H", message, 0)[0] != 4:
        return None
    hash_val = struct.unpack_from("<I", message, 2)[0]
    cursor = 6
    if hash_val == ERROR_MESSAGE:
        err_type, cursor = read_ascii(message, cursor)
        err_detail, cursor = read_ascii(message, cursor)
        raise RuntimeError(f"Login Rejected: {err_type} - {err_detail}")
    if hash_val != LOGIN_CLIENT_TOKEN or cursor + 4 > len(message):
        return None
    token_plus_acct = struct.unpack_from("<I", message, cursor)[0]
    cursor += 4
    token_len = token_plus_acct - 4
    session_id = message[cursor:cursor + token_len].decode("ascii", errors="replace")
    cursor += token_len + 8
    username, _ = read_ascii(message, cursor)
    return {"username": username, "sessionId": session_id}

def split_messages(payload: bytes):
    if len(payload) < 2 or struct.unpack_from("<H", payload, 0)[0] != 6400:
        return [payload]
    results = []
    offset = 2
    while offset < len(payload):
        length = payload[offset]
        offset += 1
        if length == 255:
            if offset + 2 > len(payload):
                break
            length = struct.unpack_from(">H", payload, offset)[0]
            offset += 2
        results.append(payload[offset:offset + length])
        offset += length
    return results

# --- 3. Dynamic Environment & Runner Resolution ---

def get_screen_resolution() -> tuple:
    """Detect current active display resolution via xrandr."""
    try:
        output = subprocess.check_output(["xrandr"], text=True, stderr=subprocess.DEVNULL)
        for line in output.splitlines():
            if "*" in line:
                res = line.split()[0]
                w, h = res.split("x")
                return int(w), int(h)
    except Exception:
        pass
    return 1280, 800

def resolve_wine_binary(client_dir: str) -> str:
    if os.environ.get("WINE_RUNNER"):
        return os.environ["WINE_RUNNER"]

    cfg_path = os.path.join(client_dir, "runner_config.json")
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, "r") as f:
                data = json.load(f)
                saved_bin = data.get("wine_bin")
                if saved_bin and os.path.exists(saved_bin):
                    return saved_bin
        except Exception:
            pass

    user_space_candidates = [
        os.path.expanduser("~/.local/share/wine-runners/wine-9.0-staging-amd64/bin/wine"),
        os.path.expanduser("~/.local/bin/wine"),
    ]
    for runner in user_space_candidates:
        if os.path.isfile(runner) and os.access(runner, os.X_OK):
            return runner

    sys_wine = shutil.which("wine")
    if sys_wine:
        return sys_wine

    return "wine"

def main():
    client_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Resolve prefix dynamically
    prefix = os.environ.get("WINEPREFIX")
    if not prefix:
        curr = client_dir
        while curr and curr != "/":
            if os.path.isdir(os.path.join(curr, "drive_c")):
                prefix = curr
                break
            curr = os.path.dirname(curr)
        if not prefix:
            prefix = os.path.expanduser("~/Games/SWG-Uprising")

    # Step 1: Differential file sync
    check_and_apply_updates(client_dir)

    # Step 2: User Authentication
    username = input("Username: ").strip()
    if not username:
        print("Username cannot be empty.")
        sys.exit(1)
    password = getpass.getpass("Password: ")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(4.0)

    print(f"Connecting to {SERVER_IP}:{SERVER_PORT}...")
    conn_id = struct.unpack("<I", os.urandom(4))[0]
    req = struct.pack("<H", 256) + struct.pack("<H", 0) + struct.pack(">H", 2) + struct.pack("<I", conn_id) + struct.pack(">I", 496)
    sock.sendto(req, (SERVER_IP, SERVER_PORT))

    try:
        resp, _ = sock.recvfrom(2048)
    except socket.timeout:
        print("Error: Handshake timed out.")
        sys.exit(1)

    seed = struct.unpack(">I", resp[6:10])[0]

    header = struct.pack("<H", 4) + struct.pack("<I", LOGIN_CLIENT_ID)
    cred_payload = header + encode_ascii(username) + encode_ascii(password) + encode_ascii(CLIENT_VERSION)
    sock.sendto(build_data_packet(cred_payload, seed), (SERVER_IP, SERVER_PORT))

    session = None
    fragments = []
    fragment_size = 0

    while not session:
        try:
            packet, _ = sock.recvfrom(2048)
        except socket.timeout:
            print("Timed out waiting for authentication response.")
            break

        if not validate_crc(packet, seed):
            continue

        opcode = struct.unpack_from("<H", packet, 0)[0]
        if opcode not in (2304, 3328):
            continue

        pkt_ba = bytearray(packet)
        crypt_soe_packet(pkt_ba, seed, True)
        if len(pkt_ba) < 7:
            continue

        seq = struct.unpack_from(">H", pkt_ba, 2)[0]
        sock.sendto(build_ack_packet(seq, seed), (SERVER_IP, SERVER_PORT))

        payload = bytes(pkt_ba[4:-3])
        if pkt_ba[-3] == 1:
            payload = zlib.decompress(payload)

        if opcode == 3328:
            if not fragments:
                fragment_size = struct.unpack_from(">I", payload, 0)[0]
                payload = payload[4:]
            fragments.append(payload)
            if sum(len(f) for f in fragments) < fragment_size:
                continue
            payload = b"".join(fragments)[:fragment_size]
            fragments = []

        for msg in split_messages(payload):
            res = parse_application(msg)
            if res:
                session = res
                break

    if not session:
        print("Failed to acquire valid session token.")
        sys.exit(1)

    print(f"\nAuthenticated as {session['username']}")

    # Step 3: Run game client synchronously
    wine_bin = resolve_wine_binary(client_dir)
    width, height = get_screen_resolution()
    print(f"Using Wine runner: {wine_bin}")
    print(f"Target display resolution: {width}x{height}")

    game_args = [
        wine_bin,
        "explorer",
        f"/desktop=SWG,{width}x{height}",
        "SWGEmu.exe",
        "--",
        "-s", "ClientGame",
        f"loginServerAddress0={SERVER_IP}",
        f"loginServerPort0={SERVER_PORT}",
        f"loginClientID={session['username']}",
        "-s", "Station",
        "subscriptionFeatures=1",
        "gameFeatures=65535",
        f"sessionId={session['sessionId']}",
        "-s", "SwgClient",
        "allowMultipleInstances=true",
        "-s", "ClientGraphics",
        f"screenWidth={width}",
        f"screenHeight={height}",
        "windowed=true",
        "borderlessWindow=true",
    ]

    print("Launching SWG...")
    env = os.environ.copy()
    env["WINEPREFIX"] = prefix
    subprocess.run(game_args, cwd=client_dir, env=env)

if __name__ == "__main__":
    main()
