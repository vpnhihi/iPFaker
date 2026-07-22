#!/bin/sh
# iPFaker — multi-app session wipe (Zalo-depth for ALL selected App Store apps)
# Wipes Data + App Groups + PluginKit + Library crumbs + keychain patterns.
# Does NOT uninstall the app binary. Does NOT touch AppManager ADManager backups.
#
# Usage:
#   sh wipe_apps.sh --bundle com.apple.Maps --bundle ph.telegra.Telegraph
#   sh wipe_apps.sh --targets-file /var/mobile/Library/iPFaker/wipe_targets.txt
#   sh wipe_apps.sh --bundle vn.com.vng.zingalo
#   sh wipe_apps.sh --verify
#
# targets-file lines (one per app):
#   bundleId
#   bundleId|ExecutableName
#   bundleId|ExecutableName|Alias1,Alias2
#
# Design (lab-proven):
# - Kill by CFBundleExecutable AND by process path containing bundleId (covers
#   Telegram vs Telegraph, NotificationService extensions, share extensions).
# - One multi-file grep for containers (no N×M per-meta loops).
# - Deep session for EVERY third-party bid (same depth as Zalo: crumbs+keychain).
# - Pass-2 kill + re-wipe so live apps cannot rewrite session after pass-1.
# - Zalo keeps extra keychain agrp patterns (team CVB6BX97VM) via wipe_zalo_session.
# - Self-elevate to root when app launches as mobile (sudo -n often unavailable).

# Do NOT use set -e: kill/path loops + optional tools must not abort wipe mid-way.

# ── Self-elevate (critical for keychain + full kill + filter sync) ──
# App Fake often runs this as uid=501; containers wipe as mobile but spoof filter
# install + keychain need root. Re-exec once via sudo -S when possible.
if [ -z "$IPFAKER_WIPE_ROOT" ] && [ "$(id -u 2>/dev/null)" != "0" ]; then
  SELF="$0"
  case "$SELF" in
    /*) ;;
    *) SELF="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)/$(basename "$SELF")" ;;
  esac
  PASS=""
  for pf in /var/mobile/Library/iPFaker/.root_pass /var/jb/etc/ipfaker/.root_pass; do
    if [ -f "$pf" ]; then
      PASS=$(tr -d '\r\n' < "$pf" 2>/dev/null)
      [ -n "$PASS" ] && break
    fi
  done
  # Lab default (Dopamine mobile/alpine) — same as all deploy scripts
  [ -z "$PASS" ] && PASS="alpine"
  for sudoBin in /var/jb/usr/bin/sudo /usr/bin/sudo; do
    [ -x "$sudoBin" ] || continue
    # passwordless first
    IPFAKER_WIPE_ROOT=1 "$sudoBin" -n sh "$SELF" "$@"
    rc=$?
    # Elevated run always prints "uid=0"; if we got any wipe log start, trust rc
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 4 ] || [ "$rc" -eq 5 ]; then
      exit "$rc"
    fi
    # password sudo
    echo "$PASS" | IPFAKER_WIPE_ROOT=1 "$sudoBin" -S -p '' sh "$SELF" "$@"
    rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 4 ] || [ "$rc" -eq 5 ]; then
      exit "$rc"
    fi
  done
  # Fall through as mobile if sudo unavailable
fi

DRY=0
VERIFY=0
LOG_DIR="/var/mobile/Library/iPFaker/logs"
TARGETS_FILE=""
BUNDLES=""
TS=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)
START_SEC=$(date +%s 2>/dev/null || echo 0)
STAGE="/var/mobile/Library/iPFaker"
NEEDLE_FILE="$STAGE/wipe_needles_$TS.txt"
EXTRA_NEEDLE_FILE="$STAGE/wipe_needles_extra_$TS.txt"
KILL_MAP="$STAGE/wipe_kill_map_$TS.txt"
EXE_MAP="$STAGE/wipe_exe_map_$TS.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    --verify|-v) VERIFY=1; shift ;;
    --bundle|-b)
      BUNDLES="$BUNDLES $2"
      shift 2
      ;;
    --targets-file|-f)
      TARGETS_FILE="$2"
      shift 2
      ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--verify] [--bundle ID]... [--targets-file PATH]"
      exit 0
      ;;
    *) echo "Unknown: $1"; exit 2 ;;
  esac
done

mkdir -p "$LOG_DIR" "$STAGE" 2>/dev/null || true
LOG_FILE="$LOG_DIR/wipe_apps_$TS.log"

log() {
  echo "[iPFaker-wipe] $*"
  echo "[iPFaker-wipe] $*" >> "$LOG_FILE" 2>/dev/null || true
}

: > "$KILL_MAP"
: > "$EXE_MAP"
: > "$NEEDLE_FILE"
: > "$EXTRA_NEEDLE_FILE"

# Parse one target line → BUNDLES + kill map
# Formats: bid | bid|exe | bid|exe|alias1,alias2
ingest_target() {
  raw="$1"
  raw=$(echo "$raw" | tr -d '\r' | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$raw" ] && return 0
  bid=${raw%%|*}
  rest=${raw#*|}
  exe=""
  aliases=""
  if [ "$rest" != "$raw" ]; then
    exe=${rest%%|*}
    aliases=${rest#*|}
    if [ "$aliases" = "$rest" ]; then aliases=""; fi
    if [ "$exe" = "$rest" ]; then aliases=""; fi
  fi
  [ -z "$bid" ] && return 0
  BUNDLES="$BUNDLES $bid"
  short=${bid##*.}
  {
    echo "$bid"
    echo "$short"
    [ -n "$exe" ] && echo "$exe"
    if [ -n "$aliases" ]; then
      echo "$aliases" | tr ',' '\n'
    fi
  } >> "$KILL_MAP"
  [ -n "$exe" ] && echo "$bid|$exe" >> "$EXE_MAP"
  echo "$bid" >> "$NEEDLE_FILE"
  echo "$short" >> "$NEEDLE_FILE"
  # App Group identifiers commonly group.<bundleId>
  echo "group.$bid" >> "$EXTRA_NEEDLE_FILE"
  echo "group.$short" >> "$EXTRA_NEEDLE_FILE"
}

if [ -n "$TARGETS_FILE" ] && [ -f "$TARGETS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    ingest_target "$line"
  done < "$TARGETS_FILE"
fi

# CLI --bundle may be plain bid
for b in $BUNDLES; do
  case "$b" in
    *\|*) ingest_target "$b" ;;
  esac
done
# Re-collect pure bids from NEEDLE (dedup later)
BUNDLES=$(echo "$BUNDLES" | tr ' ' '\n' | sed '/^$/d;s/|.*//' | sort -u | tr '\n' ' ')

