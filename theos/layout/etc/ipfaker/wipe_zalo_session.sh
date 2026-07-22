#!/bin/sh
# iPFaker — deep LOCAL Zalo session wipe (tokens / keychain / crumbs)
# Called from wipe_apps.sh when Zalo is in targets, or standalone:
#   sh wipe_zalo_session.sh
#   sh wipe_zalo_session.sh --dry-run
#
# Scope: device-local only (owned JB lab). Removes:
#   - Keychain genp/inet/keys for Zalo agrps (team CVB6BX97VM + zalo patterns)
#   - WebKit, HTTPStorages, snapshots, crash crumbs (optional light)
#   - NEVER delete AppManager /var/mobile/Library/ADManager/*.adbk (user backups)
#   - Ensures sqlite3 available path for purge
#
# Does NOT and cannot erase VNG server account history / risk scores.
# After this + container wipe + spoof identity, local app behaves as first install.

set -e

DRY=0
LOG_DIR="/var/mobile/Library/iPFaker/logs"
TS=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)
STAGE="/var/mobile/Library/iPFaker"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      exit 0
      ;;
    *) echo "Unknown: $1"; exit 2 ;;
  esac
done

mkdir -p "$LOG_DIR" "$STAGE" 2>/dev/null || true
LOG_FILE="$LOG_DIR/wipe_zalo_session_$TS.log"

