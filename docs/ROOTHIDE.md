# iPFaker trên **RootHide**

Thiết bị của bạn dùng **RootHide** (rootless + ẩn jailbreak). Layout mặc định của project: **`roothide`**.

---

## Vì sao khác rootless thường?

| Vấn đề | Ảnh hưởng iPFaker |
|--------|-------------------|
| `/var/jb` bị ẩn / random (jbroot) | App Zalo **không đọc** config trong `/var/jb/...` |
| Inject third-party app **tắt mặc định** | Tweak `.dylib` không vào Zalo nếu chưa bật |
| Hide JB theo app | Có thể chặn path/tweak khi test |

**Giải pháp iPFaker:**

1. Đặt profile tại **`/var/mobile/Library/iPFaker/`** (Zalo/mobile đọc được).  
2. Mirror thêm `/var/jb/iPFaker/config/` (tiện SSH).  
3. Lab trước bằng **Frida** (không cần dylib).  
4. Bật inject Zalo trong RootHide Manager khi cài tweak native.

---

## Chuẩn bị trên máy (1 lần)

1. **SSH**  
   - Cài OpenSSH (Sileo/Zebra repo RootHide).  
   - Cùng Wi‑Fi với PC.  
   - User thường: `root` · port `22`.  
   - Lấy IP: Settings → Wi‑Fi → (i) → IP Address.

2. **RootHide Manager / Bootstrap**  
   - Tìm **App Inject** / cho phép inject third-party.  
   - **Bật inject cho `com.zing.zalo` (Zalo)** nếu dùng dylib.  
   - Lúc test Frida: không bắt buộc inject tweak.  
   - Lúc test spoof: tạm **không Hide Jailbreak** cho Zalo (tránh lệch kết quả).

3. **PC**  
   - OpenSSH Client (Windows optional feature).  
   - Frida + frida-server trên máy (USB khuyến nghị).

---

## Deploy config (Windows)

```powershell
cd C:\Users\Pem\Desktop\iPFaker

# Thay IP máy bạn
powershell -File injector\deploy.ps1 `
  -DeviceHost 192.168.x.x `
  -Layout roothide `
  -RebuildProfile `
  -SkipDylib `
  -KillZalo
```

Sau deploy, trên máy (SSH) kiểm tra:

```bash
ls -la /var/mobile/Library/iPFaker/
# active_profile.json  main.plist  apply.json  device_profile.json  ...
```

---

## E2E Frida (làm trước — không cần Theos)

USB:

```text
frida -U -f com.zing.zalo -l frida/iPFaker.js --no-pause
```

Trong REPL:

```text
rpc.exports.profile()
rpc.exports.verify()
rpc.exports.hits()
```

Kỳ vọng:

- `Loaded profile: /var/mobile/Library/iPFaker/active_profile.json`  
- `VERIFY` gần **GREEN** với Serial / ProductType / IDFV / …  
- Điền `docs/E2E_CHECKLIST.md`

---

## Đường dẫn RootHide (tóm tắt)

| Vai trò | Path |
|---------|------|
| Config (chính, Zalo đọc) | `/var/mobile/Library/iPFaker/active_profile.json` |
| Config mirror SSH | `/var/jb/iPFaker/config/` |
| Log | `/var/mobile/Library/iPFaker/logs/` |
| Tweak (sau khi build) | `/var/jb/Library/MobileSubstrate/DynamicLibraries/iPFaker.dylib` |
| ElleKit alt | `/var/jb/usr/lib/TweakInject/iPFaker.dylib` |

Frida script thử lần lượt:

1. `/var/mobile/Library/iPFaker/active_profile.json`  
2. `/var/jb/iPFaker/config/active_profile.json`  
3. …

---

## Tweak native (sau khi E2E Frida GREEN)

1. Build trên Mac: `theos/` → `make package` (scheme **rootless**).  
2. Copy `iPFaker.dylib` → `dylibs\`.  
3. Deploy **không** `-SkipDylib`.  
4. RootHide: inject **ON** cho Zalo.  
5. Kill Zalo → mở lại → verify lại (Frida attach optional).

---

## Troubleshooting nhanh

| Hiện tượng | Xử lý |
|------------|--------|
| Frida: `no profile found` | Deploy lại; `chmod 644` + `chown mobile`; kiểm tra path mobile Library |
| SSH refused | Bật OpenSSH, cùng Wi‑Fi, đúng IP/port/password |
| Tweak không load | Bật App Inject Zalo; kiểm tra `.dylib`+`.plist` cùng tên |
| Zalo crash | Gỡ dylib tạm; dùng Frida-only; xem log |
| `/var/jb` không list được từ app | Bình thường RootHide — dùng path mobile Library |

---

## Policy

Lab only · identity synthetic · chỉ target Zalo · máy bạn sở hữu.
