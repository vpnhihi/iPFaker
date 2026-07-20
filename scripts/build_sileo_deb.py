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
import os
import shutil
import stat
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_DEFAULT = "2.3.0"
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


def postinst_script() -> str:
    return r"""#!/bin/sh
set -e
ROOT="${JBROOT:-/var/jb}"

# --- dirs ---
mkdir -p "$ROOT/etc/ipfaker" 2>/dev/null || true
mkdir -p /var/mobile/Library/iPFaker 2>/dev/null || true
chown mobile:mobile /var/mobile/Library/iPFaker 2>/dev/null || true
chmod 755 /var/mobile/Library/iPFaker "$ROOT/etc/ipfaker" 2>/dev/null || true

# --- dylib locations (ElleKit / Dopamine) ---
for MS in \
  "$ROOT/usr/lib/TweakInject" \
  "$ROOT/Library/MobileSubstrate/DynamicLibraries" \
  /var/jb/usr/lib/TweakInject \
  /var/jb/Library/MobileSubstrate/DynamicLibraries
do
  [ -d "$MS" ] || continue
  for f in iPFakerMG.dylib iPFakerCT.dylib; do
    if [ -f "$MS/$f" ]; then
      chown root:wheel "$MS/$f" 2>/dev/null || true
      chmod 755 "$MS/$f" 2>/dev/null || true
      # trustcache (Dopamine)
      if [ -x /var/jb/basebin/jbctl ] && command -v ldid >/dev/null 2>&1; then
        H=$(ldid -h "$MS/$f" 2>/dev/null | sed -n 's/.*CDHash=//p' | head -1 | tr 'A-F' 'a-f' | cut -c1-40)
        if [ ${#H} -eq 40 ]; then
          /var/jb/basebin/jbctl trustcache add "$H" 2>/dev/null || true
        fi
      fi
    fi
  done
  for f in iPFakerMG.plist iPFakerCT.plist; do
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
  if [ -f "$APP/iPFaker" ] && [ -x /var/jb/basebin/jbctl ] && command -v ldid >/dev/null 2>&1; then
    H=$(ldid -h "$APP/iPFaker" 2>/dev/null | sed -n 's/.*CDHash=//p' | head -1 | tr 'A-F' 'a-f' | cut -c1-40)
    if [ ${#H} -eq 40 ]; then
      /var/jb/basebin/jbctl trustcache add "$H" 2>/dev/null || true
    fi
  fi
  # catalog into config dirs
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

# seed catalog from etc if app missing
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
    desc = "Lab device spoof for Zalo (MG+CT dylibs)"
    if has_app:
        desc += " + iPFaker.app (pick model/iOS, Apply profile)"
    desc += ". Rootless Dopamine. Synthetic profiles only. Does not inject Settings."
    return f"""Package: {PKG}
Name: iPFaker
Depends: firmware (>= 14.0), ellekit | mobilesubstrate | com.ex.substitute
Conflicts: com.ipfaker.tweak
Replaces: com.ipfaker.tweak
Provides: com.ipfaker.tweak
Version: {version}
Architecture: {ARCH}
Maintainer: iPFaker Lab <lab@local>
Author: iPFaker Lab
Section: Tweaks
Priority: optional
Homepage: https://github.com/vpnhihi/iPFaker
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


def add_tree(tar: tarfile.TarFile, src_dir: Path, arc_prefix: str) -> None:
    for path in sorted(src_dir.rglob("*")):
        rel = path.relative_to(src_dir).as_posix()
        arc = f"{arc_prefix}/{rel}"
        if path.is_dir():
            info = tarfile.TarInfo(name=arc.rstrip("/") + "/")
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = int(time.time())
            info.uid = 0
            info.gid = 0
            tar.addfile(info)
        elif path.is_file():
            mode = 0o755 if path.name == "iPFaker" or path.suffix == ".dylib" else 0o644
            add_path(tar, path, arc, mode)