log() {
  echo "[iPFaker-zalo-session] $*"
  echo "[iPFaker-zalo-session] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log "==== zalo session wipe start dry=$DRY ===="

# Kill Zalo family
if [ "$DRY" -eq 0 ]; then
  for n in Zalo zalo ZaloShare NotificationService NotificationServiceExtension \
           vn.com.vng.zingalo; do
    killall -9 "$n" 2>/dev/null || true
  done
  sleep 0.1 2>/dev/null || true
fi

# ── Extra local crumbs (beyond container wipe) ─────────────
if [ "$DRY" -eq 0 ]; then
  for bid in vn.com.vng.zingalo com.zing.zalo; do
    rm -rf \
      "/var/mobile/Library/Preferences/${bid}.plist" \
      "/var/mobile/Library/Cookies/${bid}.binarycookies" \
      "/var/mobile/Library/HTTPStorages/${bid}" \
      "/var/mobile/Library/Caches/${bid}" \
      "/var/mobile/Library/WebKit/WebsiteData/Default/${bid}" \
      "/var/mobile/Library/WebKit/WebsiteData"/*/"${bid}" \
      2>/dev/null || true
    for p in /var/mobile/Library/SplashBoard/Snapshots/sceneID:"${bid}"*; do
      [ -e "$p" ] && rm -rf "$p" 2>/dev/null || true
    done
  done
  # AppManager stores Zalo backups under ADManager/*.adbk + Backups.plist
  # DO NOT rm ADManager — «Đặt lại dữ liệu» would destroy user AppManager saves (0 B list)
  # Saved app state / frontboard
  rm -rf /var/mobile/Library/Saved Application State/vn.com.vng.zingalo* \
         /var/mobile/Library/Saved\ Application\ State/vn.com.vng.zingalo* \
         2>/dev/null || true
  # User notifications delivery store (bundle-scoped if present)
  find /var/mobile/Library/UserNotifications -iname '*zingalo*' -maxdepth 3 2>/dev/null \
    | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
  # Clipboard / pasteboard cache (OTP, phone numbers — lab reset)
  rm -rf /var/mobile/Library/Caches/com.apple.Pasteboard/* 2>/dev/null || true
  # Attribution / analytics SDK prefs (install-id residual after container wipe)
  for pref in /var/mobile/Library/Preferences/*; do
    bn=$(basename "$pref" 2>/dev/null)
    case "$bn" in
      *appsflyer*|*AppsFlyer*|*firebase*|*Firebase*|*crashlytics*|*Crashlytics* \
      |*google.analytics*|*GoogleAnalytics*|*adjust.com*|*Adjust* \
      |*com.google.gmp*|*com.google.uid*|*amplitude*|*mixpanel*)
        # Only remove if clearly Zalo-related or generic vendor store under mobile prefs
        case "$bn" in
          *zalo*|*zing*|*vng*|*appsflyer*|*firebase*|*crashlytics*|*adjust*)
            rm -f "$pref" 2>/dev/null || true
            ;;
        esac
        ;;
    esac
  done
  rm -f /var/mobile/Library/Preferences/com.appsflyer.* \
        /var/mobile/Library/Preferences/com.google.gmp.measurement.* \
        /var/mobile/Library/Preferences/com.google.uid.* 2>/dev/null || true
  # Caches for attribution
  rm -rf /var/mobile/Library/Caches/com.appsflyer* \
         /var/mobile/Library/Caches/*AppsFlyer* \
         /var/mobile/Library/Caches/com.google.firebase* 2>/dev/null || true
  # CloudKit / iCloud local for Zalo container id (best-effort)
  find /var/mobile/Library/Caches/CloudKit -iname '*zingalo*' 2>/dev/null \
    | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
  find /var/mobile/Library/Application\ Support -iname '*zingalo*' -maxdepth 3 2>/dev/null \
    | while IFS= read -r p; do rm -rf "$p" 2>/dev/null || true; done
  # CrashReporter Zalo dumps (device FP noise)
  rm -f /var/mobile/Library/Logs/CrashReporter/*Zalo* \
        /var/mobile/Library/Logs/CrashReporter/*zalo* 2>/dev/null || true
  # APS push topic best-effort (below with sqlite)
  log "crumbs: prefs/http/admanager/snapshots/sdk/pasteboard cleaned"
fi

# ── Keychain deep purge ────────────────────────────────────
find_sqlite() {
  for s in /var/jb/usr/bin/sqlite3 /var/jb/bin/sqlite3 /usr/bin/sqlite3 \
           /var/jb/usr/local/bin/sqlite3; do
    if [ -x "$s" ]; then
      echo "$s"
      return 0
    fi
  done
  # last resort: find (slow, once)
  f=$(find /var/jb -type f -name sqlite3 2>/dev/null | head -1)
  [ -n "$f" ] && [ -x "$f" ] && echo "$f" && return 0
  return 1
}

KC_DB=""
for p in /var/Keychains/keychain-2.db /private/var/Keychains/keychain-2.db; do
  [ -f "$p" ] && KC_DB="$p" && break
done

SQLITE=$(find_sqlite 2>/dev/null || true)
if [ -z "$SQLITE" ]; then
  log "WARN: sqlite3 CLI missing — keychain session NOT purged"
  log "TIP: apt-get install -y sqlite3  (procursus) then re-run wipe"
  echo "WARN no-sqlite3 keychain skipped" >> "$LOG_FILE"
else
  log "sqlite=$SQLITE kc=$KC_DB"
  if [ "$DRY" -eq 1 ]; then
    if [ -n "$KC_DB" ]; then
      n=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM genp WHERE agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%';" 2>/dev/null || echo 0)
      log "DRY genp zalo-ish rows=$n"
    fi
  else
    # Pause securityd writers briefly for clean DELETE + WAL
    killall -STOP securityd 2>/dev/null || true
    # WHERE: team-scoped Zalo agrps + classic patterns
    # Lab measured agrps:
    #   CVB6BX97VM.group.keychain.vn.com.vng.zalo
    #   CVB6BX97VM.vn.com.vng.zingalo.notificationserviceextension
    WHERE="agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%' OR agrp LIKE '%zing.zalo%' OR svce LIKE '%zalo%' OR acct LIKE '%zalo%' OR svce LIKE '%zingalo%' OR acct LIKE '%zingalo%'"

    BEFORE=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM genp WHERE $WHERE;" 2>>"$LOG_FILE" || echo 0)
    BEFORE=$(echo "$BEFORE" | tr -cd '0-9')
    [ -z "$BEFORE" ] && BEFORE=0
    log "keychain genp before=$BEFORE"

    "$SQLITE" "$KC_DB" "DELETE FROM genp WHERE $WHERE;" 2>>"$LOG_FILE" || true
    # inet has agrp/acct/srvr — no svce column on modern iOS keychain-2.db
    INET_WHERE="agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%' OR agrp LIKE '%zing.zalo%' OR acct LIKE '%zalo%' OR acct LIKE '%zingalo%' OR srvr LIKE '%zalo%' OR srvr LIKE '%zing.vn%' OR srvr LIKE '%zalo.me%'"
    "$SQLITE" "$KC_DB" "DELETE FROM inet WHERE $INET_WHERE;" 2>>"$LOG_FILE" || true
    # keys/cert: agrp or labl
    "$SQLITE" "$KC_DB" "DELETE FROM keys WHERE agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR agrp LIKE '%zingalo%' OR labl LIKE '%zalo%' OR labl LIKE '%zingalo%';" 2>>"$LOG_FILE" || true
    "$SQLITE" "$KC_DB" "DELETE FROM cert WHERE agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%zingalo%' OR labl LIKE '%zalo%' OR labl LIKE '%zingalo%';" 2>>"$LOG_FILE" || true

    # Checkpoint WAL so securityd sees deletes after restart
    "$SQLITE" "$KC_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>>"$LOG_FILE" || true

    killall -CONT securityd 2>/dev/null || true
    # Bounce securityd so in-memory cache drops Zalo items
    killall -9 securityd 2>/dev/null || true
    sleep 0.3 2>/dev/null || sleep 1

    AFTER=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM genp WHERE $WHERE;" 2>>"$LOG_FILE" || echo 0)
    AFTER=$(echo "$AFTER" | tr -cd '0-9')
    [ -z "$AFTER" ] && AFTER=0
    KEYS_LEFT=$("$SQLITE" "$KC_DB" "SELECT COUNT(*) FROM keys WHERE agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%zingalo%';" 2>>"$LOG_FILE" || echo 0)
    KEYS_LEFT=$(echo "$KEYS_LEFT" | tr -cd '0-9')
    [ -z "$KEYS_LEFT" ] && KEYS_LEFT=0
    DELTA=$((BEFORE - AFTER))
    log "keychain genp after=$AFTER keys_left=$KEYS_LEFT (deleted ~${DELTA} genp)"
    if [ "$AFTER" -eq 0 ] 2>/dev/null; then
      log "keychain LOCAL session tokens: CLEAN"
    else
      log "WARN keychain residual genp=$AFTER"
    fi
  fi
fi

# ── APS: remove Zalo topic rows if schema allows (best-effort) ─
if [ "$DRY" -eq 0 ] && [ -n "$SQLITE" ] && [ -f /var/mobile/Library/ApplePushService/aps.db ]; then
  APS=/var/mobile/Library/ApplePushService/aps.db
  # Dump tables once; delete any row mentioning zalo across known tables
  for tbl in incoming outgoing app topics channel; do
    "$SQLITE" "$APS" "DELETE FROM $tbl WHERE topic LIKE '%zingalo%' OR topic LIKE '%zalo%' OR app LIKE '%zingalo%' OR app LIKE '%zalo%';" 2>/dev/null || true
  done
  killall -9 apsd 2>/dev/null || true
  log "aps.db zalo topic best-effort + apsd bounce"
fi

log "==== zalo session wipe done log=$LOG_FILE ===="
echo "OK wipe_zalo_session log=$LOG_FILE"
exit 0
