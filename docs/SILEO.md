# Cài iPFaker bằng Sileo (file `.deb`)

Gói rootless **Dopamine** / architecture `iphoneos-arm64` — giống cách cài HIOS.

## File gói

Sau khi build:

```
dist/sileo/com.ipfaker_2.3.0_iphoneos-arm64.deb
```

Trong gói:

| Thành phần | Đường dẫn |
|------------|-----------|
| iPFakerMG / CT | `/var/jb/usr/lib/TweakInject/` (DynamicLibraries = symlink cùng chỗ) |
| Filter | Chỉ **Zalo** (không inject Settings) |
| App (nếu CI build được) | `/var/jb/Applications/iPFaker.app` |
| Catalog | `/var/jb/etc/ipfaker/device_catalog.json` |

`postinst`: trustcache (jbctl), `uicache`, tạo thư mục config, kill Zalo.

## Cách 1 — Cài file `.deb` (nhanh nhất)

1. Tải `com.ipfaker_*.deb` (GitHub Actions artifact **ipfaker-sileo**, hoặc PC `dist/sileo/`)
2. AirDrop / Filza / Safari → lưu vào máy  
3. **Sileo** → tab **Packages** (hoặc tìm “Install package”) → chọn file  
   hoặc **Filza** → chạm file `.deb` → **Install**  
4. Respring nếu Sileo yêu cầu  
5. Mở app **iPFaker** (nếu có trong gói) → chọn model → **Apply** → Kill Zalo → mở Zalo  

## Cách 2 — Nguồn Sileo (repo)

PC đã sinh:

```
dist/sileo/repo/
  Packages
  Packages.gz
  Release
  debs/com.ipfaker_….deb
```

Host thư mục `repo/` lên HTTPS (GitHub Pages / máy chủ), rồi trong Sileo:

**Sources → + → URL** ví dụ:

```
https://<your-pages-host>/
```

(URL trỏ tới chỗ có file `Release` + `Packages`.)

## Build trên Windows (dylibs sẵn có)

```bash
python scripts/build_sileo_deb.py --version 2.3.0
```

- Có `dylibs_ci/iPFakerMG.dylib` + `CT` → gói dylibs + catalog  
- Có thêm `theos/dist/app/iPFaker.app` → gói full (app + dylibs)

## Build full trên GitHub Actions

Push `main` → workflow **Build Theos rootless** → artifact **ipfaker-sileo** → lấy `.deb`.

## Gỡ / conflict

Package id: `com.ipfaker`  
`Conflicts/Replaces: com.ipfaker.tweak` (gói tweak cũ).

```bash
# SSH
dpkg -r com.ipfaker
```

## Lưu ý lab

- Chỉ spoof **Zalo**, không đụng Cài đặt hệ thống  
- Cần **ElleKit / Substrate** (Dopamine đã có)  
- Sau cài: nếu Zalo chưa spoof, mở app Apply lại config + kill Zalo  
