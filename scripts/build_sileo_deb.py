#!/usr/bin/env python3
"""
Build a rootless Sileo/Dopamine-compatible .deb for iPFaker.

Includes (when present):
  - iPFakerMG / iPFakerCT dylibs + filter plists  → TweakInject + MobileSubstrate
  - iPFaker.app                                  → /var/jb/Applications/
  - device_catalog.json + seed README            → /var/jb/etc/ipfaker/

Output:
  dist/sileo/com.ipfaker_<ver>_iphoneos-arm64.deb
  dist/sileo/repo/  (Packages + Release for Sileo source)

Usage:
  python scripts/build_sileo_deb.py
  python scripts/build_sileo_deb.py --app path/to/iPFaker.app
  python scripts/build_sileo_deb.py --version 2.3.0
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import lzma
import os
import shutil
import stat
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_DEFAULT = "2.7.0"
PKG = "com.ipfaker"
ARCH = "iphoneos-arm64"


def find_dylibs() -> tuple[Path | None, Path | None]:
    for base in (ROOT / "dylibs_ci", ROOT / "dylibs", ROOT / "theos" / "dist"):
        mg = base / "iPFakerMG.dylib"
        ct = base / "iPFakerCT.dylib"
        if mg.exists() and ct.exists():
            return mg, ct
    # arm64e named
    for base in (ROOT / "dylibs", ROOT / "dylibs_ci"):
        mg = base / "iPFakerMG.arm64e.dylib"
        ct = base / "iPFakerCT.arm64e.dylib"
        if mg.exists() and ct.exists():
            return mg, ct
    return None, None


def find_app(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(explicit)
        return p if p.is_dir() else None
    for p in [
        ROOT / "theos" / "dist" / "app" / "iPFaker.app",
        ROOT / "theos" / "app" / ".theos" / "obj" / "debug" / "iPFaker.app",
        ROOT / "theos" / "app" / ".theos" / "obj" / "iPFaker.app",
    ]:
        if p.is_dir() and (p / "iPFaker").exists():
            return p
    for p in (ROOT / "theos").rglob("iPFaker.app"):
        if p.is_dir() and (p / "iPFaker").exists() and "Applications" not in str(p):
            return p
    return None


def zalo_only_plist() -> bytes:
    return b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array>
			<string>vn.com.vng.zingalo</string>
			<string>com.zing.zalo</string>
		</array>
		<key>Mode</key>
		<string>Any</string>
	</dict>
</dict>
</plist>
"""


def preinst_script() -> str:
    return r"""#!/bin/sh
# Ensure extract destinations exist (rootless Dopamine)
ROOT="${JBROOT:-/var/jb}"
mkdir -p "$ROOT/usr/lib/TweakInject" 2>/dev/null || true
mkdir -p "$ROOT/Library/MobileSubstrate/DynamicLibraries" 2>/dev/null || true
mkdir -p "$ROOT/etc/ipfaker" 2>/dev/null || true
mkdir -p "$ROOT/Applications" 2>/dev/null || true
mkdir -p /var/jb/usr/lib/TweakInject 2>/dev/null || true
mkdir -p /var/jb/Library/MobileSubstrate/DynamicLibraries 2>/dev/null || true
mkdir -p /var/jb/etc/ipfaker 2>/dev/null || true
mkdir -p /var/jb/Applications 2>/dev/null || true
mkdir -p /var/mobile/Library/iPFaker 2>/dev/null || true
exit 0
"""