if [ -z "$(echo "$BUNDLES" | tr -d ' ')" ]; then
  log "ERR: no bundle ids"
  echo "ERR no bundles" >&2
  exit 3
fi

# Rebuild needles cleanly from final BUNDLES + known app extras
: > "$NEEDLE_FILE"
: > "$EXTRA_NEEDLE_FILE"
HAS_ZALO=0
HAS_THIRD=0
for bid in $BUNDLES; do
  echo "$bid" >> "$NEEDLE_FILE"
  short=${bid##*.}
  [ -n "$short" ] && echo "$short" >> "$NEEDLE_FILE"
  echo "group.$bid" >> "$EXTRA_NEEDLE_FILE"
  case "$bid" in
    com.apple.*) ;;
    *)
      HAS_THIRD=1
      echo "$bid" >> "$KILL_MAP"
      echo "$short" >> "$KILL_MAP"
      ;;
  esac
  case "$bid" in *zalo*|*zing*) HAS_ZALO=1 ;; esac
  # Well-known executable aliases (process name ≠ last path component)
  case "$bid" in
    ph.telegra.Telegraph)
      echo "Telegram" >> "$KILL_MAP"
      echo "Telegraph" >> "$KILL_MAP"
      echo "TelegramShare" >> "$KILL_MAP"
      echo "NotificationServiceExtensionv1" >> "$KILL_MAP"
      echo "NotificationServiceExtension" >> "$KILL_MAP"
      echo "SiriIntents" >> "$KILL_MAP"
      echo "BroadcastUpload" >> "$KILL_MAP"
      echo "group.ph.telegra.Telegraph" >> "$EXTRA_NEEDLE_FILE"
      echo "C67CF9S4VU" >> "$EXTRA_NEEDLE_FILE"
      ;;
    vn.com.vng.zingalo|com.zing.zalo)
      echo "Zalo" >> "$KILL_MAP"
      echo "zalo" >> "$KILL_MAP"
      echo "ZaloShare" >> "$KILL_MAP"
      echo "NotificationService" >> "$KILL_MAP"
      echo "group.keychain.vn.com.vng.zalo" >> "$EXTRA_NEEDLE_FILE"
      echo "group.vn.com.vng.zingalo" >> "$EXTRA_NEEDLE_FILE"
      ;;
    com.apple.Maps) echo "Maps" >> "$KILL_MAP" ;;
    com.apple.weather) echo "Weather" >> "$KILL_MAP" ;;
    com.apple.mobilesafari)
      echo "MobileSafari" >> "$KILL_MAP"
      echo "SafariViewService" >> "$KILL_MAP"
      ;;
    net.whatsapp.WhatsApp)
      echo "WhatsApp" >> "$KILL_MAP"
      echo "WhatsAppShare" >> "$KILL_MAP"
      ;;
    com.facebook.Facebook) echo "Facebook" >> "$KILL_MAP" ;;
    com.facebook.Messenger) echo "Messenger" >> "$KILL_MAP" ;;
    com.burbn.instagram) echo "Instagram" >> "$KILL_MAP" ;;
    com.zhiliaoapp.musically|com.ss.iphone.ugc.Ame)
      echo "TikTok" >> "$KILL_MAP"
      echo "Musically" >> "$KILL_MAP"
      ;;
  esac
  # Merge exe map for this bid
  if [ -f "$EXE_MAP" ]; then
    while IFS= read -r em || [ -n "$em" ]; do
      ebid=${em%%|*}
      eexe=${em#*|}
      if [ "$ebid" = "$bid" ] && [ -n "$eexe" ]; then
        echo "$eexe" >> "$KILL_MAP"
      fi
    done < "$EXE_MAP"
  fi
done

# Sort-unique needles / kill map
sort -u "$NEEDLE_FILE" -o "$NEEDLE_FILE" 2>/dev/null || true
sort -u "$EXTRA_NEEDLE_FILE" -o "$EXTRA_NEEDLE_FILE" 2>/dev/null || true
sort -u "$KILL_MAP" -o "$KILL_MAP" 2>/dev/null || true

# Merge extra needles into main for container scan
cat "$EXTRA_NEEDLE_FILE" >> "$NEEDLE_FILE" 2>/dev/null || true
sort -u "$NEEDLE_FILE" -o "$NEEDLE_FILE" 2>/dev/null || true

log "==== wipe_apps start $TS dry=$DRY verify=$VERIFY ===="
log "bundles:$BUNDLES"
log "uid=$(id -u 2>/dev/null) user=$(id -un 2>/dev/null)"
log "has_zalo=$HAS_ZALO has_third=$HAS_THIRD"
log "needles:$(tr '\n' ' ' < "$NEEDLE_FILE" 2>/dev/null)"

# ── Kill helpers ───────────────────────────────────────────
# Kill every process whose command line contains a needle (covers extensions).
kill_by_path_needles() {
  # Build grep pattern from kill map + all bids
  patfile="$STAGE/wipe_ps_pat_$TS.txt"
  : > "$patfile"
  cat "$KILL_MAP" >> "$patfile" 2>/dev/null || true
  for bid in $BUNDLES; do
    echo "$bid" >> "$patfile"
    echo "${bid##*.}" >> "$patfile"
  done
  sort -u "$patfile" -o "$patfile" 2>/dev/null || true
  # ps ax: pid + command
  ps ax 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    # skip self
    case "$line" in *wipe_apps*|*ipfaker-wipe*) continue ;; esac
    matched=0
    while IFS= read -r needle || [ -n "$needle" ]; do
      [ -n "$needle" ] || continue
      # require length >= 3 to avoid over-match
      case "$needle" in ?|??) continue ;; esac
      case "$line" in
        *"$needle"*) matched=1; break ;;
      esac
    done < "$patfile"
    if [ "$matched" -eq 1 ]; then
      pid=$(echo "$line" | awk '{print $1}')
      case "$pid" in
        ''|*[!0-9]*) ;;
        1) ;; # never kill launchd
        *)
          kill -9 "$pid" 2>/dev/null || true
          ;;
      esac
    fi
  done
  rm -f "$patfile" 2>/dev/null || true
}

