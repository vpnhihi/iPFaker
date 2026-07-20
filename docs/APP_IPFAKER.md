# iPFaker.app (kiểu HIOS)

App lab riêng trên Home Screen — **không inject Cài đặt / Settings** (tránh crash).

## Chức năng

| Màn | Việc |
|-----|------|
| Hồ sơ lab | Chọn **iPhone** (catalog 49 model) + **iOS** (15→26) |
| Giới thiệu lab | Xem model / serial / màn / RAM / chip (giống About, trong app) |
| Apply profile | Ghi `config.plist` + `active_profile.json` |
| Reseed | Giữ model/iOS, random serial + UUID |
| Kill Zalo | Đóng Zalo để load config mới |

Paths ghi config (dylib đã đọc theo thứ tự):

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

Nếu không thấy icon:

```text
sbreload
```

## Dùng

1. Mở **iPFaker**  
2. Chọn máy (vd iPhone 17 Pro Max)  
3. Chọn iOS  
4. **Apply profile**  
5. **Kill Zalo** → mở lại Zalo  
6. (Tuỳ chọn) **Giới thiệu lab** để xem thông số vừa apply  

## Không làm gì

- Không hook `com.apple.Preferences`  
- Không đổi trang Cài đặt → Giới thiệu hệ thống  
- Wipe Zalo full vẫn khuyến nghị từ PC: `scripts/wipe_and_ready.py`

## Source

```
theos/app/
  Makefile
  main.m AppDelegate.*
  Catalog.* ProfileBuilder.*
  RootViewController.* DeviceListController.*
  IOSListController.* AboutLabController.*
  Resources/device_catalog.json
  entitlements.plist
  control + layout/DEBIAN/postinst
```
