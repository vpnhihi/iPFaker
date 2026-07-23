#!/usr/bin/env python3
"""Assert packaged deb contains HIOS ChangeInfo dylibs 1:1, not iPFakerMG."""
from __future__ import annotations

import io
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
debs = list((ROOT / "dist" / "sileo").glob("com.ipfaker_*.deb"))
if not debs:
    debs = list((ROOT / "dist" / "sileo" / "repo" / "debs").glob("com.ipfaker_*.deb"))
if not debs:
    print("FATAL: no com.ipfaker deb", file=sys.stderr)
    sys.exit(1)
deb = max(debs, key=lambda p: p.stat().st_mtime)
print("check", deb, deb.stat().st_size)
raw = deb.read_bytes()
off = 8
while off + 60 <= len(raw):
    hdr = raw[off : off + 60]
    name = hdr[0:16].decode("ascii", "replace").strip().rstrip("/")
    size = int(hdr[48:58].decode().strip() or "0")
    off += 60
    body = raw[off : off + size]
    off += size + (size % 2)
    if "data.tar" not in name:
        continue
    bio = io.BytesIO(body)
    try:
        tf = tarfile.open(fileobj=bio, mode="r:xz")
    except Exception:
        bio.seek(0)
        tf = tarfile.open(fileobj=bio, mode="r:*")
    names = [m.name for m in tf.getmembers() if m.name.endswith(".dylib")]
    print("DYLIBS:", names)
    if not any("ChangeInfoIosMG" in n for n in names):
        print("FATAL: missing ChangeInfoIosMG", names, file=sys.stderr)
        sys.exit(2)
    if not any("ChangeInfoIosCT" in n for n in names):
        print("FATAL: missing ChangeInfoIosCT", names, file=sys.stderr)
        sys.exit(3)
    if any("iPFakerMG" in n for n in names):
        print("FATAL: still shipping iPFakerMG (must be HIOS only)", names, file=sys.stderr)
        sys.exit(4)
    # Size check vs vendor
    vendor_mg = ROOT / "vendor" / "hios_426" / "dylibs" / "ChangeInfoIosMG.dylib"
    if vendor_mg.is_file():
        for m in tf.getmembers():
            if m.name.endswith("ChangeInfoIosMG.dylib"):
                if m.size != vendor_mg.stat().st_size:
                    print(
                        f"FATAL: MG size {m.size} != vendor {vendor_mg.stat().st_size}",
                        file=sys.stderr,
                    )
                    sys.exit(5)
    print("OK HIOS 4.2.6 binary 1:1 in deb")
    sys.exit(0)
print("FATAL: no data.tar in deb", file=sys.stderr)
sys.exit(6)
