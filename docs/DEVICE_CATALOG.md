# Device catalog (lab)

Nguồn: `config/device_catalog.json` (version 2)

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

# Board CDMA / China (ProductType khác)
python scripts/select_device_profile.py -d iphone7-cdma -i 15.8.3
python scripts/select_device_profile.py -d iphonexs-max-cn -i 17.7.2

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
| 2014–15 | iPhone 6 / 6 Plus / 6s / 6s Plus / SE (1st) |
| 2016–17 | iPhone 7 / 7 Plus (+CDMA board), 8 / 8 Plus (+CDMA), X (+global board) |
| 2018 | XR / XS / XS Max (+China dual-SIM) |
| 2019–20 | 11 / 11 Pro / 11 Pro Max, SE 2, 12 mini / 12 / 12 Pro / 12 Pro Max |
| 2021–22 | 13 mini / 13 / 13 Pro / 13 Pro Max, SE 3, 14 / 14 Plus / 14 Pro / 14 Pro Max |
| 2023–24 | 15 series, 16 series, 16e |
| Lab 2025 | iPhone 17 / 17 Air / 17 Pro / **17 Pro Max** (`lab: true`) |

**Tổng: 49 device profiles** (kể cả dual ProductType).

| iOS | Ghi chú | Số bản |
|-----|---------|--------|
| 15.0 – 15.8.5 | Build gần thực tế | dày |
| 16.0 – 16.7.11 | Build gần thực tế | dày |
| 17.0 – 17.7.6 | Build gần thực tế | dày |
| 18.0 – 18.7.2 | Build gần thực tế | dày |
| 19.0 – 26.6 | Placeholder lab (`lab: true`) | mỗi major .0–.6 + point |

**Tổng: 212 iOS builds** trong catalog.

## Thông số mỗi model

| Field | Ý nghĩa |
|-------|---------|
| `ProductType` | `hw.machine` / MG ProductType (vd `iPhone16,1`) |
| `HWModelStr` | Board id (vd `D83AP`) |
| `HardwarePlatform` | SoC platform (vd `t8130`) |
| `chip` / `cpuCores` / `gpuCores` | Chip + số nhân |
| `PhysicalMemoryMB` | RAM (MB) → hook `hw.memsize` |
| `display.NativeWidth/Height` | Pixel vật lý |
| `display.ScreenScale` | @2 / @3 |
| `display.LogicalWidth/Height` | Point UIKit |
| `display.Pitch` | PPI |
| `display.DiagonalInches` | Inch màn |
| `display.MaxRefreshHz` | 60 / 120 ProMotion |
| `batteryMah` | Pin (mAh, tham khảo) |
| `year` | Năm ra mắt |
| `storageOptionsGB` | Các mức dung lượng (tham khảo) |
| `ModelNumber` / `RegulatoryModelNumber` | Model / Axxxx |
| `minIOS` / `maxIOS` / `defaultIOS` | Gợi ý range |

## Ghi chú lab

- Serial / IDFA / IDFV / MAC / IMEI **random** mỗi lần chọn.
- iOS 19–26 và iPhone 17 series là **lab**, không đảm bảo khớp Apple production.
- Model thật máy (XS Max) vẫn có thể lộ qua path chưa hook; spoof đã cover ProductType, marketing-name, sysctl, HTTP rewrite, màn hình, RAM.
