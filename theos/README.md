# iPFaker Theos — rootless dual/triple dylib stack (lab)

| Thành phần | Vai trò |
|------------|---------|
| `iPFakerMG.dylib` | Identity spoof (MG / sysctl / UIDevice / Extra) |
| `iPFakerCT.dylib` | Telephony + Deep rewrite + CommCenter filter |
| `iPFakerJB.dylib` | JB hide expand (fopen/getenv/open/fileExists) |
| Config | `/var/jb/etc/ipfaker/` + mirror `/var/mobile/Library/iPFaker/` |
| App | `iPFaker.app` (Main / Devices / Wipe / Settings) |
| Inject | ElleKit (TweakInject) |
| Arch | `iphoneos-arm64` rootless (Dopamine) |

## Cấu trúc

```
theos/
├── Makefile              # MG + CT + JB, THEOS_PACKAGE_SCHEME=rootless
├── control
├── TweakMG.x / TweakCT.x / TweakJB.x
├── src/                  # IPFConfig, IPFHooks*
├── app/                  # iPFaker.app
└── layout/
    ├── DEBIAN/postinst
    ├── etc/ipfaker/
    └── Library/MobileSubstrate/DynamicLibraries/
        ├── iPFakerMG.plist
        ├── iPFakerCT.plist
        └── iPFakerJB.plist
```

## Build (macOS + Theos)

```bash
export THEOS=~/theos
cd theos
make clean
make package
```

## Filter mặc định (Lab-core)

- **MG/JB:** Zalo + Safari + Maps + Weather + WebKit helpers  
- **CT:** same bundles + Executables `CommCenter` / `commcenter` / `CoreTelephonyHelper`  
- Không inject Settings  

## Ghi chú

- Không copy binary proprietary từ gói spoof bên thứ ba  
- MG giữ size AMFI-safe (~≤130k)  
