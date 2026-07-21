# iPFaker — hook surface (dylib / Frida)

Target process only: **`com.zing.zalo`**.

Runtime config: **`active_profile.json`** (merged Nông + Sâu).  
Do **not** hardcode identity values in binary source.

## Module cover (source + dylib)

| Module | Cover |
|--------|-------|
| **IPFHooksMG** | MGCopyAnswer(+Error), sysctl, uname, UIDevice, IDFA/IDFV, boottime, Fake* gates; MSHook primary |
| **IPFHooksCT** | CTCarrier name/MCC/MNC/ISO/VoIP/radio |
| **IPFHooksDeep** | Rewrite HTTP body/**query** ProductType/HW; IOKit |
| **IPFHooksExtra** | UIScreen, disk, path hide, canOpenURL, UA, locale/TZ, location… (**always linked in MG ≥110k**) |

See `docs/MODULE_COVER.md`.

## Surface matrix (lab — đồng bộ config)

| Surface | API / symbol | Values from |
|---------|--------------|-------------|
| MobileGestalt | `MGCopyAnswer` / `WithError` | ProductType/Version/Build, Serial, IDFA… |
| sysctl / uname | `sysctlbyname` / `sysctl` / `uname` | hw.machine, hw.serialnumber, kern.boottime, board… |
| UIDevice | name/model/localizedModel/systemName/systemVersion/idfv | UserAssignedDeviceName, ProductVersion, IDFV |
| UIScreen | bounds/nativeBounds/scale/maxFPS | main-screen-*, LogicalScreen* |
| WebView | WKWebView UA + WKUserScript | UserAgent + screen JS |
| Network iface | getifaddrs / gethostname / hostName | WifiAddress, Hostname |
| JB hide | access/stat/lstat + JB fopen/getenv/open | bootstrap/electra denylist |
| Zalo-specific | keychain wipe binding | `group.keychain.vn.com.vng.zalo` |
| fishhook + MSHook | dual path (ctor log both) | MSHook primary; fishhook if miss |
| Carrier | CTCarrier + radio + CommCenter | MCC/MNC/ISO + filter Executables |
| Multi-app | ElleKit filter | Lab core/stock/**social** (FB IG TT Shopee TG) |

See `docs/SURFACE_MATRIX.md`.

## Priority P0 (ship first)

| Module | API / symbol | Values from |
|--------|--------------|-------------|
| MobileGestalt | `MGCopyAnswer` / `MGCopyAnswerWithError` | flat / mgMap |
| Sysctl | `sysctlbyname` | sysctlMap + Serial |
| UIDevice | `name`, `model`, `systemVersion`, `identifierForVendor` | uidevice / identity |
| IDFA | `ASIdentifierManager.advertisingIdentifier` | identity.IDFA |
| CoreTelephony | `CTCarrier` getters | telephony |
| uname | `uname()` | ProductType, Hostname |
| NSProcessInfo | `operatingSystemVersionString` / `hostName` | ProductVersion, Hostname |

## Priority P1 (Fake Sâu)

| Module | Notes |
|--------|--------|
| UIScreen | scale / native bounds vs spoofed model |
| DiskSpace | `NSFileSystemSize` / free |
| IOKit | `IOPlatformSerialNumber`, `IOPlatformUUID` |
| JailbreakHide | `access`/`stat`/`lstat`/`fopen`/`getenv` + `NSFileManager fileExists` + `canOpenURL` schemes; allowlist `/var/jb/etc/ipfaker` |
| WebViewUA | WKWebView custom UA from `webview` |
| BootTime | `kern.boottime` via sysctl |
| getifaddrs / hostname | `getifaddrs` AF_LINK MAC ← `WifiAddress`; `gethostname` + `NSProcessInfo.hostName` + `uname.nodename` ← `Hostname` (derived device name) |
| CNCopyCurrentNetworkInfo | SSID + BSSID (**BSSID ≡ WifiAddress**) |
| WKWebView.customUserAgent + setCustomUserAgent | ≡ `UserAgent` / HTTPUserAgent |
| WKUserScript (atDocumentStart/End) | `navigator.userAgent`, `screen.*`, `devicePixelRatio` ≡ LogicalScreen + scale |
| IOKit serial | `IOPlatformSerialNumber` / MLB ≡ `SerialNumber` (Deep) |
| CommCenter (CT filter) | CT dylib inject `CommCenter` + `CoreTelephonyHelper` (lab flat) |
| VolumeUUID | Class B field in profile (disk volume id lab) |

## Priority P2 (lab later)

| Module | Notes |
|--------|--------|
| Metal / GPU | family consistency with A17 Pro |
| Biometry | Face ID flags |
| SDKAttribution | AppsFlyer / Adjust / Firebase IDs (ObjC if present) |
| ZaloStorageWipe | keychain / defaults wipe on profile change (injector-side preferred) |
| Dyld hide | image name blocklist (careful — hide self carefully) |

## Build notes

- Windows workspace holds configs + Frida + deploy only.
- Native `.dylib` requires **macOS + Theos** (or CI) → drop artifact into `dylibs/iPFaker.dylib`.
- Filter plist: `injector/ApplyFull.plist` → install as Substrate/ElleKit filter for `com.zing.zalo`.

## Lab path without dylib

```text
1. scripts\build_active_profile.ps1
2. injector\deploy.ps1 -DeviceHost <IP> -SkipDylib -RebuildProfile
3. frida -U -f com.zing.zalo -l frida/iPFaker.js --no-pause
4. rpc.exports.verify()
5. Fill docs/E2E_CHECKLIST.md
```

## Theos path (native)

```text
1. On Mac: cd theos && make package
2. Copy iPFaker.dylib → dylibs/
3. injector\deploy.ps1 -DeviceHost <IP> -RebuildProfile -KillZalo
4. Re-run E2E without Frida (tweak-only)
```

See `theos/README.md`.
