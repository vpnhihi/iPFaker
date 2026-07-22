# Xóa sạch Zalo (kiểu reference stack)

Mục tiêu lab: sau wipe, Zalo mở như **cài mới** (mất device id local / session / keychain app), rồi mới bật spoof và tạo account test.

> Chỉ dùng trên máy jailbreak **bạn sở hữu**. Mất hết chat/login Zalo trên máy.

---

## So với baseline reference

| reference stack | iPFaker |
|-------------------|---------|
| `wipeZaloKC` trong dylib | `frida/wipe_zalo_kc.js` + SQL keychain best-effort |
| App bấm “đổi máy” → wipe | `scripts/wipe_zalo.ps1` / `injector/wipe_zalo.sh` |
| Xóa binding local | Container + App Group + Preferences + keychain pattern |

---

## Cách 1 — SSH (đầy đủ nhất)

```powershell
cd C:\Users\Pem\Desktop\iPFaker

# Xem trước (không xóa)
powershell -File scripts\wipe_zalo.ps1 -DeviceHost 192.168.x.x -DryRun

# Xóa thật
powershell -File scripts\wipe_zalo.ps1 -DeviceHost 192.168.x.x
```

Script remote: `/var/mobile/Library/iPFaker/wipe_zalo.sh`  
Log: `/var/mobile/Library/iPFaker/logs/wipe_zalo_*.log`

### NewTerm / Filza (không PC)

1. Copy `injector/wipe_zalo.sh` → `/var/mobile/Library/iPFaker/wipe_zalo.sh`  
2. `chmod 755`  
3. `sh /var/mobile/Library/iPFaker/wipe_zalo.sh`

---

## Cách 2 — Frida only (USB, không SSH)

```powershell
powershell -File scripts\wipe_zalo.ps1 -FridaOnly
# hoặc:
frida -U -f vn.com.vng.zingalo -l frida\wipe_zalo_kc.js -q -t 20
```

Xóa sandbox process + UserDefaults + keychain **trong entitlement app**.  
Không thay thế hoàn toàn wipe container qua root (Cách 1 mạnh hơn).

---

## Flow lab “máy mới” (quan trọng)

```text
1. Tắt iFakePro / spoof khác cho Zalo
2. wipe_zalo (SSH hoặc Frida)
3. (Optional) đổi IDFV/IDFA/Serial trong device_profile → build_active_profile.ps1
4. Bật spoof TRƯỚC khi mở Zalo
     python scripts\e2e_frida_usb.py --ultra
5. Cold start Zalo → màn hình như cài mới
6. Mới tạo tài khoản / đăng nhập lab
```

**Sai:** mở Zalo trước spoof sau wipe → ghi lại id máy thật.  
**Sai:** wipe nhưng không spoof → vẫn thiết bị gốc.

---

## Script xóa những gì?

| Hạng mục | `wipe_zalo.sh` | `wipe_zalo_kc.js` |
|----------|----------------|-------------------|
| Kill Zalo | ✓ | exit process |
| Data container Documents/Library/tmp | ✓ | sandbox paths |
| App Group shared | ✓ | — |
| Preferences / Cookies crumbs | ✓ | UserDefaults |
| Keychain (pattern / app-visible) | SQL best-effort + backup | SecItemDelete app scope |
| Gỡ app binary | ✗ (giữ app) | ✗ |

Keychain SQL có **backup** `keychain-2.db.ipfaker_bak_*`. Nếu lỡ xóa nhầm, restore từ backup (advanced).

---

## Troubleshooting

| Hiện tượng | Xử lý |
|------------|--------|
| Vẫn “thiết bị gốc” | Chưa wipe keychain / mở Zalo trước spoof / iFakePro conflict |
| Không tìm container | Sai bundle — dùng `vn.com.vng.zingalo` |
| SSH fail | Dùng Filza + NewTerm hoặc `-FridaOnly` |
| Login Apple/keychain lỗi hệ thống | Restore keychain backup; lần sau dùng Frida wipe only |

---

## File

| Path | Vai trò |
|------|---------|
| `injector/wipe_zalo.sh` | Wipe root trên máy |
| `scripts/wipe_zalo.ps1` | Điều khiển từ Windows |
| `frida/wipe_zalo_kc.js` | Wipe in-process |
| `config/device_profile.json` → `zalo_storage` | Rules / flow |
