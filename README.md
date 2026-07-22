# iPFaker

Jailbreak tool (**Dopamine rootless**) — spoof device identity cho **Zalo**, app quản lý trên máy, license **Google Sheet**, tùy chọn app **PC** (SSH).

---

## Khách hàng — cài ngay

| Bước | Link / hành động |
|------|------------------|
| 1. Nguồn Sileo | **`https://vpnhihi.github.io/ipfaker/`** (chữ thường) |
| 2. Hướng dẫn cài + key | **[INSTALL_KHACH.md](INSTALL_KHACH.md)** |
| 3. Sheet license | **[docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md)** |
| 4. Deb trực tiếp | `https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.0_iphoneos-arm64.deb` |
| 5. Tools / máy mới | **[tools/README.md](tools/README.md)** — full stack 1 lần = như lab |

> Repo GitHub: https://github.com/vpnhihi/ipfaker  

---

## Dev / vận hành (nhớ toàn bộ)

| Tài liệu | Nội dung |
|----------|----------|
| **[docs/MEMORY.md](docs/MEMORY.md)** | **Bộ nhớ dự án đầy đủ** — Sileo, license, PC 18 bước, path máy, không push secret |
| [docs/SILEO.md](docs/SILEO.md) | Build/publish nguồn Sileo |
| [pc_app/README.md](pc_app/README.md) | App Windows điều khiển SSH |

### Chạy app PC (Windows)

```bat
pc_app\CHAY_APP.bat
```

### Publish lại Sileo Pages

```bat
python scripts\publish_gh_pages_sileo.py
```

### Icon app

```bat
python scripts\gen_app_icons.py path\to\icon.png
```

---

## Tính năng chính (máy)

- Full stack lab: **MG · CT · JB · About · AboutUI · AboutVer · AA**  
- Spoof identity + Settings About sync + multi-app wipe (Zalo-depth)  
- Multi model iPhone + multi iOS (matrix), multi-select pool  
- **Đặt lại dữ liệu app** / **Đặt lại + Lưu dữ liệu** (giữ login)  
- License key + **ID máy** + Chạy/Dừng/Out  
- UI tiếng Việt, icon custom  

## Tính năng chính (PC — tùy chọn)

- Spoof/wipe theo pool điện thoại  
- Pipeline reg Zalo 18 bước (BossOTP, RotaProxy, captcha, AppManager…)  
- Delay random từng bước, bảng tên / DOB  

---

## Không đưa lên git

Secrets, settings API, lab inject scripts, logs, artifact build thô — xem `.gitignore` và [docs/MEMORY.md](docs/MEMORY.md) §1.

---

## Legal

Chỉ dùng trên thiết bị sở hữu / lab hợp pháp. Không dùng để lừa đảo, mạo danh, vi phạm pháp luật.
