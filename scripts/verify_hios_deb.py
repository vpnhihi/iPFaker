#!/usr/bin/env python3
"""
Assert packaged iPFaker deb embeds FULL HIOS ChangeInfo 4.2.6 payload 1:1.

Checks:
  - ChangeInfoIosMG + CT dylibs present (no iPFakerMG inject)
  - dual path: TweakInject + MobileSubstrate
  - dylib/plist/cdhashes SHA256 match vendor/hios_426
  - HIOSFakerV3.app present with matching binary hash
"""
from __future__ import annotations

import hashlib
import io
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor" / "hios_426"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256(path.read_bytes())


def extract_data_members(deb: Path) -> dict[str, bytes]:
    raw = deb.read_bytes()
    off = 8
    out: dict[str, bytes] = {}
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
            tf = tarfile.open(fileobj=bio, mode="r:*")
        except Exception as e:
            print(f"FATAL: open data.tar failed: {e}", file=sys.stderr)
            sys.exit(1)
        for m in tf.getmembers():
            if not m.isfile():
                continue
            f = tf.extractfile(m)
            if f is None:
                continue
            # normalize arc name
            n = m.name.lstrip("./")
            out[n] = f.read()
        return out
    print("FATAL: no data.tar in deb", file=sys.stderr)
    sys.exit(6)


def main() -> int:
    debs = list((ROOT / "dist" / "sileo").glob("com.ipfaker_*.deb"))
    if not debs:
        debs = list((ROOT / "dist" / "sileo" / "repo" / "debs").glob("com.ipfaker_*.deb"))
    if not debs:
        print("FATAL: no com.ipfaker deb", file=sys.stderr)
        return 1
    deb = max(debs, key=lambda p: p.stat().st_mtime)
    print("check", deb, deb.stat().st_size)

    files = extract_data_members(deb)
    dylibs = [n for n in files if n.endswith(".dylib")]
    print("DYLIBS:", dylibs)

    if any(n.endswith("iPFakerMG.dylib") for n in dylibs):
        print("FATAL: still shipping iPFakerMG (must be HIOS only)", dylibs, file=sys.stderr)
        return 4
    abouts = [n for n in dylibs if "iPFakerAbout" in n]
    if not abouts:
        print("WARN: no iPFakerAbout* dylibs (Settings Giới thiệu may be missing)")
    else:
        print("About stack:", abouts)

    required_suffixes = [
        "ChangeInfoIosMG.dylib",
        "ChangeInfoIosCT.dylib",
        "ChangeInfoIosMG.plist",
        "ChangeInfoIosCT.plist",
    ]
    paths_needed = [
        "var/jb/usr/lib/TweakInject",
        "var/jb/Library/MobileSubstrate/DynamicLibraries",
    ]

    errors: list[str] = []
    for base in paths_needed:
        for suf in required_suffixes:
            key = f"{base}/{suf}"
            if key not in files:
                errors.append(f"missing {key}")

    # vendor byte match (MG may be lab-patched; CT/plists pure)
    vendor_pairs = [
        ("ChangeInfoIosMG.dylib", VENDOR / "dylibs" / "ChangeInfoIosMG.dylib"),
        ("ChangeInfoIosCT.dylib", VENDOR / "dylibs" / "ChangeInfoIosCT.dylib"),
        ("ChangeInfoIosMG.plist", VENDOR / "dylibs" / "ChangeInfoIosMG.plist"),
        ("ChangeInfoIosCT.plist", VENDOR / "dylibs" / "ChangeInfoIosCT.plist"),
    ]
    pure_mg = VENDOR / "dylibs" / "ChangeInfoIosMG.dylib.orig"
    if pure_mg.is_file() and (VENDOR / "dylibs" / "ChangeInfoIosMG.dylib").is_file():
        if sha256_file(pure_mg) != sha256_file(VENDOR / "dylibs" / "ChangeInfoIosMG.dylib"):
            print("OK MG lab-patched (differs from .orig pure HIOS)")
        else:
            print("WARN MG equals pure HIOS — license gate may still inert")
    for suf, vpath in vendor_pairs:
        if not vpath.is_file():
            errors.append(f"vendor missing {vpath}")
            continue
        vh = sha256_file(vpath)
        for base in paths_needed:
            key = f"{base}/{suf}"
            if key not in files:
                continue
            dh = sha256(files[key])
            if dh != vh:
                errors.append(f"HASH MISMATCH {key}: deb={dh[:16]} vendor={vh[:16]}")
            else:
                print(f"OK vendor-match {key} ({len(files[key])} bytes)")

    # cdhashes
    cd_key = "var/jb/etc/changeinfoios/cdhashes"
    cd_vendor = VENDOR / "etc" / "cdhashes"
    if cd_key not in files:
        errors.append(f"missing {cd_key}")
    elif cd_vendor.is_file():
        if sha256(files[cd_key]) != sha256_file(cd_vendor):
            errors.append("cdhashes hash mismatch")
        else:
            print(f"OK 1:1 {cd_key}")

    # HIOS app
    app_bin = "var/jb/Applications/HIOSFakerV3.app/HIOSFakerV3"
    vendor_bin = VENDOR / "app" / "HIOSFakerV3.app" / "HIOSFakerV3"
    if app_bin not in files:
        errors.append(f"missing {app_bin}")
    elif vendor_bin.is_file():
        if sha256(files[app_bin]) != sha256_file(vendor_bin):
            errors.append("HIOSFakerV3 binary hash mismatch")
        else:
            print(f"OK 1:1 {app_bin} ({len(files[app_bin])} bytes)")
        # all app files
        app_prefix = "var/jb/Applications/HIOSFakerV3.app/"
        app_files = [k for k in files if k.startswith(app_prefix)]
        print(f"HIOSFakerV3.app files in deb: {len(app_files)}")
        for p in sorted(vendor_bin.parent.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(vendor_bin.parent).as_posix()
            key = app_prefix + rel
            if key not in files:
                errors.append(f"missing app file {key}")
            elif sha256(files[key]) != sha256_file(p):
                errors.append(f"app file mismatch {key}")

    # iPFaker.app should still be present (lab UI)
    if not any(k.startswith("var/jb/Applications/iPFaker.app/") for k in files):
        print("WARN: iPFaker.app not in package (dylibs+HIOS only build?)")

    if errors:
        for e in errors:
            print("FATAL:", e, file=sys.stderr)
        return 2

    print("OK HIOS 4.2.6 FULL 1:1 embedded in iPFaker deb")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
