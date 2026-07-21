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
  python scripts/select_device_profile.py --device iphone17-pro-max --ios 26.0 --name "Lab Max"
  python scripts/select_device_profile.py --random
  python scripts/select_device_profile.py --device iphone14-pro --ios 16.7.10 --deploy
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import string
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "config" / "device_catalog.json"
COMPAT = ROOT / "config" / "ios_device_compat.json"
OUT_PLIST = ROOT / "config" / "config.plist"
OUT_ACTIVE = ROOT / "config" / "active_profile.json"
OUT_SELECTED = ROOT / "config" / "selected_profile.json"


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def load_compat() -> dict:
    if COMPAT.exists():
        return json.loads(COMPAT.read_text(encoding="utf-8"))
    return {}


def device_supported_ios(device: dict, cat: dict, compat: dict | None = None) -> list[str]:
    """iOS versions allowed for this device (strict matrix)."""
    if device.get("supportedIOS"):
        return list(device["supportedIOS"])
    did = device.get("id") or ""
    inherit = device.get("compatInherit") or did
    if compat is None:
        compat = load_compat()
    return list(compat.get("device_to_ios", {}).get(inherit, []))


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
    print(
        f"{'ID':22} {'MarketingName':28} {'ProductType':12} {'RAM':>5}  "
        f"{'Screen':16} {'Inch':>4}  {'Chip':12} Year  Battery"
    )
    print("-" * 118)
    for d in cat["devices"]:
        disp = d["display"]
        lab = " *" if d.get("lab") else ""
        inch = disp.get("DiagonalInches", "")
        bat = d.get("batteryMah") or ""
        print(
            f"{d['id']:22} {d['MarketingName'][:28]:28} {d['ProductType']:12} "
            f"{d['PhysicalMemoryMB']:>5}  "
            f"{disp['NativeWidth']}x{disp['NativeHeight']}@{disp['ScreenScale']:<2} "
            f"{str(inch):>4}  "
            f"{(d.get('chip') or ''):12} {d.get('year', ''):4}  {str(bat)+'mAh' if bat else '':>8}{lab}"
        )
    print(f"\nTotal devices: {len(cat['devices'])}  (* = lab model)")
    print("iOS builds in catalog:", len(cat["ios_releases"]))


def list_ios(cat: dict, device: dict | None = None) -> None:
    supported = set(device_supported_ios(device, cat)) if device else None
    for ver, meta in cat["ios_releases"].items():
        if supported is not None and ver not in supported:
            continue
        lab = " [lab]" if meta.get("lab") else ""
        print(f"  {ver:10}  build={meta['BuildVersion']}{lab}")
    if device:
        print(f"\nDevice: {device.get('MarketingName')} ({device.get('id')})")
        print(f"Supported builds: {len(device_supported_ios(device, cat))}")



# Identity: BOTH Part Number (Settings default) + Axxxx (tap) + max random pool.
# Hardware/catalog (ProductType, display, RAM, iOS matrix) left untouched.
#
# Formats (lab-synthetic, Apple-like — not real device dumps):
#   Serial:  no I/O/0/1; pre-2021 = 12 chars; 2021+ mostly 10 (randomised style)
#   IDFA/IDFV: RFC 4122 UUID v4 uppercase with hyphens
#   UniqueDeviceID: 40 hex (legacy UDID length / SHA-1 style)
#   UniqueChipID / ECID: 64-bit as decimal + hex alias
#   IMEI: 15 digits, real-length TAC + Luhn
#   EID: 32 decimal digits (eSIM)

_SERIAL_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no I,O,0,1
# Common factory / plant-style prefixes (public knowledge patterns, not secrets)
_SERIAL_PLANTS = (
    "C", "F", "D", "G", "H", "M", "P", "R", "S", "W",
    "CK", "F7", "DN", "F2", "G6", "FK", "YM", "C3",
)
# Part Number region codes (Settings: MU783KH/A, MT6T2J/A, LL/A, CH/A…)
_PART_REGIONS = (
    "LL",  # USA
    "J",   # Japan
    "CH",  # China
    "KH",  # Korea
    "ZA",  # Singapore / Asia (often VN grey)
    "ZP",  # HK / Macao
    "B",   # UK
    "D",   # Germany
    "F",   # France
    "T",   # Italy
    "X",   # Australia
    "Y",   # Spain
    "QN",  # Denmark
    "C",   # Canada
    "HN",  # India
    "PP",  # Philippines
    "TH",  # Thailand
    "TU",  # Turkey
    "RU",  # Russia
)
_PART_REGION_TO_CODE = {
    "LL": "US", "J": "JP", "CH": "CN", "KH": "KR", "ZA": "SG", "ZP": "HK",
    "B": "GB", "D": "DE", "F": "FR", "T": "IT", "X": "AU", "Y": "ES",
    "QN": "DK", "C": "CA", "HN": "IN", "PP": "PH", "TH": "TH",
    "TU": "TR", "RU": "RU",
}
# 8-digit Type Allocation Codes (lab pool — Apple-range style 35xxxxxx, not a real unit dump)
_IMEI_TAC = (
    "35328510", "35325809", "35672011", "35299109", "35334709",
    "35445107", "35569508", "35397710", "35925406", "35407115",
    "35316606", "35881507", "35613307", "35397711", "35407116",
    "35260908", "35328511", "35728909", "35876108", "35929006",
)
# Public Apple Ethernet/Wi‑Fi OUI prefixes (IEEE/public) — NIC random
_APPLE_OUI = (
    "F0:18:98", "A4:83:E7", "3C:22:FB", "DC:A9:04", "AC:DE:48",
    "F4:5C:89", "28:CF:E9", "D0:03:4B", "BC:52:B7", "6C:96:CF",
    "88:66:5A", "B8:63:4D", "F0:D1:A9", "A8:86:DD", "C8:69:CD",
)
_DEVICE_NAME_POOL = (
    "iPhone", "My iPhone", "iPhone Lab", "iPhone {}", "Lab {}", "{} iPhone",
)
_CARRIERS = (
    ("Viettel", "452", "04", "vn"),
    ("Vinaphone", "452", "02", "vn"),
    ("Mobifone", "452", "01", "vn"),
    ("Vietnamobile", "452", "05", "vn"),
    ("AT&T", "310", "410", "us"),
    ("T-Mobile", "310", "260", "us"),
    ("Verizon", "311", "480", "us"),
    ("NTT DOCOMO", "440", "10", "jp"),
    ("SoftBank", "440", "20", "jp"),
    ("SKTelecom", "450", "05", "kr"),
    ("China Mobile", "460", "00", "cn"),
)


