# iPFaker trên **Windows only** (không Mac)

Windows **không build** được `iPFakerMG.dylib` / Theos (cần macOS + clang iOS SDK).

## Đường đi lab (đang dùng)

| Bước | Công cụ | Máy |
|------|---------|-----|
| Config / profile | PowerShell scripts | Windows |
| Deploy + wipe | SSH (`mobile`/`[REDACTED]`) | Windows → iPhone |
| Spoof runtime | **Frida Gadget** + `iPFaker.js` (ElleKit load) | iPhone |
| Verify | Mở Zalo + log / sau này attach | — |

## Không cần Mac nếu

- Chấp nhận spoof qua **Frida Gadget** (script mode, load khi mở Zalo)
- Chưa cần app UI native (Prefs / .app)

## Cần Mac (hoặc CI macOS) nếu

- Muốn `.deb` / dylib **iPFakerMG + iPFakerCT** giống HIOS (không gadget)
- Muốn app Settings native Theos

## Lệnh Windows thường dùng

```powershell
cd C:\Users\Pem\Desktop\iPFaker

# Deploy config
python scripts\deploy_ssh_mobile.py

# Deploy Frida Gadget + script (sau khi có file downloads\FridaGadget.dylib)
python scripts\deploy_gadget.py

# Wipe Zalo
python scripts\_tmp_ssh_wipe.py
```

SSH: `mobile@IP` / `[REDACTED]` → `sudo -i` khi cần root.
