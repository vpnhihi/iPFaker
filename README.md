# iPFaker

**iPFaker** is a modular iOS jailbreak project for spoofing full device identity parameters, scoped to **Zalo** (`com.zing.zalo`).

> Target: jailbroken iOS devices only.  
> Scope: device fingerprint / identity spoofing for the Zalo process.  
> Platform workspace: Windows (`C:\Users\Pem\Desktop\iPFaker\`) — build/deploy artifacts and configs are prepared here; runtime hooks execute on-device.

---

## 1. Goals

| Goal | Description |
|------|-------------|
| Full device spoof | Override common hardware / OS / identity values read by apps |
| App-scoped | Prefer injection only into `com.zing.zalo` (not global unless required) |
| Configurable | All fake values live in `config/` — no hardcoding in dylib source |
| Auditable | Runtime and inject logs under `logs/` |
| Step-by-step | Build, inject, verify, and iterate without changing unrelated system state |

### Non-goals (out of scope unless explicitly requested)

- Non-jailbroken / sideload-only devices
- Spoofing apps other than Zalo
- Kernel patches beyond what is needed for process-level hooks
- App Store / distribution packaging

---

## 2. Target application

| Field | Value |
|-------|--------|
| App name | Zalo |
| Bundle ID | `com.zing.zalo` |
| Typical process | `Zalo` / `com.zing.zalo` |
| Injection mode | Per-app (preferred) via injector |

---

## 3. Repository layout

```
C:\Users\Pem\Desktop\iPFaker\
├── README.md          # This file — project overview & workflow
├── config/            # Spoof profiles, plist/json, feature flags
├── docs/              # E2E_CHECKLIST.md
├── dylibs/            # Built hook libraries (.dylib) + HOOKS.md
├── frida/             # Lab Frida script (iPFaker.js) — no Theos required
├── injector/          # Deploy scripts, filter plist, on-device paths
├── scripts/           # build_active_profile.ps1, pull_logs.ps1
├── theos/             # Native tweak scaffold (build on macOS + Theos)
└── logs/              # Inject logs, runtime dumps, verification output
```

### 3.1 `config/`

Holds **all spoof parameters** and feature toggles.

Expected contents (to be added in later steps):

| File (planned) | Role |
|----------------|------|
| `device_profile.json` | Master fake identity (UDID, serial, model, etc.) |
| `hooks.json` | Which APIs / keys to hook and priority |
| `target.json` | Bundle ID filter (`com.zing.zalo` only) |
| `feature_flags.json` | Enable/disable individual spoof categories |

Rules:

- Runtime dylib **reads** config; does not embed secrets or fixed IDs.
- One active profile at a time; keep backups as `device_profile.<name>.json`.
- Never commit real personal device identifiers if you treat this tree as shared.

### 3.2 `dylibs/`

Holds compiled **hook libraries** and optional companion binaries.

| Artifact (planned) | Role |
|--------------------|------|
| `iPFaker.dylib` | Main spoof hooks (UIDevice, sysctl, keychain-related IDs, etc.) |
| `iPFaker.plist` | Substrate/ElleKit filter (bundle ID) — may live under `injector/` instead |

Rules:

- Only ship ARM64 (and arm64e if required by the jailbreak stack).
- Version/tag dylibs when behavior changes: `iPFaker.v1.dylib`, etc.
- Keep unstripped debug builds separate from release if needed.

### 3.3 `injector/`

Holds **how** the dylib is loaded into Zalo.

Possible pieces (depending on jailbreak toolchain):

| Piece | Role |
|-------|------|
| Filter plist | Limit load to `com.zing.zalo` |
| Inject script | Copy dylib + config to device, respring / kill Zalo |
| Substrate / ElleKit / TweakLoader notes | Loader-specific install path |
| Entitlements / signing notes | If re-signing is required on-device |

Rules:

- Prefer **app-scoped** injection over global `MobileSubstrate` for all apps.
- Document exact install paths for the active jailbreak (rootless vs rootful).

### 3.4 `logs/`

Holds **evidence** that spoofing applied correctly.

| Log type | Examples |
|----------|----------|
| Inject | Copy/success/fail of dylib + config to device |
| Runtime | Hook hit counts, values returned to Zalo |
| Verify | Before/after dumps of identifiers |

Rules:

- Rotate or clear old logs when testing new profiles.
- Do not paste production account tokens or full session data into logs.

---

## 4. Spoof surface (high-level)

Categories iPFaker aims to cover for Zalo (implementation steps later):

### 4.1 Device identity

- UDID / identifierForVendor-style values (where hooked)
- Serial number
- Hardware model / machine (`iPhoneXX,Y`)
- Product type / marketing name

### 4.2 System / OS

- iOS version strings
- Build number
- Device name (user-visible)

### 4.3 Network / carrier (if Zalo reads them)

- Carrier name / MCC-MNC (where accessible from process)
- Local hostname

### 4.4 Storage / hardware traits (optional flags)

- Disk capacity / free space snapshots
- Screen scale / bounds consistency with spoofed model
- Battery / thermal only if needed for fingerprint consistency

> Exact API list and hook points will be defined when dylib source is added.  
> Consistency across hooks matters more than faking a single field.

---

## 5. Typical workflow

```
1. Edit config/          → set spoof profile for Zalo
2. Build dylibs/         → produce iPFaker.dylib (on macOS/Linux toolchain or CI)
3. Deploy via injector/  → push dylib + config to jailbroken device
4. Relaunch Zalo         → force process to load hooks
5. Read logs/            → confirm hooks fired and values match profile
6. Adjust profile        → iterate without rebuilding when only values change
```

### 5.1 Windows role

This workspace is the **control plane**:

- Author and version configs
- Store built dylibs transferred from a build machine
- Keep injector scripts (SSH/SCP, AFC, or USB tooling)
- Archive logs pulled from the device

Build of Objective-C/Swift tweaks usually requires a **macOS + Theos** (or similar) environment; Windows holds project assets and deploy helpers.

### 5.2 Device prerequisites

- Jailbroken iOS with a working tweak loader (Substrate / Substitute / ElleKit / equivalent)
- SSH or equivalent file transfer to the device
- Ability to restart SpringBoard or kill the Zalo process
- Zalo installed and launchable

---

## 6. Security & ethics

- Use only on devices and accounts you are authorized to test.
- Spoofing can violate app ToS; you accept that risk.
- Do not use this project to commit fraud, evade law enforcement, or harm others.
- Keep spoof profiles and logs private if they map to real identities.

---

## 7. Versioning

| Component | Scheme |
|-----------|--------|
| Config profiles | Semantic labels: `profile-default`, `profile-iphone15-ios17` |
| Dylib | `MAJOR.MINOR.PATCH` embedded or filename suffix |
| README / layout | Update this file when folder roles change |

---

## 8. Status

| Item | Status |
|------|--------|
| Folder structure | Done |
| README | Done |
| Config schema (Nông + Sâu, one-button full) | Done |
| `active_profile.json` builder | Done (`scripts/build_active_profile.ps1`) |
| Injector deploy (SSH/SCP) + device paths | Done |
| Frida lab runtime (expanded + RPC verify) | Done (`frida/iPFaker.js`) |
| E2E checklist | Done (`docs/E2E_CHECKLIST.md`) |
| Hook surface doc | Done (`dylibs/HOOKS.md`) |
| Theos dual dylib (MG+CT) rootless deb scaffold | Done (`theos/`) — like ChangeInfo layout |
| Compare doc vs ChangeInfo deb | Done (`docs/COMPARE_CHANGEINFO.md`) |
| Built `iPFakerMG/CT.dylib` + `.deb` artifact | Pending (macOS `make package`) |
| HIOS-style GUI app | Out of scope for now (Windows deploy) |
| On-device E2E verify (fill checklist) | Pending (needs device) |

---

## 9. Next steps (planned)

1. ~~Define `config/` schema~~ — `device_profile.json` + `active_profile.json` + `apply.json` + `main.plist`
2. ~~Injector paths + deploy~~ — rootless `/var/jb/iPFaker`, rootful fallback
3. ~~Frida lab hooks~~ — load active profile, hook MG / sysctl / UIDevice / CT / …
4. On-device test: deploy config → Frida attach Zalo → verify Serial / ProductType / IDFV
5. Optional: Theos dylib implementing same surface as `HOOKS.md`

### 9.1 Quick lab commands (Windows control plane)

```powershell
# Rebuild merged profile (Nông + Sâu)
powershell -File scripts\build_active_profile.ps1

# After reset: Dopamine ROOTLESS (default layout)
powershell -File injector\deploy.ps1 -DeviceHost 192.168.x.x -Layout rootless -RebuildProfile -SkipDylib -KillZalo

# Pull logs later
powershell -File scripts\pull_logs.ps1 -DeviceHost 192.168.x.x -Layout rootless
```

Post-reset guide: `docs/ROOTLESS_AFTER_RESET.md`  
HIOS+ roadmap: `docs/HIOS_PLUS_ROADMAP.md`  
RootHide (legacy option): `docs/ROOTHIDE.md`

### 9.2 Wipe Zalo sạch (kiểu HIOS)

```powershell
# SSH full wipe (container + keychain best-effort)
powershell -File scripts\wipe_zalo.ps1 -DeviceHost 192.168.x.x

# Hoặc USB Frida only
powershell -File scripts\wipe_zalo.ps1 -FridaOnly

# Rồi bật spoof TRƯỚC khi mở Zalo
python scripts\e2e_frida_usb.py --ultra
```

Chi tiết: `docs/WIPE_ZALO.md`

```text
# On PC with Frida + USB
frida -U -f com.zing.zalo -l frida/iPFaker.js --no-pause

# In Frida REPL after attach
rpc.exports.verify()
rpc.exports.hits()
rpc.exports.dump()
```

E2E form: `docs/E2E_CHECKLIST.md`  
RootHide: `docs/ROOTHIDE.md`  
vs ChangeInfo deb: `docs/COMPARE_CHANGEINFO.md`  
Theos dual-dylib deb: `theos/README.md`

---

## 10. Quick reference

| Path | Purpose |
|------|---------|
| `C:\Users\Pem\Desktop\iPFaker\` | Project root (Windows) |
| `config\` | Spoof profiles & flags |
| `dylibs\` | Hook binaries |
| `injector\` | Install / inject tooling |
| `logs\` | Debug & verification output |

**Bundle ID (fixed target):** `com.zing.zalo`

---

*iPFaker — device identity spoofing for Zalo on jailbroken iOS.*