def random_serial(year: int | None = None) -> str:
    """
    Synthetic Apple-like serial.
    - Pre-2021 hardware: classic **12** chars (factory prefix + body).
    - 2021+: randomised style, mostly **10** chars (also 11–12 rarely).
    Alphabet excludes I, O, 0, 1 (Apple serial convention).
    """
    plant = random.choice(_SERIAL_PLANTS)
    if year is not None and int(year) < 2021:
        length = 12
    else:
        # Observed modern lengths cluster at 10; avoid silly 13–14
        length = random.choices((10, 10, 10, 11, 12), weights=(55, 55, 55, 15, 10))[0]
    need = max(1, length - len(plant))
    body = "".join(random.choice(_SERIAL_ALPHABET) for _ in range(need))
    serial = (plant + body)[:length]
    # Never all-numeric / never start with digit-only noise
    if serial[0].isdigit():
        serial = random.choice("CDFGHJKLMNPQRSTUVWXYZ") + serial[1:]
    return serial


def format_part_number(device: dict | None = None) -> tuple:
    """
    Part Number — Settings "Số máy" mặc định (vd MU783KH/A, MT6T2J/A).
    Returns (part_number, region_letters). Always NEW random each call.
    """
    alnum = string.ascii_uppercase + string.digits
    prefix = random.choice(["M", "N", "F", "P"])
    body_len = random.choice((4, 4, 4, 5))
    body = "".join(random.choice(alnum) for _ in range(body_len))
    if isinstance(device, dict):
        base = str(device.get("PartNumber") or "").split("/")[0].upper()
        base = re.sub(r"[^A-Z0-9]", "", base)
        if len(base) >= 5 and base[0] in "MNFP":
            prefix = base[0]
            body = "".join(random.choice(alnum) for _ in range(4))
    region = random.choice(_PART_REGIONS)
    return f"{prefix}{body}{region}/A", region


def format_axxxx(device: dict | str | None, *, randomize: bool = True) -> str:
    """Regulatory Axxxx — Settings after tap. Random from modelNumbers when possible."""
    if isinstance(device, dict):
        nums = [
            str(x).upper()
            for x in (device.get("modelNumbers") or [])
            if re.match(r"^A\d{4}$", str(x).upper())
        ]
        default = device.get("RegulatoryModelNumber") or device.get("ModelNumber")
        if nums:
            if randomize:
                return random.choice(nums)
            d = str(default or "").upper()
            if re.match(r"^A\d{4}$", d) and d in nums:
                return d
            # Prefer last (often "other countries") when present
            return nums[-1]
        raw = str(default or "")
    else:
        raw = str(device or "")
    raw = raw.strip().upper()
    m = re.search(r"A\d{4}", raw)
    return m.group(0) if m else (raw if re.match(r"^A\d{4}$", raw) else "A0000")


def format_model_number(device: dict | str | None, region: str = "other") -> str:
    return format_axxxx(device, randomize=False)


def apple_uuid() -> str:
    """IDFA / IDFV — RFC 4122 UUID version 4, uppercase with hyphens (NSUUID style)."""
    u = uuid.uuid4()
    # Force version=4 and RFC variant bits even if platform UUID differs
    b = bytearray(u.bytes)
    b[6] = (b[6] & 0x0F) | 0x40
    b[8] = (b[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(b))).upper()


def random_udid() -> str:
    """
    UniqueDeviceID — 40 hex chars (legacy iOS UDID / SHA-1 digest length).
    Uppercase hex as commonly seen in MG dumps.
    """
    return hashlib.sha1(os.urandom(32)).hexdigest().upper()


def random_ecid() -> tuple[str, str]:
    """
    UniqueChipID / ECID-like 64-bit id.
    Returns (decimal_string, hex16_upper) — lockdown often shows decimal.
    """
    n = random.randint(0x10_0000_0000, 0xFFFF_FFFF_FFFF_FFFF)
    return str(n), f"{n:016X}"


def random_mac() -> str:
    """
    Wi‑Fi MAC: public Apple OUI + random NIC (lab).
    Unicast; not forced local-admin bit so it looks like factory OUI traffic.
    """
    if random.random() < 0.85:
        oui = random.choice(_APPLE_OUI)
        nic = [random.randint(0, 255) for _ in range(3)]
        return oui + ":" + ":".join(f"{b:02X}" for b in nic)
    b0 = (random.randint(0, 255) | 0x02) & 0xFE
    parts = [b0] + [random.randint(0, 255) for _ in range(5)]
    return ":".join(f"{b:02X}" for b in parts)


