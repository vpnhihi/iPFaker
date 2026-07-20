# iPFaker.app (Shadow Tech–style lab UI)

App lab riêng trên Home Screen — **không inject Cài đặt / Settings** (tránh crash).

## Tab bar

| Tab | Việc |
|-----|------|
| **Main** | Card Device Info + Profile Info, **Reseed Identity**, **Apply Profile**, Kill Zalo, quick toggles |
| **Select Devices** | **Dòng trên: Chọn đời máy** · **Dòng dưới: Chọn iOS** → Apply / Reseed |
| **Wipe App** | Kill Zalo, Reseed, wipe lab note |
| **Settings** | Fake Device / Screen / Hardware / Ads / Network / Sysctl / Hide JB… |

## Select Devices (yêu cầu UI)

```
┌─────────────────────────────┐
│ Chọn đời máy                │  → danh sách iPhone (catalog)
│ iPhone 15 Pro · iPhone16,1  │
├─────────────────────────────┤
│ Chọn iOS                    │  → chỉ iOS trong matrix máy đó
│ iOS 18.5 · Build 22F76      │
└─────────────────────────────┘
        [ Apply Profile ]
```

## Luồng lab

1. Mở **iPFaker** → tab **Select Devices**
2. Chọn đời máy + iOS
3. **Apply Profile** (ghi `config.plist` + `active_profile.json`)
4. **Kill Zalo** → mở lại Zalo
5. (Tuỳ chọn) tab **Main** xem Status / IDFA / Serial

Paths ghi config (dylib đọc theo thứ tự):

1. `/var/mobile/Library/iPFaker/config.plist`
2. `/var/jb/etc/ipfaker/config.plist`

## Build

### GitHub Actions (không cần Mac local)

1. Push `theos/app/` lên repo  
2. Workflow **Build Theos rootless** build dylibs + app  
3. Tải artifact → `theos/dist/app/iPFaker.app`

### Mac + Theos

```bash
export THEOS=~/theos
cd theos/app
make package FINALPACKAGE=1
```

## Deploy lên máy (Windows)

```bash
python scripts/deploy_app.py
# hoặc
python scripts/deploy_app.py --app path/to/iPFaker.app
```

Sau đó: **uicache** (script đã gọi) → icon **iPFaker** trên SpringBoard.

## Source

```
theos/app/
  AppDelegate.m          # UITabBarController
  AppTheme.* AppState.*  # dark theme + shared selection/apply
  MainViewController.*
  SelectDevicesViewController.*   # 2 rows: đời máy + iOS
  WipeViewController.*
  SettingsViewController.*
  DeviceListController.* IOSListController.*
  Catalog.* ProfileBuilder.*
  Resources/device_catalog.json
```

## Không làm gì

- Không hook `com.apple.Preferences`
- Không đổi trang Cài đặt → Giới thiệu hệ thống
- Wipe Zalo full: `scripts/wipe_and_ready.py`
