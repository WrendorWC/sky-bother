#!/usr/bin/env python3
"""Read-only check of a Seestar's live stack, for proving Session View's
Connect to Telescope against real hardware.

Start a session in the Seestar phone app first (Station Mode, same Wi-Fi as
this Mac), let it begin stacking, then run:

    python3 Scripts/seestar_live_check.py            # find the scope, watch 3 minutes
    python3 Scripts/seestar_live_check.py 192.168.1.55 --minutes 10
    python3 Scripts/seestar_live_check.py --preview   # daytime: one camera frame first

It sends only `scan_iscope` (discovery), `test_connection` (keepalive) and
`get_stacked_img` (read the current stack) - the same three things Sky
Bother sends - plus, with --preview, one `get_current_img` (read the
camera's current single frame), which works in daylight in Scenery mode. No GoTo, no capture control, no settings changes. Keep the
phone app open and note whether it is disturbed in any way.

Everything it sees goes to a folder named seestar-check-<time>/: a log of
every frame header with timestamps, and each distinct stack picture (JPEG
stacks as .jpg, raw stacks as .bin plus their header). Standard library
only; nothing to install.
"""

import argparse
import datetime
import json
import os
import socket
import struct
import sys
import threading
import time

DISCOVERY_PORT = 4720
IMAGE_PORT = 4800
MAGIC = b"\x03\xc3"
TYPES = {0: "ack", 1: "preview", 4: "jpeg stack", 5: "raw stack"}


def discover(timeout=3.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.2)
    probe = json.dumps({"id": 1, "method": "scan_iscope", "params": ""}).encode() + b"\n\n"
    found = {}
    deadline = time.monotonic() + timeout
    next_probe = 0.0
    while time.monotonic() < deadline:
        if time.monotonic() >= next_probe:
            try:
                sock.sendto(probe, ("255.255.255.255", DISCOVERY_PORT))
            except OSError as exc:
                print("broadcast failed:", exc)
            next_probe = time.monotonic() + 0.5
        try:
            data, (ip, _) = sock.recvfrom(4096)
        except OSError:
            continue
        try:
            result = json.loads(data.decode("utf-8", "replace")).get("result") or {}
        except ValueError:
            continue
        if result.get("sn"):
            found[ip] = result
    sock.close()
    return found


def recv_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(min(n - len(buf), 1 << 20))
        if not chunk:
            raise ConnectionError(f"closed after {len(buf)}/{n} bytes")
        buf.extend(chunk)
    return bytes(buf)