def random_eid() -> str:
    """eSIM EID — 32 decimal digits with Luhn-style check on 31-digit body."""
    body31 = "".join(str(random.randint(0, 9)) for _ in range(31))
    total = 0
    for i, ch in enumerate(body31[::-1]):
        n = int(ch)
        if i % 2 == 0:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return body31 + str((10 - (total % 10)) % 10)


def random_device_name(marketing: str, device_id: str) -> str:
    tpl = random.choice(_DEVICE_NAME_POOL)
    if "{}" in tpl:
        return tpl.format(random.choice((marketing.split()[-1], device_id, "Lab", "Pro")))
    return tpl


def hostname_from_name(name: str) -> str:
    """
    DNS-label / gethostname-safe hostname derived from device name.
    Keep identical to IPFConfig sanitize + uname.nodename / NSProcessInfo.hostName.
    """
    raw = (name or "iPhone").strip()
    out = []
    for ch in raw:
        if ch.isalnum() or ch == "-":
            out.append(ch)
        elif ch in " _." and out and out[-1] != "-":
            out.append("-")
    s = "".join(out).strip("-")[:63]
    return s or "iPhone"


def random_capacity_gb(device: dict):
    opts = device.get("storageOptionsGB") or []
    if not opts:
        return None
    return int(random.choice(opts))


def _luhn_check_digit(digits14: str) -> str:
    total = 0
    for i, ch in enumerate(digits14):
        n = int(ch)
        if i % 2 == 1:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return str((10 - (total % 10)) % 10)


def random_imei() -> str:
    """15-digit IMEI: 8-digit TAC + SNR + Luhn check digit."""
    tac = random.choice(_IMEI_TAC)
    assert len(tac) == 8 and tac.isdigit()
    body14 = tac + "".join(str(random.randint(0, 9)) for _ in range(6))
    return body14 + _luhn_check_digit(body14)


