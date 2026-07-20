# Device catalog (lab)

Nguồn: `config/device_catalog.json` (version **6**)  
Matrix: first/max OS Apple + iOS **8–18 & 26** (gồm iPhone 6/6 Plus).  
Xem chi tiết: [IOS_DEVICE_COMPAT.md](./IOS_DEVICE_COMPAT.md)

## Liệt kê

```bash
python scripts/select_device_profile.py --list
python scripts/select_device_profile.py --list-ios
python scripts/select_device_profile.py --list-ios -d iphone15-pro
```

## Chọn model + iOS

```bash
# iPhone 16 Pro Max, iOS 18.7.9 (security train)
python scripts/select_device_profile.py -d iphone16-pro-max -i 18.7.9

# Theo tên marketing
python scripts/select_device_profile.py -d "iPhone 15 Pro" -i 17.6.1

# Board CDMA / China (ProductType khác)
python scripts/select_device_profile.py -d iphone7-cdma -i 15.8.8
python scripts/select_device_profile.py -d iphonexs-max-cn -i 18.7.9

# Lab iPhone 17 / 17e + latest iOS 26
python scripts/select_device_profile.py -d iphone17-pro-max -i 26.5.2
python scripts/select_device_profile.py -d iphone17e -i 26.5.2

# Random
python scripts/select_device_profile.py --random

# Ghi config + đẩy lên máy (SSH)
python scripts/select_device_profile.py -d iphone17-pro-max -i 26.5.2 --deploy
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
| 2023–25 | 15 series, 16 series, 16e |
| Lab 2025–26 | iPhone 17 / **Air** / 17 Pro / 17 Pro Max / **17e** (`lab: true`) |

**Tổng: 50 device profiles** (kể cả dual ProductType).

| iOS | Ghi chú | Max / ghi chú |
|-----|---------|----------------|
| **8.0 – 8.4.1** | iPhone 6 launch train | Historical |
| **9.0 – 9.3.6** | 6s / SE1 | Historical |
| **10.0 – 10.3.4** | iPhone 7 | Historical |
| **11.0 – 11.4.1** | 8 / X | Historical |
| **12.0 – 12.5.8** | **Max iPhone 6 / 6 Plus** | Security 12.5.x |
| **13.0 – 13.7** | iPhone 11 launch | Historical |
| 14.x | Build gần thực tế | — |
| 15.0 – **15.8.8** | Max 6s/7/SE1 | Security |
| 16.0 – **16.7.16** | Max 8/X | Security |
| 17.x | — | — |
| 18.0 – **18.7.9** | Max XR/XS | Security |
| 26.0 – **26.5.2** | Lab; latest | Security |
| **19 – 25** | **Không có** | — |

**Tổng: ~244 iOS builds** (major **8–18 + 26**).

## Rebuild từ nguồn Apple

```bash
python scripts/rebuild_apple_matrix.py
```

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
| `minIOS` / `maxIOS` / `defaultIOS` | Range strict từ matrix Apple |
| `supportedIOS` | Danh sách iOS tools/app cho chọn |

## Ghi chú lab

- Serial / IDFA / IDFV / MAC / IMEI **random** mỗi lần chọn.
- iOS **26.x** và iPhone 17 series / 17e / Air là **lab**. **Không có iOS 19–25.**
- Build labels 26.x và một số security patch mới là **near-real** (đủ spoof; không đảm bảo IPSW exact).
- Model thật máy vẫn có thể lộ qua path chưa hook; spoof cover ProductType, marketing-name, sysctl, HTTP rewrite, màn hình, RAM.
