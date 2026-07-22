# Tools â€” mÃ¡y má»›i táº£i 1 láº§n

Má»¥c tiÃªu: clone / táº£i repo **má»™t láº§n** lÃ  Ä‘á»§ cháº¡y nhÆ° mÃ¡y lab (khÃ´ng cáº§n copy dylib tay).

## 1. MÃ¡y iPhone (Dopamine rootless)

CÃ¡ch nhanh nháº¥t â€” **khÃ´ng cáº§n build**:

| CÃ¡ch | URL |
|------|-----|
| Nguá»“n Sileo | `https://vpnhihi.github.io/ipfaker/` |
| Deb full stack | `https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.2_iphoneos-arm64.deb` |

GÃ³i `com.ipfaker` **2.8.2+** Ä‘Ã£ gá»“m:

- App `iPFaker.app` + `device_catalog.json` + matrix iOS
- Dylib full stack: **MG Â· CT Â· JB Â· About Â· AboutUI Â· AboutVer Â· AA**
- Filter Ä‘Ãºng lab (About* = Preferences only; CT + CommCenter)
- Wipe multi-app: `wipe_apps.sh` / `wipe_zalo_session.sh` (libexec + dual-path)
- `postinst`: trustcache + chmod filter 0666 (app Fake ghi inject list live)

HÆ°á»›ng dáº«n khÃ¡ch: [../INSTALL_KHACH.md](../INSTALL_KHACH.md)

## 2. MÃ¡y PC (Windows) â€” dev / Ä‘iá»u khiá»ƒn SSH

```bat
cd pc_app
pip install -r requirements.txt
CHAY_APP.bat
```

Script public cáº§n thiáº¿t (Ä‘Ã£ trong repo):

| Script | Viá»‡c |
|--------|------|
| `scripts/build_sileo_deb.py` | ÄÃ³ng gÃ³i deb full stack |
| `scripts/publish_gh_pages_sileo.py` | Äáº©y nguá»“n Sileo (gh-pages) |
| `scripts/select_device_profile.py` | Sinh profile identity (PC) |
| `scripts/gen_app_icons.py` | Icon app |
| `injector/wipe_apps.sh` | Wipe multi-app (source, cÅ©ng náº±m trong deb) |
| `pc_app/*` | App Windows SSH + pipeline |

## 3. Build láº¡i deb tá»« source (khi cÃ³ artifact)

TrÃªn mÃ¡y cÃ³ folder CI lab (`_ci_art_ui/â€¦/theos/dist` â€” **local only, khÃ´ng push**):

```bat
python scripts\build_sileo_deb.py --version 2.8.2
```

Output:

- `dist/sileo/com.ipfaker_2.8.2_iphoneos-arm64.deb`
- `dist/sileo/repo/` (Packages + Release)

Copy vÃ o `sileo-repo/` rá»“i:

```bat
python scripts\publish_gh_pages_sileo.py
```

## 4. KhÃ´ng cÃ³ trÃªn GitHub (cá»‘ Ã½)

- `_ci_art*`, `dist/`, `*.dylib` thÃ´, logs, lab notes
- Script one-off `scripts/_*`, deploy/debug táº¡m
- Secret API key, profile mÃ¡y tháº­t

MÃ¡y má»›i **khÃ´ng cáº§n** nhá»¯ng thá»© Ä‘Ã³ â€” chá»‰ cáº§n deb 2.8.2 + (tuá»³ chá»n) `pc_app`.