def read_frame(sock, log):
    while True:
        first = recv_exact(sock, 1)
        if first == b"{":
            line = bytearray(first)
            while not line.endswith(b"\r\n") and len(line) < 4096:
                line.extend(recv_exact(sock, 1))
            log(f"json  {line.decode('utf-8', 'replace').strip()[:160]}")
            continue
        if first == b"\x03" and recv_exact(sock, 1) == b"\xc3":
            break
    rest = recv_exact(sock, 32)
    raw = MAGIC + rest
    header_size = struct.unpack_from(">H", raw, 4)[0]
    if not 34 <= header_size <= 4096:
        header_size = 80
    header = {
        "version": struct.unpack_from(">H", raw, 2)[0],
        "header_size": header_size,
        "length": struct.unpack_from(">I", raw, 6)[0],
        "img_type": raw[13],
        "data_type": raw[14],
        "frame_id": raw[15],
        "width": struct.unpack_from(">H", raw, 16)[0],
        "height": struct.unpack_from(">H", raw, 18)[0],
        "hfd": struct.unpack_from(">H", raw, 24)[0],
        "image_id": struct.unpack_from(">H", raw, 28)[0],
    }
    if header_size > 34:
        recv_exact(sock, header_size - 34)
    payload = recv_exact(sock, header["length"])
    return header, payload


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ip", nargs="?", help="scope address; found automatically if left out")
    parser.add_argument("--minutes", type=float, default=3.0, help="how long to watch (default 3)")
    parser.add_argument("--every", type=float, default=10.0, help="seconds between stack requests (default 10)")
    parser.add_argument("--preview", action="store_true",
                        help="first ask once for the camera's current single frame (works in daylight)")
    args = parser.parse_args()

    out = "seestar-check-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    os.makedirs(out)
    log_file = open(os.path.join(out, "log.txt"), "w")

    def log(message):
        line = f"{datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]}  {message}"
        print(line)
        log_file.write(line + "\n")
        log_file.flush()

    # Sky Bother tries this name first: it needs no incoming-connection
    # permission. Worth knowing whether the scope answers to it.
    try:
        log(f"seestar.local resolves to {socket.gethostbyname('seestar.local')}")
    except OSError as exc:
        log(f"seestar.local does not resolve ({exc})")

    ip = args.ip
    if not ip:
        log("looking for a Seestar (UDP 4720)...")
        found = discover()
        for address, info in found.items():
            # The reply carries the scope's own hotspot password; keep it
            # out of the log.
            shown = {k: ("[redacted]" if "pass" in k.lower() or k.lower() in ("psk", "key") else v)
                     for k, v in info.items()}
            log(f"found {address}: " + json.dumps(shown))
        if not found:
            log("nothing answered. Is the scope in Station Mode on this Wi-Fi? Pass its IP to skip discovery.")
            return 1
        ip = next(iter(found))

    log(f"connecting to {ip}:{IMAGE_PORT}")
    sock = socket.create_connection((ip, IMAGE_PORT), timeout=10)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    # Long enough for a raw stack over weak Wi-Fi; the watch still ends on time.
    sock.settimeout(45)
    lock = threading.Lock()
    stop = threading.Event()

    def send(method):
        with lock:
            sock.sendall((json.dumps({"id": 2, "method": method}) + "\r\n").encode())

    def heartbeat():
        last_request = 0.0
        while not stop.wait(4):
            try:
                if time.monotonic() - last_request >= args.every:
                    send("get_stacked_img")
                    last_request = time.monotonic()
                else:
                    send("test_connection")
            except OSError:
                return

    send("get_current_img" if args.preview else "get_stacked_img")
    threading.Thread(target=heartbeat, daemon=True).start()

    deadline = time.monotonic() + args.minutes * 60
    last_id = None
    saved = 0
    try:
        while time.monotonic() < deadline:
            sock.settimeout(max(1.0, min(45.0, deadline - time.monotonic())))
            try:
                header, payload = read_frame(sock, log)
            except socket.timeout:
                if time.monotonic() >= deadline:
                    break
                log("no data for 45 s")
                continue
            kind = TYPES.get(header["img_type"], f"type {header['img_type']}")
            log(f"frame {kind:10} id={header['image_id']:<5} {header['width']}x{header['height']} "
                f"{header['length']:>10,} bytes  data_type={header['data_type']} hfd={header['hfd']} "
                f"header={header['header_size']}"
                + (f"  payload={payload!r}" if header["length"] <= 64 else ""))
            if header["img_type"] == 1 and header["length"]:
                stem = os.path.join(out, f"preview-{header['width']}x{header['height']}-id{header['image_id']}")
                open(stem + ".bin", "wb").write(payload)
                json.dump(header, open(stem + ".json", "w"))
                log(f"saved camera frame {stem}.bin (raw 16-bit Bayer)")
            if header["img_type"] in (4, 5) and header["image_id"] != last_id:
                last_id = header["image_id"]
                saved += 1
                stem = os.path.join(out, f"{saved:03d}-id{header['image_id']}")
                if payload[:3] == b"\xff\xd8\xff":
                    open(stem + ".jpg", "wb").write(payload)
                else:
                    open(stem + ".bin", "wb").write(payload)
                    json.dump(header, open(stem + ".json", "w"))
    except (ConnectionError, socket.timeout, OSError) as exc:
        log(f"connection ended: {exc}")
    finally:
        stop.set()
        sock.close()
    log(f"done: {saved} distinct stack pictures saved in {out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
