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
2. SSH user mặc định: `mobile` (mật khẩu rootless thường là mật khẩu bạn đặt / `alpine` lab)
3. Trong app PC: nhập IP + mật khẩu → **Kết nối**

Cấu hình được lưu tại: `%APPDATA%\iPFakerPC\settings.json`

## Nút chức năng

| Nút | Giống app iOS | Hành vi |
|-----|---------------|---------|
| **Áp dụng máy đã chọn** | Ghi config | Random 1 cặp máy+iOS **hợp lệ** trong pool → ghi spoof |
| **Đặt lại dữ liệu app** | Đặt lại dữ liệu app | Random spoof + **xóa data** → **mất login** |
| **Đặt lại + Lưu dữ liệu** | Đặt lại + Lưu | Backup config+data → random spoof → wipe → **restore login** |
| **Chỉ xóa data app** | Wipe tab | Xóa data app đã tick |
| **Mở Zalo** | — | `uiopen` Zalo |

## App mục tiêu

Tick app cần lưu/xóa (mặc định Zalo). Maps / Thời tiết tùy chọn.

Backup trên máy: `/var/mobile/Library/iPFaker/backups/<timestamp>/`

## Lưu ý

- Máy và PC **cùng mạng** (hoặc VPN/tunnel có route SSH).
- Spoof Zalo vẫn do dylib `iPFakerMG` / `iPFakerCT` trên máy — app PC chỉ **ghi config + wipe/backup**.
- Sau mỗi lần spoof: **mở lại Zalo** để nạp identity mới.
- Không commit mật khẩu lên git; file settings nằm ngoài repo.
