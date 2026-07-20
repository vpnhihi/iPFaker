#!/usr/bin/env python3
"""
Select an iPhone lab profile from device_catalog.json and write:
  - config/config.plist  (HIOS flat for iPFakerMG/CT)
  - config/active_profile.json
  - config/selected_profile.json (snapshot)

Usage:
  python scripts/select_device_profile.py --list
  python scripts/select_device_profile.py --list-ios
  python scripts/select_device_profile.py --device iphone15-pro --ios 18.5
  python scripts/select_device_profile.py --device "iPhone 16 Pro Max" --ios 17.6.1
  python scripts/select_device_profile.py --device iphone17-pro-max --ios 19.0 --name "Lab Max"
  python scripts/select_device_profile.py --random
  python scripts/select_device_profile.py --device iphone14-pro --ios 16.7.10 --deploy
"""
from __future__ import annotations

import argparse
import json
import random
import re
import string
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "config" / "device_catalog.json"
OUT_PLIST = ROOT / "config" / "config.plist"
OUT_ACTIVE = ROOT / "config" / "active_profile.json"
OUT_SELECTED = ROOT / "config" / "selected_profile.json"


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def find_device(cat: dict, query: str) -> dict | None:
    q = norm(query)
    devices = cat["devices"]
    for d in devices:
        if d["id"] == query or norm(d["id"]) == q:
            return d
        if norm(d["MarketingName"]) == q:
            return d
        if d["ProductType"].lower() == query.lower():
            return d
    # partial
    hits = [
        d
        for d in devices
        if q in norm(d["id"]) or q in norm(d["MarketingName"]) or q in norm(d["ProductType"])
    ]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        print("Ambiguous device, matches:", file=sys.stderr)
        for d in hits:
            print(f"  {d['id']:22} {d['MarketingName']:28} {d['ProductType']}", file=sys.stderr)
        return None
    return None


def list_devices(cat: dict) -> None:
    print(f"{'ID':22} {'MarketingName':30} {'ProductType':12} {'RAM':>5}  Screen        Chip")
    print("-" * 100)
    for d in cat["devices"]:
        disp = d["display"]
        print(
            f"{d['id']:22} {d['MarketingName'][:30]:30} {d['ProductType']:12} "
            f"{d['PhysicalMemoryMB']:>5}  {disp['NativeWidth']}x{disp['NativeHeight']}@{disp['ScreenScale']}  {d['chip']}"
        )
    print(f"\nTotal devices: {len(cat['devices'])}")
    print("iOS builds in catalog:", len(cat["ios_releases"]))


def list_ios(cat: dict) -> None:
    for ver, meta in cat["ios_releases"].items():
        lab = " [lab]" if meta.get("lab") else ""
        print(f"  {ver:10}  build={meta['BuildVersion']}{lab}")


def random_serial() -> str:
    # 12-char alphanumeric serial-like
    alphabet = string.ascii_uppercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(12))


def random_mac() -> str:
    parts = [0xF0, 0x18, 0x98] + [random.randint(0, 255) for _ in range(3)]
    return ":".join(f"{b:02X}" for b in parts)


def random_imei() -> str:
    # 15 digits, Luhn-ish lab only
    body = "35" + "".join(str(random.randint(0, 9)) for _ in range(12))
    return body[:15]


def clamp_ios(device: dict, ios: str | None, cat: dict) -> tuple[str, dict]:
    releases = cat["ios_releases"]
    if ios is None:
        ios = device.get("defaultIOS") or "18.5"
    if ios not in releases:
        # try prefix match latest
        cands = [k for k in releases if k.startswith(ios)]
        if cands:
            ios = sorted(cands, key=lambda x: [int(p) for p in x.split(".")])[-1]
        else:
            raise SystemExit(f"Unknown iOS version: {ios}. Use --list-ios")
    # soft warn range
    def ver_tuple(v: str):
        return tuple(int(x) for x in v.split(".")[:3])

    try:
        vt = ver_tuple(ios)
        if device.get("minIOS") and vt < ver_tuple(device["minIOS"]):
            print(f"WARN: {device['MarketingName']} rarely runs iOS {ios} (min ~{device['minIOS']})", file=sys.stderr)
        if device.get("maxIOS") and vt > ver_tuple(device["maxIOS"].split(".")[0] + ".99.99" if device["maxIOS"].count(".") == 0 else device["maxIOS"]):
            # simple: compare major
            if int(ios.split(".")[0]) > int(device["maxIOS"].split(".")[0]):
                print(f"WARN: {device['MarketingName']} lab maxIOS={device['maxIOS']}, you chose {ios}", file=sys.stderr)
    except Exception:
        pass
    return ios, releases[ios]