def make_tar_gz(members_builder) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        members_builder(tar)
    return buf.getvalue()


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

        # dirs as empty entries (optional)
        for d in (
            "var/jb/usr/lib/TweakInject/",
            "var/jb/Library/MobileSubstrate/DynamicLibraries/",
            "var/jb/etc/ipfaker/",
            "var/jb/Applications/",
            "var/mobile/Library/iPFaker/",
        ):
            info = tarfile.TarInfo(name=d)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = int(time.time())
            tar.addfile(info)

        plist = zalo_only_plist()
        for dest_root in (
            "var/jb/usr/lib/TweakInject",
            "var/jb/Library/MobileSubstrate/DynamicLibraries",
        ):
            add_file(tar, f"{dest_root}/iPFakerMG.dylib", track(mg.read_bytes()), 0o755)
            add_file(tar, f"{dest_root}/iPFakerCT.dylib", track(ct.read_bytes()), 0o755)
            add_file(tar, f"{dest_root}/iPFakerMG.plist", track(plist), 0o644)
            add_file(tar, f"{dest_root}/iPFakerCT.plist", track(plist), 0o644)

        if catalog.exists():
            cdata = track(catalog.read_bytes())
            add_file(tar, "var/jb/etc/ipfaker/device_catalog.json", cdata, 0o644)
            add_file(tar, "var/mobile/Library/iPFaker/device_catalog.json", cdata, 0o644)

        readme = b"iPFaker lab config dir. Apply profile from iPFaker.app or PC scripts.\n"
        add_file(tar, "var/jb/etc/ipfaker/README.txt", track(readme), 0o644)

        if app:
            add_tree(tar, app, "var/jb/Applications/iPFaker.app")
            # recount size roughly
            for f in app.rglob("*"):
                if f.is_file():
                    size_bytes += f.stat().st_size

    data_gz = make_tar_gz(data_builder)
    installed_kb = max(1, size_bytes // 1024)

    # --- control.tar.gz ---
    ctrl = control_text(version, installed_kb, has_app=bool(app), has_dylibs=True)
    postinst = postinst_script()
    prerm = prerm_script()

    def control_builder(tar: tarfile.TarFile) -> None:
        add_file(tar, "./control", ctrl.encode(), 0o644)
        add_file(tar, "./postinst", postinst.encode(), 0o755)
        add_file(tar, "./prerm", prerm.encode(), 0o755)

    control_gz = make_tar_gz(control_builder)

    deb_name = f"{PKG}_{version}_{ARCH}.deb"
    deb_bytes = make_ar(
        [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", control_gz),
            ("data.tar.gz", data_gz),
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
    packages_path = out_dir / "repo" / "Packages"
    packages_path.write_text(packages, encoding="utf-8")
    with gzip.open(str(out_dir / "repo" / "Packages.gz"), "wb") as gz:
        gz.write(packages.encode())

    release = f"""Origin: iPFaker Lab
Label: iPFaker
Suite: stable
Version: 1.0
Codename: ipfaker
Architectures: {ARCH}
Components: main
Description: iPFaker lab packages for Dopamine rootless / Sileo
"""
    (out_dir / "repo" / "Release").write_text(release, encoding="utf-8")

    # human readme
    (out_dir / "INSTALL.txt").write_text(
        f"""iPFaker Sileo package
=====================
File: {deb_name}
Size: {deb_path.stat().st_size} bytes
App included: {bool(app)}
Dylibs: {mg.parent}

Install on device (pick one):
1) Sileo → Packages → Install from file → select this .deb
2) Filza → open .deb → Install
3) SSH: dpkg -i {deb_name}

Sileo repo (local/GitHub Pages):
  Point Sileo to a host serving dist/sileo/repo/
  (Packages, Packages.gz, Release, debs/)

After install:
  Open iPFaker app (if included) → pick model → Apply → Kill Zalo → open Zalo
""",
        encoding="utf-8",
    )

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