def postinst_script() -> str:
    return r"""#!/bin/sh
set -e
ROOT="${JBROOT:-/var/jb}"

# --- dirs (mobile MUST write jb config — Zalo only reads /var/jb/etc/ipfaker) ---
mkdir -p "$ROOT/etc/ipfaker" 2>/dev/null || true
mkdir -p /var/jb/etc/ipfaker 2>/dev/null || true
mkdir -p /var/mobile/Library/iPFaker 2>/dev/null || true
chown -R mobile:mobile /var/mobile/Library/iPFaker 2>/dev/null || true
chown -R mobile:mobile "$ROOT/etc/ipfaker" 2>/dev/null || true
chown -R mobile:mobile /var/jb/etc/ipfaker 2>/dev/null || true
chmod 775 /var/mobile/Library/iPFaker "$ROOT/etc/ipfaker" /var/jb/etc/ipfaker 2>/dev/null || true
# If config.plist was root-owned from older package, reclaim for app Apply
for f in "$ROOT/etc/ipfaker/config.plist" /var/jb/etc/ipfaker/config.plist \
         "$ROOT/etc/ipfaker/active_profile.json" /var/jb/etc/ipfaker/active_profile.json; do
  if [ -f "$f" ]; then
    chown mobile:mobile "$f" 2>/dev/null || true
    chmod 644 "$f" 2>/dev/null || true
  fi
done
# Wipe helper executable
for w in /var/jb/usr/libexec/ipfaker-wipe-zalo /var/jb/etc/ipfaker/wipe_zalo.sh \
         /var/mobile/Library/iPFaker/wipe_zalo.sh; do
  if [ -f "$w" ]; then
    chmod 755 "$w" 2>/dev/null || true
    chown root:wheel "$w" 2>/dev/null || true
  fi
done

# --- dylib locations (ElleKit / Dopamine) ---
for MS in \
  "$ROOT/usr/lib/TweakInject" \
  "$ROOT/Library/MobileSubstrate/DynamicLibraries" \
  /var/jb/usr/lib/TweakInject \
  /var/jb/Library/MobileSubstrate/DynamicLibraries
do
  [ -d "$MS" ] || continue
  for f in iPFakerMG.dylib iPFakerCT.dylib iPFakerJB.dylib; do
    if [ -f "$MS/$f" ]; then
      chown root:wheel "$MS/$f" 2>/dev/null || true
      chmod 755 "$MS/$f" 2>/dev/null || true
      if command -v ldid >/dev/null 2>&1; then
        ldid -S "$MS/$f" 2>/dev/null || true
      fi
      if [ -x /var/jb/basebin/jbctl ] && command -v ldid >/dev/null 2>&1; then
        H=$(ldid -h "$MS/$f" 2>/dev/null | sed -n 's/.*CDHash=//p' | head -1 | tr 'A-F' 'a-f' | cut -c1-40)
        if [ ${#H} -eq 40 ]; then
          /var/jb/basebin/jbctl trustcache add "$H" 2>/dev/null || true
        fi
      fi
    fi
  done
  for f in iPFakerMG.plist iPFakerCT.plist iPFakerJB.plist; do
    [ -f "$MS/$f" ] && chmod 644 "$MS/$f" 2>/dev/null || true
  done
done

# --- app ---
APP=""
for d in "$ROOT/Applications/iPFaker.app" /var/jb/Applications/iPFaker.app; do
  if [ -d "$d" ]; then APP="$d"; break; fi
done
if [ -n "$APP" ]; then
  chown -R root:wheel "$APP" 2>/dev/null || true
  [ -f "$APP/iPFaker" ] && chmod 755 "$APP/iPFaker" 2>/dev/null || true
  if [ -f "$APP/iPFaker" ] && command -v ldid >/dev/null 2>&1; then
    ldid -S "$APP/iPFaker" 2>/dev/null || true
    if [ -x /var/jb/basebin/jbctl ]; then
      H=$(ldid -h "$APP/iPFaker" 2>/dev/null | sed -n 's/.*CDHash=//p' | head -1 | tr 'A-F' 'a-f' | cut -c1-40)
      if [ ${#H} -eq 40 ]; then
        /var/jb/basebin/jbctl trustcache add "$H" 2>/dev/null || true
      fi
    fi
  fi
  if [ -f "$APP/device_catalog.json" ]; then
    cp -f "$APP/device_catalog.json" "$ROOT/etc/ipfaker/device_catalog.json" 2>/dev/null || true
    cp -f "$APP/device_catalog.json" /var/mobile/Library/iPFaker/device_catalog.json 2>/dev/null || true
    chown mobile:mobile /var/mobile/Library/iPFaker/device_catalog.json 2>/dev/null || true
  fi
  if [ -x /var/jb/usr/bin/uicache ]; then
    /var/jb/usr/bin/uicache -p "$APP" 2>/dev/null || true
  elif command -v uicache >/dev/null 2>&1; then
    uicache -p "$APP" 2>/dev/null || true
  fi
fi

if [ -f "$ROOT/etc/ipfaker/device_catalog.json" ]; then
  cp -f "$ROOT/etc/ipfaker/device_catalog.json" /var/mobile/Library/iPFaker/device_catalog.json 2>/dev/null || true
  chown mobile:mobile /var/mobile/Library/iPFaker/device_catalog.json 2>/dev/null || true
fi

killall -9 Zalo 2>/dev/null || true
exit 0
"""


