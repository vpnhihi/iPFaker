# Ma trận iOS ↔ iPhone (strict)

Nguồn **chuẩn Apple** (cập nhật 2026-07-20):

| Nguồn | URL |
|-------|-----|
| iPhone User Guide — models compatible with iOS 14 / 15 / 16 / 17 / 18 / **26** | https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/ios |
| How to download iOS 18 (danh sách máy) | https://support.apple.com/en-us/104985 |
| Apple security releases (point version mới nhất) | https://support.apple.com/en-us/100100 |

File machine-readable:

- `config/ios_device_compat.json` — `ios_to_devices` + `device_to_ios` + `device_first_max_major`
- `config/device_catalog.json` — mỗi device có `supportedIOS`, `minIOS`, `maxIOS`, `defaultIOS`
- Rebuild: `python scripts/rebuild_apple_matrix.py` (đồng bộ luôn sang `theos/app/Resources/`)

## Quy tắc tools

1. **Chỉ cho chọn cặp** có trong matrix.  
2. Script: `scripts/select_device_profile.py` (strict mặc định; `--force` để bỏ qua).  
3. App iPFaker: màn **Chọn iOS** chỉ liệt kê `supportedIOS` của máy đang chọn.  
4. **Apply** tự snap về iOS hợp lệ nếu user lỡ chọn sai.

## Phạm vi major

| Major | Trạng thái |
|-------|------------|
| **8 – 13** | Có (historical point builds) |
| **14 – 18** | Có |
| **19 – 25** | **Không tồn tại** — tools **không** offer |
| **26** | Có (lab builds); latest **26.5.2** |

## First / max (tóm tắt Apple)

| Model | First | Max major | Max point |
|-------|-------|-----------|-----------|
| **iPhone 6 / 6 Plus** | **8.0** | **12** | **12.5.8** |
| 6s / 6s Plus | 9.0 | 15 | **15.8.8** |
| SE1 | 9.3 | 15 | **15.8.8** |
| 7 / 7 Plus | 10.0 | 15 | **15.8.8** |
| 8 / 8 Plus | 11.0 | 16 | **16.7.16** |
| X | 11.0.1 | 16 | **16.7.16** |
| XR / XS / XS Max | 12.0 | 18 | **18.7.9** |
| 11 / 11 Pro / SE2 | 13 / 13.4 | 26 | **26.5.2** |
| 12 series | 14.1 | 26 | **26.5.2** |
| 13 – 16e | 15–18.3 | 26 | **26.5.2** |
| 17 / Air / 17 Pro / 17 PM / **17e** | 26.0 | 26 | **26.5.2** |

## Ngoại lệ

| Model | Ghi chú |
|-------|---------|
| iPhone 6 / 6 Plus | **8.0 → 12.5.8** (83 builds) — **không** iOS 13+ |
| Board CDMA / China (`*-cdma`, `iphonex-global`, `iphonexs-max-cn`) | Cùng range GSM/Global |
| iOS 26.x | `lab: true` trên build labels (spoof lab) |

## Ví dụ

```bash
# iOS hợp lệ cho 15 Pro
python scripts/select_device_profile.py -d iphone15-pro --list-ios

# Cặp sai → lỗi
python scripts/select_device_profile.py -d iphone6s -i 18.5
# → INVALID pair … try -i 15.8.8

python scripts/select_device_profile.py -d iphonexr -i 26.0
# → INVALID (XR max 18.7.9)

# Cặp đúng
python scripts/select_device_profile.py -d iphone16-pro-max -i 18.7.9 --deploy
python scripts/select_device_profile.py -d iphone17-pro-max -i 26.5.2 --deploy
```

## Cập nhật matrix

1. Chỉnh `DEVICE_RANGE` / `EXTRA_RELEASES` trong `scripts/rebuild_apple_matrix.py` theo Apple Support mới.  
2. Chạy `python scripts/rebuild_apple_matrix.py`.  
3. Copy đã tự sync vào `theos/app/Resources/` — rebuild app / push catalog lên máy khi cần.
