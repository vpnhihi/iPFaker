# iPFaker — E2E checklist (lab)

**Target:** `com.zing.zalo`  
**Profile:** `config/active_profile.json` (Nông + Sâu, one-button full)  
**Policy:** synthetic identity only · owned jailbroken device only

Mark each box when verified. Fill **Actual** column on device.

---

## 0. Prerequisites

| # | Check | OK |
|---|--------|----|
| 0.1 | Device **RootHide** jailbroken + SSH (root) | [ ] |
| 0.2 | Zalo installed (`com.zing.zalo`) | [ ] |
| 0.3 | PC: OpenSSH client, Frida, USB or Wi‑Fi | [ ] |
| 0.4 | `scripts\build_active_profile.ps1` runs without error | [ ] |
| 0.5 | `active_profile.json` has non-null `uidevice` | [ ] |
| 0.6 | (Tweak later) RootHide Manager: **App Inject ON** for Zalo | [ ] |
| 0.7 | Đã đọc `docs/ROOTHIDE.md` | [ ] |
| 0.8 | Đã đọc `docs/E2E_FRIDA_ROOTHIDE.md` | [ ] |
| 0.9 | `frida-ps -U` thấy process (frida-server chạy) | [ ] |

```powershell
powershell -File scripts\build_active_profile.ps1
```

---

## 1. Deploy config

| # | Step | OK |
|---|------|----|
| 1.1 | Deploy rootless config to device | [ ] |
| 1.2 | Confirm remote files exist | [ ] |
| 1.3 | Kill Zalo before first attach | [ ] |

```powershell
powershell -File injector\deploy.ps1 -DeviceHost <IP> -Layout roothide -RebuildProfile -SkipDylib -KillZalo
```

```bash
# on device via SSH — RootHide primary path
ls -la /var/mobile/Library/iPFaker/
# expect: active_profile.json  device_profile.json  main.plist  apply.json
```

| Path (RootHide) | Present |
|-----------------|---------|
| `/var/mobile/Library/iPFaker/active_profile.json` | [ ] |
| `/var/mobile/Library/iPFaker/main.plist` | [ ] |
| `/var/mobile/Library/iPFaker/frida/iPFaker.js` (optional) | [ ] |
| `/var/jb/iPFaker/config/` (mirror, optional) | [ ] |

---

## 2. Frida attach

| # | Step | OK |
|---|------|----|
| 2.1 | Spawn Zalo with script | [ ] |
| 2.2 | Console shows `Loaded profile` | [ ] |
| 2.3 | Console shows `Hooks installed` | [ ] |
| 2.4 | No immediate crash of Zalo | [ ] |

```text
frida -U -f com.zing.zalo -l frida/iPFaker.js --no-pause
```

Optional (after attach):

```text
# in Frida REPL
rpc.exports.verify()
rpc.exports.hits()
rpc.exports.dump()
```

---

## 3. P0 identity verify (must pass)

Compare **Expected** (from current lab profile) vs **Actual** (from `rpc.exports.verify()` or hook logs).

| Field | Expected (lab profile v2.1.1) | Actual | Pass |
|-------|-------------------------------|--------|------|
| ProductType / hw.machine | `iPhone16,1` | | [ ] |
| HWModel / D83AP | `D83AP` | | [ ] |
| SerialNumber | `G6TZN2X0JK` | | [ ] |
| UniqueDeviceID / UDID | `a1b2c3d4e5f6789012345678abcdef9012345678` | | [ ] |
| IDFV | `7B2E9A1C-3D4F-4E5A-8C6B-1F2A3B4C5D6E` | | [ ] |
| IDFA | `E3A1C8B2-4F5D-4A6E-9B10-C2D3E4F50617` | | [ ] |
| ProductVersion (iOS) | `17.6.1` | | [ ] |
| BuildVersion | `21G93` | | [ ] |
| UIDevice.name | `iPhone Lab Test` | | [ ] |
| CarrierName | `Viettel` | | [ ] |
| MCC / MNC | `452` / `04` | | [ ] |
| WifiAddress (MAC) | `F0:18:98:A3:7C:1E` | | [ ] |

**P0 gate:** all rows above Pass before claiming E2E green.

---

## 4. P1 deep consistency (Fake Sâu)

| Field / behavior | Expected | Actual | Pass |
|------------------|----------|--------|------|
| UniqueChipID / ApECID | `000A1B2C3D4E5F67` | | [ ] |
| Screen scale | `3` | | [ ] |
| Native size | `1179 x 2556` | | [ ] |
| Disk total ~256GB | `255881465856` | | [ ] |
| Hostname | `iPhone-Lab-Test` | | [ ] |
| PlatformUUID | `A1B2C3D4-E5F6-7890-A1B2-C3D4E5F67890` | | [ ] |
| DeviceSupportsFaceID (MG) | `true` | | [ ] |
| DeviceSupportsDynamicIsland | `true` | | [ ] |
| JB path `access("/var/jb")` | fails / -1 | | [ ] |
| WebView UA contains `17_6_1` / `21G93` | yes | | [ ] |

---

## 5. Hook hit smoke (open Zalo UI)

Use Zalo normally 30–60s (login screen is enough for lab). Then:

```text
rpc.exports.hits()
```

| Hook family | Min hits (lab) | Hits | Pass |
|-------------|----------------|------|------|
| mobilegestalt | ≥ 1 | | [ ] |
| uidevice | ≥ 1 | | [ ] |
| sysctl | ≥ 0 (may be lazy) | | [ ] |
| coretelephony | ≥ 0 | | [ ] |

If MG + UIDevice never fire → profile/hooks not active; re-check attach + filter.

---

## 6. Negative / safety checks

| # | Check | OK |
|---|--------|----|
| 6.1 | SpringBoard still shows **real** device name (not spoofed globally) | [ ] |
| 6.2 | Other apps (Safari/Settings) not spoofed when only Frida-on-Zalo | [ ] |
| 6.3 | No real personal Serial/UDID written into repo or logs | [ ] |
| 6.4 | Profile still marked synthetic in `_meta.identity_note` | [ ] |

---

## 7. Logs archive

| # | Step | OK |
|---|------|----|
| 7.1 | Save Frida console output to `logs/e2e_<date>.txt` | [ ] |
| 7.2 | Save `rpc.exports.verify()` JSON dump | [ ] |
| 7.3 | Optional: `scripts\pull_logs.ps1 -DeviceHost <IP>` | [ ] |

```powershell
# example naming
# logs/e2e_2026-07-20_frida.txt
# logs/e2e_2026-07-20_verify.json
```

---

## 8. Result

| Verdict | Meaning |
|---------|---------|
| **GREEN** | All P0 Pass + no crash + safety 6.x OK |
| **YELLOW** | P0 Pass but P1 partial / low hook hits |
| **RED** | Any P0 fail or Zalo crash loop |

**Date:** ____________  
**Device JB:** ____________  
**Zalo version:** ____________  
**Verdict:** [ ] GREEN  [ ] YELLOW  [ ] RED  
**Notes:**

```
(write short notes here)
```

---

## 9. After E2E green (next engineering)

1. Build Theos `iPFaker.dylib` on macOS (`theos/` folder).  
2. Deploy dylib via `injector\deploy.ps1` **without** `-SkipDylib`.  
3. Re-run this checklist without Frida (tweak-only path).  
4. Only then consider wipe/reseed (`zalo_storage`) experiments.
