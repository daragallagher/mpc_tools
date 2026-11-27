#!/usr/bin/env python3
"""Sign an MPC device script: add the checksum the MPC needs before it will load the script.

The MPC loads a device script only if its .ini carries
    checksum = sha256(<lua bytes> + <36-byte seed>)
where the seed is baked, obfuscated, into the MPC program. This reads the seed from a stock
MPC OS 3.10.1 Gen2 firmware image (--img) and writes a signed .ini for each device folder. The
seed is never written to disk.

A device folder holds:
  - device.ini : the .ini template, with every field except checksum= (comment and blank lines
                 are dropped from the output).
  - <script>.lua : the script that device.ini's script= names.
For each folder this writes <script>.ini (the template plus checksum=) beside the .lua. Copy
that <script>.ini and <script>.lua into <MPC Documents>/Devices/<any folder>/ on the MPC.

Usage:
    python3 sign_scripts.py --img MPC-3.10.1-Gen2-update.img my-device/

--img needs 7zz (7-Zip) to read the image's root filesystem.
"""
from __future__ import annotations

import argparse
import hashlib
import lzma
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SEED_LENGTH = 36
SEED_SHA256 = "fc239913b495136422dbbed00f6350f64d65e7e0cd32dbb8e1253164b6131ed3"
# Where the seed sits in the MPC OS 3.10.1 Gen2 /usr/bin/MPC (sha256 bd55df49…0bc61aa): offset
# and the repeating 8-byte XOR key it is obfuscated with. These differ between firmware builds.
SEED_LOCATION = (0x5483400, bytes.fromhex("45313dd9270dbfe7"))

XZ_MAGIC = b"\xfd7zXZ\x00"
REQUIRED_FIELDS = ("device", "manufacturer", "input", "output", "script", "scriptVersion")


def decompress_xz(data: memoryview, start: int, out: Path) -> bool:
    """Decompress the xz stream at data[start:] into out. False if it isn't a complete stream."""
    decoder = lzma.LZMADecompressor(lzma.FORMAT_XZ)
    pos, chunk = start, 1 << 24
    try:
        with out.open("wb") as f:
            while not decoder.eof and pos < len(data):
                f.write(decoder.decompress(data[pos:pos + chunk]))
                pos += chunk
    except lzma.LZMAError:
        return False
    return decoder.eof


def extract_mpc_binary(img: Path) -> bytes:
    """usr/bin/MPC from a stock MPC OS Gen2 firmware image.

    The image is an "AZ0x" container of xz-compressed partitions, one of which is the ext4 root
    filesystem. Each xz stream is decompressed to a temporary file in turn, until 7zz finds
    usr/bin/MPC in one. Nothing is kept on disk.
    """
    if shutil.which("7zz") is None:
        sys.exit("--img needs 7zz (7-Zip)")
    data = memoryview(img.read_bytes())
    with tempfile.TemporaryDirectory() as tmp:
        part = Path(tmp) / "partition"
        start = data.obj.find(XZ_MAGIC)
        while start != -1:
            if decompress_xz(data, start, part):
                got = subprocess.run(["7zz", "e", "-so", str(part), "usr/bin/MPC"], capture_output=True)
                if got.returncode == 0 and got.stdout:
                    return got.stdout
            start = data.obj.find(XZ_MAGIC, start + 1)
    sys.exit(f"{img}: usr/bin/MPC not found in any partition")


def read_seed(img: Path) -> bytes:
    """The 36-byte checksum seed, decoded from the MPC binary in a firmware image."""
    binary = extract_mpc_binary(img)
    offset, key = SEED_LOCATION
    decoded = bytes(b ^ key[i % 8] for i, b in enumerate(binary[offset:offset + SEED_LENGTH + 1]))
    seed = decoded[:-1]
    if decoded[-1:] != b"\0" or hashlib.sha256(seed).hexdigest() != SEED_SHA256:
        sys.exit(f"{img}: couldn't read the checksum seed. Is this the MPC OS 3.10.1 Gen2 image?")
    return seed


def read_template(device_dir: Path) -> tuple[list[tuple[str, str]], str]:
    """Return the template's fields in order, and the device name. Exit on anything malformed."""
    path = device_dir / "device.ini"
    if not path.is_file():
        sys.exit(f"{path}: missing")
    fields: list[tuple[str, str]] = []
    section_seen = False
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line == "[info]":
            section_seen = True
            continue
        if not section_seen or "=" not in line:
            sys.exit(f"{path}:{n}: expected key=value after [info]: {raw!r}")
        key, value = (s.strip() for s in line.split("=", 1))
        if key == "checksum":
            sys.exit(f"{path}:{n}: remove checksum=; signing adds it")
        fields.append((key, value))
    keys = [k for k, _ in fields]
    missing = [k for k in REQUIRED_FIELDS if k not in keys]
    if missing:
        sys.exit(f"{path}: missing field(s) {', '.join(missing)}")
    for single in ("device", "manufacturer", "script", "scriptVersion"):
        if keys.count(single) != 1:
            sys.exit(f"{path}: {single}= must appear exactly once")
    return fields, dict(fields)["device"]


def sign_device(device_dir: Path, seed: bytes) -> None:
    fields, device = read_template(device_dir)
    script = dict(fields)["script"]
    if "/" in script or not script.endswith(".lua"):
        sys.exit(f"{device_dir}/device.ini: script= must be a .lua file name in the same folder")
    lua_path = device_dir / script
    if not lua_path.is_file():
        sys.exit(f"{lua_path}: missing (named by script=)")
    lua = lua_path.read_bytes()
    checksum = hashlib.sha256(lua + seed).hexdigest()
    ini_name = script[: -len(".lua")] + ".ini"
    ini = ("[info]\n" + "".join(f"{k}={v}\n" for k, v in fields) + f"checksum={checksum}\n").encode()
    out = device_dir / ini_name
    out.write_bytes(ini)
    print(f"{device}: checksum {checksum}")
    print(f"{device}: wrote    {out}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Sign MPC device scripts (write <script>.ini with its checksum).")
    ap.add_argument("devices", nargs="+", type=Path, help="device folder(s), each with device.ini + <script>.lua")
    ap.add_argument("--img", required=True, type=Path, help="stock MPC OS 3.10.1 Gen2 firmware image")
    args = ap.parse_args()
    for device_dir in args.devices:
        if not device_dir.is_dir():
            sys.exit(f"{device_dir}: not a device folder")

    seed = read_seed(args.img)
    for device_dir in args.devices:
        sign_device(device_dir, seed)


if __name__ == "__main__":
    main()
