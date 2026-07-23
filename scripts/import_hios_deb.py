#!/usr/bin/env python3
"""
Import ChangeInfoIos / HIOS Faker v3 .deb → vendor/hios_426/ (100% payload).

Writes:
  vendor/hios_426/
    SOURCE.txt              provenance + hashes
    MANIFEST.sha256         relative path + sha256
    DEBIAN/control
    DEBIAN/postinst
    dylibs/ChangeInfoIos{MG,CT}.{dylib,plist}   (original bytes from deb)
    etc/cdhashes
    app/HIOSFakerV3.app/…   full app bundle
    root/…                  full data tree under var/jb (mirror)

Usage:
  python scripts/import_hios_deb.py
  python scripts/import_hios_deb.py path/to/ChangeInfoIos-v3_4.2.6_iphoneos-arm64.deb
"""
from __future__ import annotations

import hashlib
import io
import lzma
import shutil
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor" / "hios_426"
DEFAULT_CANDIDATES = [
    Path(r"C:\Users\Pem\Downloads\ChangeInfoIos-v3_4.2.6_iphoneos-arm64.deb"),
    ROOT / "_ref" / "ChangeInfoIos-v3_4.2.6_iphoneos-arm64.deb",
    ROOT / "downloads" / "ChangeInfoIos-v3_4.2.6_iphoneos-arm64.deb",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ar_members(raw: bytes) -> dict[str, bytes]:
    if raw[:8] != b"!<arch>\n":
        raise SystemExit("not a deb/ar archive")
    pos = 8
    out: dict[str, bytes] = {}
    while pos + 60 <= len(raw):
        hdr = raw[pos : pos + 60]
        if hdr.strip(b"\x00") == b"":
            break
        name = hdr[0:16].decode("ascii", "replace").strip().rstrip("/")
        size = int(hdr[48:58].decode("ascii").strip())
        pos += 60
        payload = raw[pos : pos + size]
        pos += size + (size % 2)
        out[name] = payload
    return out


def extract_tar_xz(blob: bytes, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    raw = lzma.decompress(blob)
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tf:
        tf.extractall(dest)


def find_deb(cli: str | None) -> Path:
    if cli:
        p = Path(cli)
        if not p.is_file():
            raise SystemExit(f"deb not found: {p}")
        return p
    for c in DEFAULT_CANDIDATES:
        if c.is_file():
            return c
    raise SystemExit(
        "No HIOS deb found. Pass path:\n"
        "  python scripts/import_hios_deb.py path/to/ChangeInfoIos-v3_*.deb"
    )


def main() -> int:
    deb_path = find_deb(sys.argv[1] if len(sys.argv) > 1 else None)
    print("Import from:", deb_path)
    raw = deb_path.read_bytes()
    deb_hash = sha256_bytes(raw)
    print("DEB SHA256:", deb_hash)
    print("DEB size  :", len(raw))

    members = ar_members(raw)
    for n in ("debian-binary", "control.tar.xz", "data.tar.xz"):
        if n not in members:
            raise SystemExit(f"missing ar member {n}: {list(members)}")

    # wipe vendor (keep folder)
    if VENDOR.exists():
        for child in VENDOR.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
    VENDOR.mkdir(parents=True, exist_ok=True)

    staging = VENDOR / "_staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    (staging / "control").mkdir()
    (staging / "data").mkdir()
    extract_tar_xz(members["control.tar.xz"], staging / "control")
    extract_tar_xz(members["data.tar.xz"], staging / "data")

    # DEBIAN
    deb_dir = VENDOR / "DEBIAN"
    deb_dir.mkdir(parents=True, exist_ok=True)
    for name in ("control", "postinst", "preinst", "prerm", "postrm"):
        src = staging / "control" / name
        if src.is_file():
            shutil.copy2(src, deb_dir / name)

    # full root mirror (var/jb/…)
    root_out = VENDOR / "root"
    if root_out.exists():
        shutil.rmtree(root_out)
    shutil.copytree(staging / "data", root_out)

    # convenience: dylibs/
    dy_out = VENDOR / "dylibs"
    dy_out.mkdir(parents=True, exist_ok=True)
    ms = (
        staging
        / "data"
        / "var"
        / "jb"
        / "Library"
        / "MobileSubstrate"
        / "DynamicLibraries"
    )
    for name in (
        "ChangeInfoIosMG.dylib",
        "ChangeInfoIosMG.plist",
        "ChangeInfoIosCT.dylib",
        "ChangeInfoIosCT.plist",
    ):
        src = ms / name
        if not src.is_file():
            raise SystemExit(f"missing in deb: {name}")
        shutil.copy2(src, dy_out / name)
        print(f"  dylibs/{name}: {src.stat().st_size} sha={sha256_file(src)[:16]}")

    # etc
    etc_out = VENDOR / "etc"
    etc_out.mkdir(parents=True, exist_ok=True)
    cd = staging / "data" / "var" / "jb" / "etc" / "changeinfoios" / "cdhashes"
    if cd.is_file():
        shutil.copy2(cd, etc_out / "cdhashes")
        print(f"  etc/cdhashes: {cd.stat().st_size}")

    # app
    app_src = staging / "data" / "var" / "jb" / "Applications" / "HIOSFakerV3.app"
    app_out = VENDOR / "app" / "HIOSFakerV3.app"
    if app_out.exists():
        shutil.rmtree(app_out.parent)
    if app_src.is_dir():
        shutil.copytree(app_src, app_out)
        n = sum(1 for _ in app_out.rglob("*") if _.is_file())
        print(f"  app/HIOSFakerV3.app: {n} files")

    # also store raw ar members for exact rebuild
    ar_out = VENDOR / "ar"
    ar_out.mkdir(exist_ok=True)
    for n, blob in members.items():
        (ar_out / n).write_bytes(blob)

    # MANIFEST
    lines: list[str] = []
    for p in sorted(VENDOR.rglob("*")):
        if not p.is_file():
            continue
        if p.name in ("MANIFEST.sha256", "SOURCE.txt") or "_staging" in p.parts:
            continue
        rel = p.relative_to(VENDOR).as_posix()
        lines.append(f"{sha256_file(p)}  {rel}")
    (VENDOR / "MANIFEST.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")

    ctrl_txt = (deb_dir / "control").read_text(encoding="utf-8", errors="replace")
    source = f"""HIOS / ChangeInfoIos import — 100% payload
==========================================
Source deb : {deb_path}
DEB size   : {len(raw)}
DEB SHA256 : {deb_hash}
Imported   : full data + control + ar members

Debian control:
{ctrl_txt}

Layout:
  DEBIAN/           control scripts from deb
  dylibs/           ChangeInfoIos MG+CT (original bytes)
  etc/cdhashes      trustcache list
  app/HIOSFakerV3.app/  full UI app from HIOS
  root/             full extracted data tree
  ar/               debian-binary, control.tar.xz, data.tar.xz

Rebuild iPFaker package:
  python scripts/build_sileo_deb.py --version 2.17.0
  python scripts/verify_hios_deb.py
"""
    (VENDOR / "SOURCE.txt").write_text(source, encoding="utf-8")

    # cleanup staging
    shutil.rmtree(staging)

    print("OK →", VENDOR)
    print("Files in MANIFEST:", len(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
