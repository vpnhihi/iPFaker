# Làm iPFaker **không cần Mac** (Windows only)

## Kết luận nhanh

| Cách | Fake model (XS Max → 15 Pro) | Cần Mac nhà? |
|------|------------------------------|--------------|
| Frida Gadget + ElleKit | **Không ổn** (đã thử, Zalo vẫn XS Max) | Không |
| **GitHub Actions build Theos** | **Có** (dylib native như HIOS) | **Không** |
| Mượn/thuê Mac 1 giờ | Có | Có (tạm) |
| Chỉ wipe + config | Không spoof hardware | Không |

→ **Hướng chính: GitHub Actions (macOS runner).**

---

## Hướng 1 — GitHub Actions (khuyến nghị)

### Ý tưởng
- Code Theos nằm trong repo `theos/`
- GitHub cho mượn **máy Mac ảo** build `.dylib` / `.deb`
- Bạn (Windows): push code → bấm Run → tải zip → SSH copy lên iPhone

### Chuẩn bị (1 lần)

1. Tạo tài khoản [GitHub](https://github.com) (free).
2. Cài [Git for Windows](https://git-scm.com/download/win) (nếu chưa có).
3. Trên PC, trong thư mục project:

```powershell
cd C:\Users\Pem\Desktop\iPFaker

git init
git add .
git commit -m "iPFaker rootless lab"
```

4. Trên GitHub: **New repository** (private cũng được) tên ví dụ `iPFaker`.
5. Push:

```powershell
git remote add origin https://github.com/USER_CUA_BAN/iPFaker.git
git branch -M main
git push -u origin main
```

(Đăng nhập GitHub khi được hỏi.)

### Build dylib

1. Vào repo trên web → tab **Actions**
2. Chọn workflow **Build Theos rootless**
3. **Run workflow** → Run
4. Đợi ~10–20 phút (lần đầu lâu hơn)
5. Vào run đã xong → **Artifacts** → tải **`ipfaker-dylibs`**
6. Giải nén, copy vào:

```text
C:\Users\Pem\Desktop\iPFaker\dylibs\iPFakerMG.dylib
C:\Users\Pem\Desktop\iPFaker\dylibs\iPFakerCT.dylib
```

(plist filter đã có trong `theos/layout/...` hoặc trong artifact)

### Cài lên iPhone (từ Windows)

```powershell
cd C:\Users\Pem\Desktop\iPFaker
python scripts\deploy_native_dylibs.py
```

(Script sẽ SSH `mobile@IP` / `[REDACTED]`, copy dylib vào TweakInject, **gỡ FridaGadget**, kill Zalo.)

Rồi:

1. Respring: NewTerm `sudo killall -9 SpringBoard`
2. Wipe Zalo (nếu cần): `python scripts\_tmp_ssh_wipe.py`
3. Mở Zalo → **Quản lý thiết bị** — kỳ vọng **không** còn XS Max nếu hook MG OK (sẽ là 15 Pro / tên lab)

### Lưu ý GitHub Free

- Repo **public**: macOS minutes rộng hơn
- Repo **private**: có giới hạn phút Mac/tháng — đủ lab vài lần build
- Workflow file: `.github/workflows/build-theos.yml`

Nếu build **fail** (thiếu SDK Theos): gửi log Actions — chỉnh workflow (thêm SDK).

---

## Hướng 2 — Frida Gadget (đã thử)

- **Không** cần Mac  
- **Không** đủ để Zalo đổi đời máy (vẫn XS Max)  
- Chỉ giữ để thử hook nhẹ / debug, **không** dựa vào cho fake sâu  

Có thể gỡ:

```sh
# NewTerm root
rm -f /var/jb/usr/lib/TweakInject/FridaGadget.*
rm -f /var/jb/usr/lib/TweakInject/iPFakerGadget.*
killall -9 SpringBoard
```

---

## Hướng 3 — Thuê Mac cloud / Mac cafe

- MacStadium, GitHub Codespaces (ít hỗ trợ Theos), hoặc bạn bè Mac  
- `cd theos && make package`  
- Copy deb/dylib về Windows rồi SSH lên máy  

Chỉ khi không muốn dùng GitHub.

---

## Thứ tự làm việc (Windows → fake sâu)

```text
1. GitHub repo + push iPFaker
2. Actions build → tải iPFakerMG + iPFakerCT
3. deploy_native_dylibs.py  (SSH lên [DEVICE_HOST])
4. Gỡ FridaGadget
5. Respring
6. Wipe Zalo (SSH)
7. Mở Zalo / tạo account lab
8. Kiểm tra "Quản lý thiết bị" ≠ XS Max
```

---

## SSH máy bạn (nhắc lại)

| | |
|--|--|
| IP | `[DEVICE_HOST]` (đổi nếu Wi‑Fi đổi) |
| User | `mobile` |
| Pass | `[REDACTED]` |
| Root | `sudo -i` (cùng pass) |

---

## Tóm một câu

**Không Mac nhà → dùng GitHub Actions build dylib, Windows chỉ deploy SSH.**  
Gadget không thay được bước đó cho fake đời máy trên Zalo.
