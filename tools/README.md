# Tools — máy mới tải 1 lần

Mục tiêu: clone / tải repo **một lần** là đủ chạy như máy lab (không cần copy dylib tay).

## 1. Máy iPhone (Dopamine rootless)

Cách nhanh nhất — **không cần build**:

| Cách | URL |
|------|-----|
| Nguồn Sileo | `https://vpnhihi.github.io/ipfaker/` |
| Deb full stack | `https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.0_iphoneos-arm64.deb` |

Gói `com.ipfaker` **2.8.0+** đã gồm:

- App `iPFaker.app` + `device_catalog.json` + matrix iOS
- Dylib full stack: **MG · CT · JB · About · AboutUI · AboutVer · AA**
- Filter đúng lab (About* = Preferences only; CT + CommCenter)
- Wipe multi-app: `wipe_apps.sh` / `wipe_zalo_session.sh` (libexec + dual-path)
- `postinst`: trustcache + chmod filter 0666 (app Fake ghi inject list live)

Hướng dẫn khách: [../INSTALL_KHACH.md](../INSTALL_KHACH.md)

## 2. Máy PC (Windows) — dev / điều khiển SSH

```bat
cd pc_app
pip install -r requirements.txt
CHAY_APP.bat
```

Script public cần thiết (đã trong repo):

| Script | Việc |
|--------|------|
| `scripts/build_sileo_deb.py` | Đóng gói deb full stack |
| `scripts/publish_gh_pages_sileo.py` | Đẩy nguồn Sileo (gh-pages) |
| `scripts/select_device_profile.py` | Sinh profile identity (PC) |
| `scripts/gen_app_icons.py` | Icon app |
| `injector/wipe_apps.sh` | Wipe multi-app (source, cũng nằm trong deb) |
| `pc_app/*` | App Windows SSH + pipeline |

## 3. Build lại deb từ source (khi có artifact)

Trên máy có folder CI lab (`_ci_art_ui/…/theos/dist` — **local only, không push**):

```bat
python scripts\build_sileo_deb.py --version 2.8.0
```

Output:

- `dist/sileo/com.ipfaker_2.8.0_iphoneos-arm64.deb`
- `dist/sileo/repo/` (Packages + Release)

Copy vào `sileo-repo/` rồi:

```bat
python scripts\publish_gh_pages_sileo.py
```

## 4. Không có trên GitHub (cố ý)

- `_ci_art*`, `dist/`, `*.dylib` thô, logs, lab notes
- Script one-off `scripts/_*`, deploy/debug tạm
- Secret API key, profile máy thật

Máy mới **không cần** những thứ đó — chỉ cần deb 2.8.0 + (tuỳ chọn) `pc_app`.
