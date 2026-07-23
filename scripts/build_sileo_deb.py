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
VERSION_DEFAULT = "2.10.2"
PKG = "com.ipfaker"
ARCH = "iphoneos-arm64"

# Full lab stack shipped to every Sileo install (same as dev after CI)
STACK_MODULES = (
    "iPFakerMG",
    "iPFakerCT",
    "iPFakerJB",
    "iPFakerAbout",
    "iPFakerAboutID",
    "iPFakerAboutUI",
    "iPFakerAboutVer",
    "iPFakerAA",
)


def _ci_dist_bases() -> list[Path]:
    """Prefer newest CI/lab artifacts, then local build dirs."""
    bases: list[Path] = []
    # Newest first among known lab snapshots
    for name in (
        "_ci_art_mglean",  # newest Zalo-safe MG lean
        "_ci_art_sot",
        "_ci_art_dual",
        "_ci_art_ui",
        "_ci_art_swver2",
        "_ci_art_swver",
        "_ci_art_aboutver_ok",
        "_ci_art_open",
        "_ci_art21011b",
        "_ci_art21011",
        "_ci_art21010",
    ):
        for sub in (
            ROOT / name / "ipfaker-sileo" / "theos" / "dist",
            ROOT / name / "theos" / "dist",
        ):
            if sub.is_dir():
                bases.append(sub)
    for base in (
        ROOT / "theos" / "dist",
        ROOT / "dylibs_ci",
        ROOT / "dylibs",
    ):
        if base.is_dir():
            bases.append(base)
    return bases


def find_stack_dir() -> Path | None:
    """Directory containing at least MG+CT (full stack preferred)."""
    best: Path | None = None
    best_n = -1
    for base in _ci_dist_bases():
        mg = base / "iPFakerMG.dylib"
        ct = base / "iPFakerCT.dylib"
        if not (mg.is_file() and ct.is_file()):
            # arm64e names
            mg = base / "iPFakerMG.arm64e.dylib"
            ct = base / "iPFakerCT.arm64e.dylib"
            if not (mg.is_file() and ct.is_file()):
                continue
        n = sum(1 for m in STACK_MODULES if (base / f"{m}.dylib").is_file() or (base / f"{m}.arm64e.dylib").is_file())
        if n > best_n:
            best_n = n
            best = base
            if n >= len(STACK_MODULES):
                break
    return best


def find_dylibs() -> tuple[Path | None, Path | None]:
    base = find_stack_dir()
    if not base:
        return None, None
    mg = base / "iPFakerMG.dylib"
    ct = base / "iPFakerCT.dylib"
    if mg.is_file() and ct.is_file():
        return mg, ct
    mg = base / "iPFakerMG.arm64e.dylib"
    ct = base / "iPFakerCT.arm64e.dylib"
    if mg.is_file() and ct.is_file():
        return mg, ct
    return None, None