def validate_identity(flat: dict, device: dict | None = None, ios_meta: dict | None = None) -> list[str]:
    """Return list of problems (empty = OK). Lab format + catalog cross-field consistency.

    When *device* / *ios_meta* are provided, Class A fields must match catalog
    (works for every device row — not only one SKU like 15 Pro Max).
    """
    errs: list[str] = []
    sn = str(flat.get("SerialNumber") or "")
    if not re.fullmatch(r"[A-Z2-9]{10,12}", sn):
        errs.append(f"SerialNumber bad len/charset: {sn!r}")
    if any(c in sn for c in "IO01"):
        errs.append(f"SerialNumber forbidden I/O/0/1: {sn!r}")
    for k in ("IDFA", "IDFV", "identifierForVendor", "advertisingIdentifier"):
        v = str(flat.get(k) or "")
        if v and not re.fullmatch(
            r"[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}",
            v,
        ):
            errs.append(f"{k} not UUID v4 upper: {v!r}")
    if flat.get("IDFA") and flat.get("IDFV") and flat["IDFA"] == flat["IDFV"]:
        errs.append("IDFA must differ from IDFV")
    udid = str(flat.get("UniqueDeviceID") or "")
    if not re.fullmatch(r"[0-9A-F]{40}", udid):
        errs.append(f"UniqueDeviceID not 40 hex: {udid!r}")
    imei = str(flat.get("InternationalMobileEquipmentIdentity") or "")
    if imei:
        if not re.fullmatch(r"\d{15}", imei):
            errs.append(f"IMEI not 15 digits: {imei!r}")
        elif _luhn_check_digit(imei[:14]) != imei[14]:
            errs.append(f"IMEI Luhn fail: {imei!r}")
    eid = str(flat.get("EID") or "")
    if eid and not re.fullmatch(r"\d{32}", eid):
        errs.append(f"EID not 32 digits: {eid!r}")
    # Consistency: MAC family
    wifi = str(flat.get("WifiAddress") or "")
    eth = str(flat.get("EthernetMacAddress") or "")
    bssid = str(flat.get("BSSID") or "")
    mac_re = r"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
    if wifi and not re.fullmatch(mac_re, wifi):
        errs.append(f"WifiAddress bad MAC: {wifi!r}")
    if wifi and eth and wifi.upper() != eth.upper():
        errs.append("EthernetMacAddress must equal WifiAddress")
    if wifi and bssid and wifi.upper() != bssid.upper():
        errs.append("BSSID must equal WifiAddress")
    # Hostname ↔ device name derive
    hn = str(flat.get("Hostname") or "")
    if hn and not re.fullmatch(r"[A-Za-z0-9-]{1,63}", hn):
        errs.append(f"Hostname not DNS-safe: {hn!r}")
    # Serial aliases
    for ak in ("IOPlatformSerialNumber", "MLBSerialNumber"):
        if flat.get(ak) and flat.get(ak) != sn:
            errs.append(f"{ak} must equal SerialNumber")
    # Screen: if catalog provided, catalog is authority (Plus models: 1080≠414*3).
    # Without catalog, only flag gross mismatch (allow Apple downsampling slack).
    try:
        nw = int(flat.get("main-screen-width") or 0)
        nh = int(flat.get("main-screen-height") or 0)
        sc = int(flat.get("main-screen-scale") or 0)
        lw = int(flat.get("LogicalScreenWidth") or 0)
        lh = int(flat.get("LogicalScreenHeight") or 0)
        if nw and nh and sc and lw and lh and not device:
            # Loose check only when no catalog row (Plus can be ~20% off)
            if abs(nw - lw * sc) > max(sc * 80, nw * 0.25) or abs(
                nh - lh * sc
            ) > max(sc * 80, nh * 0.25):
                errs.append(
                    f"screen mismatch native {nw}x{nh} vs logical {lw}x{lh}@{sc}"
                )
    except (TypeError, ValueError):
        pass
    # Disk: free <= total
    try:
        tot = int(flat.get("TotalDiskCapacity") or 0)
        fre = int(flat.get("FreeDiskSpace") or 0)
        if tot and fre and fre > tot:
            errs.append("FreeDiskSpace > TotalDiskCapacity")
    except (TypeError, ValueError):
        pass

    # --- Class A: flat must match selected catalog device + iOS (all models) ---
    if device:
        if flat.get("ProductType") != device.get("ProductType"):
            errs.append(
                f"ProductType {flat.get('ProductType')!r} != catalog {device.get('ProductType')!r}"
            )
        if flat.get("MarketingName") != device.get("MarketingName"):
            errs.append(
                f"MarketingName {flat.get('MarketingName')!r} != catalog {device.get('MarketingName')!r}"
            )
        if flat.get("HWModelStr") != device.get("HWModelStr"):
            errs.append(
                f"HWModelStr {flat.get('HWModelStr')!r} != catalog {device.get('HWModelStr')!r}"
            )
        disp = device.get("display") or {}
        try:
            if int(flat.get("main-screen-width") or 0) != int(disp.get("NativeWidth") or 0):
                errs.append("main-screen-width != catalog NativeWidth")
            if int(flat.get("main-screen-height") or 0) != int(disp.get("NativeHeight") or 0):
                errs.append("main-screen-height != catalog NativeHeight")
            if int(flat.get("main-screen-scale") or 0) != int(disp.get("ScreenScale") or 0):
                errs.append("main-screen-scale != catalog ScreenScale")
            cat_lw = int(disp.get("LogicalWidth") or 0)
            cat_lh = int(disp.get("LogicalHeight") or 0)
            if cat_lw and int(flat.get("LogicalScreenWidth") or 0) != cat_lw:
                errs.append("LogicalScreenWidth != catalog LogicalWidth")
            if cat_lh and int(flat.get("LogicalScreenHeight") or 0) != cat_lh:
                errs.append("LogicalScreenHeight != catalog LogicalHeight")
            if int(flat.get("PhysicalMemoryMB") or 0) != int(device.get("PhysicalMemoryMB") or 0):
                errs.append("PhysicalMemoryMB != catalog")
        except (TypeError, ValueError) as ex:
            errs.append(f"catalog numeric compare: {ex}")
        opts = device.get("storageOptionsGB") or []
        try:
            cap = flat.get("DiskCapacityGB")
            if cap not in ("", None) and opts:
                if int(cap) not in [int(x) for x in opts]:
                    errs.append(f"DiskCapacityGB {cap} not in storageOptionsGB {opts}")
        except (TypeError, ValueError):
            errs.append("DiskCapacityGB not int")
    if ios_meta:
        if flat.get("ProductVersion") != ios_meta.get("ProductVersion"):
            errs.append(
                f"ProductVersion {flat.get('ProductVersion')!r} != {ios_meta.get('ProductVersion')!r}"
            )
        if flat.get("BuildVersion") != ios_meta.get("BuildVersion"):
            errs.append(
                f"BuildVersion {flat.get('BuildVersion')!r} != {ios_meta.get('BuildVersion')!r}"
            )
        # UA must embed same OS version (underscored)
        ua = str(flat.get("UserAgent") or flat.get("HTTPUserAgent") or "")
        pv = str(ios_meta.get("ProductVersion") or "")
        if ua and pv:
            ua_os = pv.replace(".", "_")
            if ua_os not in ua:
                errs.append(f"UserAgent missing OS {ua_os!r}")
    return errs