def build_profile(device: dict, ios_ver: str, ios_meta: dict, name: str | None) -> dict:
    disp = device["display"]
    ram_mb = int(device["PhysicalMemoryMB"])
    ram_bytes = ram_mb * 1024 * 1024
    wifi = random_mac()
    bt_parts = wifi.split(":")
    bt_parts[-1] = f"{(int(bt_parts[-1], 16) ^ 1) & 0xFF:02X}"
    bluetooth = ":".join(bt_parts)
    idfv = str(uuid.uuid4()).upper()
    idfa = str(uuid.uuid4()).upper()
    udid = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    serial = random_serial()
    imei = random_imei()
    imei2 = imei[:-1] + str((int(imei[-1]) + 1) % 10)
    dev_name = name or f"iPhone Lab {device['id']}"

    flat = {
        "Enabled": True,
        "ProductType": device["ProductType"],
        "MarketingName": device["MarketingName"],
        "DeviceName": "iPhone",
        "UserAssignedDeviceName": dev_name,
        "HWModelStr": device["HWModelStr"],
        "HardwareModel": device["HWModelStr"],
        "ModelNumber": device.get("ModelNumber", ""),
        "RegionInfo": "VN/A",
        "RegionCode": "VN",
        "RegulatoryModelNumber": device.get("RegulatoryModelNumber", ""),
        "HardwarePlatform": device.get("HardwarePlatform", ""),
        "CPUArchitecture": device.get("CPUArchitecture", "arm64e"),
        "DeviceClass": "iPhone",
        "SerialNumber": serial,
        "UniqueDeviceID": udid,
        "UniqueChipID": f"{random.randint(0, 0xFFFFFFFFFFFFFFFF):016X}",
        "ProductVersion": ios_meta["ProductVersion"],
        "BuildVersion": ios_meta["BuildVersion"],
        "ProductBuildVersion": ios_meta["BuildVersion"],
        "IDFA": idfa,
        "IDFV": idfv,
        "identifierForVendor": idfv,
        "InternationalMobileEquipmentIdentity": imei,
        "InternationalMobileEquipmentIdentity2": imei2,
        "MobileEquipmentIdentifier": imei[:14],
        "WifiAddress": wifi,
        "BluetoothAddress": bluetooth,
        "EthernetMacAddress": wifi,
        "carrierName": "Viettel",
        "carrierMCC": "452",
        "carrierMNC": "04",
        "carrierISO": "vn",
        "carrierRadioAccess": "CTRadioAccessTechnologyNR",
        "CarrierName": "Viettel",
        "MobileCountryCode": "452",
        "MobileNetworkCode": "04",
        "ISOCountryCode": "vn",
        "main-screen-width": int(disp["NativeWidth"]),
        "main-screen-height": int(disp["NativeHeight"]),
        "main-screen-scale": int(disp["ScreenScale"]),
        "main-screen-pitch": int(disp.get("Pitch", 460)),
        # extra for hooks
        "PhysicalMemoryMB": ram_mb,
        "PhysicalMemoryBytes": ram_bytes,
        "hw.memsize": ram_bytes,
        "hw.ncpu": int(device.get("cpuCores", 6)),
        "hw.physicalcpu": int(device.get("cpuCores", 6)),
        "hw.logicalcpu": int(device.get("cpuCores", 6)),
        "ChipName": device.get("chip", ""),
        "DeviceCatalogId": device["id"],
    }

    active = {
        "schema": "ipfaker.active_profile/2",
        "generated_from": "device_catalog.json",
        "device_id": device["id"],
        "ios": ios_ver,
        "model": {
            "ProductType": device["ProductType"],
            "MarketingName": device["MarketingName"],
            "HWModelStr": device["HWModelStr"],
            "HardwareModel": device["HWModelStr"],
            "ModelNumber": device.get("ModelNumber", ""),
            "RegulatoryModelNumber": device.get("RegulatoryModelNumber", ""),
            "HardwarePlatform": device.get("HardwarePlatform", ""),
            "CPUArchitecture": device.get("CPUArchitecture", "arm64e"),
            "DeviceName": "iPhone",
            "UserAssignedDeviceName": dev_name,
            "ChipName": device.get("chip", ""),
            "PhysicalMemoryMB": ram_mb,
        },
        "os": {
            "ProductVersion": ios_meta["ProductVersion"],
            "BuildVersion": ios_meta["BuildVersion"],
        },
        "display": {
            "NativeWidth": disp["NativeWidth"],
            "NativeHeight": disp["NativeHeight"],
            "ScreenScale": disp["ScreenScale"],
            "main-screen-pitch": disp.get("Pitch", 460),
        },
        "identity": {
            "SerialNumber": serial,
            "UniqueDeviceID": udid,
            "IDFA": idfa,
            "IDFV": idfv,
            "IMEI": imei,
            "IMEI2": imei2,
        },
        "network": {
            "WifiAddress": wifi,
            "BluetoothAddress": bluetooth,
            "EthernetMacAddress": wifi,
        },
        "telephony": {
            "CarrierName": "Viettel",
            "MobileCountryCode": "452",
            "MobileNetworkCode": "04",
            "ISOCountryCode": "vn",
            "CurrentRadioAccessTechnology": "CTRadioAccessTechnologyNR",
        },
        "hooks": {
            "mobilegestalt": {
                "ProductType": device["ProductType"],
                "MarketingName": device["MarketingName"],
                "HWModelStr": device["HWModelStr"],
            },
            "sysctl": {
                "hw.machine": device["ProductType"],
                "hw.model": device["HWModelStr"],
                "hw.memsize": ram_bytes,
                "hw.ncpu": device.get("cpuCores", 6),
            },
        },
        "flat": flat,
    }
    return {"flat": flat, "active": active}


