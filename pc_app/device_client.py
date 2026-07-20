#!/usr/bin/env python3
"""SSH client for controlling iPFaker on a jailbroken iPhone (Wi‑Fi / USB network)."""
from __future__ import annotations

import io
import json
import re
import time
from dataclasses import dataclass
from typing import Callable

try:
    import paramiko
except ImportError as e:  # pragma: no cover
    raise SystemExit("Cần cài paramiko: pip install paramiko") from e

STAGE = "/var/mobile/Library/iPFaker"
ETC = "/var/jb/etc/ipfaker"
BACKUP_BASE = f"{STAGE}/backups"
WIPE_BIN = "/var/jb/usr/libexec/ipfaker-wipe-zalo"
WIPE_SH = f"{STAGE}/wipe_zalo.sh"

LogFn = Callable[[str], None]


@dataclass
class DeviceStatus:
    ok: bool
    package: str = ""
    marketing: str = ""
    product_type: str = ""
    ios: str = ""
    build: str = ""
    serial: str = ""
    model: str = ""
    imei: str = ""
    idfv: str = ""
    message: str = ""


class DeviceClient:
    def __init__(
        self,
        host: str,
        password: str,
        user: str = "mobile",
        port: int = 22,
        log: LogFn | None = None,
    ):
        self.host = host.strip()
        self.password = password
        self.user = user.strip() or "mobile"
        self.port = int(port)
        self.log = log or (lambda _s: None)
        self._client: paramiko.SSHClient | None = None

    def connect(self, timeout: float = 20) -> None:
        self.close()
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.log(f"Đang kết nối {self.user}@{self.host}:{self.port}…")
        c.connect(
            self.host,
            port=self.port,
            username=self.user,
            password=self.password,
            timeout=timeout,
            allow_agent=False,
            look_for_keys=False,
            banner_timeout=timeout,
            auth_timeout=timeout,
        )
        self._client = c
        self.log("Đã kết nối SSH.")

    def close(self) -> None:
        if self._client:
            try:
                self._client.close()
            except Exception:
                pass
            self._client = None

    @property
    def connected(self) -> bool:
        if not self._client:
            return False
        t = self._client.get_transport()
        return bool(t and t.is_active())

    def _require(self) -> paramiko.SSHClient:
        if not self.connected:
            raise RuntimeError("Chưa kết nối SSH. Bấm «Kết nối» trước.")
        assert self._client is not None
        return self._client

    def run(self, cmd: str, sudo: bool = False, timeout: int = 120) -> str:
        c = self._require()
        if sudo:
            full = f"echo {self._shell_quote(self.password)} | sudo -S -p '' {cmd}"
        else:
            full = cmd
        _, stdout, stderr = c.exec_command(full, timeout=timeout)
        out = stdout.read().decode(errors="replace")
        err = stderr.read().decode(errors="replace")
        # drop sudo password noise
        lines = []
        for line in (out + err).splitlines():
            if "password" in line.lower() and "sudo" in line.lower():
                continue
            lines.append(line)
        return "\n".join(lines).strip()

    @staticmethod
    def _shell_quote(s: str) -> str:
        return "'" + s.replace("'", "'\"'\"'") + "'"

    def put_bytes(self, data: bytes, remote: str) -> None:
        c = self._require()
        sftp = c.open_sftp()
        try:
            parent = remote.rsplit("/", 1)[0]
            self.run(f"mkdir -p {parent}", sudo=True)
            # write via mobile-writable stage then sudo cp if needed
            tmp = f"{STAGE}/.pc_upload_tmp"
            self.run(f"mkdir -p {STAGE}", sudo=True)
            self.run(f"chown mobile:mobile {STAGE} 2>/dev/null || true", sudo=True)
            bio = io.BytesIO(data)
            sftp.putfo(bio, tmp)
            if remote != tmp:
                self.run(f"cp -f {tmp} {remote}; chmod 644 {remote}", sudo=True)
        finally:
            sftp.close()

    def get_text(self, remote: str, max_bytes: int = 2_000_000) -> str:
        c = self._require()
        sftp = c.open_sftp()
        try:
            with sftp.open(remote, "rb") as f:
                return f.read(max_bytes).decode(errors="replace")
        finally:
            sftp.close()

    def fetch_status(self) -> DeviceStatus:
        try:
            pkg = self.run("dpkg -l | grep -i ipfaker || true", sudo=True)
            pkg_line = ""
            for line in pkg.splitlines():
                if "ipfaker" in line.lower():
                    pkg_line = " ".join(line.split())
                    break
            # Prefer jb config (what Zalo reads)
            cfg = ""
            for path in (f"{ETC}/config.plist", f"{STAGE}/config.plist"):
                try:
                    cfg = self.get_text(path)
                    if cfg.strip():
                        break
                except Exception:
                    continue
            keys = self._parse_plist_strings(cfg)

            def g(*names: str) -> str:
                for n in names:
                    if keys.get(n):
                        return keys[n]
                return ""

            return DeviceStatus(
                ok=True,
                package=pkg_line or "(chưa thấy com.ipfaker)",
                marketing=g("MarketingName"),
                product_type=g("ProductType"),
                ios=g("ProductVersion"),
                build=g("BuildVersion", "ProductBuildVersion"),
                serial=g("SerialNumber"),
                model=g("ModelNumber", "PartNumber"),
                imei=g("InternationalMobileEquipmentIdentity", "IMEI"),
                idfv=g("IDFV", "identifierForVendor"),
                message="OK",
            )
        except Exception as e:
            return DeviceStatus(ok=False, message=str(e))

    @staticmethod
    def _parse_plist_strings(xml: str) -> dict[str, str]:
        """Minimal key/string|integer|true|false extraction from XML plist."""
        out: dict[str, str] = {}
        if not xml:
            return out
        # split by <key>
        parts = re.split(r"<key>([^<]+)</key>", xml)
        # parts[0]=preamble, then key, value, key, value…
        i = 1
        while i + 1 < len(parts):
            key = parts[i].strip()
            val_block = parts[i + 1]
            i += 2
            m = re.search(
                r"<(string|integer)>([^<]*)</\1>|<true\s*/>|<false\s*/>",
                val_block,
                re.I,
            )
            if not m:
                continue
            if m.group(0).lower().startswith("<true"):
                out[key] = "true"
            elif m.group(0).lower().startswith("<false"):
                out[key] = "false"
            else:
                out[key] = m.group(2)
        return out

    def deploy_config(self, plist_text: str, active_json: str | dict) -> str:
        if isinstance(active_json, dict):
            active_json = json.dumps(active_json, indent=2, ensure_ascii=False) + "\n"
        self.log("Ghi config lên máy…")
        self.run(f"mkdir -p {STAGE} {ETC}", sudo=True)
        self.run(f"chown -R mobile:mobile {STAGE} {ETC} 2>/dev/null || true", sudo=True)
        self.put_bytes(plist_text.encode("utf-8"), f"{STAGE}/config.plist")
        self.put_bytes(active_json.encode("utf-8"), f"{STAGE}/active_profile.json")
        # jb path first (Zalo reads this)
        out = self.run(
            f"cp -f {STAGE}/config.plist {ETC}/config.plist; "
            f"cp -f {STAGE}/active_profile.json {ETC}/active_profile.json; "
            f"chmod 644 {ETC}/config.plist {ETC}/active_profile.json {STAGE}/config.plist; "
            f"chown mobile:mobile {ETC}/config.plist {ETC}/active_profile.json 2>/dev/null || true; "
            f"grep -A1 MarketingName {ETC}/config.plist; grep -A1 ProductVersion {ETC}/config.plist",
            sudo=True,
        )
        self.log(out or "Config đã ghi.")
        return out

    def kill_apps(self, names: list[str] | None = None) -> str:
        names = names or ["Zalo", "zalo", "ZaloShare", "NotificationService", "Maps", "Weather"]
        cmds = " ; ".join(f"killall -9 {n} 2>/dev/null || true" for n in names)
        return self.run(cmds, sudo=True)

    def wipe_apps(self, bundle_ids: list[str], skip_keychain: bool = False) -> str:
        """Wipe app data via packaged script + container rm best-effort."""
        self.log(f"Xóa data {len(bundle_ids)} app…")
        logs: list[str] = []
        for bid in bundle_ids:
            self.kill_apps()
            # Prefer wipe helper for zalo
            if "zalo" in bid.lower() and not skip_keychain:
                script = WIPE_BIN
                chk = self.run(f"test -x {WIPE_BIN} && echo OK || test -f {WIPE_SH} && echo SH || echo NO", sudo=True)
                if "OK" in chk:
                    logs.append(self.run(f"{WIPE_BIN} --bundle {bid} 2>&1 | tail -40", sudo=True, timeout=180))
                    continue
                if "SH" in chk:
                    logs.append(self.run(f"sh {WIPE_SH} --bundle {bid} 2>&1 | tail -40", sudo=True, timeout=180))
                    continue
            logs.append(self._wipe_bundle_containers(bid, skip_keychain=skip_keychain))
        return "\n".join(x for x in logs if x)

    def _wipe_bundle_containers(self, bid: str, skip_keychain: bool = False) -> str:
        # Find data containers via metadata / path name
        script = f"""
set +e
BID={self._shell_quote(bid)}
TOKEN=$(echo "$BID" | awk -F. '{{print $NF}}')
killall -9 Zalo 2>/dev/null
# Data Application
for d in /var/mobile/Containers/Data/Application/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -q "$BID" "$meta" 2>/dev/null || grep -qi "$TOKEN" "$meta" 2>/dev/null; then
    rm -rf "$d/Documents"/* "$d/Library"/* "$d/tmp"/* 2>/dev/null
    find "$d" -mindepth 1 -maxdepth 3 -type f -delete 2>/dev/null
    echo "wiped data $d"
  fi
done
# App Group
for d in /var/mobile/Containers/Shared/AppGroup/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -qi "zalo\\|zing" "$meta" 2>/dev/null || grep -q "$BID" "$meta" 2>/dev/null; then
    rm -rf "$d"/* 2>/dev/null
    echo "wiped group $d"
  fi
done
rm -f /var/mobile/Library/Preferences/${{BID}}.plist 2>/dev/null
rm -f /var/mobile/Library/Cookies/${{BID}}.binarycookies 2>/dev/null
echo DONE_$BID
"""
        return self.run(f"bash -lc {self._shell_quote(script)}", sudo=True, timeout=180)

    def backup_apps(self, bundle_ids: list[str]) -> str:
        """Backup device config + app containers → returns backup root path."""
        ts = str(int(time.time()))
        root = f"{BACKUP_BASE}/{ts}"
        self.log(f"Sao lưu → {root}")
        self.run(f"mkdir -p {root}/device {root}/apps {BACKUP_BASE}/latest/device {BACKUP_BASE}/latest/apps", sudo=True)
        self.run(
            f"cp -f {ETC}/config.plist {root}/device/ 2>/dev/null; "
            f"cp -f {ETC}/active_profile.json {root}/device/ 2>/dev/null; "
            f"cp -f {STAGE}/config.plist {root}/device/ 2>/dev/null; "
            f"cp -f {STAGE}/active_profile.json {root}/device/ 2>/dev/null; "
            f"cp -f {root}/device/* {BACKUP_BASE}/latest/device/ 2>/dev/null; true",
            sudo=True,
        )
        self.kill_apps()
        time.sleep(0.4)
        for bid in bundle_ids:
            self._backup_one_app(bid, f"{root}/apps/{bid}")
            self.run(
                f"mkdir -p {BACKUP_BASE}/latest/apps; "
                f"rm -rf {BACKUP_BASE}/latest/apps/{bid}; "
                f"cp -a {root}/apps/{bid} {BACKUP_BASE}/latest/apps/ 2>/dev/null; true",
                sudo=True,
                timeout=180,
            )
        self.run(f"echo {root} > {BACKUP_BASE}/LAST_BACKUP_PATH.txt", sudo=True)
        self.run(f"chown -R mobile:mobile {BACKUP_BASE} 2>/dev/null || true", sudo=True)
        return root

    def _backup_one_app(self, bid: str, dest: str) -> None:
        script = f"""
set +e
BID={self._shell_quote(bid)}
DEST={self._shell_quote(dest)}
mkdir -p "$DEST/data" "$DEST/groups" "$DEST/crumbs"
i=0
for d in /var/mobile/Containers/Data/Application/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -q "$BID" "$meta" 2>/dev/null; then
    mkdir -p "$DEST/data/c$i"
    cp -a "$d/." "$DEST/data/c$i/" 2>/dev/null
    # drop metadata from copy noise ok
    echo "bak data $d -> c$i"
    i=$((i+1))
  fi
done
g=0
TOKEN=$(echo "$BID" | awk -F. '{{print $NF}}')
for d in /var/mobile/Containers/Shared/AppGroup/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -q "$BID" "$meta" 2>/dev/null || grep -qi "zalo\\|zing" "$meta" 2>/dev/null; then
    mkdir -p "$DEST/groups/g$g"
    cp -a "$d/." "$DEST/groups/g$g/" 2>/dev/null
    echo "bak group $d -> g$g"
    g=$((g+1))
  fi
done
cp -f "/var/mobile/Library/Preferences/${{BID}}.plist" "$DEST/crumbs/" 2>/dev/null
cp -f "/var/mobile/Library/Cookies/${{BID}}.binarycookies" "$DEST/crumbs/" 2>/dev/null
echo BAK_OK
"""
        out = self.run(f"bash -lc {self._shell_quote(script)}", sudo=True, timeout=300)
        self.log(out[-500:] if out else f"backup {bid}")

    def restore_apps(self, backup_root: str, bundle_ids: list[str]) -> str:
        self.log(f"Khôi phục từ {backup_root}")
        self.kill_apps()
        time.sleep(0.3)
        logs = []
        for bid in bundle_ids:
            script = f"""
set +e
BID={self._shell_quote(bid)}
SRC={self._shell_quote(backup_root)}/apps/$BID
[ -d "$SRC" ] || {{ echo "NO_BAK $BID"; exit 0; }}
i=0
for d in /var/mobile/Containers/Data/Application/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -q "$BID" "$meta" 2>/dev/null; then
    SLOT="$SRC/data/c$i"
    if [ -d "$SLOT" ]; then
      # clear content then restore (keep container UUID)
      find "$d" -mindepth 1 -maxdepth 1 ! -name '.com.apple.mobile_container_manager.metadata.plist' -exec rm -rf {{}} + 2>/dev/null
      cp -a "$SLOT"/. "$d"/ 2>/dev/null
      echo "restored data c$i -> $d"
    fi
    i=$((i+1))
  fi
done
g=0
for d in /var/mobile/Containers/Shared/AppGroup/*; do
  [ -d "$d" ] || continue
  meta="$d/.com.apple.mobile_container_manager.metadata.plist"
  if grep -q "$BID" "$meta" 2>/dev/null || grep -qi "zalo\\|zing" "$meta" 2>/dev/null; then
    SLOT="$SRC/groups/g$g"
    if [ -d "$SLOT" ]; then
      find "$d" -mindepth 1 -maxdepth 1 ! -name '.com.apple.mobile_container_manager.metadata.plist' -exec rm -rf {{}} + 2>/dev/null
      cp -a "$SLOT"/. "$d"/ 2>/dev/null
      echo "restored group g$g -> $d"
    fi
    g=$((g+1))
  fi
done
if [ -f "$SRC/crumbs/${{BID}}.plist" ]; then
  cp -f "$SRC/crumbs/${{BID}}.plist" "/var/mobile/Library/Preferences/${{BID}}.plist" 2>/dev/null
fi
echo REST_OK_$BID
"""
            logs.append(self.run(f"bash -lc {self._shell_quote(script)}", sudo=True, timeout=300))
        return "\n".join(logs)

    def open_zalo(self) -> str:
        return self.run(
            "uiopen 'zalo://' 2>/dev/null || "
            "uiopen 'https://zalo.me' 2>/dev/null || "
            "open com.apple.mobilesafari 2>/dev/null || true",
            sudo=True,
        )

    def open_ipfaker(self) -> str:
        # Bundle id of iPFaker.app may vary; try common launch
        return self.run(
            "uiopen 'ipfaker://' 2>/dev/null; "
            "ls /var/jb/Applications/iPFaker.app 2>/dev/null; "
            "true",
            sudo=True,
        )

    def list_installed_apps_hint(self) -> str:
        return self.run(
            "ls /var/containers/Bundle/Application 2>/dev/null | head -5; "
            "echo '---'; "
            "find /var/containers/Bundle/Application -name Info.plist 2>/dev/null | "
            "xargs grep -l CFBundleIdentifier 2>/dev/null | head -3 || true",
            sudo=True,
            timeout=60,
        )
