# iPFaker

Jailbreak tool (**Dopamine rootless**) â€” spoof device identity cho **Zalo**, app quáº£n lÃ½ trÃªn mÃ¡y, license **Google Sheet**, tÃ¹y chá»n app **PC** (SSH).

---

## KhÃ¡ch hÃ ng â€” cÃ i ngay

| BÆ°á»›c | Link / hÃ nh Ä‘á»™ng |
|------|------------------|
| 1. Nguá»“n Sileo | **`https://vpnhihi.github.io/ipfaker/`** (chá»¯ thÆ°á»ng) |
| 2. HÆ°á»›ng dáº«n cÃ i + key | **[INSTALL_KHACH.md](INSTALL_KHACH.md)** |
| 3. Sheet license | **[docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md)** |
| 4. Deb trá»±c tiáº¿p | `https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.2_iphoneos-arm64.deb` |
| 5. Tools / mÃ¡y má»›i | **[tools/README.md](tools/README.md)** â€” full stack 1 láº§n = nhÆ° lab |

> Repo GitHub: https://github.com/vpnhihi/ipfaker  

---

## Dev / váº­n hÃ nh (nhá»› toÃ n bá»™)

| TÃ i liá»‡u | Ná»™i dung |
|----------|----------|
| **[docs/MEMORY.md](docs/MEMORY.md)** | **Bá»™ nhá»› dá»± Ã¡n Ä‘áº§y Ä‘á»§** â€” Sileo, license, PC 18 bÆ°á»›c, path mÃ¡y, khÃ´ng push secret |
| [docs/SILEO.md](docs/SILEO.md) | Build/publish nguá»“n Sileo |
| [pc_app/README.md](pc_app/README.md) | App Windows Ä‘iá»u khiá»ƒn SSH |

### Cháº¡y app PC (Windows)

```bat
pc_app\CHAY_APP.bat
```

### Publish láº¡i Sileo Pages

```bat
python scripts\publish_gh_pages_sileo.py
```

### Icon app

```bat
python scripts\gen_app_icons.py path\to\icon.png
```

---

## TÃ­nh nÄƒng chÃ­nh (mÃ¡y)

- Full stack lab: **MG Â· CT Â· JB Â· About Â· AboutUI Â· AboutVer Â· AA**  
- Spoof identity + Settings About sync + multi-app wipe (Zalo-depth)  
- Multi model iPhone + multi iOS (matrix), multi-select pool  
- **Äáº·t láº¡i dá»¯ liá»‡u app** / **Äáº·t láº¡i + LÆ°u dá»¯ liá»‡u** (giá»¯ login)  
- License key + **ID mÃ¡y** + Cháº¡y/Dá»«ng/Out  
- UI tiáº¿ng Viá»‡t, icon custom  

## TÃ­nh nÄƒng chÃ­nh (PC â€” tÃ¹y chá»n)

- Spoof/wipe theo pool Ä‘iá»‡n thoáº¡i  
- Pipeline reg Zalo 18 bÆ°á»›c (BossOTP, RotaProxy, captcha, AppManagerâ€¦)  
- Delay random tá»«ng bÆ°á»›c, báº£ng tÃªn / DOB  

---

## KhÃ´ng Ä‘Æ°a lÃªn git

Secrets, settings API, lab inject scripts, logs, artifact build thÃ´ â€” xem `.gitignore` vÃ  [docs/MEMORY.md](docs/MEMORY.md) Â§1.

---

## Legal

Chá»‰ dÃ¹ng trÃªn thiáº¿t bá»‹ sá»Ÿ há»¯u / lab há»£p phÃ¡p. KhÃ´ng dÃ¹ng Ä‘á»ƒ lá»«a Ä‘áº£o, máº¡o danh, vi pháº¡m phÃ¡p luáº­t.