def prerm_script() -> str:
    return r"""#!/bin/sh
killall -9 Zalo 2>/dev/null || true
killall -9 iPFaker 2>/dev/null || true
exit 0
"""


def control_text(version: str, installed_size_kb: int, has_app: bool, has_dylibs: bool) -> str:
    desc = "Lab device identity tools (MG+CT dylibs)"
    if has_app:
        desc += " + iPFaker.app (device/iOS pool, Reset Data / Save)"
    desc += ". Rootless Dopamine. Synthetic profiles only. Does not inject Settings."
    return f"""Package: {PKG}
Name: iPFaker
Depends: firmware (>= 14.0)
Version: {version}
Architecture: {ARCH}
Maintainer: iPFaker Lab
Author: iPFaker Lab
Section: Tweaks
Priority: optional
Homepage: https://github.com/vpnhihi/ipfaker
Description: {desc}
Installed-Size: {installed_size_kb}
"""


def add_file(tar: tarfile.TarFile, arcname: str, data: bytes, mode: int = 0o644) -> None:
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    info.mtime = int(time.time())
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    tar.addfile(info, io.BytesIO(data))


def add_path(tar: tarfile.TarFile, src: Path, arcname: str, mode: int | None = None) -> None:
    data = src.read_bytes()
    if mode is None:
        mode = 0o755 if src.suffix == ".dylib" or src.name == "iPFaker" else 0o644
    add_file(tar, arcname, data, mode)


def add_dir_parents(tar: tarfile.TarFile, arc_path: str, seen: set[str]) -> None:
    """Ensure every parent directory exists in the tar (dpkg needs them)."""
    parts = arc_path.strip("/").split("/")
    cur = ""
    for p in parts:
        cur = f"{cur}/{p}" if cur else p
        dname = cur.rstrip("/") + "/"
        if dname in seen:
            continue
        seen.add(dname)
        info = tarfile.TarInfo(name=dname)
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        info.mtime = int(time.time())
        info.uid = 0
        info.gid = 0
        tar.addfile(info)


def add_tree(tar: tarfile.TarFile, src_dir: Path, arc_prefix: str) -> None:
    seen: set[str] = set()
    add_dir_parents(tar, arc_prefix, seen)
    for path in sorted(src_dir.rglob("*")):
        rel = path.relative_to(src_dir).as_posix()
        arc = f"{arc_prefix}/{rel}"
        if path.is_dir():
            add_dir_parents(tar, arc, seen)
        elif path.is_file():
            # parent dirs for file
            parent = "/".join(arc.split("/")[:-1])
            if parent:
                add_dir_parents(tar, parent, seen)
            mode = 0o755 if path.name == "iPFaker" or path.suffix == ".dylib" else 0o644
            add_path(tar, path, arc, mode)


def make_tar_gz(members_builder) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        members_builder(tar)
    return buf.getvalue()


