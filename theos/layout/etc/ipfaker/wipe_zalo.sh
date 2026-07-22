#!/bin/sh
# iPFaker — wipe Zalo local binding (lab/split-stack "clean app")
# Run ON DEVICE as root (SSH / NewTerm).
#
# What it does (lab only, owned device):
#   1) kill Zalo
#   2) wipe Data Application container (Documents/Library/tmp/…)
#   3) wipe Shared App Group containers for Zalo
#   4) wipe Caches / Preferences crumbs under /var/mobile/Library if present
#   5) best-effort keychain item purge via known service/account patterns
#   6) optional: leave app binary installed (reinstall NOT required)
#
# Usage:
#   sh /var/mobile/Library/iPFaker/wipe_zalo.sh
#   sh /var/mobile/Library/iPFaker/wipe_zalo.sh --dry-run
#   sh /var/mobile/Library/iPFaker/wipe_zalo.sh --bundle vn.com.vng.zingalo
#
# After wipe: open Zalo with spoof ALREADY active (Frida/dylib) before login/register.

set -e

DRY=0
BUNDLE=""
LOG_DIR="/var/mobile/Library/iPFaker/logs"
LOG_FILE=""
TS=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)

# Bundles seen on App Store / VN / RootHide lab
BUNDLES_DEFAULT="vn.com.vng.zingalo com.zing.zalo"

# App group id patterns (metadata match)
GROUP_PATTERNS="zalo zing.zalo vng.zalo"

# Keychain service / account substrings (lab flat + lab placeholders)
KC_PATTERNS="zalo Zalo ZALO zing.zalo vng.zalo zalo_device_id ZaloDeviceId ZADeviceID kZAIDForDevice AppsFlyer af_device install_id deviceId device_id"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    --bundle|-b) BUNDLE="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--bundle BUNDLE_ID]"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/wipe_zalo_$TS.log"

log() {
  echo "[iPFaker-wipe] $*"
  echo "[iPFaker-wipe] $*" >> "$LOG_FILE" 2>/dev/null || true
}

run() {
  if [ "$DRY" -eq 1 ]; then
    log "DRY: $*"
  else
    log "RUN: $*"
    # shellcheck disable=SC2086
    eval "$@" >> "$LOG_FILE" 2>&1 || log "WARN: cmd failed (continue): $*"
  fi
}

log "==== wipe start $TS dry=$DRY ===="

# ── 1) Kill Zalo ────────────────────────────────────────────
log "Kill Zalo processes..."
if [ "$DRY" -eq 0 ]; then
  killall -9 Zalo 2>/dev/null || true
  killall -9 zalo 2>/dev/null || true
  # extensions
  killall -9 ZaloShare 2>/dev/null || true
  killall -9 NotificationService 2>/dev/null || true
  sleep 1
fi

# ── 2) Resolve bundles ──────────────────────────────────────
if [ -n "$BUNDLE" ]; then
  BUNDLES="$BUNDLE"
else
  BUNDLES="$BUNDLES_DEFAULT"
fi
log "Target bundles: $BUNDLES"

# ── 3) Find data containers by metadata plist ───────────────
# Path: /var/mobile/Containers/Data/Application/<UUID>/.com.apple.mobile_container_manager.metadata.plist
# contains MCMMetadataIdentifier = bundle id

find_data_containers() {
  bid="$1"
  # Prefer mdfind-like scan; fall back to grep -l on metadata files
  for meta in /var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist; do
    [ -f "$meta" ] || continue
    if grep -q "$bid" "$meta" 2>/dev/null; then
      dirname "$meta"
    fi
  done
}

find_group_containers() {
  # Shared App Groups under /var/mobile/Containers/Shared/AppGroup/<UUID>
  for meta in /var/mobile/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist; do
    [ -f "$meta" ] || continue
    # match zalo-ish group id
    if grep -qiE 'zalo|zing\.zalo|vng\.zalo' "$meta" 2>/dev/null; then
      dirname "$meta"
    fi
  done
}