def find_app(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(explicit)
        return p if p.is_dir() else None
    for p in [
        ROOT / "_ci_art_dual" / "ipfaker-sileo" / "theos" / "dist" / "app" / "iPFaker.app",
        ROOT / "_ci_art_ui" / "ipfaker-sileo" / "theos" / "dist" / "app" / "iPFaker.app",
        ROOT / "_ci_art_ui" / "theos" / "dist" / "app" / "iPFaker.app",
        ROOT / "theos" / "dist" / "app" / "iPFaker.app",
        ROOT / "theos" / "app" / ".theos" / "obj" / "debug" / "iPFaker.app",
        ROOT / "theos" / "app" / ".theos" / "obj" / "iPFaker.app",
    ]:
        if p.is_dir() and (p / "iPFaker").exists():
            return p
    for base in _ci_dist_bases():
        p = base / "app" / "iPFaker.app"
        if p.is_dir() and (p / "iPFaker").exists():
            return p
    for p in (ROOT / "theos").rglob("iPFaker.app"):
        if p.is_dir() and (p / "iPFaker").exists() and "Applications" not in str(p):
            return p
    return None


def lab_core_bundles_xml() -> str:
    """Lab-core inject surface (Zalo + Safari/Maps/Weather/WebKit; not mass multi-acc)."""
    return """			<string>vn.com.vng.zingalo</string>
			<string>com.zing.zalo</string>
			<string>com.apple.mobilesafari</string>
			<string>com.apple.Maps</string>
			<string>com.apple.weather</string>
			<string>com.apple.WebKit.WebContent</string>
			<string>com.apple.WebKit.Networking</string>
			<string>com.apple.WebKit.GPU</string>"""


def zalo_only_plist() -> bytes:
    """MG/JB/AA filter: Lab-core bundles (no CommCenter executables)."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array>
{lab_core_bundles_xml()}
		</array>
		<key>Mode</key>
		<string>Any</string>
	</dict>
</dict>
</plist>
""".encode("utf-8")


def about_prefs_only_plist() -> bytes:
    """About / AboutUI / AboutVer: Settings.app only (never Zalo)."""
    return b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array>
			<string>com.apple.Preferences</string>
		</array>
		<key>Mode</key>
		<string>Any</string>
	</dict>
</dict>
</plist>
"""


def ct_filter_plist() -> bytes:
    """CT filter: Lab-core bundles + CommCenter executables (lab CT daemon)."""
    # Prefer theos CT if it already has CommCenter; else generate full Lab-core+CT
    for p in (
        ROOT / "theos" / "iPFakerCT.plist",
        ROOT / "dylibs" / "iPFakerCT.plist",
        ROOT / "theos" / "layout" / "Library" / "MobileSubstrate" / "DynamicLibraries" / "iPFakerCT.plist",
    ):
        if p.is_file():
            data = p.read_bytes()
            if b"CommCenter" in data and b"mobilesafari" in data:
                return data
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array>
{lab_core_bundles_xml()}
		</array>
		<key>Executables</key>
		<array>
			<string>CommCenter</string>
			<string>commcenter</string>
			<string>CoreTelephonyHelper</string>
		</array>
		<key>Mode</key>
		<string>Any</string>
	</dict>
</dict>
</plist>
""".encode("utf-8")


# Soft size hint — thin arm64e MG ~155KB; dual-arch fat ~310KB
MG_SAFE_MAX = 360_000
MG_HYBRID_HINT = 130_000


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
# Rootless: ldid/uicache live under /var/jb, often NOT on default PATH
export PATH="/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
LDID=""
for c in /var/jb/usr/bin/ldid /var/jb/bin/ldid /usr/bin/ldid ldid; do
  if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then LDID="$c"; break; fi
done
JBCTL=""
[ -x /var/jb/basebin/jbctl ] && JBCTL=/var/jb/basebin/jbctl
ENT="/var/jb/etc/ipfaker/entitlements.plist"
[ -f "$ENT" ] || ENT="$ROOT/etc/ipfaker/entitlements.plist"

trust_add() {
  f="$1"
  [ -n "$JBCTL" ] || return 0
  [ -f "$f" ] || return 0
  if [ -n "$LDID" ]; then
    H=$("$LDID" -h "$f" 2>/dev/null | sed -n 's/.*CDHash=//p' | head -1 | tr 'A-F' 'a-f' | cut -c1-40)
    if [ ${#H} -eq 40 ]; then
      "$JBCTL" trustcache add "$H" 2>/dev/null || true
    fi
  fi
  # Precomputed hashes (package-time) — works when device has no ldid
  base=$(basename "$f")
  for hf in /var/jb/etc/ipfaker/cdhashes.txt "$ROOT/etc/ipfaker/cdhashes.txt"; do
    [ -f "$hf" ] || continue
    for H in $(grep -i "^$base " "$hf" 2>/dev/null | awk '{print $2}'); do
      H=$(echo "$H" | tr 'A-F' 'a-f' | cut -c1-40)
      [ ${#H} -eq 40 ] && "$JBCTL" trustcache add "$H" 2>/dev/null || true
    done
  done
}

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
# Wipe helpers (multi-app + Zalo legacy)
for w in /var/jb/usr/libexec/ipfaker-wipe-apps /var/jb/etc/ipfaker/wipe_apps.sh \
         /var/mobile/Library/iPFaker/wipe_apps.sh \
         /var/jb/usr/libexec/ipfaker-wipe-zalo /var/jb/etc/ipfaker/wipe_zalo.sh \
         /var/mobile/Library/iPFaker/wipe_zalo.sh \
         /var/jb/usr/libexec/ipfaker-wipe-zalo-session /var/jb/etc/ipfaker/wipe_zalo_session.sh \
         /var/mobile/Library/iPFaker/wipe_zalo_session.sh; do
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
  for f in iPFakerMG.dylib iPFakerCT.dylib iPFakerJB.dylib \
           iPFakerAbout.dylib iPFakerAboutID.dylib iPFakerAboutUI.dylib iPFakerAboutVer.dylib iPFakerAA.dylib; do
    if [ -f "$MS/$f" ]; then
      chown root:wheel "$MS/$f" 2>/dev/null || true
      chmod 755 "$MS/$f" 2>/dev/null || true
      if [ -n "$LDID" ]; then
        "$LDID" -S "$MS/$f" 2>/dev/null || true
      fi
      trust_add "$MS/$f"
    fi
  done
  for f in iPFakerMG.plist iPFakerCT.plist iPFakerJB.plist \
           iPFakerAbout.plist iPFakerAboutID.plist iPFakerAboutUI.plist iPFakerAboutVer.plist iPFakerAA.plist; do
    # mobile-writable so Fake can extend inject list live (Zalo-depth multi-app)
    [ -f "$MS/$f" ] && chmod 666 "$MS/$f" 2>/dev/null || true
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
  if [ -f "$APP/iPFaker" ] && [ -n "$LDID" ]; then
    if [ -f "$ENT" ]; then
      "$LDID" -S"$ENT" "$APP/iPFaker" 2>/dev/null || "$LDID" -S "$APP/iPFaker" 2>/dev/null || true
    else
      "$LDID" -S "$APP/iPFaker" 2>/dev/null || true
    fi
  fi
  trust_add "$APP/iPFaker"
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

# --- Preferences About auto-inject (ElleKit often SKIPS platform Preferences) ---
# AboutVer OFF by default (Preferences crash history on some hosts)
for MS in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
  [ -d "$MS" ] || continue
  if [ -f "$MS/iPFakerAboutVer.dylib" ]; then
    mv -f "$MS/iPFakerAboutVer.dylib" "$MS/iPFakerAboutVer.dylib.off" 2>/dev/null || true
  fi
done

# Ensure SpoofSettingsAbout default on seed config if missing
for CFG in /var/jb/etc/ipfaker/config.plist /var/mobile/Library/iPFaker/config.plist; do
  if [ -f "$CFG" ] && command -v plutil >/dev/null 2>&1; then
    plutil -replace SpoofSettingsAbout -bool true "$CFG" 2>/dev/null || true
    plutil -replace Enabled -bool true "$CFG" 2>/dev/null || true
  fi
done

# prefs inject daemon: opainject About+AboutUI+AboutID into Preferences
DAEMON_SRC="/var/jb/etc/ipfaker/prefs_inject_daemon.sh"
if [ -f "$DAEMON_SRC" ]; then
  cp -f "$DAEMON_SRC" /var/mobile/Library/iPFaker/prefs_inject_daemon.sh 2>/dev/null || true
  chmod 755 /var/mobile/Library/iPFaker/prefs_inject_daemon.sh 2>/dev/null || true
  chmod 755 "$DAEMON_SRC" 2>/dev/null || true
  mkdir -p /var/jb/Library/LaunchDaemons 2>/dev/null || true
  if [ -f /var/jb/etc/ipfaker/com.ipfaker.prefs-inject.plist ]; then
    cp -f /var/jb/etc/ipfaker/com.ipfaker.prefs-inject.plist \
      /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null || true
    launchctl bootout system/com.ipfaker.prefs-inject 2>/dev/null || true
    launchctl unload /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null || true
    launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null \
      || launchctl load -w /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null || true
    launchctl kickstart -k system/com.ipfaker.prefs-inject 2>/dev/null || true
  fi
  # ALWAYS nohup fallback (launchctl often fails silently on rootless)
  killall -9 prefs_inject_daemon 2>/dev/null || true
  # kill old loops by pattern
  for p in $(ps ax | grep 'prefs_inject_daemon.sh' | grep -v grep | awk '{print $1}'); do
    kill -9 "$p" 2>/dev/null || true
  done
  nohup /bin/sh /var/mobile/Library/iPFaker/prefs_inject_daemon.sh \
    >/var/mobile/Library/iPFaker/logs/prefs_inject_daemon.out 2>&1 &
  echo "prefs_inject_daemon started pid=$!" >> /var/mobile/Library/iPFaker/logs/prefs_inject_daemon.log 2>/dev/null || true
fi

# Hard requirement check (new phone often misses these if installed without deps)
if [ ! -e /var/jb/usr/lib/libellekit.dylib ] && [ ! -e /var/jb/usr/lib/libsubstrate.dylib ]; then
  echo "WARN: ElleKit missing — install package ellekit from same Sileo source" >&2
fi
if [ ! -x /var/jb/basebin/opainject ]; then
  echo "WARN: opainject missing — Settings About spoof needs opainject (Dopamine basebin)" >&2
fi

killall -9 Zalo 2>/dev/null || true
killall -9 Preferences 2>/dev/null || true

# --- Auto Userspace Reboot (Dopamine) ---
# Tweaks only inject after launchd userspace restart. Delay so Sileo/dpkg can
# finish the transaction and show Done before reboot3 runs.
# Skip: IPFAKER_SKIP_USERSPACE_REBOOT=1 dpkg -i ... (lab only)
if [ -z "$IPFAKER_SKIP_USERSPACE_REBOOT" ]; then
  echo "iPFaker: Userspace Reboot in ~6s (tweak inject + About daemon)..." >&2
  mkdir -p /var/mobile/Library/iPFaker/logs 2>/dev/null || true
  # Detach fully so package manager exits cleanly (no hang on open fd)
  nohup /bin/sh -c '
    sleep 6
    echo "$(date) auto userspace reboot start" >> /var/mobile/Library/iPFaker/logs/userspace_reboot.log 2>/dev/null || true
    # Official Dopamine path: jbctl reboot_userspace → reboot3(RB2_USERREBOOT)
    if [ -x /var/jb/basebin/jbctl ]; then
      /var/jb/basebin/jbctl reboot_userspace >> /var/mobile/Library/iPFaker/logs/userspace_reboot.log 2>&1 \
        && exit 0
    fi
    # Fallbacks
    if [ -x /var/jb/usr/bin/launchctl ]; then
      /var/jb/usr/bin/launchctl reboot userspace >> /var/mobile/Library/iPFaker/logs/userspace_reboot.log 2>&1 && exit 0
    fi
    launchctl reboot userspace >> /var/mobile/Library/iPFaker/logs/userspace_reboot.log 2>&1 || true
    echo "$(date) reboot_userspace failed — open Dopamine → Reboot Userspace" \
      >> /var/mobile/Library/iPFaker/logs/userspace_reboot.log 2>/dev/null || true
  ' >/dev/null 2>&1 &
else
  echo "iPFaker: skip auto Userspace Reboot (IPFAKER_SKIP_USERSPACE_REBOOT set)" >&2
fi

exit 0
"""


def prerm_script() -> str:
    return r"""#!/bin/sh
killall -9 Zalo 2>/dev/null || true
killall -9 iPFaker 2>/dev/null || true
exit 0
"""


def control_text(version: str, installed_size_kb: int, has_app: bool, has_dylibs: bool) -> str:
    desc = (
        "Full lab stack MG(Zalo-safe lean)+CT+Deep+JB+About+AboutID+AboutUI+AA. "
        "Zalo: delayed MG, no UIScreen crash; NET ss via CT. "
        "Requires ElleKit. Auto Userspace Reboot ~6s after install (Dopamine jbctl)."
    )
    if has_app:
        desc += " Includes iPFaker.app (device pool, wipe, Apply)."
    return f"""Package: {PKG}
Name: iPFaker
Depends: firmware (>= 14.0), ellekit (>= 1.1), libsqlite3-1, sqlite3, ldid, libplist3
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
    """data.tar.lzma — same as classic Theos/lab debs (max iOS dpkg compatibility)."""
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


def _resolve_dylib(base: Path, name: str) -> Path | None:
    for cand in (base / f"{name}.dylib", base / f"{name}.arm64e.dylib"):
        if cand.is_file():
            return cand
    return None


def _filter_for_module(name: str, pl_mg: bytes, pl_ct: bytes, pl_about: bytes) -> bytes:
    if name == "iPFakerCT":
        return pl_ct
    if name in ("iPFakerAbout", "iPFakerAboutID", "iPFakerAboutUI", "iPFakerAboutVer"):
        return pl_about
    return pl_mg


def build(version: str, app_path: str | None) -> Path:
    stack = find_stack_dir()
    mg, ct = find_dylibs()
    app = find_app(app_path)
    catalog = ROOT / "config" / "device_catalog.json"
    if not catalog.exists():
        catalog = ROOT / "theos" / "app" / "Resources" / "device_catalog.json"

    if not mg or not ct or not stack:
        raise SystemExit("Missing iPFakerMG/CT dylibs (_ci_art_ui/theos/dist, dylibs_ci/, or theos/dist)")

    out_dir = ROOT / "dist" / "sileo"
    repo_dir = out_dir / "repo" / "debs"
    out_dir.mkdir(parents=True, exist_ok=True)
    repo_dir.mkdir(parents=True, exist_ok=True)

    # --- data.tar ---
    size_bytes = 0

    def data_builder(tar: tarfile.TarFile) -> None:
        nonlocal size_bytes

        def track(data: bytes) -> bytes:
            nonlocal size_bytes
            size_bytes += len(data)
            return data

        # Full paths under /var/jb (lab flat).
        # NOTE: On Dopamine, DynamicLibraries -> symlink to TweakInject.
        # Package ONLY TweakInject to avoid dpkg double-extract failure.
        for d in (
            "var/",
            "var/jb/",
            "var/jb/usr/",
            "var/jb/usr/lib/",
            "var/jb/usr/lib/TweakInject/",
            "var/jb/usr/libexec/",
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

        # Distinct filters: MG/JB/AA = lab-core; CT = +CommCenter; About* = Preferences only
        pl_mg = zalo_only_plist()
        pl_ct = ct_filter_plist()
        pl_about = about_prefs_only_plist()
        if b"CommCenter" not in pl_ct:
            raise SystemExit("FATAL: CT filter missing CommCenter — refuse package")
        dest = "var/jb/usr/lib/TweakInject"
        mg_bytes = mg.read_bytes()
        if len(mg_bytes) > MG_SAFE_MAX:
            raise SystemExit(
                f"FATAL: iPFakerMG.dylib {len(mg_bytes)} > {MG_SAFE_MAX} "
                f"(refuse package)."
            )
        if len(mg_bytes) > MG_HYBRID_HINT:
            print(
                f"WARN: MG size {len(mg_bytes)} > {MG_HYBRID_HINT} "
                f"— full lab stack still packaged (trustcache postinst)."
            )

        packed: list[str] = []
        for mod in STACK_MODULES:
            dy = _resolve_dylib(stack, mod)
            if not dy:
                # allow missing optional only if not MG/CT
                if mod in ("iPFakerMG", "iPFakerCT"):
                    raise SystemExit(f"FATAL: missing required {mod}.dylib in {stack}")
                print(f"skip optional {mod} (not in {stack.name})")
                continue
            raw = track(dy.read_bytes())
            add_file(tar, f"{dest}/{mod}.dylib", raw, 0o755)
            filt = _filter_for_module(mod, pl_mg, pl_ct, pl_about)
            add_file(tar, f"{dest}/{mod}.plist", track(filt), 0o644)
            packed.append(f"{mod}={len(raw)}")
        print(f"stack dir: {stack}")
        print("pack " + " ".join(packed))

        if catalog.exists():
            cdata = track(catalog.read_bytes())
            add_file(tar, "var/jb/etc/ipfaker/device_catalog.json", cdata, 0o644)
            add_file(tar, "var/mobile/Library/iPFaker/device_catalog.json", cdata, 0o644)

        readme = (
            b"iPFaker lab config dir (new device = same as dev).\n"
            b"- config.plist + active_profile.json from iPFaker.app Apply\n"
            b"- Stack: MG CT JB About AboutUI AboutVer AA + wipe_apps.sh\n"
            b"- Dual-arch: arm64 (A9-A11) + arm64e (A12+)\n"
            b"- Mirror: /var/mobile/Library/iPFaker/\n"
        )
        add_file(tar, "var/jb/etc/ipfaker/README.txt", track(readme), 0o644)
        ent = ROOT / "theos" / "app" / "entitlements.plist"
        if ent.is_file():
            add_file(tar, "var/jb/etc/ipfaker/entitlements.plist", track(ent.read_bytes()), 0o644)

        # Preferences About: ElleKit often SKIPS platform Preferences — must opainject.
        daemon_sh = r"""#!/bin/sh
# iPFaker prefs inject — About + AboutUI + AboutID into Settings
export PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/basebin:/usr/bin:/bin:/sbin:$PATH
LAST=""
LOGDIR=/var/mobile/Library/iPFaker/logs
LOG=$LOGDIR/prefs_inject_daemon.log
mkdir -p "$LOGDIR" 2>/dev/null
chmod 755 "$LOGDIR" 2>/dev/null
echo "$(date) daemon start sh=$(command -v sh) opainject=$(command -v opainject || echo /var/jb/basebin/opainject)" >> "$LOG" 2>/dev/null
OPAINJECT=/var/jb/basebin/opainject
[ -x "$OPAINJECT" ] || OPAINJECT=$(command -v opainject 2>/dev/null)
JBCTL=/var/jb/basebin/jbctl
TI=/var/jb/usr/lib/TweakInject
# order matters: About (MG lite) then UI wash then ID wash
DYLIBS="iPFakerAbout iPFakerAboutUI iPFakerAboutID"
while true; do
  PID=$(ps ax 2>/dev/null | grep 'Preferences.app/Preferences' | grep -v grep | head -1 | awk '{print $1}')
  if [ -z "$PID" ]; then
    # alternate path some iOS
    PID=$(ps ax 2>/dev/null | grep '[P]references' | grep -v grep | head -1 | awk '{print $1}')
  fi
  if [ -n "$PID" ] && [ "$PID" != "$LAST" ]; then
    echo "$(date) Preferences pid=$PID inject…" >> "$LOG" 2>/dev/null
    [ -x "$JBCTL" ] && "$JBCTL" proc_set_debugged "$PID" >/dev/null 2>&1
    for d in $DYLIBS; do
      DY="$TI/$d.dylib"
      if [ ! -f "$DY" ]; then
        echo "$(date) missing $DY" >> "$LOG" 2>/dev/null
        continue
      fi
      if [ -x "$OPAINJECT" ]; then
        "$OPAINJECT" "$PID" "$DY" >>"$LOG" 2>&1
        echo "$(date) opainject $d -> $PID rc=$?" >> "$LOG" 2>/dev/null
      else
        echo "$(date) NO opainject — cannot inject $d" >> "$LOG" 2>/dev/null
      fi
      sleep 0.3
    done
    LAST="$PID"
  fi
  if [ -z "$PID" ]; then LAST=""; fi
  sleep 2
done
"""
        add_file(tar, "var/jb/etc/ipfaker/prefs_inject_daemon.sh", track(daemon_sh.replace("\r\n", "\n").encode("utf-8")), 0o755)
        add_file(tar, "var/mobile/Library/iPFaker/prefs_inject_daemon.sh", track(daemon_sh.replace("\r\n", "\n").encode("utf-8")), 0o755)
        daemon_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.ipfaker.prefs-inject</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/var/mobile/Library/iPFaker/prefs_inject_daemon.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>UserName</key>
	<string>root</string>
	<key>StandardOutPath</key>
	<string>/var/mobile/Library/iPFaker/logs/prefs_inject_launchd.out</string>
	<key>StandardErrorPath</key>
	<string>/var/mobile/Library/iPFaker/logs/prefs_inject_launchd.err</string>
</dict>
</plist>
"""
        add_file(
            tar,
            "var/jb/etc/ipfaker/com.ipfaker.prefs-inject.plist",
            track(daemon_plist.replace("\r\n", "\n").encode("utf-8")),
            0o644,
        )
        # NEW_DEVICE deps note
        deps_txt = (
            b"Required packages (same Sileo source as iPFaker):\n"
            b"  ellekit, libsqlite3-1, sqlite3, ldid, libplist3\n"
            b"Install ALL before/with com.ipfaker. Then Dopamine Userspace Reboot.\n"
        )
        add_file(tar, "var/jb/etc/ipfaker/REQUIRED_PACKAGES.txt", track(deps_txt), 0o644)

        # Multi-app wipe (1-tap trusted) + legacy Zalo-only helper
        wipe_apps = ROOT / "injector" / "wipe_apps.sh"
        if not wipe_apps.is_file():
            wipe_apps = ROOT / "theos" / "layout" / "etc" / "ipfaker" / "wipe_apps.sh"
        if wipe_apps.is_file():
            wdata = track(wipe_apps.read_bytes())
            add_file(tar, "var/jb/usr/libexec/ipfaker-wipe-apps", wdata, 0o755)
            add_file(tar, "var/jb/etc/ipfaker/wipe_apps.sh", wdata, 0o755)
            add_file(tar, "var/mobile/Library/iPFaker/wipe_apps.sh", wdata, 0o755)
        wipe_src = ROOT / "injector" / "wipe_zalo.sh"
        if wipe_src.is_file():
            wdata = track(wipe_src.read_bytes())
            add_file(tar, "var/jb/usr/libexec/ipfaker-wipe-zalo", wdata, 0o755)
            add_file(tar, "var/jb/etc/ipfaker/wipe_zalo.sh", wdata, 0o755)
            add_file(tar, "var/mobile/Library/iPFaker/wipe_zalo.sh", wdata, 0o755)
        sess_src = ROOT / "injector" / "wipe_zalo_session.sh"
        if not sess_src.is_file():
            sess_src = ROOT / "theos" / "layout" / "etc" / "ipfaker" / "wipe_zalo_session.sh"
        if sess_src.is_file():
            sdata = track(sess_src.read_bytes())
            add_file(tar, "var/jb/usr/libexec/ipfaker-wipe-zalo-session", sdata, 0o755)
            add_file(tar, "var/jb/etc/ipfaker/wipe_zalo_session.sh", sdata, 0o755)
            add_file(tar, "var/mobile/Library/iPFaker/wipe_zalo_session.sh", sdata, 0o755)

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