def make_tar_lzma(members_builder) -> bytes:
    """data.tar.lzma — same as classic Theos/HIOS debs (max iOS dpkg compatibility)."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        members_builder(tar)
    return lzma.compress(raw.getvalue(), format=lzma.FORMAT_ALONE, preset=6)


def make_ar(members: list[tuple[str, bytes]]) -> bytes:
    """GNU ar for dpkg."""
    out = io.BytesIO()
    out.write(b"!<arch>\n")
    for name, data in members:
        name_b = name.encode("ascii")
        if len(name_b) > 16:
            raise ValueError(f"ar name too long: {name}")
        header = (
            name_b.ljust(16)
            + str(int(time.time())).encode().ljust(12)
            + b"0".ljust(6)
            + b"0".ljust(6)
            + b"100644".ljust(8)
            + str(len(data)).encode().ljust(10)
            + b"`\n"
        )
        out.write(header)
        out.write(data)
        if len(data) % 2 == 1:
            out.write(b"\n")
    return out.getvalue()


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    h.update(path.read_bytes())
    return h.hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def build(version: str, app_path: str | None) -> Path:
    mg, ct = find_dylibs()
    app = find_app(app_path)
    catalog = ROOT / "config" / "device_catalog.json"
    if not catalog.exists():
        catalog = ROOT / "theos" / "app" / "Resources" / "device_catalog.json"

    if not mg or not ct:
        raise SystemExit("Missing iPFakerMG/CT dylibs (dylibs_ci/ or dylibs/)")

    out_dir = ROOT / "dist" / "sileo"
    repo_dir = out_dir / "repo" / "debs"
    out_dir.mkdir(parents=True, exist_ok=True)
    repo_dir.mkdir(parents=True, exist_ok=True)

    # --- data.tar.gz ---
    size_bytes = 0

    def data_builder(tar: tarfile.TarFile) -> None:
        nonlocal size_bytes

        def track(data: bytes) -> bytes:
            nonlocal size_bytes
            size_bytes += len(data)
            return data

        # Full paths under /var/jb (HIOS-style).
        # NOTE: On Dopamine, DynamicLibraries -> symlink to TweakInject.
        # Package ONLY TweakInject to avoid dpkg double-extract failure.
        for d in (
            "var/",
            "var/jb/",
            "var/jb/usr/",
            "var/jb/usr/lib/",
            "var/jb/usr/lib/TweakInject/",
            "var/jb/etc/",
            "var/jb/etc/ipfaker/",
            "var/jb/Applications/",
            "var/mobile/",
            "var/mobile/Library/",
            "var/mobile/Library/iPFaker/",
        ):
            info = tarfile.TarInfo(name=d)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = int(time.time())
            info.uid = 0
            info.gid = 0
            tar.addfile(info)

        plist = zalo_only_plist()
        dest = "var/jb/usr/lib/TweakInject"
        add_file(tar, f"{dest}/iPFakerMG.dylib", track(mg.read_bytes()), 0o755)
        add_file(tar, f"{dest}/iPFakerCT.dylib", track(ct.read_bytes()), 0o755)
        add_file(tar, f"{dest}/iPFakerMG.plist", track(plist), 0o644)
        add_file(tar, f"{dest}/iPFakerCT.plist", track(plist), 0o644)
        # Optional split-stack JB hide (fopen/getenv/fileExists)
        for base in (mg.parent, ROOT / "dylibs_ci", ROOT / "theos" / "dist"):
            jb = base / "iPFakerJB.dylib"
            if jb.is_file():
                add_file(tar, f"{dest}/iPFakerJB.dylib", track(jb.read_bytes()), 0o755)
                add_file(tar, f"{dest}/iPFakerJB.plist", track(plist), 0o644)
                break

        if catalog.exists():
            cdata = track(catalog.read_bytes())
            add_file(tar, "var/jb/etc/ipfaker/device_catalog.json", cdata, 0o644)
            add_file(tar, "var/mobile/Library/iPFaker/device_catalog.json", cdata, 0o644)

        readme = b"iPFaker lab config dir. Apply profile from iPFaker.app or PC scripts.\n"
        add_file(tar, "var/jb/etc/ipfaker/README.txt", track(readme), 0o644)

        # Full wipe helper used by app Kill Zalo
        wipe_src = ROOT / "injector" / "wipe_zalo.sh"
        if wipe_src.is_file():
            wdata = track(wipe_src.read_bytes())
            add_file(tar, "var/jb/usr/libexec/ipfaker-wipe-zalo", wdata, 0o755)
            add_file(tar, "var/jb/etc/ipfaker/wipe_zalo.sh", wdata, 0o755)
            add_file(tar, "var/mobile/Library/iPFaker/wipe_zalo.sh", wdata, 0o755)

        if app:
            add_tree(tar, app, "var/jb/Applications/iPFaker.app")
            for f in app.rglob("*"):
                if f.is_file():
                    size_bytes += f.stat().st_size

    data_lzma = make_tar_lzma(data_builder)
    installed_kb = max(1, size_bytes // 1024)

    # --- control.tar.gz (Unix LF only — CRLF breaks iOS dpkg/apt) ---
    ctrl = control_text(version, installed_kb, has_app=bool(app), has_dylibs=True).replace("\r\n", "\n")
    postinst = postinst_script().replace("\r\n", "\n")
    prerm = prerm_script().replace("\r\n", "\n")
    preinst = preinst_script().replace("\r\n", "\n")

    def control_builder(tar: tarfile.TarFile) -> None:
        add_file(tar, "./control", ctrl.encode("utf-8"), 0o644)
        add_file(tar, "./preinst", preinst.encode("utf-8"), 0o755)
        add_file(tar, "./postinst", postinst.encode("utf-8"), 0o755)
        add_file(tar, "./prerm", prerm.encode("utf-8"), 0o755)

    control_gz = make_tar_gz(control_builder)

    deb_name = f"{PKG}_{version}_{ARCH}.deb"
    # Match classic Theos layout: debian-binary + control.tar.gz + data.tar.lzma
    deb_bytes = make_ar(
        [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", control_gz),
            ("data.tar.lzma", data_lzma),
        ]
    )

    deb_path = out_dir / deb_name
    deb_path.write_bytes(deb_bytes)
    # copy into repo
    shutil.copy2(deb_path, repo_dir / deb_name)

    # Packages file (Sileo/Cydia)
    md5 = md5_file(deb_path)
    sha256 = sha256_file(deb_path)
    packages = (
        ctrl.rstrip()
        + f"\nFilename: debs/{deb_name}\n"
        + f"Size: {deb_path.stat().st_size}\n"
        + f"MD5sum: {md5}\n"
        + f"SHA256: {sha256}\n"
        + "\n"
    )
    # Apt on iOS requires Unix LF only (CRLF breaks package index parsing)
    packages_lf = packages.replace("\r\n", "\n").replace("\r", "\n")
    packages_path = out_dir / "repo" / "Packages"
    packages_path.write_bytes(packages_lf.encode("utf-8"))
    with gzip.open(str(out_dir / "repo" / "Packages.gz"), "wb") as gz:
        gz.write(packages_lf.encode("utf-8"))

    release = f"""Origin: iPFaker Lab