def validate_all_devices(cat: dict, *, samples_per_device: int = 1) -> int:
    """Generate + validate a profile for every catalog device (matrix-valid iOS).

    Returns number of failures. Ensures identity pipeline is SKU-agnostic.
    """
    fails = 0
    ok = 0
    skipped = 0
    print(
        f"{'device_id':22} {'MarketingName':28} {'ProductType':12} iOS        result"
    )
    print("-" * 100)
    for device in cat["devices"]:
        supported = device_supported_ios(device, cat)
        if not supported:
            skipped += 1
            print(f"{device.get('id',''):22} {str(device.get('MarketingName',''))[:28]:28} SKIP no iOS matrix")
            continue
        # Exercise default + mid + first supported when possible
        picks = []
        picks.append(device.get("defaultIOS") if device.get("defaultIOS") in supported else supported[-1])
        if samples_per_device > 1 and len(supported) > 1:
            picks.append(supported[0])
        if samples_per_device > 2 and len(supported) > 2:
            picks.append(supported[len(supported) // 2])
        seen = set()
        for ios in picks:
            if ios in seen:
                continue
            seen.add(ios)
            try:
                ios_ver, ios_meta = clamp_ios(device, ios, cat, force=False)
            except SystemExit as e:
                fails += 1
                print(f"{device['id']:22} clamp fail: {e}")
                continue
            built = build_profile(device, ios_ver, ios_meta, None)
            errs = validate_identity(built["flat"], device=device, ios_meta=ios_meta)
            if errs:
                fails += 1
                print(
                    f"{device['id']:22} {device['MarketingName'][:28]:28} "
                    f"{device['ProductType']:12} {ios_ver:10} FAIL"
                )
                for e in errs[:6]:
                    print(f"  · {e}")
            else:
                ok += 1
                disp = device["display"]
                print(
                    f"{device['id']:22} {device['MarketingName'][:28]:28} "
                    f"{device['ProductType']:12} {ios_ver:10} OK "
                    f"{disp['NativeWidth']}x{disp['NativeHeight']}@"
                    f"{disp['ScreenScale']} RAM={device['PhysicalMemoryMB']}"
                )
    print("-" * 100)
    print(f"OK={ok} FAIL={fails} SKIP={skipped} devices={len(cat['devices'])}")
    return fails


def clamp_ios(
    device: dict,
    ios: str | None,
    cat: dict,
    *,
    force: bool = False,
) -> tuple[str, dict]:
    releases = cat["ios_releases"]
    supported = device_supported_ios(device, cat)
    strict = bool(cat.get("compat", {}).get("strict", True)) and not force

    if ios is None:
        ios = device.get("defaultIOS") or (supported[-1] if supported else "18.5")

    if ios not in releases:
        # try prefix match latest within supported if strict
        pool = supported if (strict and supported) else list(releases.keys())
        cands = [k for k in pool if k.startswith(ios)]
        if not cands:
            cands = [k for k in releases if k.startswith(ios)]
        if cands:
            ios = sorted(cands, key=lambda x: [int(p) for p in x.split(".")])[-1]
        else:
            raise SystemExit(f"Unknown iOS version: {ios}. Use --list-ios")

    if strict:
        if not supported:
            raise SystemExit(
                f"Device {device.get('id')} has no supported iOS in matrix "
                f"(iphone6/6-plus not listed). Use another model or --force."
            )
        if ios not in supported:
            # nearest supported same major if any
            maj = ios.split(".")[0]
            same = [v for v in supported if v.split(".")[0] == maj]
            hint = same[-1] if same else supported[-1]
            raise SystemExit(
                f"INVALID pair: {device.get('MarketingName')} ({device.get('id')}) "
                f"does not support iOS {ios} per matrix.\n"
                f"  supported: {supported[0]} … {supported[-1]} ({len(supported)} builds)\n"
                f"  try: -i {hint}   or --force to override"
            )

    return ios, releases[ios]


def build_profile(device: dict, ios_ver: str, ios_meta: dict, name: str | None) -> dict:
    disp = device["display"]
    ram_mb = int(device["PhysicalMemoryMB"])
    ram_bytes = ram_mb * 1024 * 1024
    wifi = random_mac()
    bt_parts = wifi.split(":")
    bt_parts[-1] = f"{(int(bt_parts[-1], 16) ^ 1) & 0xFF:02X}"
    bluetooth = ":".join(bt_parts)
    # Identity — BOTH Part Number + Axxxx; max random (hardware untouched)
    idfv = apple_uuid()
    idfa = apple_uuid()
    # IDFA ≠ IDFV (different identifiers in real iOS)
    while idfa == idfv:
        idfa = apple_uuid()
    udid = random_udid()
    ecid_dec, ecid_hex = random_ecid()
    year = device.get("year")
    try:
        year_i = int(year) if year is not None else None
    except (TypeError, ValueError):
        year_i = None
    serial = random_serial(year_i)
    # Settings "Số máy" default = Part Number (MU783KH/A); tap = Axxxx
    part_number, part_region = format_part_number(device)
    axxxx = format_axxxx(device, randomize=True)
    imei = random_imei()
    imei2 = random_imei()
    while imei2 == imei:
        imei2 = random_imei()
    meid = imei[:14]  # MEID-like: 14 decimal from IMEI body
    eid = random_eid()
    dev_name = name or random_device_name(device.get("MarketingName") or "iPhone", device["id"])
    host_name = hostname_from_name(dev_name)
    capacity = random_capacity_gb(device)
    carrier = random.choice(_CARRIERS)
    c_name, c_mcc, c_mnc, c_iso = carrier
    region_code = _PART_REGION_TO_CODE.get(part_region, "VN")
    region_info = f"{region_code}/A"
    radio = random.choice(
        (
            "CTRadioAccessTechnologyNR",
            "CTRadioAccessTechnologyLTE",
            "CTRadioAccessTechnologyNRNSA",
        )
    )

    flat = {
        "Enabled": True,
        # Surface toggles — FakeScreen spoofs native+logical together (no real-display leak)
        "FakeDevice": True,
        "FakeScreen": True,
        "FakeRealScreen": True,
        "FakeHardware": True,
        "FakeAds": True,
        "FakeWifi": True,
        "FakeNetwork": True,
        "FakeSysctl": True,
        "FakeSysOSVersion": True,
        "HideJailbreak": True,
        "FakeBrowser": True,
        "ProductType": device["ProductType"],
        "MarketingName": device["MarketingName"],
        "DeviceName": "iPhone",
        "UserAssignedDeviceName": dev_name,
        "Hostname": host_name,
        "kern.hostname": host_name,
        "HWModelStr": device["HWModelStr"],
        "HardwareModel": device["HWModelStr"],
        # BOTH numbers (Settings toggles ModelNumber ↔ Regulatory):
        "ModelNumber": part_number,              # default UI: MU783KH/A
        "PartNumber": part_number,               # same Part Number
        "RegulatoryModelNumber": axxxx,          # tap: A3106
        "ModelNumberAxxxx": axxxx,               # explicit alias
        "RegionInfo": region_info,
        "RegionCode": region_code,
        "PartNumberRegion": part_region,
        "HardwarePlatform": device.get("HardwarePlatform", ""),
        "CPUArchitecture": device.get("CPUArchitecture", "arm64e"),
        "DeviceClass": "iPhone",
        "SerialNumber": serial,
        "UniqueDeviceID": udid,
        "UniqueChipID": ecid_hex,
        "ECID": ecid_dec,
        "ChipID": ecid_dec,
        "ProductVersion": ios_meta["ProductVersion"],
        "BuildVersion": ios_meta["BuildVersion"],
        "ProductBuildVersion": ios_meta["BuildVersion"],
        "IDFA": idfa,
        "IDFV": idfv,
        "identifierForVendor": idfv,
        "advertisingIdentifier": idfa,
        "AdvertisingIdentifier": idfa,
        "InternationalMobileEquipmentIdentity": imei,
        "InternationalMobileEquipmentIdentity2": imei2,
        "MobileEquipmentIdentifier": meid,
        "EID": eid,
        # MG / IOKit-style aliases (same values)
        "serial-number": serial,
        "Serial": serial,
        "unique-device-id": udid,
        "DeviceUniqueIdentifier": udid,
        "WifiAddress": wifi,
        "BluetoothAddress": bluetooth,
        "EthernetMacAddress": wifi,  # must == WifiAddress
        "BSSID": wifi,               # CNCopyCurrentNetworkInfo ≡ Wifi MAC
        "SSID": random.choice(
            ("Viettel-WiFi", "Viettel", "VNPT-Fiber", "FPT-Telecom", "iPhone", "MyWiFi")
        ),
        "VolumeUUID": apple_uuid(),  # Class B — disk volume id lab
        "IOPlatformSerialNumber": serial,  # IOKit alias ≡ SerialNumber
        "MLBSerialNumber": serial,
        "carrierName": c_name,
        "carrierMCC": c_mcc,
        "carrierMNC": c_mnc,
        "carrierISO": c_iso,
        "carrierRadioAccess": radio,
        "CarrierName": c_name,
        "MobileCountryCode": c_mcc,
        "MobileNetworkCode": c_mnc,
        "ISOCountryCode": c_iso,
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
        "LogicalScreenWidth": int(disp.get("LogicalWidth") or (disp["NativeWidth"] // max(1, disp["ScreenScale"]))),
        "LogicalScreenHeight": int(disp.get("LogicalHeight") or (disp["NativeHeight"] // max(1, disp["ScreenScale"]))),
        "ScreenDiagonalInches": str(disp.get("DiagonalInches", "")),
        "MaxRefreshHz": int(disp.get("MaxRefreshHz", 60)),
        "BatteryMah": int(device.get("batteryMah", 0) or 0),
        "DeviceYear": int(device.get("year", 0) or 0),
        "DiskCapacityGB": capacity if capacity is not None else "",
        "TotalDiskCapacity": (int(capacity) * 1_000_000_000) if capacity else "",
        # Free = 35–75% of capacity (lab)
        "FreeDiskSpace": (
            int(int(capacity) * 1_000_000_000 * random.uniform(0.35, 0.75))
            if capacity
            else ""
        ),
        # Colors / baseband / UA / boottime — extra Zalo surface
        "DeviceColor": random.choice(
            ("1", "2", "3", "4", "5", "6", "7", "8", "9", "black", "white", "blue", "natural")
        ),
        "DeviceEnclosureColor": random.choice(
            ("1", "2", "3", "4", "5", "6", "7", "8", "9", "black", "white", "blue", "natural")
        ),
        "BasebandVersion": f"1.{random.randint(10, 90):02d}.0{random.randint(0, 9)}",
        "UserAgent": (
            f"Mozilla/5.0 (iPhone; CPU iPhone OS "
            f"{ios_meta['ProductVersion'].replace('.', '_')} like Mac OS X) "
            f"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 "
            f"Zalo/{random.randint(420, 480)}.0.0"
        ),
        "HTTPUserAgent": (
            f"Mozilla/5.0 (iPhone; CPU iPhone OS "
            f"{ios_meta['ProductVersion'].replace('.', '_')} like Mac OS X) "
            f"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        ),
        # boot seconds ago → consumers convert to absolute; we store absolute unix
        "BootTimeUnix": int(__import__("time").time()) - random.randint(3600, 14 * 86400),
        "kern.boottime": int(__import__("time").time()) - random.randint(3600, 14 * 86400),
    }

    active = {
        "schema": "ipfaker.active_profile/3",
        "generated_from": "device_catalog.json",
        "device_id": device["id"],
        "ios": ios_ver,
        "model": {
            "ProductType": device["ProductType"],
            "MarketingName": device["MarketingName"],
            "HWModelStr": device["HWModelStr"],
            "HardwareModel": device["HWModelStr"],
            "ModelNumber": part_number,
            "PartNumber": part_number,
            "RegulatoryModelNumber": axxxx,
            "ModelNumberAxxxx": axxxx,
            "HardwarePlatform": device.get("HardwarePlatform", ""),
            "CPUArchitecture": device.get("CPUArchitecture", "arm64e"),
            "DeviceName": "iPhone",
            "UserAssignedDeviceName": dev_name,
            "ChipName": device.get("chip", ""),
            "PhysicalMemoryMB": ram_mb,
            "DiskCapacityGB": capacity,
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
            "LogicalWidth": disp.get("LogicalWidth"),
            "LogicalHeight": disp.get("LogicalHeight"),
            "DiagonalInches": disp.get("DiagonalInches"),
            "MaxRefreshHz": disp.get("MaxRefreshHz", 60),
        },
        "storage": {
            "TotalDiskCapacity": flat.get("TotalDiskCapacity"),
            "FreeDiskSpace": flat.get("FreeDiskSpace"),
            "DiskCapacityGB": capacity,
        },
        "webview": {
            "UserAgent": flat.get("UserAgent"),
            "HTTPUserAgent": flat.get("HTTPUserAgent"),
        },
        "jailbreak_hide": {
            "paths": [
                "/Applications/Cydia.app",
                "/Applications/Sileo.app",
                "/Applications/Zebra.app",
                "/Applications/Filza.app",
                "/Library/MobileSubstrate",
                "/usr/lib/TweakInject",
                "/usr/lib/libsubstrate.dylib",
                "/usr/lib/libellekit.dylib",
                "/var/jb",
                "/private/var/jb",
                "/usr/lib/frida",
                "FridaGadget",
                "frida-server",
                "/.bootstrapped",
                "/.bootstrapped_electra",
                "/bin/bash",
                "/etc/apt",
                "CydiaSubstrate",
                "Dopamine",
            ]
        },
        "hardware": {
            "chip": device.get("chip"),
            "cpuCores": device.get("cpuCores"),
            "gpuCores": device.get("gpuCores"),
            "PhysicalMemoryMB": ram_mb,
            "batteryMah": device.get("batteryMah"),
            "year": device.get("year"),
            "storageOptionsGB": device.get("storageOptionsGB"),
        },
        "identity": {
            "SerialNumber": serial,
            "ModelNumber": part_number,
            "PartNumber": part_number,
            "RegulatoryModelNumber": axxxx,
            "ModelNumberAxxxx": axxxx,
            "UniqueDeviceID": udid,
            "UniqueChipID": ecid_hex,
            "ECID": ecid_dec,
            "IDFA": idfa,
            "IDFV": idfv,
            "IMEI": imei,
            "IMEI2": imei2,
            "MEID": meid,
            "EID": eid,
            "formats": {
                "ModelNumber": "Part Number Settings default e.g. MU783KH/A",
                "RegulatoryModelNumber": "Axxxx after tap e.g. A3106",
                "SerialNumber": "12 pre-2021 / ~10 post-2021; no I/O/0/1",
                "UniqueDeviceID": "40 hex SHA-1 style (UDID length)",
                "UniqueChipID": "16 hex ECID; ECID decimal twin",
                "PartNumberRegion": "LL/J/CH/KH/ZA/…",
                "IDFA": "UUID v4 uppercase (version nibble 4)",
                "IDFV": "UUID v4 uppercase ≠ IDFA",
                "IMEI": "8-digit TAC + 6 SNR + Luhn",
                "EID": "32 digits eSIM + Luhn-style check",
                "WifiAddress": "Apple OUI + random NIC",
            },
            "model_number_source": "config/iPhone_Model_Lookup.xlsx + Apple 108044",
        },
        "network": {
            "WifiAddress": wifi,
            "BluetoothAddress": bluetooth,
            "EthernetMacAddress": wifi,
        },
        "telephony": {
            # Must mirror flat (random carrier) — no fixed Viettel split-brain
            "CarrierName": c_name,
            "MobileCountryCode": c_mcc,
            "MobileNetworkCode": c_mnc,
            "ISOCountryCode": c_iso,
            "CurrentRadioAccessTechnology": radio,
        },
        "hooks": {
            "mobilegestalt": {
                "ProductType": device["ProductType"],
                "MarketingName": device["MarketingName"],
                "HWModelStr": device["HWModelStr"],
                "SerialNumber": serial,
                "UniqueDeviceID": udid,
                "ProductVersion": ios_meta["ProductVersion"],
                "BuildVersion": ios_meta["BuildVersion"],
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
        "LogicalScreenWidth",
        "LogicalScreenHeight",
        "MaxRefreshHz",
        "BatteryMah",
        "DeviceYear",
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
    _sys_path = str(Path(__file__).resolve().parent)
    if _sys_path not in sys.path:
        sys.path.insert(0, _sys_path)
    from _device_env import require as _dev_require

    host, user, password = _dev_require()
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
    sudo(
        f"grep -A1 ProductType {etc}/config.plist; "
        f"grep -A1 MarketingName {etc}/config.plist; "
        f"grep -A1 ProductVersion {etc}/config.plist"
    )
    # soft restart Zalo so next open reloads config (if auto-inject)
    sudo("killall -9 Zalo 2>/dev/null || true")
    c.close()
    print("Deployed to device. Re-open Zalo (auto-inject if plists on).")


def main() -> int:
    ap = argparse.ArgumentParser(description="Select iPFaker device + iOS lab profile")
    ap.add_argument("--list", action="store_true", help="List all devices")
    ap.add_argument("--list-ios", action="store_true", help="List iOS versions (filter by -d if set)")
    ap.add_argument("--device", "-d", help="Device id / marketing name / ProductType")
    ap.add_argument("--ios", "-i", help="iOS version e.g. 18.5, 17.6.1")
    ap.add_argument("--name", help="UserAssignedDeviceName")
    ap.add_argument("--random", action="store_true", help="Random device + default iOS (matrix-valid only)")
    ap.add_argument(
        "--validate-all",
        action="store_true",
        help="Build+validate profile for EVERY catalog device (no write)",
    )
    ap.add_argument(
        "--samples",
        type=int,
        default=1,
        help="With --validate-all: iOS samples per device (1–3)",
    )
    ap.add_argument("--deploy", action="store_true", help="Push config.plist to phone via SSH")
    ap.add_argument("--force", action="store_true", help="Allow invalid device+iOS pairs (bypass matrix)")
    args = ap.parse_args()

    cat = load_catalog()
    if args.list:
        list_devices(cat)
        return 0
    if args.list_ios:
        dev = find_device(cat, args.device) if args.device else None
        if args.device and not dev:
            print(f"Device not found: {args.device}", file=sys.stderr)
            return 1
        list_ios(cat, dev)
        return 0
    if args.validate_all:
        n = max(1, min(3, int(args.samples or 1)))
        fails = validate_all_devices(cat, samples_per_device=n)
        return 1 if fails else 0

    if args.random:
        pool = [d for d in cat["devices"] if device_supported_ios(d, cat)]
        if not pool:
            pool = cat["devices"]
        device = random.choice(pool)
    elif args.device:
        device = find_device(cat, args.device)
        if not device:
            print(f"Device not found: {args.device}", file=sys.stderr)
            return 1
    else:
        ap.print_help()
        print("\nExamples:\n  python scripts/select_device_profile.py --list")
        print("  python scripts/select_device_profile.py -d iphone16-pro-max -i 18.5 --deploy")
        print("  python scripts/select_device_profile.py -d iphone15-pro --list-ios")
        print("  python scripts/select_device_profile.py --validate-all")
        print("  python scripts/select_device_profile.py --random --deploy  # any matrix-valid device")
        return 2

    ios_ver, ios_meta = clamp_ios(device, args.ios, cat, force=args.force)
    built = build_profile(device, ios_ver, ios_meta, args.name)
    flat = built["flat"]
    id_errs = validate_identity(flat, device=device, ios_meta=ios_meta)
    if id_errs:
        print("IDENTITY CONSISTENCY FAIL — not writing:", file=sys.stderr)
        for e in id_errs:
            print(" ", e, file=sys.stderr)
        return 1
    write_plist(flat, OUT_PLIST)
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
                "SerialNumber": flat.get("SerialNumber"),
                "ModelNumber": flat.get("ModelNumber"),
                "PartNumber": flat.get("PartNumber"),
                "RegulatoryModelNumber": flat.get("RegulatoryModelNumber"),
                "IDFA": flat.get("IDFA"),
                "IDFV": flat.get("IDFV"),
                "IMEI": flat.get("InternationalMobileEquipmentIdentity"),
                "EID": flat.get("EID"),
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
    print(
        f"  Chip   : {device.get('chip')}  RAM={device['PhysicalMemoryMB']}MB  "
        f"CPU={device.get('cpuCores')}  GPU={device.get('gpuCores')}"
    )
    d = device["display"]
    print(
        f"  Screen : {d['NativeWidth']}x{d['NativeHeight']} @{d['ScreenScale']}  "
        f"{d.get('Pitch')} ppi  {d.get('DiagonalInches')}\"  {d.get('MaxRefreshHz', 60)}Hz"
    )
    if device.get("batteryMah"):
        print(f"  Battery: {device['batteryMah']} mAh  year={device.get('year')}  storage={device.get('storageOptionsGB')}")
    print(f"  iOS    : {ios_ver} ({ios_meta['BuildVersion']})" + (" [lab build]" if ios_meta.get("lab") else ""))
    print(f"  Serial : {flat.get('SerialNumber')}  ({len(flat.get('SerialNumber') or '')} chars)")
    print(f"  So may : {flat.get('ModelNumber')}  (Part Number — Settings default)")
    print(f"  Axxxx  : {flat.get('RegulatoryModelNumber')}  (tap So may)")
    print(f"  UDID   : {flat.get('UniqueDeviceID')}")
    print(f"  ECID   : {flat.get('ECID')}  (hex {flat.get('UniqueChipID')})")
    print(f"  IDFA   : {flat.get('IDFA')}")
    print(f"  IDFV   : {flat.get('IDFV')}")
    print(f"  IMEI   : {flat.get('InternationalMobileEquipmentIdentity')}")
    print(f"  WiFi   : {flat.get('WifiAddress')}")
    id_errs = validate_identity(flat)
    if id_errs:
        print("  IDENTITY WARN:", "; ".join(id_errs))
    else:
        print("  Identity formats: OK (serial/UUID/UDID/IMEI/EID)")
    print(f"  EID    : {(flat.get('EID') or '')[:16]}…")
    if flat.get("DiskCapacityGB"):
        print(f"  Storage: {flat.get('DiskCapacityGB')} GB")
    print(f"  Wrote  : {OUT_PLIST.relative_to(ROOT)}")
    print(f"           {OUT_ACTIVE.relative_to(ROOT)}")
    print(f"           {OUT_SELECTED.relative_to(ROOT)}")

    if args.deploy:
        deploy_to_device()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
