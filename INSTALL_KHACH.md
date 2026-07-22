# iPFaker â€” CÃ i Ä‘áº·t cho khÃ¡ch hÃ ng

> Báº£n dÃ¹ng ngay trÃªn Dopamine rootless. Chi tiáº¿t ká»¹ thuáº­t / lab: [docs/MEMORY.md](docs/MEMORY.md).

## YÃªu cáº§u

- iPhone **jailbreak Dopamine** (rootless)
- **Sileo** Ä‘Ã£ cÃ i
- Key kÃ­ch hoáº¡t (shop cáº¥p qua Google Sheet)

---

## 1. ThÃªm nguá»“n Sileo

### URL nguá»“n (copy nguyÃªn â€” **chá»¯ thÆ°á»ng**)

```
https://vpnhihi.github.io/ipfaker/
```

> âš ï¸ Sai: `â€¦/iPFaker/` (chá»¯ hoa) hoáº·c gÃµ nháº§m â†’ **404**, Sileo hiá»‡n **0 gÃ³i**.  
> ÄÃºng: toÃ n bá»™ **`ipfaker`** chá»¯ thÆ°á»ng.

### CÃ¡c bÆ°á»›c

1. **Sileo** â†’ tab **Nguá»“n** â†’ **+**
2. DÃ¡n URL trÃªn â†’ **Add**
3. **LÃ m má»›i nguá»“n** (kÃ©o refresh)
4. TÃ¬m **iPFaker** â†’ **CÃ i** / **Get** (gÃ³i `com.ipfaker`, version **2.8.1+**)
5. Respring náº¿u Sileo yÃªu cáº§u

### Táº£i file `.deb` trá»±c tiáº¿p (khÃ´ng cáº§n nguá»“n)

```
https://vpnhihi.github.io/ipfaker/debs/com.ipfaker_2.8.1_iphoneos-arm64.deb
```

Báº£n **2.8.1** = full stack nhÆ° mÃ¡y lab (app + 7 dylib + wipe multi-app + catalog).  
CÃ i **má»™t láº§n** lÃ  Ä‘á»§; khÃ´ng cáº§n copy file tay.

AirDrop / Safari / Filza â†’ cháº¡m file â†’ **Install**.

---

## 2. KÃ­ch hoáº¡t key

1. Má»Ÿ app **iPFaker**
2. MÃ n **ÄÄƒng nháº­p key** â†’ **Copy ID mÃ¡y** (dáº¡ng `IPF-XXXXXXXX`)
3. Gá»­i ID cho shop **hoáº·c** tá»± dÃ¡n vÃ o Google Sheet:
   - Cá»™t **B** = Key  
   - Cá»™t **C** = sá»‘ ngÃ y (vd `30`)  
   - Cá»™t **D** = ID mÃ¡y vá»«a copy  
   - Cá»™t **E** = **`Cháº¡y`**
4. Nháº­p **Key** â†’ **KÃ­ch hoáº¡t**

### TÃ¬nh tráº¡ng key (cá»™t E trÃªn Sheet)

| GiÃ¡ trá»‹ | Ã nghÄ©a |
|---------|---------|
| **Cháº¡y** | DÃ¹ng bÃ¬nh thÆ°á»ng |
| **Dá»«ng** | App Ä‘áº©y key khá»i mÃ¡y, táº¡m dá»«ng (khÃ´ng tÃ­nh ngÃ y khi dá»«ng) |
| **Out** | VÃ´ hiá»‡u / Ä‘Äƒng xuáº¥t háº³n |

TrÃªn app: nÃºt **ÄÄƒng xuáº¥t** (Trang chá»§) Ä‘á»ƒ gá»¡ key local.

Chi tiáº¿t Sheet: [docs/LICENSE_SHEET.md](docs/LICENSE_SHEET.md)

---

## 3. DÃ¹ng app trÃªn iPhone

| Tab | Viá»‡c |
|-----|------|
| **Trang chá»§** | Xem spoof Â· **Äáº·t láº¡i dá»¯ liá»‡u app** Â· **Äáº·t láº¡i + LÆ°u dá»¯ liá»‡u** Â· toggles Â· **ÄÄƒng xuáº¥t** |
| **Chá»n mÃ¡y** | Chá»n pool Ä‘á»i mÃ¡y + iOS (cÃ³ chá»n táº¥t cáº£) |
| **XÃ³a app** | Chá»n app cáº§n xÃ³a dá»¯ liá»‡u |
| **CÃ i Ä‘áº·t** | Báº­t/táº¯t tá»«ng nhÃ³m hook |

### Hai nÃºt quan trá»ng

| NÃºt | Káº¿t quáº£ |
|-----|---------|
| **Äáº·t láº¡i dá»¯ liá»‡u app** | MÃ¡y spoof má»›i + xÃ³a data app â†’ **máº¥t Ä‘Äƒng nháº­p** |
| **Äáº·t láº¡i + LÆ°u dá»¯ liá»‡u** | LÆ°u data + thÃ´ng sá»‘ â†’ spoof má»›i â†’ khÃ´i phá»¥c data â†’ **giá»¯ Ä‘Äƒng nháº­p** |

Pool mÃ¡y/iOS chá»‰ chá»n **trÃªn Ä‘iá»‡n thoáº¡i** (tab Chá»n mÃ¡y).

---

## 4. App PC (tuá»³ chá»n â€” Windows)

Äiá»u khiá»ƒn qua **Wiâ€‘Fi SSH** (khÃ´ng báº¯t buá»™c USB):

```bat
pc_app\CHAY_APP.bat
```

- Cáº§n Python 3 + `paramiko` (+ `frida` náº¿u dÃ¹ng Reg tá»± Ä‘á»™ng)
- Pool mÃ¡y láº¥y tá»« iPhone; API BossOTP / Proxy / Captcha: **tá»± Ä‘iá»n key cá»§a báº¡n**
- Chi tiáº¿t: [pc_app/README.md](pc_app/README.md) Â· [docs/MEMORY.md](docs/MEMORY.md)

---

## 5. LÆ°u Ã½

- Chá»‰ dÃ¹ng trÃªn thiáº¿t bá»‹ sá»Ÿ há»¯u / lab há»£p phÃ¡p  
- **1 key â†” 1 ID mÃ¡y** (cá»™t D)  
- KhÃ´ng chia sáº» key / khÃ´ng cÃ i gÃ³i giáº£ máº¡o  
- Repo: https://github.com/vpnhihi/ipfaker  

