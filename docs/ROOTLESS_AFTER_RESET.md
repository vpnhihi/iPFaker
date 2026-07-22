# Sau khi reset → Rootless (Dopamine) — checklist iPFaker

Mục tiêu: môi trường **rootless `/var/jb` cố định** để build app/tweak fake sâu lab clean-app (hoặc hơn về profile + Zalo-only lab).

---

## A. Jailbreak rootless

1. Reset máy (Settings → Erase All Content and Settings) nếu bạn đã chốt.
2. Setup iPhone, **không** restore bản RootHide cũ nếu muốn sạch.
3. Cài **TrollStore** (nếu cần) → **Dopamine** (bản rootless chuẩn, **không** bản RootHide).
4. Jailbreak xong → mở Sileo.
5. Cài tối thiểu:
   - **OpenSSH**
   - **ElleKit** (hoặc substitute stack Dopamine dùng)
   - **NewTerm 2** / Filza (tiện)
   - **PreferenceLoader** (nếu sau này có Settings pane)

6. Đặt mật khẩu root **ngay** và ghi ra chỗ an toàn:

```sh
passwd
# user root — đặt pass mới, nhớ kỹ
```

7. Cùng Wi‑Fi PC → lấy IP (Settings → Wi‑Fi → i).

```powershell
# PC test
ssh root@192.168.x.x
```

---

## B. Xác nhận rootless (không RootHide)

Trên máy (SSH hoặc NewTerm):

```sh
ls -la /var/jb
ls /var/jb/Library/MobileSubstrate/DynamicLibraries
echo $PATH
```

- Có **`/var/jb`** ổn định → đúng rootless lab.
- Nếu path JB random / app không thấy `/var/jb` → vẫn đang RootHide-like.

---

## C. Deploy iPFaker (Windows)

```powershell
cd C:\Users\Pem\Desktop\iPFaker

# 1) Build profile
powershell -File scripts\build_active_profile.ps1

# 2) Deploy config rootless
powershell -File injector\deploy.ps1 `
  -DeviceHost 192.168.x.x `
  -Layout rootless `
  -RebuildProfile `
  -SkipDylib `
  -KillZalo

# 3) Wipe Zalo full (SSH root)
powershell -File scripts\wipe_zalo.ps1 -DeviceHost 192.168.x.x
```

---

## D. Frida (lab verify)

```powershell
# frida-server cùng version với PC (frida --version)
# copy frida-server vào /var/jb/usr/sbin/ , chmod +x, chạy root

frida-ps -U
python scripts\e2e_frida_usb.py
```

Zalo bundle: thường `vn.com.vng.zingalo` hoặc `com.zing.zalo` — script auto-detect.

---

## E. Tweak native (lab flat) — khi có Mac + Theos

```bash
export THEOS=~/theos
cd theos
# rootless đã bật trong Makefile
make clean && make package
# cài deb lên máy, hoặc copy iPFakerMG/CT.dylib → dylibs/ rồi deploy.ps1
```

---

## F. Báo cho AI khi xong

Gửi:

1. **IP** máy (SSH OK)  
2. iOS version + **Dopamine rootless** (confirm `/var/jb` list được)  
3. Bundle Zalo (`frida-ps -Uai` có chữ Zalo)  
4. Có **Mac** build Theos không (có/không)

→ Tiếp tục: app/prefs + dylib MG+CT fake sâu, wipe 1 nút, verify E2E.

---

## Policy lab (giữ nguyên)

- Synthetic identity only  
- Máy / account test bạn sở hữu  
- Scope mặc định: **Zalo** (mở rộng app khác chỉ khi bạn yêu cầu)
