# iPFaker PC

App Windows điều khiển **iPFaker** trên iPhone jailbreak qua **Wi‑Fi SSH** — **không cần cắm USB**.

## Yêu cầu

| PC | iPhone |
|----|--------|
| Windows + Python 3.10+ | Dopamine rootless còn JB |
| Cùng Wi‑Fi với máy | OpenSSH (mobile) bật |
| `pip install paramiko` | Gói `com.ipfaker` đã cài (Sileo) |

## Chạy

```bat
pc_app\run_ipfaker_pc.bat
```

hoặc:

```bat
cd Desktop\iPFaker
python -m pip install -r pc_app\requirements.txt
python pc_app\app.py
```

## Kết nối

1. Trên iPhone: **Cài đặt → Wi‑Fi → (i) → Địa chỉ IP** (vd `192.168.1.10`)
2. SSH user mặc định: `mobile`
3. Trong app PC: nhập IP + mật khẩu → **Kết nối**

**Pool máy / iOS:** chọn trên app **iPFaker iPhone** (tab Chọn máy / iOS). PC **không** chọn pool — chỉ đọc `pools.json` từ máy.

Cấu hình PC: `%APPDATA%\iPFakerPC\settings.json` (tab **API SMS / Captcha**).

## Nút chức năng

| Nút | Giống app iOS | Hành vi |
|-----|---------------|---------|
| **Áp dụng máy đã chọn** | Ghi config | Random 1 cặp máy+iOS **hợp lệ** trong pool → ghi spoof |
| **Đặt lại dữ liệu app** | Đặt lại dữ liệu app | Random spoof + **xóa data** → **mất login** |
| **Đặt lại + Lưu dữ liệu** | Đặt lại + Lưu | Backup config+data → random spoof → wipe → **restore login** |
| **Chỉ xóa data app** | Wipe tab | Xóa data app đã tick |
| **Mở Zalo** | — | `uiopen` Zalo |
| **Reg tự động → tới OTP** | Lab Frida | Spoof/wipe (tuỳ chọn) → mở Zalo → inject Gadget → chạm Đăng ký → điền SĐT |
| **Gửi OTP / Tiếp reg** | Lab Frida | Điền OTP (nếu gõ trên PC) + tên + bấm Tiếp tục |
| **Dừng Frida reg** | — | Gỡ session Frida |

### Reg tự động — cách dùng

1. Kết nối SSH, chọn pool máy/iOS  
2. Nhập **SĐT** (+ tên hiển thị)  
3. Tick *Random spoof* / *Xóa data Zalo* nếu muốn profile sạch  
4. **Mở khóa màn hình** iPhone  
5. Bấm **Reg tự động → tới OTP**  
6. Khi Zalo hỏi OTP: nhập SMS trên máy **hoặc** gõ vào ô OTP → **Gửi OTP / Tiếp reg**  
7. Captcha / chọn ảnh (nếu có) làm tay trên máy  

Cần: `pip install frida`, file `frida/zalo_ui_auto.bundle.js`, `opainject` trên máy (Dopamine), FridaGadget trên máy hoặc `downloads/FridaGadget.dylib`.

### API SMS (SĐT + OTP)

Tab **API SMS / Captcha**:

| Field | Ví dụ |
|-------|--------|
| URL thuê số | `https://PROVIDER/rent?key={api_key}&service=zalo` |
| URL OTP | `https://PROVIDER/code?key={api_key}&id={order_id}` |
| JSON path SĐT | `phone\|data.phone\|number` |
| JSON path order | `id\|data.id\|order_id` |
| JSON path OTP | `otp\|code\|data.code\|message` |

Placeholder: `{api_key}`, `{order_id}`, `{id}`.

### AchiCaptcha

| Field | Mặc định |
|-------|----------|
| createTask | `https://achicaptcha.com/api/createTask` |
| getTaskResult | `https://achicaptcha.com/api/getTaskResult` |
| API key | clientKey |

Luồng: chụp màn hình iPhone → gửi ảnh base64 (ImageToTextTask) → điền text vào Zalo qua Frida.  
Nếu docs Achi của bạn khác URL/body — sửa 2 URL (hoặc báo để chỉnh template JSON).

## App mục tiêu

Tick app cần lưu/xóa (mặc định Zalo). Maps / Thời tiết tùy chọn.

Backup trên máy: `/var/mobile/Library/iPFaker/backups/<timestamp>/`

## Lưu ý

- Máy và PC **cùng mạng** (hoặc VPN/tunnel có route SSH).
- Spoof Zalo vẫn do dylib `iPFakerMG` / `iPFakerCT` trên máy — app PC chỉ **ghi config + wipe/backup**.
- Sau mỗi lần spoof: **mở lại Zalo** để nạp identity mới.
- Không commit mật khẩu lên git; file settings nằm ngoài repo.