def write_plist(flat: dict, path: Path) -> None:
    def esc(s: str) -> str:
        return (
            str(s)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
        )

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        "<dict>",
    ]
    int_keys = {
        "main-screen-width",
        "main-screen-height",
        "main-screen-scale",
        "main-screen-pitch",
        "PhysicalMemoryMB",
        "PhysicalMemoryBytes",
        "hw.memsize",
        "hw.ncpu",
        "hw.physicalcpu",
        "hw.logicalcpu",
    }
    bool_keys = {"Enabled"}
    for k, v in flat.items():
        lines.append(f"  <key>{esc(k)}</key>")
        if k in bool_keys:
            lines.append("  <true/>" if v else "  <false/>")
        elif k in int_keys or isinstance(v, int):
            lines.append(f"  <integer>{int(v)}</integer>")
        else:
            lines.append(f"  <string>{esc(v)}</string>")
    lines.append("</dict>")
    lines.append("</plist>")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def deploy_to_device() -> None:
    try:
        import paramiko
    except ImportError:
        print("paramiko required for --deploy", file=sys.stderr)
        raise SystemExit(2)
    host, user, password = "[DEVICE_HOST]", "mobile", "[REDACTED]"
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, password=password, timeout=20, allow_agent=False, look_for_keys=False)
    stage = "/var/mobile/Library/iPFaker"
    etc = "/var/jb/etc/ipfaker"
    sftp = c.open_sftp()
    sftp.put(str(OUT_PLIST), f"{stage}/config.plist")
    sftp.put(str(OUT_ACTIVE), f"{stage}/active_profile.json")
    sftp.close()

    def sudo(cmd: str) -> None:
        _, o, e = c.exec_command(f"echo {password} | sudo -S -p '' {cmd}", timeout=60)
        out = o.read().decode(errors="replace")
        if out.strip():
            print(out.strip()[:500])

    sudo(f"mkdir -p {etc} {stage}")
    sudo(f"cp -f {stage}/config.plist {etc}/config.plist")
    sudo(f"cp -f {stage}/active_profile.json {etc}/active_profile.json")
    sudo(f"chmod 644 {etc}/config.plist {etc}/active_profile.json")
    sudo(f"grep -A1 ProductType {etc}/config.plist; grep -A1 MarketingName {etc}/config.plist; grep -A1 ProductVersion {etc}/config.plist")
    # soft restart Zalo so next open reloads config (if auto-inject)
    sudo("killall -9 Zalo 2>/dev/null || true")
    c.close()
    print("Deployed to device. Re-open Zalo (auto-inject if plists on).")


