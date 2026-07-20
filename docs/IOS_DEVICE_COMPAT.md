# Ma trận iOS ↔ iPhone (strict)

Nguồn: danh sách user (iOS **14.4 → 26.5.1**).  
File machine-readable:

- `config/ios_device_compat.json` — `ios_to_devices` + `device_to_ios`
- `config/device_catalog.json` — mỗi device có `supportedIOS`, `minIOS`, `maxIOS`, `defaultIOS`

## Quy tắc tools

1. **Chỉ cho chọn cặp** có trong matrix.  
2. Script: `scripts/select_device_profile.py` (strict mặc định; `--force` để bỏ qua).  
3. App iPFaker: màn **Chọn iOS** chỉ liệt kê `supportedIOS` của máy đang chọn.  
4. **Apply** tự snap về iOS hợp lệ nếu user lỡ chọn sai.

## Ngoại lệ

| Model | Ghi chú |
|-------|---------|
| iPhone 6 / 6 Plus | **Không** có trong matrix user → `supportedIOS: []` |
| Board CDMA / China (`*-cdma`, `iphonex-global`, `iphonexs-max-cn`) | Kế thừa matrix của bản GSM/Global |
| iOS 19–25 | **Không** có trong list user (nhảy 18.7.1 → 26.0) → không offer |
| iOS 26.x | Có trong matrix; đánh dấu `lab: true` trong builds |

## Ví dụ

```bash
# iOS hợp lệ cho 15 Pro
python scripts/select_device_profile.py -d iphone15-pro --list-ios

# Cặp sai → lỗi
python scripts/select_device_profile.py -d iphone6s -i 18.5
# → INVALID pair … try -i 15.8.5

# Cặp đúng
python scripts/select_device_profile.py -d iphone16-pro-max -i 18.5 --deploy
```

## Cập nhật matrix

Sửa / thay `config/ios_device_compat.json` rồi chạy lại script merge (hoặc chỉnh `device_catalog.json` `supportedIOS`).  
Copy catalog sang `theos/app/Resources/` trước khi build app.
