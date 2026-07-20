# iPFaker — Cài đặt cho khách hàng

## Yêu cầu
- iPhone jailbreak **Dopamine** (rootless)
- **Sileo** đã cài
- Key kích hoạt (Google Sheet của shop)

## Cài package (Sileo)

### Cách 1 — File `.deb` (nhanh)
1. Tải file `com.ipfaker_*.deb` từ **Releases** trên GitHub (hoặc artifact CI **Build Theos rootless**)
2. AirDrop / Safari / Filza → mở file `.deb` → **Install**
3. Respring nếu Sileo yêu cầu
4. Mở app **iPFaker** trên SpringBoard

### Cách 2 — Nguồn Sileo (nếu shop host repo)
1. Sileo → Sources → Add  
2. Cài package **com.ipfaker**

## Kích hoạt key
1. Mở **iPFaker** → màn đăng nhập  
2. **Copy ID máy** → gửi shop / dán cột **D** trên Sheet  
3. Shop set cột **E = Chạy**, cột **C = số ngày**, cột **B = key**  
4. Nhập key → **Kích hoạt**

Chi tiết Sheet: [docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md)

## Dùng trên máy (đủ như lab)
| Tab | Việc |
|-----|------|
| Trang chủ | Đặt lại dữ liệu app / Đặt lại + Lưu / Đăng xuất |
| Chọn máy | Pool đời máy + iOS |
| Xóa app | Chọn app wipe |
| Cài đặt | Bật/tắt hook |

## App PC (tuỳ chọn, Windows)
Thư mục `pc_app/` — điều khiển qua Wi‑Fi SSH:
```bat
pc_app\CHAY_APP.bat
```
Cần Python 3 + `pip install paramiko frida`.  
API BossOTP / Proxy / Captcha: khách tự điền key của mình (không kèm sẵn secret).

## Lưu ý
- Chỉ dùng trên thiết bị bạn sở hữu / lab hợp pháp  
- Không chia sẻ key giữa nhiều máy (ràng buộc ID máy cột D)
