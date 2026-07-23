# iPFaker — Cài đặt (máy mới = máy lab)

> Bản dùng ngay trên **Dopamine rootless**. Nguồn Sileo chứa đủ gói phụ thuộc (ElleKit, sqlite3, ldid…).

## Yêu cầu

- iPhone jailbreak **Dopamine** (rootless)
- **Sileo**
- Key kích hoạt (Google Sheet)

## 1. Thêm nguồn Sileo

```
https://vpnhihi.github.io/ipfaker/
```

(chữ thường `ipfaker` — sai chữ hoa → 404)

Sileo → **Nguồn** → **+** → dán URL → **Add** → refresh.

## 2. Cài đủ gói (bắt buộc)

| Gói | Việc | Có trên nguồn? |
|-----|------|----------------|
| **ellekit** | Inject tweak (thiếu = spoof không vào Zalo/Settings) | ✅ `debs/ellekit_…` |
| **libplist3** | Phụ thuộc ldid | ✅ |
| **ldid** | Ký / trustcache | ✅ |
| **libsqlite3-1** + **sqlite3** | Wipe keychain session | ✅ |
| **com.ipfaker 2.10.2+** | App + MG lean Zalo-safe + CT Deep + AA + About* + wipe + **auto Userspace Reboot** | ✅ (sau publish) |

**Cách nhanh:** cài **iPFaker 2.10.2+** — Depends kéo ElleKit + sqlite + ldid.

**Thứ tự:** ElleKit → sqlite/ldid → iPFaker.  
Từ **2.10.2**, sau khi Sileo xong cài (~6 giây) máy **tự Userspace Reboot** (Dopamine `jbctl reboot_userspace`) — không cần mở Dopamine bấm tay. Đợi logo / màn hình về Home rồi mở iPFaker.

### Deb trực tiếp

- iPFaker: `https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.10.2_iphoneos-arm64.deb`
- ElleKit: `https://vpnhihi.github.io/ipfaker/debs/ellekit_1.1.3_iphoneos-arm64.deb`

### Máy dev vs máy khách (vì sao “thiếu chức năng”)

| | Máy lab/dev | Máy cài Sileo cũ (≤2.8.2) |
|--|-------------|---------------------------|
| Dylib | SSH/CI **mới mỗi ngày** | Deb **cũ trên Pages** |
| MG Zalo-safe delay | Có (2.10+) | Không |
| CT Deep `ss`/UA | Có | Thiếu / cũ |
| AboutID | Có | Có thể thiếu |

→ **Máy khác phải cài / nâng lên 2.10.2+** — postinst tự Userspace Reboot; không chỉ copy app.

## 3. Sau reboot (tự động ~6s sau cài 2.10.2+)

1. Mở **iPFaker** → key  
2. **Chọn máy** (không chọn đúng đời host nếu muốn nhìn khác)  
3. **Đặt lại dữ liệu app**  
4. Mở Zalo / **Cài đặt → Giới thiệu** (daemon inject About tự chạy)

## 4. Nếu Giới thiệu vẫn máy gốc

```sh
# NewTerm root — daemon inject Preferences
ps aux | grep prefs_inject
# hoặc:
sh /var/mobile/Library/iPFaker/prefs_inject_daemon.sh &
```

Rồi **vuốt tắt Cài đặt** → mở lại **Giới thiệu**.

## 5. Khác máy lab?

| Thành phần | Lab cần | Máy mới cần |
|------------|---------|-------------|
| ElleKit | có | **phải có** (trong repo) |
| iPFaker deb | có | 2.8.2+ |
| sqlite3 | có | **phải có** |
| ldid | có | **phải có** |
| Userspace Reboot | sau cài inject | **bắt buộc** |

## 6. Key / Sheet

Xem [docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md).

## Legal

Chỉ thiết bị sở hữu / lab hợp pháp.