Label: iPFaker
Suite: stable
Version: 1.0
Codename: ipfaker
Architectures: {ARCH}
Components: main
Description: iPFaker lab packages for Dopamine rootless / Sileo
"""
    release_lf = release.replace("\r\n", "\n").replace("\r", "\n")
    if not release_lf.endswith("\n"):
        release_lf += "\n"
    (out_dir / "repo" / "Release").write_bytes(release_lf.encode("utf-8"))

    install = f"""iPFaker Sileo package
=====================
File: {deb_name}
Size: {deb_path.stat().st_size} bytes
App included: {bool(app)}
Dylibs: {mg.parent}

Install on device (pick one):
1) Sileo → Packages → Install from file → select this .deb
2) Filza → open .deb → Install
3) SSH: dpkg -i {deb_name}

Sileo source:
  https://vpnhihi.github.io/ipfaker/

After install:
  Open iPFaker app (if included) → pick model → Apply → Kill Zalo → open Zalo
"""
    (out_dir / "INSTALL.txt").write_bytes(install.replace("\r\n", "\n").encode("utf-8"))

    print("Built:", deb_path)
    print("Size :", deb_path.stat().st_size)
    print("App  :", app or "(not found — dylibs+catalog only)")
    print("Repo :", out_dir / "repo")
    return deb_path


def main() -> int:
    ap = argparse.ArgumentParser(description="Build iPFaker Sileo .deb")
    ap.add_argument("--version", default=VERSION_DEFAULT)
    ap.add_argument("--app", default=None, help="Path to iPFaker.app")
    args = ap.parse_args()
    build(args.version, args.app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
