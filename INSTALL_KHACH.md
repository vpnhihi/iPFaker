# iPFaker — Cài đặt cho khách hàng

> Bản dùng ngay trên Dopamine rootless. Chi tiết kỹ thuật / lab: [docs/MEMORY.md](docs/MEMORY.md).

## Yêu cầu

- iPhone **jailbreak Dopamine** (rootless)
- **Sileo** đã cài
- Key kích hoạt (shop cấp qua Google Sheet)

---

## 1. Thêm nguồn Sileo

### URL nguồn (copy nguyên — **chữ thường**)

```
https://vpnhihi.github.io/ipfaker/
```

> ⚠️ Sai: `…/iPFaker/` (chữ hoa) hoặc gõ nhầm → **404**, Sileo hiện **0 gói**.  
> Đúng: toàn bộ **`ipfaker`** chữ thường.

### Các bước

1. **Sileo** → tab **Nguồn** → **+**
2. Dán URL trên → **Add**
3. **Làm mới nguồn** (kéo refresh)
4. Tìm **iPFaker** → **Cài** / **Get** (gói `com.ipfaker`, version **2.8.0+**)
5. Respring nếu Sileo yêu cầu

### Tải file `.deb` trực tiếp (không cần nguồn)

```
https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.0_iphoneos-arm64.deb
```

Bản **2.8.0** = full stack như máy lab (app + 7 dylib + wipe multi-app + catalog).  
Cài **một lần** là đủ; không cần copy file tay.

AirDrop / Safari / Filza → chạm file → **Install**.

---

## 2. Kích hoạt key

1. Mở app **iPFaker**
2. Màn **Đăng nhập key** → **Copy ID máy** (dạng `IPF-XXXXXXXX`)
3. Gửi ID cho shop **hoặc** tự dán vào Google Sheet:
   - Cột **B** = Key  
   - Cột **C** = số ngày (vd `30`)  
   - Cột **D** = ID máy vừa copy  
   - Cột **E** = **`Chạy`**
4. Nhập **Key** → **Kích hoạt**

### Tình trạng key (cột E trên Sheet)

| Giá trị | Ý nghĩa |
|---------|---------|
| **Chạy** | Dùng bình thường |
| **Dừng** | App đẩy key khỏi máy, tạm dừng (không tính ngày khi dừng) |
| **Out** | Vô hiệu / đăng xuất hẳn |

Trên app: nút **Đăng xuất** (Trang chủ) để gỡ key local.

Chi tiết Sheet: [docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md)

---

## 3. Dùng app trên iPhone

| Tab | Việc |
|-----|------|
| **Trang chủ** | Xem spoof · **Đặt lại dữ liệu app** · **Đặt lại + Lưu dữ liệu** · toggles · **Đăng xuất** |
| **Chọn máy** | Chọn pool đời máy + iOS (có chọn tất cả) |
| **Xóa app** | Chọn app cần xóa dữ liệu |
| **Cài đặt** | Bật/tắt từng nhóm hook |

### Hai nút quan trọng

| Nút | Kết quả |
|-----|---------|
| **Đặt lại dữ liệu app** | Máy spoof mới + xóa data app → **mất đăng nhập** |
| **Đặt lại + Lưu dữ liệu** | Lưu data + thông số → spoof mới → khôi phục data → **giữ đăng nhập** |

Pool máy/iOS chỉ chọn **trên điện thoại** (tab Chọn máy).

---

## 4. App PC (tuỳ chọn — Windows)

Điều khiển qua **Wi‑Fi SSH** (không bắt buộc USB):

```bat
pc_app\CHAY_APP.bat
```

- Cần Python 3 + `paramiko` (+ `frida` nếu dùng Reg tự động)
- Pool máy lấy từ iPhone; API BossOTP / Proxy / Captcha: **tự điền key của bạn**
- Chi tiết: [pc_app/README.md](pc_app/README.md) · [docs/MEMORY.md](docs/MEMORY.md)

---

## 5. Lưu ý

- Chỉ dùng trên thiết bị sở hữu / lab hợp pháp  
- **1 key ↔ 1 ID máy** (cột D)  
- Không chia sẻ key / không cài gói giả mạo  
- Repo: https://github.com/vpnhihi/ipfaker  
