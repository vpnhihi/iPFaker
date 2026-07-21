# iPFaker — hook surface (dylib / Frida)

Target process only: **`com.zing.zalo`**.

Runtime config: **`active_profile.json`** (merged Nông + Sâu).  
Do **not** hardcode identity values in binary source.

## Priority P0 (ship first)

| Module | API / symbol | Values from |
|--------|--------------|-------------|
| MobileGestalt | `MGCopyAnswer` / `MGCopyAnswerWithError` | `hooks.mobilegestalt` |
| Sysctl | `sysctlbyname` | `hooks.sysctl` |
| UIDevice | `name`, `model`, `systemVersion`, `identifierForVendor` | `uidevice` / `identity` |
| IDFA | `ASIdentifierManager.advertisingIdentifier` | `identity.IDFA` |
| CoreTelephony | `CTCarrier` getters | `telephony` |
| uname | `uname()` | `model.ProductType`, `os.Hostname` |
| NSProcessInfo | `operatingSystemVersionString` | `os` |

## Priority P1 (Fake Sâu)

| Module | Notes |
|--------|--------|
| UIScreen | scale / native bounds vs spoofed model |
| DiskSpace | `NSFileSystemSize` / free |
| IOKit | `IOPlatformSerialNumber`, `IOPlatformUUID` |
| JailbreakHide | `access` / `stat` path deny list from `jailbreak_hide` |
| WebViewUA | WKWebView custom UA from `webview` |
| BootTime | `kern.boottime` via sysctl |
| getifaddrs / hostname | `getifaddrs` AF_LINK MAC ← `WifiAddress`; `gethostname` + `NSProcessInfo.hostName` + `uname.nodename` ← `Hostname` (derived device name) |
| CNCopyCurrentNetworkInfo | SSID + BSSID (**BSSID ≡ WifiAddress**) |
| WKWebView.customUserAgent + setCustomUserAgent | ≡ `UserAgent` / HTTPUserAgent |
| WKUserScript (atDocumentStart/End) | `navigator.userAgent`, `screen.*`, `devicePixelRatio` ≡ LogicalScreen + scale |
| IOKit serial | `IOPlatformSerialNumber` / MLB ≡ `SerialNumber` (Deep) |
| CommCenter (CT filter) | CT dylib inject `CommCenter` + `CoreTelephonyHelper` (HIOS-style) |
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