def main() -> int:
    ap = argparse.ArgumentParser(description="Select iPFaker device + iOS lab profile")
    ap.add_argument("--list", action="store_true", help="List all devices")
    ap.add_argument("--list-ios", action="store_true", help="List iOS versions")
    ap.add_argument("--device", "-d", help="Device id / marketing name / ProductType")
    ap.add_argument("--ios", "-i", help="iOS version e.g. 18.5, 17.6.1, 19.0")
    ap.add_argument("--name", help="UserAssignedDeviceName")
    ap.add_argument("--random", action="store_true", help="Random device + default iOS")
    ap.add_argument("--deploy", action="store_true", help="Push config.plist to phone via SSH")
    args = ap.parse_args()

    cat = load_catalog()
    if args.list:
        list_devices(cat)
        return 0
    if args.list_ios:
        list_ios(cat)
        return 0

    if args.random:
        device = random.choice(cat["devices"])
    elif args.device:
        device = find_device(cat, args.device)
        if not device:
            print(f"Device not found: {args.device}", file=sys.stderr)
            return 1
    else:
        ap.print_help()
        print("\nExamples:\n  python scripts/select_device_profile.py --list")
        print("  python scripts/select_device_profile.py -d iphone16-pro-max -i 18.5 --deploy")
        return 2

    ios_ver, ios_meta = clamp_ios(device, args.ios, cat)
    built = build_profile(device, ios_ver, ios_meta, args.name)
    write_plist(built["flat"], OUT_PLIST)
    OUT_ACTIVE.write_text(json.dumps(built["active"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    OUT_SELECTED.write_text(
        json.dumps(
            {
                "device_id": device["id"],
                "MarketingName": device["MarketingName"],
                "ProductType": device["ProductType"],
                "ios": ios_ver,
                "BuildVersion": ios_meta["BuildVersion"],
                "PhysicalMemoryMB": device["PhysicalMemoryMB"],
                "display": device["display"],
                "chip": device.get("chip"),
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    print("Selected:")
    print(f"  Device : {device['MarketingName']} ({device['id']})")
    print(f"  Type   : {device['ProductType']} / {device['HWModelStr']}")
    print(f"  Chip   : {device.get('chip')}  RAM={device['PhysicalMemoryMB']}MB  CPU={device.get('cpuCores')}")
    d = device["display"]
    print(f"  Screen : {d['NativeWidth']}x{d['NativeHeight']} @{d['ScreenScale']}  {d.get('Pitch')} ppi")
    print(f"  iOS    : {ios_ver} ({ios_meta['BuildVersion']})" + (" [lab build]" if ios_meta.get("lab") else ""))
    print(f"  Wrote  : {OUT_PLIST.relative_to(ROOT)}")
    print(f"           {OUT_ACTIVE.relative_to(ROOT)}")
    print(f"           {OUT_SELECTED.relative_to(ROOT)}")

    if args.deploy:
        deploy_to_device()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
