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
VERSION_DEFAULT = "2.18.0"
PKG = "com.ipfaker"
ARCH = "iphoneos-arm64"

# 2.17: ship FULL HIOS ChangeInfo 4.2.6 payload 1:1 (not reimplementation).
# Import: python scripts/import_hios_deb.py path/to/ChangeInfoIos-v3_4.2.6_*.deb
# - dylibs MG+CT + original plists (postinst strips weather like HIOS)
# - dual install: TweakInject + MobileSubstrate/DynamicLibraries
# - HIOSFakerV3.app (full) + iPFaker.app (lab UI)
# - cdhashes + config path /var/jb/etc/changeinfoios
HIOS_VENDOR = ROOT / "vendor" / "hios_426"
HIOS_MG = HIOS_VENDOR / "dylibs" / "ChangeInfoIosMG.dylib"
HIOS_CT = HIOS_VENDOR / "dylibs" / "ChangeInfoIosCT.dylib"
HIOS_MG_PL = HIOS_VENDOR / "dylibs" / "ChangeInfoIosMG.plist"
HIOS_CT_PL = HIOS_VENDOR / "dylibs" / "ChangeInfoIosCT.plist"
HIOS_CDHASHES = HIOS_VENDOR / "etc" / "cdhashes"
HIOS_APP = HIOS_VENDOR / "app" / "HIOSFakerV3.app"
HIOS_ROOT = HIOS_VENDOR / "root"  # full extracted data tree (optional mirror)

# Legacy (unused when HIOS vendor present)
STACK_MODULES = (
    "iPFakerMG",
    "iPFakerCT",
)


def _ci_dist_bases() -> list[Path]:
    """All local CI/theos dist dirs (includes Deep/IOKit fat builds under any _ci_art*)."""
    bases: list[Path] = []
    seen: set[str] = set()

    def add(p: Path) -> None:
        try:
            key = str(p.resolve())
        except Exception:
            key = str(p)
        if key in seen or not p.is_dir():
            return
        seen.add(key)
        bases.append(p)

    for art in ROOT.glob("_ci_art*"):
        if not art.is_dir():
            continue
        add(art / "ipfaker-sileo" / "theos" / "dist")
        add(art / "theos" / "dist")
    for base in (
        ROOT / "theos" / "dist",
        ROOT / "dylibs_ci",
        ROOT / "dylibs",
    ):
        add(base)
    return bases


def find_stack_dir() -> Path | None:
    """Prefer current theos/dist (this build), then newest mtime among MG+CT pairs."""
    preferred = [
        ROOT / "theos" / "dist",
        ROOT / "dylibs_ci",
    ]
    for base in preferred:
        mg = base / "iPFakerMG.dylib"
        ct = base / "iPFakerCT.dylib"
        if mg.is_file() and ct.is_file():
            return base

    best: Path | None = None
    best_mtime = -1.0
    best_mg = -1
    for base in _ci_dist_bases():
        mg = base / "iPFakerMG.dylib"
        ct = base / "iPFakerCT.dylib"
        if not (mg.is_file() and ct.is_file()):
            mg = base / "iPFakerMG.arm64e.dylib"
            ct = base / "iPFakerCT.arm64e.dylib"
            if not (mg.is_file() and ct.is_file()):
                continue
        try:
            mt = mg.stat().st_mtime
            mgsz = mg.stat().st_size
        except OSError:
            continue
        # Newest first; on same second pick larger MG
        if mt > best_mtime or (mt == best_mtime and mgsz > best_mg):
            best_mtime = mt
            best_mg = mgsz
            best = base
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
    """HIOS-style deep multi-app inject surface (social + Safari/WebKit/Maps)."""
    return """			<string>vn.com.vng.zingalo</string>
			<string>com.zing.zalo</string>
			<string>com.facebook.Facebook</string>
			<string>com.facebook.Messenger</string>
			<string>com.burbn.instagram</string>
			<string>ph.telegra.Telegraph</string>
			<string>com.viber</string>
			<string>com.zhiliaoapp.musically</string>
			<string>com.shopee.vn</string>
			<string>vn.shopee.vnapp</string>
			<string>com.apple.mobilesafari</string>
			<string>com.apple.WebKit.WebContent</string>
			<string>com.apple.Maps</string>"""


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
# Fat MG = Extra+Deep+JB+ServerLite (2-dylib HIOS wall) — up to ~700k expected
MG_SAFE_MAX = 900_000
MG_HYBRID_HINT = 300_000


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
# Do NOT use set -e: Sileo postinst must always reach auto-reboot scheduler.
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

