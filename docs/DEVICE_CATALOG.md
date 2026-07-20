# Device catalog (lab)

Nguồn mẫu: `config/device_catalog.json`

## Liệt kê

```bash
python scripts/select_device_profile.py --list
python scripts/select_device_profile.py --list-ios
```

## Chọn model + iOS

```bash
# iPhone 16 Pro Max, iOS 18.5
python scripts/select_device_profile.py -d iphone16-pro-max -i 18.5

# Theo tên marketing
python scripts/select_device_profile.py -d "iPhone 15 Pro" -i 17.6.1

# Random
python scripts/select_device_profile.py --random

# Ghi config + đẩy lên máy (SSH [DEVICE_HOST])
python scripts/select_device_profile.py -d iphone17-pro-max -i 19.0 --deploy
```

Output:

- `config/config.plist` — flat HIOS (dùng bởi iPFakerMG/CT)
- `config/active_profile.json`
- `config/selected_profile.json`

Sau `--deploy`: kill Zalo, mở lại (auto-inject nếu plist còn bật).

## Phạm vi

| Nhóm | Model |
|------|--------|
| Cũ | iPhone 6 → X |
| 11–13 | 11 / 12 / 13 (+ mini, Pro, Pro Max), SE 2/3 |
| 14–16 | 14 / 15 / 16 (+ Plus, Pro, Pro Max), 16e |
| Lab mới | iPhone 17 / 17 Air / 17 Pro / **17 Pro Max** (`lab: true`) |

| iOS | Ghi chú |
|-----|---------|
| 15.0 – 18.x | Build number gần thực tế |
| 19.0 – 26.x | Placeholder lab (`lab: true`) |

Mỗi model có: ProductType, HWModelStr, màn (px + scale + ppi), RAM (MB), CPU cores, chip, ModelNumber, Regulatory, platform.

## Ghi chú lab

- Serial / IDFA / IDFV / MAC / IMEI **random** mỗi lần chọn.
- iOS 19–26 và iPhone 17 series là **lab**, không đảm bảo khớp Apple production.
- Model thật máy (XS Max) vẫn có thể lộ qua path chưa hook; spoof đã cover ProductType, marketing-name, sysctl, HTTP rewrite.
