# iPFaker Theos — package giống ChangeInfoIos (HIOS Faker v3)

Deb tham chiếu: `ChangeInfoIos-v3_4.2.0_iphoneos-arm64.deb`

| ChangeInfo | iPFaker |
|------------|---------|
| `ChangeInfoIosMG.dylib` | `iPFakerMG.dylib` |
| `ChangeInfoIosCT.dylib` | `iPFakerCT.dylib` |
| `/var/jb/etc/changeinfoios/` | `/var/jb/etc/ipfaker/` |
| HIOSFakerV3.app | *(chưa — dùng deploy Windows)* |
| `Architecture: iphoneos-arm64` | same (rootless) |
| `ellekit \| mobilesubstrate` | same |

## Cấu trúc

```
theos/
├── Makefile              # 2 library + THEOS_PACKAGE_SCHEME=rootless
├── control               # deb metadata
├── TweakMG.x / TweakCT.x
├── src/                  # IPFConfig, IPFHooksMG, IPFHooksCT
└── layout/
    ├── DEBIAN/postinst
    ├── etc/ipfaker/
    └── Library/MobileSubstrate/DynamicLibraries/
        ├── iPFakerMG.plist
        └── iPFakerCT.plist
```

## Build (macOS only)

```bash
export THEOS=~/theos
cd /path/to/iPFaker/theos
make clean
make package
```

Output:

```text
packages/com.ipfaker.tweak_<ver>_iphoneos-arm64.deb
```

Cài trên RootHide:

```bash
dpkg -i packages/com.ipfaker.tweak_*.deb
# hoặc copy deb → Sileo
```

Copy dylib ra Windows tree (optional deploy.ps1):

```bash
cp .theos/obj/debug/iPFakerMG.dylib ../dylibs/
cp .theos/obj/debug/iPFakerCT.dylib ../dylibs/
```

## Sau khi cài deb

1. Windows: deploy profile  
   `deploy.ps1 -DeviceHost <IP> -Layout roothide -RebuildProfile -SkipDylib -KillZalo`  
2. RootHide Manager: **App Inject ON** cho Zalo  
3. Mở Zalo / Frida `rpc.exports.verify()`

## Filter Zalo

Cả hai bundle (như filter HIOS có `vn.com.vng.zingalo`):

- `com.zing.zalo`
- `vn.com.vng.zingalo`

CT còn inject: `CommCenter`, `CoreTelephonyHelper`.

## Không làm

- Không copy binary / logic proprietary từ ChangeInfo deb  
- Chỉ bắt chước **kiến trúc package + split MG/CT**