# --- dirs: iPFaker UI config + HIOS dylib config (ChangeInfo reads changeinfoios) ---
mkdir -p "$ROOT/etc/ipfaker" 2>/dev/null || true
mkdir -p /var/jb/etc/ipfaker 2>/dev/null || true
mkdir -p /var/jb/etc/changeinfoios 2>/dev/null || true
mkdir -p /var/mobile/Library/iPFaker 2>/dev/null || true
chown -R mobile:mobile /var/mobile/Library/iPFaker 2>/dev/null || true
chown -R mobile:mobile "$ROOT/etc/ipfaker" /var/jb/etc/ipfaker 2>/dev/null || true
chown -R mobile:mobile /var/jb/etc/changeinfoios 2>/dev/null || true
chmod 777 /var/jb/etc/changeinfoios 2>/dev/null || true
chmod 775 /var/mobile/Library/iPFaker "$ROOT/etc/ipfaker" /var/jb/etc/ipfaker 2>/dev/null || true
for f in "$ROOT/etc/ipfaker/config.plist" /var/jb/etc/ipfaker/config.plist \
         /var/jb/etc/changeinfoios/config.plist \
         "$ROOT/etc/ipfaker/active_profile.json" /var/jb/etc/ipfaker/active_profile.json; do
  if [ -f "$f" ]; then
    chown mobile:mobile "$f" 2>/dev/null || true
    chmod 644 "$f" 2>/dev/null || true
  fi
done
# HIOS 4.2.6 FULL 1:1 — trust ChangeInfo dylibs on BOTH inject paths
for MS in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
  [ -d "$MS" ] || continue
  for f in ChangeInfoIosMG.dylib ChangeInfoIosCT.dylib; do
    [ -f "$MS/$f" ] || continue
    chown root:wheel "$MS/$f" 2>/dev/null || true
    chmod 0755 "$MS/$f" 2>/dev/null || true
    trust_add "$MS/$f"
  done
  for f in ChangeInfoIosMG.plist ChangeInfoIosCT.plist; do
    [ -f "$MS/$f" ] || continue
    chown root:wheel "$MS/$f" 2>/dev/null || true
    chmod 0644 "$MS/$f" 2>/dev/null || true
  done
  # HIOS postinst (verbatim intent): strip weather from filters (crashes WeatherCore)
  for P in "$MS/ChangeInfoIosMG.plist" "$MS/ChangeInfoIosCT.plist"; do
    [ -f "$P" ] || continue
    sed -i '' '/com\.apple\.weather/d' "$P" 2>/dev/null || sed -i '/com\.apple\.weather/d' "$P" 2>/dev/null || true
  done
  # Disable OUR MG/CT reimplementation only (must not double-inject with HIOS).
  # KEEP About/AboutUI/AboutID/AboutVer — Settings → Giới thiệu sync.
  for n in iPFakerMG iPFakerCT iPFakerJB iPFakerAA; do
    if [ -f "$MS/${n}.dylib" ]; then
      mv -f "$MS/${n}.dylib" "$MS/${n}.dylib.off" 2>/dev/null || true
    fi
  done
  # Recover About stack if older postinst disabled them
  for n in iPFakerAbout iPFakerAboutUI iPFakerAboutID iPFakerAboutVer; do
    if [ -f "$MS/${n}.dylib.off" ] && [ ! -f "$MS/${n}.dylib" ]; then
      mv -f "$MS/${n}.dylib.off" "$MS/${n}.dylib" 2>/dev/null || true
    fi
    if [ -f "$MS/${n}.dylib" ]; then
      chown root:wheel "$MS/${n}.dylib" 2>/dev/null || true
      chmod 0755 "$MS/${n}.dylib" 2>/dev/null || true
      trust_add "$MS/${n}.dylib"
    fi
  done
