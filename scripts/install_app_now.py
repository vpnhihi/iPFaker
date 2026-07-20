#!/usr/bin/env python3
"""Install iPFaker.app + dylibs from CI artifact to device (bypass broken deb app path)."""
from __future__ import annotations

import io
import tarfile
import time
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parents[1]
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from _device_env import require as _dev_require
HOST, _USER, PASS = _dev_require()
APP = ROOT / "ci_artifact" / "theos" / "dist" / "app" / "iPFaker.app"
MG = ROOT / "ci_artifact" / "theos" / "dist" / "iPFakerMG.dylib"
CT = ROOT / "ci_artifact" / "theos" / "dist" / "iPFakerCT.dylib"
CATALOG = ROOT / "config" / "device_catalog.json"
REMOTE_APP = "/var/jb/Applications/iPFaker.app"
INJ = "/var/jb/usr/lib/TweakInject"
STAGE = "/var/mobile/Library/iPFaker"

ZALO_PLIST = b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Filter</key><dict>
<key>Bundles</key><array>
<string>vn.com.vng.zingalo</string>
<string>com.zing.zalo</string>
</array>
<key>Mode</key><string>Any</string>
</dict></dict></plist>
"""


def main() -> int:
    if not APP.is_dir():
        print("Missing", APP)
        return 1
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="mobile", password=PASS, timeout=25, allow_agent=False, look_for_keys=False)

    def sudo(cmd: str, t: int = 120) -> str:
        _, o, e = c.exec_command(f"echo {PASS} | sudo -S -p '' {cmd}", timeout=t)
        out = o.read().decode(errors="replace")
        print(">>", cmd[:130])
        if out.strip():
            print(out.strip()[:1800])
        return out

    sudo(f"mkdir -p {STAGE} {INJ} /var/jb/Applications /var/jb/etc/ipfaker /var/mobile/Library/iPFaker")
    sudo(f"rm -rf {REMOTE_APP}")

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(str(APP), arcname="iPFaker.app")
    buf.seek(0)
    sftp = c.open_sftp()
    with sftp.file(f"{STAGE}/iPFaker.app.tgz", "wb") as f:
        f.write(buf.read())
    if MG.exists():
        sftp.put(str(MG), f"{STAGE}/iPFakerMG.dylib")
        sftp.put(str(CT), f"{STAGE}/iPFakerCT.dylib")
    if CATALOG.exists():
        sftp.put(str(CATALOG), f"{STAGE}/device_catalog.json")
    with sftp.file(f"{STAGE}/iPFakerMG.plist", "wb") as f:
        f.write(ZALO_PLIST)
    with sftp.file(f"{STAGE}/iPFakerCT.plist", "wb") as f:
        f.write(ZALO_PLIST)
    sftp.close()

    sudo(f"tar -xzf {STAGE}/iPFaker.app.tgz -C /var/jb/Applications")
    sudo(f"chown -R root:wheel {REMOTE_APP}")
    sudo(f"chmod 755 {REMOTE_APP}/iPFaker")
    # catalog into app + etc
    sudo(f"cp -f {STAGE}/device_catalog.json {REMOTE_APP}/device_catalog.json 2>/dev/null || true")
    sudo(f"cp -f {STAGE}/device_catalog.json /var/jb/etc/ipfaker/device_catalog.json")
    sudo(f"cp -f {STAGE}/device_catalog.json /var/mobile/Library/iPFaker/device_catalog.json")
    sudo("chown mobile:mobile /var/mobile/Library/iPFaker/device_catalog.json")

    for name in ("iPFakerMG.dylib", "iPFakerCT.dylib"):
        sudo(f"ldid -S {STAGE}/{name}")
        hinfo = sudo(f"ldid -h {STAGE}/{name} 2>&1")
        for line in hinfo.splitlines():
            if "CDHash=" in line:
                h = line.split("CDHash=", 1)[1].strip().lower()[:40]
                if len(h) == 40:
                    sudo(f"/var/jb/basebin/jbctl trustcache add {h}")
        sudo(f"cp -f {STAGE}/{name} {INJ}/{name}")
        sudo(f"chmod 755 {INJ}/{name}")
    sudo(f"cp -f {STAGE}/iPFakerMG.plist {INJ}/iPFakerMG.plist")
    sudo(f"cp -f {STAGE}/iPFakerCT.plist {INJ}/iPFakerCT.plist")
    sudo(f"chmod 644 {INJ}/iPFakerMG.plist {INJ}/iPFakerCT.plist")

    # app trust
    sudo(f"ldid -S {REMOTE_APP}/iPFaker 2>&1 || true")
    hinfo = sudo(f"ldid -h {REMOTE_APP}/iPFaker 2>&1")
    for line in hinfo.splitlines():
        if "CDHash=" in line:
            h = line.split("CDHash=", 1)[1].strip().lower()[:40]
            if len(h) == 40:
                sudo(f"/var/jb/basebin/jbctl trustcache add {h}")

    sudo(f"/var/jb/usr/bin/uicache -p {REMOTE_APP} 2>&1 || uicache -p {REMOTE_APP} 2>&1 || true")
    sudo(f"ls -la {REMOTE_APP}")
    sudo(f"ls -la {INJ}/iPFaker*")
    print("\nOK — Home Screen should show iPFaker (respring if needed: sbreload)")
    print("Open app → pick model → Apply → Kill Zalo → open Zalo")
    c.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
