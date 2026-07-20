# Cài iPFaker bằng Sileo

Gói **rootless Dopamine** · architecture **`iphoneos-arm64`** · package **`com.ipfaker`**.

---

## Nguồn Sileo (URL chuẩn)

```
https://vpnhihi.github.io/ipfaker/
```

### Quan trọng — chữ thường

| URL | Kết quả |
|-----|---------|
| `https://vpnhihi.github.io/ipfaker/` | ✅ Đúng (Sileo dùng chữ thường) |
| `https://vpnhihi.github.io/iPFaker/` | ❌ 404 — 0 gói |

Repo GitHub đã rename: **`vpnhihi/ipfaker`** (all lowercase) để khớp Sileo.

### Thêm nguồn

1. **Sileo** → **Nguồn** → **+**  
2. Dán URL → Add  
3. Làm mới nguồn  
4. Search **iPFaker** → Cài (**2.7.0+**)

### Nếu lỗi “status 404 / Could not find release file”

- Xóa nguồn cũ  
- Thêm lại đúng `…/ipfaker/` (chữ thường)  
- Kiểm tra Safari: mở URL trên có trang “iPFaker — nguồn Sileo” không  

---

## File `.deb` trực tiếp

```
https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.7.0_iphoneos-arm64.deb
```

Filza / AirDrop / Sileo Install package.

---

## Trong gói cài

| Thành phần | Đường dẫn on-device |
|------------|---------------------|
| iPFakerMG / iPFakerCT | `/var/jb/usr/lib/TweakInject/` |
| Filter | Chỉ **Zalo** (không inject Settings) |
| App | `/var/jb/Applications/iPFaker.app` |
| Catalog / config | `/var/jb/etc/ipfaker/` |
| Backup / license | `/var/mobile/Library/iPFaker/` |

`postinst`: trustcache (nếu có), `uicache`, chown mobile config, kill Zalo.

---

## Build & publish (dev)

```bash
# Build deb (sau Theos app + dylibs)
python scripts/build_sileo_deb.py --version 2.7.0 --app theos/dist/app/iPFaker.app

# Copy vào sileo-repo/debs, cập nhật Packages, rồi:
python scripts/publish_gh_pages_sileo.py
```

- CI: workflow **Build Theos rootless** → artifact `ipfaker-sileo`  
- Pages: branch **`gh-pages`** = nội dung `sileo-repo/`  
- Script publish force-push `gh-pages` (ổn định hơn workflow Pages khi fail)

### Cấu trúc `sileo-repo/`

```
sileo-repo/
  index.html
  Release
  Packages
  Packages.gz
  debs/com.ipfaker_2.7.0_iphoneos-arm64.deb
  .nojekyll
```

`Packages` / `Release`: **LF only** (không CRLF).

---

## Khách sau khi cài

→ [INSTALL_KHACH.md](../INSTALL_KHACH.md) (kích key Sheet)  
→ [LICENSE_SHEET.md](LICENSE_SHEET.md)
