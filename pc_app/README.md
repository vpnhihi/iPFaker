# iPFaker PC

App Windows điều khiển iPhone lab qua **Wi‑Fi SSH** (không bắt buộc USB).

Tổng quan dự án: [docs/MEMORY.md](../docs/MEMORY.md) · Cài iOS: [INSTALL_KHACH.md](../INSTALL_KHACH.md)

---

## Chạy

```bat
pc_app\CHAY_APP.bat
```

hoặc:

```bat
cd C:\Users\Pem\Desktop\iPFaker
python -m pip install -r pc_app\requirements.txt
python pc_app\app.py
```

Cấu hình local (IP, mật khẩu SSH, API keys):  
`%APPDATA%\iPFakerPC\settings.json` — **không commit**.

---

## Tabs

| Tab | Việc |
|-----|------|
| **Điều khiển** | Kết nối SSH · spoof từ pool ĐT · wipe · **CHẠY QUY TRÌNH REG** |
| **Quy trình 18 bước** | Bảng tên, DOB/gender, delay min–max từng bước |
| **API keys** | BossOTP · RotaProxy · Captcha (2captcha / CapSolver / Achi) |

### Pool máy / iOS

Chọn trên **app iPFaker iPhone** (tab Chọn máy). PC chỉ **đọc** `pools.json` / prefs — không có list chọn máy trên PC.

---

## Quy trình reg 18 bước (tóm tắt)

1. RotaProxy xoay IP  
2. Shadowrocket tắt/bật  
3. iPFaker đặt lại data (pool điện thoại)  
4–5. Zalo tạo TK + SĐT (BossOTP) + tick điều khoản  
6. Captcha (Achi / 2captcha / CapSolver)  
7. OTP BossOTP (có send-sms 7539/8500 nếu cần)  
8. Privacy options  
9. Tên (bảng random)  
10. Sinh nhật + giới tính (bảng random)  
11. Avatar → Bỏ qua  
12. Danh bạ → skip/continue  
13. Ngâm random (`13_soak`)  
14–18. App Data Manager `com.tigisoftware.appdatamanager`  

Mọi bước: delay random — sửa tab **Quy trình 18 bước**.

---

## Module code

| File | Vai trò |
|------|---------|
| `app.py` | GUI |
| `device_client.py` | SSH |
| `reg_pipeline.py` | Pipeline 18 bước |
| `bossotp.py` | BossOTP API |
| `rotaproxy.py` | RotaProxy changeip |
| `captcha_providers.py` | Multi captcha |
| `phone_pool.py` | Đọc pool từ iPhone |
| `workflow_data/` | names, profiles, delays |

---

## Dependencies

```
paramiko
frida   # reg Frida UI
```