done
# HIOS cdhashes (package + any runtime list)
if [ -n "$JBCTL" ] && [ -f /var/jb/etc/changeinfoios/cdhashes ]; then
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    H=$(echo "$h" | tr 'A-F' 'a-f' | cut -c1-40)
    [ ${#H} -eq 40 ] && "$JBCTL" trustcache add "$H" 2>/dev/null || true
  done < /var/jb/etc/changeinfoios/cdhashes
fi
# HIOS app icon cache (full HIOSFakerV3.app when packaged)
for APP in /var/jb/Applications/HIOSFakerV3.app /var/jb/Applications/iPFaker.app; do
  [ -d "$APP" ] || continue
  for u in uicache /var/jb/usr/bin/uicache "$ROOT/usr/bin/uicache" /usr/bin/uicache; do
    if command -v "$u" >/dev/null 2>&1 || [ -x "$u" ]; then
      "$u" -p "$APP" 2>/dev/null && break
    fi
  done
done
# Seed HIOS lab enable flags if config missing (full bridge after first Apply from app)
if [ ! -f /var/jb/etc/changeinfoios/config.plist ] && [ -f /var/jb/etc/changeinfoios/defaults_lab.plist ]; then
  cp -f /var/jb/etc/changeinfoios/defaults_lab.plist /var/jb/etc/changeinfoios/config.plist 2>/dev/null || true
  chown mobile:mobile /var/jb/etc/changeinfoios/config.plist 2>/dev/null || true
fi
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

# --- Product: NO About dylib recover / NO prefs_inject (hung Apply + crash Preferences) ---
for MS in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
  [ -d "$MS" ] || continue
  for n in iPFakerAbout iPFakerAboutUI iPFakerAboutID iPFakerAboutVer iPFakerAA iPFakerJB; do
    if [ -f "$MS/${n}.dylib" ]; then
      mv -f "$MS/${n}.dylib" "$MS/${n}.dylib.off" 2>/dev/null || true
    fi
  done
done
# Kill leftover prefs inject daemon from older packages
launchctl bootout system/com.ipfaker.prefs-inject 2>/dev/null || true
launchctl unload /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null || true
rm -f /var/jb/Library/LaunchDaemons/com.ipfaker.prefs-inject.plist 2>/dev/null || true
for p in $(ps ax 2>/dev/null | grep prefs_inject_daemon | grep -v grep | awk '{print $1}'); do
  kill -9 "$p" 2>/dev/null || true
done

# Product flags: multi-app deep + STABLE social (lean Extra, no FakeScreen)
for CFG in /var/jb/etc/ipfaker/config.plist /var/mobile/Library/iPFaker/config.plist; do
  if [ -f "$CFG" ] && command -v plutil >/dev/null 2>&1; then
    plutil -replace Enabled -bool true "$CFG" 2>/dev/null || true
    plutil -replace DeepSpoofSocial -bool true "$CFG" 2>/dev/null || true
    plutil -replace InjectWebKit -bool true "$CFG" 2>/dev/null || true
    # HIOS parity flags (full wall). CrashSafeMode OFF.
    plutil -replace CrashSafeMode -bool false "$CFG" 2>/dev/null || true
    plutil -replace AllowDeepSocial -bool true "$CFG" 2>/dev/null || true
    plutil -replace AllowEnvSocial -bool true "$CFG" 2>/dev/null || true
    plutil -replace SkipExtraForZalo -bool false "$CFG" 2>/dev/null || true
    plutil -replace StableSocialHooks -bool false "$CFG" 2>/dev/null || true
    plutil -replace DeepSpoofSocial -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeDevice -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeHardware -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeScreen -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeRealScreen -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeBrowser -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeNetwork -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeWifi -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeSysctl -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeSysOSVersion -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeLocale -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeLocation -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeSensor -bool true "$CFG" 2>/dev/null || true
    plutil -replace FakeWebRTC -bool true "$CFG" 2>/dev/null || true
    plutil -replace HideJailbreak -bool true "$CFG" 2>/dev/null || true
    plutil -replace BlockFork -bool true "$CFG" 2>/dev/null || true
    plutil -replace fake_keychain -bool true "$CFG" 2>/dev/null || true
    plutil -replace ClearKeychainOnLaunch -bool false "$CFG" 2>/dev/null || true
    plutil -replace SpoofSettingsAbout -bool false "$CFG" 2>/dev/null || true
  fi
done

# prefs inject: DISABLED (do not start daemon)
if false; then
  DAEMON_SRC="/var/jb/etc/ipfaker/prefs_inject_daemon.sh"
  if [ -f "$DAEMON_SRC" ]; then
    true
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
# NEVER reboot inside postinst (causes "Dpkg bị gián đoạn").
# Waiter: payload present + short grace; do NOT require dpkg Status string
# (Sileo/rootless often never shows install ok to waiter → silent no-reboot).
# Skip: IPFAKER_SKIP_USERSPACE_REBOOT=1
if [ -z "$IPFAKER_SKIP_USERSPACE_REBOOT" ]; then
  echo "iPFaker: schedule Userspace Reboot after install (payload + dpkg quiet)..." >&2
  mkdir -p /var/mobile/Library/iPFaker/logs /var/jb/etc/ipfaker /var/jb/Library/LaunchDaemons 2>/dev/null || true
  REBOOT_SH="/var/jb/etc/ipfaker/userspace_reboot_once.sh"
  REBOOT_PL="/var/jb/Library/LaunchDaemons/com.ipfaker.userspace-reboot.plist"
  REBOOT_FLAG="/var/jb/etc/ipfaker/.pending_userspace_reboot"
  LOGF="/var/mobile/Library/iPFaker/logs/userspace_reboot.log"
  cat > "$REBOOT_SH" <<'REBOOT_EOF'
#!/bin/sh
export PATH="/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
FLAG="/var/jb/etc/ipfaker/.pending_userspace_reboot"
RUNLOCK="/var/jb/etc/ipfaker/.reboot_script_running"
DONE="/var/jb/etc/ipfaker/.userspace_reboot_done"
LOG="/var/mobile/Library/iPFaker/logs/userspace_reboot.log"
PL="/var/jb/Library/LaunchDaemons/com.ipfaker.userspace-reboot.plist"
mkdir -p /var/mobile/Library/iPFaker/logs 2>/dev/null || true

log() { echo "$(date) $*" >> "$LOG" 2>/dev/null || true; }

if [ ! -f "$FLAG" ]; then
  log "no pending flag — skip"
  exit 0
fi
if [ -f "$DONE" ]; then
  # already rebooted once this install cycle
  age=9999
  if [ -f "$DONE" ]; then
    # clear DONE older than 120s so reinstall still reboots
    :
  fi
fi

if ! mkdir "$RUNLOCK" 2>/dev/null; then
  log "another reboot waiter already running — exit"
  exit 0
fi
trap 'rmdir "$RUNLOCK" 2>/dev/null || true' EXIT INT TERM

log "waiter start — payload + short quiet window then Userspace Reboot"

payload_ok() {
  [ -f /var/jb/usr/lib/TweakInject/iPFakerMG.dylib ] \
    || [ -f /var/jb/Library/MobileSubstrate/DynamicLibraries/iPFakerMG.dylib ] \
    || [ -f /var/jb/Applications/iPFaker.app/iPFaker ]
}

dpkg_busy() {
  # Only treat real package managers as busy — avoid false positives that aborted reboot
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x dpkg >/dev/null 2>&1 && return 0
    pgrep -x apt >/dev/null 2>&1 && return 0
    pgrep -x apt-get >/dev/null 2>&1 && return 0
  fi
  ps ax 2>/dev/null | grep -E '[/ ](dpkg|apt-get)( |$)' | grep -v grep >/dev/null 2>&1 && return 0
  return 1
}

# Let postinst/dpkg exit (Sileo UI may still show Installing for a bit)
sleep 12

i=0
max=40
quiet=0
need_quiet=2
while [ "$i" -lt "$max" ]; do
  if ! payload_ok; then
    log "wait: payload not on disk yet ($i)"
    quiet=0
    sleep 2
    i=$((i + 1))
    continue
  fi
  if dpkg_busy; then
    log "wait: dpkg still busy ($i)"
    quiet=0
    sleep 2
    i=$((i + 1))
    continue
  fi
  quiet=$((quiet + 1))
  log "quiet $quiet/$need_quiet payload ok"
  if [ "$quiet" -ge "$need_quiet" ]; then
    break
  fi
  sleep 2
  i=$((i + 1))
done

# HARD rule: if payload is on disk, always try reboot.
if ! payload_ok; then
  log "ABORT: no payload after wait — keep flag for next LaunchDaemon tick"
  exit 0
fi

log "INSTALL PAYLOAD OK — Userspace Reboot now"

do_reboot() {
  if [ -x /var/jb/basebin/jbctl ]; then
    log "jbctl reboot_userspace"
    /var/jb/basebin/jbctl reboot_userspace >> "$LOG" 2>&1 && return 0
  fi
  for c in /var/jb/basebin/jbctl /basebin/jbctl; do
    [ -x "$c" ] || continue
    log "try $c reboot_userspace"
    "$c" reboot_userspace >> "$LOG" 2>&1 && return 0
  done
  launchctl reboot userspace >> "$LOG" 2>&1 && return 0
  /bin/launchctl reboot userspace >> "$LOG" 2>&1 && return 0
  return 1
}

if do_reboot; then
  rm -f "$FLAG"
  date > "$DONE" 2>/dev/null || true
  launchctl bootout system/com.ipfaker.userspace-reboot 2>/dev/null || true
  launchctl unload "$PL" 2>/dev/null || true
  rm -f "$PL" 2>/dev/null || true
  log "reboot command accepted"
  exit 0
fi

# Keep FLAG so StartInterval / next nohup can retry (do NOT set DONE)
log "reboot_userspace FAILED — keep flag for retry; or Dopamine → Reboot Userspace"
exit 0
REBOOT_EOF
  chmod 755 "$REBOOT_SH" 2>/dev/null || true
  cp -f "$REBOOT_SH" /var/mobile/Library/iPFaker/userspace_reboot_once.sh 2>/dev/null || true
  rmdir /var/jb/etc/ipfaker/.reboot_script_running 2>/dev/null || true
  rm -f /var/jb/etc/ipfaker/.userspace_reboot_done 2>/dev/null || true
  touch "$REBOOT_FLAG" 2>/dev/null || true
  chmod 644 "$REBOOT_FLAG" 2>/dev/null || true
  cat > "$REBOOT_PL" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.ipfaker.userspace-reboot</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/var/jb/etc/ipfaker/userspace_reboot_once.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartInterval</key>
	<integer>15</integer>
	<key>AbandonProcessGroup</key>
	<true/>
	<key>StandardOutPath</key>
	<string>/var/mobile/Library/iPFaker/logs/userspace_reboot_launchd.out</string>
	<key>StandardErrorPath</key>
	<string>/var/mobile/Library/iPFaker/logs/userspace_reboot_launchd.err</string>
</dict>
</plist>
PLIST_EOF
  chmod 644 "$REBOOT_PL" 2>/dev/null || true
  # Schedule only — do NOT reboot inside postinst.
  launchctl bootout system/com.ipfaker.userspace-reboot 2>/dev/null || true
  launchctl unload "$REBOOT_PL" 2>/dev/null || true
  launchctl bootstrap system "$REBOOT_PL" 2>/dev/null \
    || launchctl load -w "$REBOOT_PL" 2>/dev/null || true
  # Triple fallback: Sileo often kills postinst children — launchd StartInterval is primary.
  # Also spawn detached waiters if launchd load fails.
  ( nohup /bin/sh "$REBOOT_SH" </dev/null >>"$LOGF" 2>&1 & ) >/dev/null 2>&1 || true
  ( (sleep 20; /bin/sh "$REBOOT_SH") </dev/null >>"$LOGF" 2>&1 & ) >/dev/null 2>&1 || true
  ( (sleep 45; /bin/sh "$REBOOT_SH") </dev/null >>"$LOGF" 2>&1 & ) >/dev/null 2>&1 || true
  echo "$(date) scheduled reboot waiter (launchd+nohup+sleep20+sleep45)" >> "$LOGF" 2>/dev/null || true
else
  echo "iPFaker: skip auto Userspace Reboot (IPFAKER_SKIP_USERSPACE_REBOOT set)" >&2
fi

exit 0
"""


def prerm_script() -> str:
    return r"""#!/bin/sh
killall -9 Zalo 2>/dev/null || true
killall -9 iPFaker 2>/dev/null || true
killall -9 HIOSFakerV3 2>/dev/null || true
exit 0
"""


def control_text(version: str, installed_size_kb: int, has_app: bool, has_dylibs: bool) -> str:
    desc = (
        "2.18 HIOS FULL + license-gate lab patch + About Giới thiệu. "
        "ChangeInfoIosMG+CT dual-path, HIOSFakerV3.app, iPFaker About stack, "
        "config bridge full keys. Config→/var/jb/etc/changeinfoios."
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
    app = find_app(app_path)
    catalog = ROOT / "config" / "device_catalog.json"
    if not catalog.exists():
        catalog = ROOT / "theos" / "app" / "Resources" / "device_catalog.json"

    use_hios = HIOS_MG.is_file() and HIOS_CT.is_file() and HIOS_MG_PL.is_file() and HIOS_CT_PL.is_file()
    stack = find_stack_dir()
    mg, ct = find_dylibs()
    if not use_hios and (not mg or not ct or not stack):
        raise SystemExit(
            "Missing HIOS vendor (vendor/hios_426/dylibs) AND iPFakerMG/CT dylibs"
        )
    if use_hios:
        print(f"PACK MODE: HIOS 4.2.6 FULL 1:1 from {HIOS_VENDOR}")
        print(f"  MG={HIOS_MG.stat().st_size} CT={HIOS_CT.stat().st_size}")
        print(f"  APP={HIOS_APP.is_dir()} dual-path=TweakInject+MobileSubstrate")
    else:
        print("PACK MODE: fallback iPFaker theos dylibs (HIOS vendor missing)")

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
        # HIOS ships MobileSubstrate/DynamicLibraries; Dopamine also uses TweakInject.
        # We install both so inject works regardless of loader layout.
        for d in (
            "var/",
            "var/jb/",
            "var/jb/usr/",
            "var/jb/usr/lib/",
            "var/jb/usr/lib/TweakInject/",
            "var/jb/usr/libexec/",
            "var/jb/Library/",
            "var/jb/Library/MobileSubstrate/",
            "var/jb/Library/MobileSubstrate/DynamicLibraries/",
            "var/jb/etc/",
            "var/jb/etc/ipfaker/",
            "var/jb/etc/changeinfoios/",
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

        dest_ti = "var/jb/usr/lib/TweakInject"
        dest_ms = "var/jb/Library/MobileSubstrate/DynamicLibraries"
        packed: list[str] = []

        if use_hios:
            # === HIOS ChangeInfo 4.2.6 FULL (MG may be lab-patched license gate) ===
            mg_raw = track(HIOS_MG.read_bytes())
            ct_raw = track(HIOS_CT.read_bytes())
            pl_mg = track(HIOS_MG_PL.read_bytes())
            pl_ct = track(HIOS_CT_PL.read_bytes())
            if b"CommCenter" not in pl_ct:
                print("WARN: HIOS CT plist may lack CommCenter string (check Executables)")
            mg_note = ROOT / "vendor" / "hios_426" / "dylibs" / "ChangeInfoIosMG.dylib.orig"
            if mg_note.is_file() and mg_note.stat().st_size == len(mg_raw):
                # same size always; check hash differs from pure
                import hashlib as _hl

                pure_h = _hl.sha256(mg_note.read_bytes()).hexdigest()
                cur_h = _hl.sha256(mg_raw).hexdigest()
                if pure_h != cur_h:
                    print(f"NOTE: MG lab-patched license gate (pure={pure_h[:12]} now={cur_h[:12]})")
                else:
                    print("WARN: MG still pure HIOS — run scripts/patch_hios_license_gate.py")
            # Dual-path install (same bytes on both — HIOS path + Dopamine TweakInject)
            # Installed-Size counts unique payload once; both paths get identical files.
            for dest in (dest_ti, dest_ms):
                add_file(tar, f"{dest}/ChangeInfoIosMG.dylib", mg_raw, 0o755)
                add_file(tar, f"{dest}/ChangeInfoIosMG.plist", pl_mg, 0o644)
                add_file(tar, f"{dest}/ChangeInfoIosCT.dylib", ct_raw, 0o755)
                add_file(tar, f"{dest}/ChangeInfoIosCT.plist", pl_ct, 0o644)
            packed.append(f"ChangeInfoIosMG={len(mg_raw)}")
            packed.append(f"ChangeInfoIosCT={len(ct_raw)}")
            packed.append("paths=TweakInject+MobileSubstrate")
            # HIOS cdhashes for trustcache
            if HIOS_CDHASHES.is_file():
                add_file(
                    tar,
                    "var/jb/etc/changeinfoios/cdhashes",
                    track(HIOS_CDHASHES.read_bytes()),
                    0o644,
                )
            # Full HIOSFakerV3.app (100% from deb)
            if HIOS_APP.is_dir() and (HIOS_APP / "HIOSFakerV3").is_file():
                add_tree(tar, HIOS_APP, "var/jb/Applications/HIOSFakerV3.app")
                for f in HIOS_APP.rglob("*"):
                    if f.is_file():
                        size_bytes += f.stat().st_size
                packed.append("HIOSFakerV3.app=yes")
                print(f"pack HIOSFakerV3.app from {HIOS_APP}")
            else:
                print("WARN: HIOSFakerV3.app missing under vendor/hios_426/app — run import_hios_deb.py")
            # Marker so app/UI knows inject engine
            add_file(
                tar,
                "var/jb/etc/changeinfoios/ENGINE.txt",
                track(
                    b"ChangeInfoIos-v3_4.2.6 FULL via iPFaker 2.18\n"
                    b"MG=lab-patch license gate (see ChangeInfoIosMG.dylib.orig)\n"
                ),
                0o644,
            )
            add_file(
                tar,
                "var/jb/etc/ipfaker/ENGINE.txt",
                track(
                    b"HIOS_FULL=ChangeInfoIos-4.2.6\n"
                    b"HIOS_LICENSE_GATE=patched\n"
                    b"HIOS_APP=HIOSFakerV3.app\n"
                    b"HIOS_DYLIBS=ChangeInfoIosMG+ChangeInfoIosCT\n"
                    b"ABOUT=iPFakerAbout+UI+ID+Ver\n"
                ),
                0o644,
            )
            # Seed empty dirs HIOS expects (license/hwid written by app Apply)
            add_file(
                tar,
                "var/jb/etc/changeinfoios/hwid",
                track(b"lab\n"),
                0o644,
            )
            # Lab defaults: enable all HIOS hook modules + fake_* (merged/used if no config yet)
            defaults_lab = b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Enabled</key><true/>
	<key>_ci_enable_sysctlbyname</key><true/>
	<key>_ci_enable_iokit_reg</key><true/>
	<key>_ci_enable_hw_hook</key><true/>
	<key>_ci_enable_net_hook</key><true/>
	<key>_ci_enable_uname_hook</key><true/>
	<key>_ci_lic_tok</key><string>lab-ipfaker-hios-full</string>
	<key>_ci_lic_dev</key><string>lab</string>
	<key>fake_hardware</key><true/>
	<key>fake_uiddevice</key><true/>
	<key>fake_uiddevice2</key><true/>
	<key>fake_ads</key><true/>
	<key>fake_screen</key><true/>
	<key>fake_realscreen</key><true/>
	<key>fake_browser</key><true/>
	<key>fake_network</key><true/>
	<key>fake_wifi</key><true/>
	<key>fake_sysctl</key><true/>
	<key>fake_sysosversion</key><true/>
	<key>fake_jbhide</key><true/>
	<key>fake_locale</key><true/>
	<key>fake_locale2</key><true/>
	<key>fake_location</key><true/>
	<key>fake_sensor</key><true/>
	<key>fake_webrtc</key><true/>
	<key>fake_keychain</key><true/>
	<key>fake_battery</key><true/>
	<key>fake_metal</key><true/>
	<key>fake_processinfo</key><true/>
	<key>fake_tracking_pasteboard</key><true/>
	<key>fake_trackingdefaults</key><true/>
	<key>zalo_mode</key><true/>
	<key>locationEnabled</key><true/>
	<key>keychainReset</key><false/>
	<key>SpoofSettingsAbout</key><true/>
</dict>
</plist>
"""
            add_file(
                tar,
                "var/jb/etc/changeinfoios/defaults_lab.plist",
                track(defaults_lab.replace(b"\r\n", b"\n")),
                0o644,
            )
            print("pack HIOS FULL 1:1 " + " ".join(packed))
            # Settings → Giới thiệu: ship About stack next to HIOS (not iPFakerMG/CT)
            about_mods = (
                "iPFakerAboutID",
                "iPFakerAboutUI",
                "iPFakerAbout",
                "iPFakerAboutVer",
            )
            pl_about = about_prefs_only_plist()
            about_bases = []
            if stack:
                about_bases.append(stack)
            about_bases.extend(
                [
                    ROOT / "theos" / "dist",
                    ROOT / "_ci_art_2112" / "theos" / "dist",
                    ROOT / "_ci_art_pack2112" / "ipfaker-sileo" / "theos" / "dist",
                    ROOT / "_ci_ids" / "ipfaker-sileo" / "theos" / "dist",
                ]
            )
            for mod in about_mods:
                dy = None
                for base in about_bases:
                    if not base:
                        continue
                    dy = _resolve_dylib(base, mod)
                    if dy:
                        break
                if not dy:
                    print(f"WARN: missing {mod}.dylib (About Giới thiệu incomplete)")
                    continue
                raw = track(dy.read_bytes())
                pl_src = dy.with_suffix(".plist")
                filt = pl_src.read_bytes() if pl_src.is_file() else pl_about
                for dest in (dest_ti, dest_ms):
                    add_file(tar, f"{dest}/{mod}.dylib", raw, 0o755)
                    add_file(tar, f"{dest}/{mod}.plist", track(filt), 0o644)
                packed.append(f"{mod}={len(raw)}")
            print("pack About stack " + " ".join(x for x in packed if x.startswith("iPFakerAbout")))
        else:
            pl_mg = zalo_only_plist()
            pl_ct = ct_filter_plist()
            pl_about = about_prefs_only_plist()
            if b"CommCenter" not in pl_ct:
                raise SystemExit("FATAL: CT filter missing CommCenter — refuse package")
            for mod in STACK_MODULES:
                dy = _resolve_dylib(stack, mod)
                if not dy:
                    if mod in ("iPFakerMG", "iPFakerCT"):
                        raise SystemExit(f"FATAL: missing required {mod}.dylib in {stack}")
                    continue
                raw = track(dy.read_bytes())
                add_file(tar, f"{dest_ti}/{mod}.dylib", raw, 0o755)
                filt = _filter_for_module(mod, pl_mg, pl_ct, pl_about)
                add_file(tar, f"{dest_ti}/{mod}.plist", track(filt), 0o644)
                packed.append(f"{mod}={len(raw)}")
            print(f"stack dir: {stack}")
            print("pack " + " ".join(packed))

        if catalog.exists():
            cdata = track(catalog.read_bytes())
            add_file(tar, "var/jb/etc/ipfaker/device_catalog.json", cdata, 0o644)
            add_file(tar, "var/mobile/Library/iPFaker/device_catalog.json", cdata, 0o644)
            add_file(tar, "var/jb/etc/changeinfoios/device_catalog.json", cdata, 0o644)

        readme = (
            b"iPFaker 2.17 - FULL HIOS ChangeInfo 4.2.6 payload 1:1\n"
            b"- Dylibs: ChangeInfoIosMG + ChangeInfoIosCT (vendor/hios_426) dual path\n"
            b"- App: HIOSFakerV3.app (from HIOS) + iPFaker.app (lab UI)\n"
            b"- Config for dylibs: /var/jb/etc/changeinfoios/config.plist\n"
            b"- iPFaker.app Apply dual-writes ipfaker + changeinfoios\n"
            b"- Import: python scripts/import_hios_deb.py <ChangeInfoIos deb>\n"
        )
        add_file(tar, "var/jb/etc/ipfaker/README.txt", track(readme), 0o644)
        add_file(tar, "var/jb/etc/changeinfoios/README.txt", track(readme), 0o644)
        ent = ROOT / "theos" / "app" / "entitlements.plist"
        if ent.is_file():
            add_file(tar, "var/jb/etc/ipfaker/entitlements.plist", track(ent.read_bytes()), 0o644)

        # Preferences About: ElleKit often SKIPS platform Preferences — must opainject.
        # Customer zero-touch: AboutID washes model+iOS+serial+part; AboutUI backup; About MG-lite.
        daemon_sh = r"""#!/bin/sh
# iPFaker prefs inject — keep Settings → About = lab profile (no SSH)
export PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/basebin:/usr/bin:/bin:/sbin:$PATH
LAST=""
INJECTED_AT=0
LOGDIR=/var/mobile/Library/iPFaker/logs
LOG=$LOGDIR/prefs_inject_daemon.log
mkdir -p "$LOGDIR" 2>/dev/null
chmod 755 "$LOGDIR" 2>/dev/null
echo "$(date) daemon start v2 opainject=$(ls /var/jb/basebin/opainject 2>/dev/null)" >> "$LOG" 2>/dev/null
OPAINJECT=/var/jb/basebin/opainject
[ -x "$OPAINJECT" ] || OPAINJECT=$(command -v opainject 2>/dev/null)
JBCTL=/var/jb/basebin/jbctl
TI=/var/jb/usr/lib/TweakInject
# AboutID first (model+iOS+serial+part), then AboutUI, then About MG-lite
DYLIBS="iPFakerAboutID iPFakerAboutUI iPFakerAbout"
# Recover dylibs disabled by older postinst
for n in iPFakerAboutID iPFakerAboutUI iPFakerAbout; do
  if [ -f "$TI/${n}.dylib.off" ] && [ ! -f "$TI/${n}.dylib" ]; then
    mv -f "$TI/${n}.dylib.off" "$TI/${n}.dylib" 2>/dev/null || true
    echo "$(date) recovered $n.dylib from .off" >> "$LOG" 2>/dev/null
  fi
done
find_prefs_pid() {
  PID=$(ps ax 2>/dev/null | grep 'Preferences.app/Preferences' | grep -v grep | head -1 | awk '{print $1}')
  if [ -z "$PID" ]; then
    PID=$(ps ax 2>/dev/null | grep '/Applications/Preferences.app' | grep -v grep | head -1 | awk '{print $1}')
  fi
  if [ -z "$PID" ]; then
    PID=$(ps ax 2>/dev/null | grep '[P]references' | grep -v grep | grep -v prefs_inject | head -1 | awk '{print $1}')
  fi
  echo "$PID"
}
do_inject() {
  PID="$1"
  [ -n "$PID" ] || return 1
  echo "$(date) inject Preferences pid=$PID" >> "$LOG" 2>/dev/null
  [ -x "$JBCTL" ] && "$JBCTL" proc_set_debugged "$PID" >/dev/null 2>&1
  for d in $DYLIBS; do
    DY="$TI/$d.dylib"
    [ -f "$DY" ] || DY="/var/jb/Library/MobileSubstrate/DynamicLibraries/$d.dylib"
    if [ ! -f "$DY" ]; then
      echo "$(date) missing $d.dylib" >> "$LOG" 2>/dev/null
      continue
    fi
    if [ -x "$OPAINJECT" ]; then
      "$OPAINJECT" "$PID" "$DY" >>"$LOG" 2>&1
      echo "$(date) opainject $d -> $PID rc=$?" >> "$LOG" 2>/dev/null
    else
      echo "$(date) NO opainject" >> "$LOG" 2>/dev/null
    fi
    sleep 0.25
  done
  return 0
}
while true; do
  PID=$(find_prefs_pid)
  NOW=$(date +%s 2>/dev/null || echo 0)
  if [ -n "$PID" ]; then
    # New process OR re-inject every 12s while Preferences stays open (wash after UI paints)
    NEED=0
    if [ "$PID" != "$LAST" ]; then NEED=1; fi
    if [ "$NOW" -gt 0 ] && [ $((NOW - INJECTED_AT)) -ge 12 ]; then NEED=1; fi
    if [ "$NEED" -eq 1 ]; then
      do_inject "$PID"
      LAST="$PID"
      INJECTED_AT="$NOW"
    fi
  else
    LAST=""
    INJECTED_AT=0
  fi
  sleep 1
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