wipe_tree_contents() {
  root="$1"
  label="$2"
  if [ ! -d "$root" ]; then
    log "skip missing $label: $root"
    return 0
  fi
  log "Wipe $label: $root"
  # Remove common binding dirs; keep container shell so iOS does not get confused
  for sub in Documents Library tmp SystemData StoreKit Caches; do
    if [ -e "$root/$sub" ]; then
      run "rm -rf '$root/$sub'"
    fi
  done
  # leftover files at root of container
  if [ "$DRY" -eq 0 ]; then
    find "$root" -mindepth 1 -maxdepth 1 \
      ! -name '.com.apple.mobile_container_manager.metadata.plist' \
      ! -name 'iTunesMetadata.plist' \
      -exec rm -rf {} + 2>/dev/null || true
  else
    log "DRY: would clear children of $root"
  fi
}

# ── 4) Wipe each bundle data container ──────────────────────
WIPED=0
for bid in $BUNDLES; do
  log "--- bundle $bid ---"
  found=0
  for c in $(find_data_containers "$bid"); do
    found=1
    wipe_tree_contents "$c" "DataContainer($bid)"
    WIPED=$((WIPED + 1))
  done
  if [ "$found" -eq 0 ]; then
    log "No data container found for $bid (app not installed or path differs)"
  fi
done

# ── 5) Wipe app groups ──────────────────────────────────────
log "--- app groups ---"
for g in $(find_group_containers); do
  wipe_tree_contents "$g" "AppGroup"
  WIPED=$((WIPED + 1))
done

# ── 6) Preferences / cookies / HTTPStorages crumbs ──────────
log "--- mobile Library crumbs ---"
for bid in $BUNDLES; do
  # Preferences plist by bundle id
  pref="/var/mobile/Library/Preferences/${bid}.plist"
  if [ -f "$pref" ]; then
    run "rm -f '$pref'"
  fi
  # Cookies
  cook="/var/mobile/Library/Cookies/${bid}.binarycookies"
  if [ -f "$cook" ]; then
    run "rm -f '$cook'"
  fi
  # WebKit
  for w in /var/mobile/Library/WebKit/WebsiteData/*/"$bid" \
           /var/mobile/Library/HTTPStorages/"$bid"; do
    if [ -e "$w" ]; then
      run "rm -rf '$w'"
    fi
  done
done

# Splash / snapshot leftovers
run "rm -rf /var/mobile/Library/SplashBoard/Snapshots/sceneID:vn.com.vng.zingalo* 2>/dev/null || true"
run "rm -rf /var/mobile/Library/SplashBoard/Snapshots/sceneID:com.zing.zalo* 2>/dev/null || true"

# ── 7) Deep local session (keychain + WebKit…; keep AppManager backups) ─
# Shared helper: wipe_zalo_session.sh (team agrp CVB6BX97VM + zalo patterns)
log "--- zalo local session (keychain/tokens) ---"
SESS=""
for s in \
  /var/jb/usr/libexec/ipfaker-wipe-zalo-session \
  /var/jb/etc/ipfaker/wipe_zalo_session.sh \
  /var/mobile/Library/iPFaker/wipe_zalo_session.sh
do
  [ -f "$s" ] && SESS=$s && break
done
if [ -n "$SESS" ]; then
  if [ "$DRY" -eq 1 ]; then
    sh "$SESS" --dry-run >>"$LOG_FILE" 2>&1 || true
  else
    sh "$SESS" >>"$LOG_FILE" 2>&1 || log "WARN session wipe rc=$?"
  fi
  log "session helper: $SESS"
else
  log "WARN wipe_zalo_session.sh missing — install package / deploy scripts"
  log "TIP: apt-get install -y sqlite3 && deploy injector/wipe_zalo_session.sh"
fi

# ── 8) uicache / fix perms ──────────────────────────────────
if [ "$DRY" -eq 0 ]; then
  chown -R mobile:mobile /var/mobile/Containers/Data/Application 2>/dev/null || true
fi

log "==== wipe done containers_touched~$WIPED log=$LOG_FILE ===="
log "NEXT:"
log "  1) Start spoof FIRST (Frida/dylib)"
log "  2) Open Zalo fresh (first launch = new local install)"
log "  3) Then register / login for lab test"
log "  4) Optional reseed: scripts/build_active_profile.ps1 after editing device_profile.json"

echo ""
echo "OK wipe finished. Log: $LOG_FILE"
[ "$DRY" -eq 1 ] && echo "(dry-run — nothing deleted)"
exit 0