kill_by_name_list() {
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    case "$name" in ?|??) continue ;; esac
    killall -9 "$name" 2>/dev/null || true
  done < "$KILL_MAP"
  # system helpers often co-running
  for name in NotificationService NotificationServiceExtension SafariViewService; do
    killall -9 "$name" 2>/dev/null || true
  done
}

if [ "$DRY" -eq 0 ]; then
  log "kill pass1: names + path-match"
  kill_by_name_list
  kill_by_path_needles
  sleep 0.35 2>/dev/null || sleep 1
  kill_by_name_list
  kill_by_path_needles
fi

# Dedup wiped container UUIDs
WIPED_KEYS=""
is_wiped() {
  case " $WIPED_KEYS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}
mark_wiped() {
  WIPED_KEYS="$WIPED_KEYS $1"
}

wipe_container() {
  root="$1"
  label="$2"
  [ -d "$root" ] || return 0
  key=$(basename "$root")
  if is_wiped "$key"; then
    return 0
  fi
  mark_wiped "$key"
  log "wipe $label $root"
  if [ "$DRY" -eq 1 ]; then
    return 0
  fi
  find "$root" -mindepth 1 -maxdepth 1 \
    ! -name '.com.apple.mobile_container_manager.metadata.plist' \
    ! -name 'iTunesMetadata.plist' \
    ! -name '.com.apple.mobile_container_manager.metadata.plist.bak' \
    -exec rm -rf {} + 2>/dev/null || true
  mkdir -p "$root/Documents" "$root/Library/Caches" "$root/Library/Preferences" \
           "$root/Library/Application Support" "$root/tmp" 2>/dev/null || true
  chown mobile:mobile "$root" "$root/Documents" "$root/Library" "$root/tmp" \
        "$root/Library/Caches" "$root/Library/Preferences" 2>/dev/null || true
}

list_matching_metas() {
  base="$1"
  needles="$2"
  [ -d "$base" ] || return 0
  [ -f "$needles" ] || return 0
  listf="$STAGE/wipe_meta_list_$$.txt"
  find "$base" -mindepth 2 -maxdepth 2 \
    -name '.com.apple.mobile_container_manager.metadata.plist' 2>/dev/null > "$listf" || true
  if [ ! -s "$listf" ]; then
    rm -f "$listf" 2>/dev/null || true
    return 0
  fi
  if command -v xargs >/dev/null 2>&1; then
    # shellcheck disable=SC2002
    cat "$listf" | xargs -n 40 grep -l -F -f "$needles" 2>/dev/null || true
  else
    batch=""
    n=0
    while IFS= read -r m || [ -n "$m" ]; do
      [ -n "$m" ] || continue
      batch="$batch $m"
      n=$((n + 1))
      if [ "$n" -ge 40 ]; then
        # shellcheck disable=SC2086
        grep -l -F -f "$needles" $batch 2>/dev/null || true
        batch=""
        n=0
      fi
    done < "$listf"
    if [ "$n" -gt 0 ]; then
      # shellcheck disable=SC2086
      grep -l -F -f "$needles" $batch 2>/dev/null || true
    fi
  fi
  rm -f "$listf" 2>/dev/null || true
  return 0
}

WIPED=0
FOUND=0

scan_and_wipe() {
  base="$1"
  label="$2"
  needles="$3"
  list_matching_metas "$base" "$needles" | while IFS= read -r meta || [ -n "$meta" ]; do
    [ -n "$meta" ] || continue
    [ -f "$meta" ] || continue
    root=$(dirname "$meta")
    echo "$root" >> "$STAGE/wipe_hit_$TS.txt"
  done
}

: > "$STAGE/wipe_hit_$TS.txt"
: > "$STAGE/wipe_count_$TS.txt"
scan_and_wipe /var/mobile/Containers/Data/Application "Data" "$NEEDLE_FILE"
scan_and_wipe /var/mobile/Containers/Shared/AppGroup "AppGroup" "$NEEDLE_FILE"
scan_and_wipe /var/mobile/Containers/Data/PluginKitPlugin "Plugin" "$NEEDLE_FILE"

if [ -f "$STAGE/wipe_hit_$TS.txt" ]; then
  sort -u "$STAGE/wipe_hit_$TS.txt" | while IFS= read -r root || [ -n "$root" ]; do
    [ -n "$root" ] || continue
    [ -d "$root" ] || continue
    case "$root" in
      */PluginKitPlugin/*) lab="Plugin" ;;
      */AppGroup/*) lab="AppGroup" ;;
      *) lab="Data" ;;
    esac
    wipe_container "$root" "$lab"
    echo 1 >> "$STAGE/wipe_count_$TS.txt"
  done
fi

# ── Zalo-depth crumbs for EVERY selected app ───────────────
if [ "$DRY" -eq 0 ]; then
  log "deep crumbs (Zalo-depth) for all selected bundles"
  for bid in $BUNDLES; do
    short=${bid##*.}
    rm -rf \
      "/var/mobile/Library/Preferences/${bid}.plist" \
      "/var/mobile/Library/Cookies/${bid}.binarycookies" \
      "/var/mobile/Library/HTTPStorages/${bid}" \
      "/var/mobile/Library/Caches/${bid}" \
      "/var/mobile/Library/WebKit/WebsiteData/Default/${bid}" \
      2>/dev/null || true
    # Saved Application State (UI restore can resurrect half-session)
    rm -rf \
      "/var/mobile/Library/Saved Application State/${bid}.savedState" \
      "/var/mobile/Library/Saved Application State/${bid}" \
      2>/dev/null || true
    # SplashBoard snapshots
    for p in /var/mobile/Library/SplashBoard/Snapshots/sceneID:"${bid}"* \
             /var/mobile/Library/SplashBoard/Snapshots/"${bid}"*; do
      [ -e "$p" ] && rm -rf "$p" 2>/dev/null || true
    done
    # UserNotifications store
    find /var/mobile/Library/UserNotifications -maxdepth 3 \( -iname "*${bid}*" -o -iname "*${short}*" \) 2>/dev/null \
      | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
    # FrontBoard / SpringBoard app state crumbs
    find /var/mobile/Library/FrontBoard -maxdepth 3 \( -iname "*${bid}*" -o -iname "*${short}*" \) 2>/dev/null \
      | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
    # CloudKit local caches mentioning bid
    find /var/mobile/Library/Caches/CloudKit -maxdepth 4 \( -iname "*${bid}*" -o -iname "*${short}*" \) 2>/dev/null \
      | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
  done
  # Pasteboard OTP/phone residual (lab)
  rm -rf /var/mobile/Library/Caches/com.apple.Pasteboard/* 2>/dev/null || true
fi

# ── Generic keychain purge for ALL third-party bids (Zalo-depth) ──
# Matches agrp/svce/acct containing full bid or last component.
if [ "$DRY" -eq 0 ] && [ "$HAS_THIRD" -eq 1 ]; then
  KC_DB=""
  for p in /var/Keychains/keychain-2.db /private/var/Keychains/keychain-2.db; do
    [ -f "$p" ] && KC_DB="$p" && break
  done
  SQLITE=""
  for s in /var/jb/usr/bin/sqlite3 /var/jb/bin/sqlite3 /usr/bin/sqlite3; do
    [ -x "$s" ] && SQLITE="$s" && break
  done
  if [ -n "$KC_DB" ] && [ -n "$SQLITE" ]; then
    WHERE_PARTS=""
    for bid in $BUNDLES; do
      case "$bid" in com.apple.*) continue ;; esac
      short=${bid##*.}
      # Escape single quotes for SQL
      bsq=$(echo "$bid" | sed "s/'/''/g")
      ssq=$(echo "$short" | sed "s/'/''/g")
      part="agrp LIKE '%${bsq}%' OR svce LIKE '%${bsq}%' OR acct LIKE '%${bsq}%'"
      if [ -n "$ssq" ] && [ "$ssq" != "$bsq" ] && [ "${#ssq}" -ge 4 ]; then
        part="$part OR agrp LIKE '%${ssq}%' OR svce LIKE '%${ssq}%' OR acct LIKE '%${ssq}%'"
      fi
      if [ -z "$WHERE_PARTS" ]; then
        WHERE_PARTS="($part)"
      else
        WHERE_PARTS="$WHERE_PARTS OR ($part)"
      fi
    done
    # Extra Zalo agrp patterns (same as wipe_zalo_session)
    if [ "$HAS_ZALO" -eq 1 ]; then
      WHERE_PARTS="$WHERE_PARTS OR agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%' OR agrp LIKE '%zing.zalo%'"
    fi
    if [ -n "$WHERE_PARTS" ]; then
      BEFORE=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM genp WHERE $WHERE_PARTS;" 2>/dev/null || echo 0)
      BEFORE=$(echo "$BEFORE" | tr -cd '0-9')
      [ -z "$BEFORE" ] && BEFORE=0
      log "keychain multi-app genp before=$BEFORE"
      if [ "$BEFORE" -gt 0 ] 2>/dev/null; then
        killall -STOP securityd 2>/dev/null || true
        "$SQLITE" "$KC_DB" "DELETE FROM genp WHERE $WHERE_PARTS;" 2>>"$LOG_FILE" || true
        "$SQLITE" "$KC_DB" "DELETE FROM inet WHERE $WHERE_PARTS;" 2>>"$LOG_FILE" || true
        "$SQLITE" "$KC_DB" "DELETE FROM keys WHERE $WHERE_PARTS;" 2>>"$LOG_FILE" || true
        "$SQLITE" "$KC_DB" "DELETE FROM cert WHERE $WHERE_PARTS;" 2>>"$LOG_FILE" || true
        "$SQLITE" "$KC_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>>"$LOG_FILE" || true
        killall -CONT securityd 2>/dev/null || true
        killall -9 securityd 2>/dev/null || true
        AFTER=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM genp WHERE $WHERE_PARTS;" 2>/dev/null || echo 0)
        AFTER=$(echo "$AFTER" | tr -cd '0-9')
        [ -z "$AFTER" ] && AFTER=0
        log "keychain multi-app genp after=$AFTER (deleted ~$((BEFORE - AFTER)))"
      else
        log "keychain multi-app genp=0 (session mostly AppGroup/file for these apps)"
      fi
    fi
  else
    log "WARN: no sqlite3/keychain — skip multi-app keychain purge"
  fi
fi

# ── Zalo extra deep session script (WebKit/SDK crumbs + team agrp) ──
if [ "$HAS_ZALO" -eq 1 ] && [ "$DRY" -eq 0 ]; then
  SESS=""
  for s in \
    /var/jb/usr/libexec/ipfaker-wipe-zalo-session \
    /var/jb/etc/ipfaker/wipe_zalo_session.sh \
    /var/mobile/Library/iPFaker/wipe_zalo_session.sh \
    "$STAGE/wipe_zalo_session.sh"
  do
    if [ -f "$s" ]; then SESS=$s; break; fi
  done
  if [ -n "$SESS" ]; then
    log "zalo session deep wipe via $SESS"
    # Do not fail whole wipe if zalo session script exits non-zero
    sh "$SESS" >>"$LOG_FILE" 2>&1 || log "WARN: zalo session wipe rc=$?"
  fi
fi

# ── Pass-2: kill again + re-wipe residual (ALL third-party) ──
# Any messenger that holds AppGroup mmap will rewrite session if still alive.
if [ "$DRY" -eq 0 ] && [ "$HAS_THIRD" -eq 1 ]; then
  log "pass2: kill + residual re-wipe (all third-party)"
  kill_by_name_list
  kill_by_path_needles
  sleep 0.3 2>/dev/null || sleep 1
  kill_by_name_list
  kill_by_path_needles

  : > "$STAGE/wipe_hit_p2_$TS.txt"
  list_matching_metas /var/mobile/Containers/Data/Application "$NEEDLE_FILE" | while IFS= read -r meta || [ -n "$meta" ]; do
    [ -n "$meta" ] && [ -f "$meta" ] && echo "$(dirname "$meta")" >> "$STAGE/wipe_hit_p2_$TS.txt"
  done
  list_matching_metas /var/mobile/Containers/Shared/AppGroup "$NEEDLE_FILE" | while IFS= read -r meta || [ -n "$meta" ]; do
    [ -n "$meta" ] && [ -f "$meta" ] && echo "$(dirname "$meta")" >> "$STAGE/wipe_hit_p2_$TS.txt"
  done
  list_matching_metas /var/mobile/Containers/Data/PluginKitPlugin "$NEEDLE_FILE" | while IFS= read -r meta || [ -n "$meta" ]; do
    [ -n "$meta" ] && [ -f "$meta" ] && echo "$(dirname "$meta")" >> "$STAGE/wipe_hit_p2_$TS.txt"
  done

  # Reset wiped keys so pass2 actually re-clears
  WIPED_KEYS=""
  if [ -f "$STAGE/wipe_hit_p2_$TS.txt" ]; then
    sort -u "$STAGE/wipe_hit_p2_$TS.txt" | while IFS= read -r root || [ -n "$root" ]; do
      [ -n "$root" ] || continue
      [ -d "$root" ] || continue
      case "$root" in
        */PluginKitPlugin/*) lab="Plugin-p2" ;;
        */AppGroup/*) lab="AppGroup-p2" ;;
        *) lab="Data-p2" ;;
      esac
      wipe_container "$root" "$lab"
      echo 1 >> "$STAGE/wipe_count_$TS.txt"
      # Explicit nuke known session dirs inside AppGroup
      for d in telegram-data Library/Application\ Support Documents; do
        if [ -e "$root/$d" ]; then
          rm -rf "$root/$d" 2>/dev/null || true
        fi
      done
    done
  fi
  # Final kill so nothing rewrites after pass2
  kill_by_name_list
  kill_by_path_needles
  log "pass2 done"
fi

if [ -f "$STAGE/wipe_count_$TS.txt" ]; then
  WIPED=$(wc -l < "$STAGE/wipe_count_$TS.txt" | tr -d ' ')
  FOUND=$WIPED
else
  WIPED=0
  FOUND=0
fi

# ── Sync spoof filters stage → LIVE TweakInject (root only) ──
# Root cause of "Telegram not faked like Zalo": app writes stage plists with
# selected apps but sudo -n fails → live filter stays package-default (Zalo only).
# When wipe elevates to root, install stage filters so ALL selected apps get MG/CT/JB.
#
# NEVER overwrite iPFakerAbout / AboutUI / AboutVer with multi-app filters.
# Those MUST stay com.apple.Preferences only — otherwise Settings → Giới thiệu
# shows host identity (name/serial/model#) while Lab UI shows spoof profile.
if [ "$(id -u 2>/dev/null)" = "0" ] && [ "$DRY" -eq 0 ]; then
  if [ -f "$STAGE/iPFakerMG.plist" ]; then
    log "sync spoof filters stage → TweakInject (MG/CT/JB/AA only — protect About*)"
    for INJ in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
      [ -d "$INJ" ] || continue
      for n in iPFakerMG iPFakerCT iPFakerJB iPFakerAA; do
        if [ -f "$STAGE/${n}.plist" ]; then
          cp -f "$STAGE/${n}.plist" "$INJ/${n}.plist" 2>/dev/null || true
          chmod 644 "$INJ/${n}.plist" 2>/dev/null || true
          chown root:wheel "$INJ/${n}.plist" 2>/dev/null || true
        fi
      done
      # Force About* → Preferences only (never copy multi-app stage About)
      ABOUT_XML='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Filter</key><dict><key>Bundles</key><array><string>com.apple.Preferences</string></array><key>Mode</key><string>Any</string></dict></dict></plist>'
      for n in iPFakerAbout iPFakerAboutUI iPFakerAboutVer; do
        # Prefer correct stage About if it already lists Preferences
        if [ -f "$STAGE/${n}.plist" ] && grep -q 'com.apple.Preferences' "$STAGE/${n}.plist" 2>/dev/null; then
          cp -f "$STAGE/${n}.plist" "$INJ/${n}.plist" 2>/dev/null || true
        else
          printf '%s\n' "$ABOUT_XML" > "$INJ/${n}.plist" 2>/dev/null || true
        fi
        chmod 644 "$INJ/${n}.plist" 2>/dev/null || true
        chown root:wheel "$INJ/${n}.plist" 2>/dev/null || true
      done
    done
    if [ -f "$STAGE/spoof_apps.json" ]; then
      cp -f "$STAGE/spoof_apps.json" /var/jb/etc/ipfaker/spoof_apps.json 2>/dev/null || true
      chown mobile:mobile /var/jb/etc/ipfaker/spoof_apps.json 2>/dev/null || true
    fi
    # Mirror stage About to Preferences-only for next Fake
    for n in iPFakerAbout iPFakerAboutUI iPFakerAboutVer; do
      if [ -f /var/jb/usr/lib/TweakInject/${n}.plist ]; then
        cp -f /var/jb/usr/lib/TweakInject/${n}.plist "$STAGE/${n}.plist" 2>/dev/null || true
      fi
    done
    if grep -q 'telegra' "$STAGE/iPFakerMG.plist" 2>/dev/null; then
      if grep -q 'telegra' /var/jb/usr/lib/TweakInject/iPFakerMG.plist 2>/dev/null; then
        log "filter LIVE: Telegram inject OK"
      else
        log "WARN filter LIVE: Telegram missing after sync"
      fi
    fi
    if grep -q 'com.apple.Preferences' /var/jb/usr/lib/TweakInject/iPFakerAbout.plist 2>/dev/null; then
      log "filter LIVE About: Preferences OK"
    else
      log "WARN filter LIVE About: missing Preferences — Settings identity desync"
    fi
    log "filter LIVE MG bundles: $(grep -oE 'ph\\.[^<]+|vn\\.[^<]+|com\\.[^<]+' /var/jb/usr/lib/TweakInject/iPFakerMG.plist 2>/dev/null | tr '\\n' ' ')"
  else
    log "filter sync skip (no stage iPFakerMG.plist — Fake must write filters first)"
  fi
fi

VERIFY_OK=1
if [ "$VERIFY" -eq 1 ]; then
  if [ -f "$STAGE/wipe_hit_$TS.txt" ]; then
    sort -u "$STAGE/wipe_hit_$TS.txt" | while IFS= read -r c; do
      case "$c" in */Data/Application/*) ;; *) continue ;; esac
      deep=$(find "$c/Documents" "$c/Library" "$c/tmp" -type f 2>/dev/null | wc -l | tr -d ' ')
      log "verify container=$c deep_files=$deep"
      if [ "${deep:-0}" -gt 0 ]; then
        echo 0 > "$STAGE/wipe_verify_fail_$TS"
      fi
    done
  fi
  [ -f "$STAGE/wipe_verify_fail_$TS" ] && VERIFY_OK=0
else
  log "verify-fast skipped deep scan (use --verify)"
fi

rm -f "$NEEDLE_FILE" "$EXTRA_NEEDLE_FILE" "$KILL_MAP" "$EXE_MAP" \
  "$STAGE/wipe_hit_$TS.txt" "$STAGE/wipe_hit_p2_$TS.txt" "$STAGE/wipe_count_$TS.txt" \
  "$STAGE/wipe_verify_fail_$TS" 2>/dev/null || true

END_SEC=$(date +%s 2>/dev/null || echo 0)
ELAPSED=0
if [ "$START_SEC" -gt 0 ] 2>/dev/null && [ "$END_SEC" -gt 0 ] 2>/dev/null; then
  ELAPSED=$((END_SEC - START_SEC))
fi

log "==== wipe_apps done wiped=$WIPED found=$FOUND verify_ok=$VERIFY_OK has_third=$HAS_THIRD elapsed=${ELAPSED}s log=$LOG_FILE ===="
echo "OK wipe_apps wiped=$WIPED found=$FOUND verify_ok=$VERIFY_OK elapsed=${ELAPSED}s log=$LOG_FILE"
[ "${FOUND:-0}" -eq 0 ] && exit 4
[ "$VERIFY" -eq 1 ] && [ "$VERIFY_OK" -eq 0 ] && exit 5
exit 0
