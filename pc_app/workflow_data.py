#!/usr/bin/env python3
"""Persisted workflow tables: names, profiles (DOB+gender), step delays."""
from __future__ import annotations

import json
import random
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent / "workflow_data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

NAMES_FILE = DATA_DIR / "names.json"
PROFILES_FILE = DATA_DIR / "profiles.json"
DELAYS_FILE = DATA_DIR / "delays.json"
CONFIG_FILE = DATA_DIR / "config.json"

# Default min/max seconds per step (user editable)
DEFAULT_DELAYS = {
    "01_rotate_proxy": [2.0, 5.0],
    "02_shadowrocket_off": [1.5, 3.0],
    "02b_shadowrocket_on": [2.0, 4.0],
    "03_ipfaker_reset": [3.0, 6.0],
    "04_zalo_create_account": [2.0, 4.0],
    "05_phone_and_terms": [1.5, 3.5],
    "06_captcha": [2.0, 5.0],
    "07_otp": [2.0, 4.0],
    "08_privacy": [1.5, 3.0],
    "09_name": [1.5, 3.0],
    "10_personal": [2.0, 4.0],
    "11_avatar_skip": [1.0, 2.5],
    "12_contacts": [1.0, 2.5],
    "13_soak": [30.0, 120.0],  # ngâm
    "14_open_appmanager": [2.0, 4.0],
    "15_backup_zalo_btn": [1.5, 3.0],
    "16_backup_clock_btn": [1.5, 3.0],
    "17_rename_backup": [2.0, 4.0],
    "18_delete_app_section": [1.5, 3.0],
    "between_actions": [0.4, 1.2],
}

DEFAULT_NAMES = [
    "Nguyen Van An",
    "Tran Thi Binh",
    "Le Minh Chau",
    "Pham Hoang Duc",
    "Hoang Thu Ha",
]

# gender: nam | nu | male | female
DEFAULT_PROFILES = [
    {"dob": "15/05/1998", "gender": "nam"},
    {"dob": "22/08/1995", "gender": "nu"},
    {"dob": "03/11/2000", "gender": "nam"},
]


def _load(path: Path, default):
    if not path.exists():
        _save(path, default)
        return json.loads(json.dumps(default))
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return json.loads(json.dumps(default))


def _save(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_names() -> list[str]:
    data = _load(NAMES_FILE, DEFAULT_NAMES)
    return [str(x).strip() for x in data if str(x).strip()]


def save_names(names: list[str]) -> None:
    _save(NAMES_FILE, [n.strip() for n in names if n.strip()])


def load_profiles() -> list[dict]:
    data = _load(PROFILES_FILE, DEFAULT_PROFILES)
    out = []
    for p in data:
        if isinstance(p, dict) and p.get("dob"):
            out.append({"dob": str(p["dob"]).strip(), "gender": str(p.get("gender") or "nam").strip()})
    return out or list(DEFAULT_PROFILES)


def save_profiles(profiles: list[dict]) -> None:
    _save(PROFILES_FILE, profiles)


def load_delays() -> dict:
    data = _load(DELAYS_FILE, DEFAULT_DELAYS)
    # merge missing keys
    for k, v in DEFAULT_DELAYS.items():
        if k not in data:
            data[k] = v
    return data


def save_delays(delays: dict) -> None:
    _save(DELAYS_FILE, delays)


def rand_delay(delays: dict, key: str, log=None) -> float:
    pair = delays.get(key) or DEFAULT_DELAYS.get(key) or [1.0, 2.0]
    try:
        a, b = float(pair[0]), float(pair[1])
    except Exception:
        a, b = 1.0, 2.0
    if b < a:
        a, b = b, a
    sec = random.uniform(a, b)
    if log:
        log(f"⏱ delay [{key}] {sec:.1f}s (random {a}-{b})")
    time_sleep = __import__("time").sleep
    time_sleep(sec)
    return sec


def pick_name(names: list[str] | None = None) -> str:
    names = names or load_names()
    return random.choice(names) if names else "Nguyen Van A"


def pick_profile(profiles: list[dict] | None = None) -> dict:
    profiles = profiles or load_profiles()
    return random.choice(profiles) if profiles else {"dob": "01/01/1999", "gender": "nam"}


def load_config() -> dict:
    default = {
        "bossotp_token": "",
        "bossotp_network": "",
        "bossotp_prefixs": "",
        "bossotp_service_id": "",
        "rotaproxy_key": "",
        "rotaproxy_app_id": "",
        "achicaptcha_key": "",
        "sms_keyword": "ZALO",
        "sms_shortcodes": "7539|8500",
        "privacy_mode": "first_only",  # first_only | first_two | all_three
        "contacts_action": "skip",  # skip | continue
        "appmanager_bundle": "",
        "shadowrocket_on_url": "shadowrocket://connect",
        "shadowrocket_off_url": "shadowrocket://disconnect",
    }
    data = _load(CONFIG_FILE, default)
    for k, v in default.items():
        data.setdefault(k, v)
    return data


def save_config(cfg: dict) -> None:
    cur = load_config()
    cur.update(cfg)
    _save(CONFIG_FILE, cur)
