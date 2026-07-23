// Extra spoof surface for Zalo — gated by config Fake* flags:
//  FakeScreen / FakeRealScreen, FakeHardware (disk), HideJailbreak (access/stat/lstat + canOpenURL),
//  FakeBrowser (UA), FakeLocale (BCP-47 + IANA TZ), FakeDateTime,
//  FakeLocation (WGS84), FakeSensor,
//  FakeWifi: getifaddrs MAC; FakeDevice/FakeNetwork: gethostname + NSProcessInfo.hostName.
// Proxy / AppAttest / WebRTC ICE → IPFHooksServer (packed in CT) — keeps MG AMFI-safe.
// Expanded fopen/getenv/fileExists → iPFakerJB.dylib (split stack / AMFI size).
// Complements IPFHooksMG / CT. Keep defensive — never crash Zalo.
//
// Standards:
//  - getifaddrs(3) BSD/iOS man — AF_LINK + sockaddr_dl / LLADDR
//  - gethostname(3) POSIX
//  - IEEE 802 MAC EUI-48 in ifa_addr when sa_family == AF_LINK

#import "IPFHooksExtra.h"
#import "IPFConfig.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
// WebKit types via runtime only (avoid hard-link WebKit → code-sign issues on Dopamine)
#import <dlfcn.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <ifaddrs.h>
#import <string.h>
#import <math.h>
#import <errno.h>
#import <ctype.h>
// CFNetwork proxy hooks live in IPFHooksServer.m (CT)

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction = NULL;
static MSHookMessageEx_t pMSHookMessageEx = NULL;

static void IPFExTrace(NSString *s) {
    @try {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/ipfaker_extra.log"];
        NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), s];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) {
            [row writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [h seekToEndOfFile];
            [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (__unused NSException *ex) {}
}

static void IPFResolve(void) {
    if (pMSHookFunction) return;
    void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
    if (!h) h = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
    if (h) {
        pMSHookFunction = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        pMSHookMessageEx = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
    }
    if (!pMSHookFunction)
        pMSHookFunction = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!pMSHookMessageEx)
        pMSHookMessageEx = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
}

// UIScreen (UIKit): bounds=points, nativeBounds=pixels, scale≈nativeScale, maxFPS ProMotion
// Disk: NSFileManager NSFileSystemSize/FreeSize + statfs(2) — must match catalog storage

static BOOL IPFScreenOn(void) {
    // Full surface when FakeScreen OR FakeRealScreen (no native leak of XS Max)
    return [[IPFConfig shared] flag:@"FakeScreen" defaultYes:YES]
        || [[IPFConfig shared] flag:@"FakeRealScreen" defaultYes:YES];
}

static CGFloat IPFScale(void) {
    double sc = [[IPFConfig shared] doubleForKey:@"main-screen-scale" fallback:0];
    if (sc < 1.0) {
        id v = [[IPFConfig shared] stringForKey:@"main-screen-scale"]
            ?: [[IPFConfig shared] mgValueForKey:@"main-screen-scale"];
        if ([v respondsToSelector:@selector(doubleValue)]) sc = [v doubleValue];
    }
    // No SKU default (was 3.0 = Pro-class); 2.0 is safest generic if profile missing
    return (sc >= 1.0) ? (CGFloat)sc : 2.0;
}

static CGSize IPFNativeSize(void) {
    double ww = [[IPFConfig shared] doubleForKey:@"main-screen-width" fallback:0];
    double hh = [[IPFConfig shared] doubleForKey:@"main-screen-height" fallback:0];
    if (ww < 1 || hh < 1) {
        id w = [[IPFConfig shared] stringForKey:@"main-screen-width"]
            ?: [[IPFConfig shared] mgValueForKey:@"main-screen-width"];
        id h = [[IPFConfig shared] stringForKey:@"main-screen-height"]
            ?: [[IPFConfig shared] mgValueForKey:@"main-screen-height"];
        if ([w respondsToSelector:@selector(doubleValue)]) ww = [w doubleValue];
        if ([h respondsToSelector:@selector(doubleValue)]) hh = [h doubleValue];
    }
    if (ww < 1 || hh < 1) {
        // Derive from LogicalScreen* × scale (any catalog device)
        double lw = [[IPFConfig shared] doubleForKey:@"LogicalScreenWidth" fallback:0];
        double lh = [[IPFConfig shared] doubleForKey:@"LogicalScreenHeight" fallback:0];
        CGFloat sc = IPFScale();
        if (lw > 0 && lh > 0) {
            ww = lw * sc;
            hh = lh * sc;
        }
    }
    // Still missing → leave zero so caller can fall through to real screen (no fake SKU)
    return CGSizeMake((CGFloat)ww, (CGFloat)hh);
}

static NSInteger IPFMaxFPS(void) {
    double v = [[IPFConfig shared] doubleForKey:@"MaxRefreshHz" fallback:0];
    if (v < 1) {
        id x = [[IPFConfig shared] stringForKey:@"MaxRefreshHz"]
            ?: [[IPFConfig shared] mgValueForKey:@"MaxRefreshHz"];
        if ([x respondsToSelector:@selector(integerValue)]) return [x integerValue];
        return 60;
    }
    return (NSInteger)v;
}

static void IPFLogScreenOnce(CGSize n, CGFloat sc, NSInteger fps) {
    static int done = 0;
    if (done) return;
    done = 1;
    CGFloat den = sc > 0 ? sc : 1;
    IPFExTrace([NSString stringWithFormat:
        @"UIScreen FAKE native=%.0fx%.0f scale=%.1f bounds=%.0fx%.0f fps=%ld",
        n.width, n.height, sc, n.width / den, n.height / den, (long)fps]);
}

#pragma mark - UIScreen

static CGRect (*orig_nativeBounds)(id, SEL);
static CGFloat (*orig_scale)(id, SEL);
static CGFloat (*orig_nativeScale)(id, SEL);
static NSInteger (*orig_maxFPS)(id, SEL);
static CGRect (*orig_bounds)(id, SEL);

static CGRect stub_nativeBounds(id self, SEL _cmd) {
    // pixels — from active profile (any catalog device). No fixed-SKU default.
    if (!IPFScreenOn())
        return orig_nativeBounds ? orig_nativeBounds(self, _cmd) : CGRectZero;
    CGSize s = IPFNativeSize();
    if (s.width < 1 || s.height < 1)
        return orig_nativeBounds ? orig_nativeBounds(self, _cmd) : CGRectZero;
    IPFLogScreenOnce(s, IPFScale(), IPFMaxFPS());
    return CGRectMake(0, 0, s.width, s.height);
}
static CGFloat stub_scale(id self, SEL _cmd) {
    if (!IPFScreenOn())
        return orig_scale ? orig_scale(self, _cmd) : 3.0;
    return IPFScale();
}
static CGFloat stub_nativeScale(id self, SEL _cmd) {
    // modern iPhone: nativeScale ≡ scale
    if (!IPFScreenOn())
        return orig_nativeScale ? orig_nativeScale(self, _cmd) : 3.0;
    return IPFScale();
}
static NSInteger stub_maxFPS(id self, SEL _cmd) {
    if (!IPFScreenOn())
        return orig_maxFPS ? orig_maxFPS(self, _cmd) : 60;
    return IPFMaxFPS();
}
static CGRect stub_bounds(id self, SEL _cmd) {
    // points = native / scale (or LogicalScreen* when set)
    if (!IPFScreenOn())
        return orig_bounds ? orig_bounds(self, _cmd) : CGRectZero;
    double lw = [[IPFConfig shared] doubleForKey:@"LogicalScreenWidth" fallback:0];
    double lh = [[IPFConfig shared] doubleForKey:@"LogicalScreenHeight" fallback:0];
    if (lw > 0 && lh > 0)
        return CGRectMake(0, 0, (CGFloat)lw, (CGFloat)lh);
    CGSize n = IPFNativeSize();
    CGFloat sc = IPFScale();
    if (sc < 1) sc = 1;
    return CGRectMake(0, 0, n.width / sc, n.height / sc);
}

#pragma mark - Disk (FakeHardware)

static void IPFDiskBytes(long long *totalOut, long long *freeOut) {
    long long total = 0, freeb = 0;
    id t = [[IPFConfig shared] stringForKey:@"TotalDiskCapacity"]
        ?: [[IPFConfig shared] mgValueForKey:@"TotalDiskCapacity"];
    id f = [[IPFConfig shared] stringForKey:@"FreeDiskSpace"]
        ?: [[IPFConfig shared] mgValueForKey:@"FreeDiskSpace"];
    if ([t respondsToSelector:@selector(longLongValue)]) total = [t longLongValue];
    if ([f respondsToSelector:@selector(longLongValue)]) freeb = [f longLongValue];
    if (total <= 0) {
        double gb = [[IPFConfig shared] doubleForKey:@"DiskCapacityGB" fallback:0];
        if (gb > 0) total = (long long)(gb * 1000.0 * 1000.0 * 1000.0);
    }
    if (freeb < 0) freeb = 0;
    // Consistency: free never exceeds total
    if (total > 0 && freeb > total) freeb = (long long)(total * 0.45);
    if (totalOut) *totalOut = total;
    if (freeOut) *freeOut = freeb;
}

static NSDictionary *(*orig_attrs)(id, SEL, NSString *, NSError **);
static NSDictionary *stub_attrs(id self, SEL _cmd, NSString *path, NSError **err) {
    NSDictionary *real = orig_attrs ? orig_attrs(self, _cmd, path, err) : nil;
    if (!real) return real;
    if (![[IPFConfig shared] flag:@"FakeHardware" defaultYes:YES]) return real;
    @try {
        long long total = 0, freeb = 0;
        IPFDiskBytes(&total, &freeb);
        if (total <= 0 && freeb <= 0) return real;
        NSMutableDictionary *m = [real mutableCopy];
        if (total > 0) {
            m[NSFileSystemSize] = @(total);
            m[@"NSFileSystemSize"] = @(total);
        }
        if (freeb > 0) {
            m[NSFileSystemFreeSize] = @(freeb);
            m[@"NSFileSystemFreeSize"] = @(freeb);
        }
        IPFExTrace([NSString stringWithFormat:@"disk FAKE total=%lld free=%lld", total, freeb]);
        return m;
    } @catch (__unused NSException *ex) {
        return real;
    }
}

// statfs(2) — apps that skip NSFileManager (POSIX)
#import <sys/mount.h>
static int (*orig_statfs)(const char *, struct statfs *);
static int stub_statfs(const char *path, struct statfs *buf) {
    int rc = orig_statfs ? orig_statfs(path, buf) : -1;
    if (rc != 0 || !buf) return rc;
    if (![[IPFConfig shared] flag:@"FakeHardware" defaultYes:YES]) return rc;
    long long total = 0, freeb = 0;
    IPFDiskBytes(&total, &freeb);
    if (total <= 0) return rc;
    uint32_t bsize = buf->f_bsize > 0 ? (uint32_t)buf->f_bsize : 4096;
    buf->f_blocks = (uint64_t)(total / bsize);
    if (freeb > 0) {
        uint64_t freen = (uint64_t)(freeb / bsize);
        buf->f_bfree = freen;
        buf->f_bavail = freen;
    }
    IPFExTrace([NSString stringWithFormat:@"statfs FAKE total=%lld free=%lld bsize=%u", total, freeb, bsize]);
    return rc;
}

#pragma mark - Jailbreak path hide
// Lab_Environment_Hardening.md + lab denylist. Fail = ENOENT / NO / NULL.
// MUST allow iPFaker config so spoof profile still loads inside Zalo.

#import <stdio.h>

static BOOL IPFIsAllowlistedPath(const char *path) {
    if (!path) return NO;
    // Keep spoof markers / config / own dylibs readable (sync with iPFakerJB allowlist).
    // Case: "ipfaker" alone misses product path "iPFakerMG.dylib".
    if (strstr(path, "ipfaker") || strstr(path, "iPFaker") || strstr(path, "IPFaker")) return YES;
    if (strstr(path, "v3_mg_loaded")) return YES;
    if (strstr(path, "v3_mg_debug")) return YES;
    if (strstr(path, "/var/jb/etc/ipfaker") || strstr(path, "/var/jb/etc/iPFaker")) return YES;
    if (strstr(path, "/private/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/var/mobile/Library/iPFaker")) return YES;
    if (strstr(path, "/var/jb/tmp/")) return YES;
    if (strstr(path, "/private/var/jb/tmp/")) return YES;
    if (strstr(path, "TweakInject/") && strstr(path, "iPF")) return YES;
    return NO;
}

static BOOL IPFIsJBPath(const char *path) {
    if (path == NULL || path[0] == '\0') return NO;
    if (![[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) return NO;
    if (IPFIsAllowlistedPath(path)) return NO;

    static const char *kDefault[] = {
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Applications/Installer.app",
        "/Applications/Filza.app",
        "/Applications/NewTerm.app",
        "/Library/MobileSubstrate",
        "/var/MobileSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/substrate",
        "/usr/libexec/substrate",
        "/usr/libexec/cydia",
        "/usr/lib/TweakInject",
        "/usr/lib/libellekit.dylib",
        "/usr/lib/ellekit",
        "CydiaSubstrate",
        "/var/jb",
        "/private/var/jb",
        "/var/LIB",
        "/var/binpack",
        "/var/lib/cydia",
        "/private/var/lib/cydia",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/.bootstrapped",
        "/.bootstrapped_electra",
        "/.bootstraprc",
        "/bootstraprc",
        "/bootstrap",
        "/electra",
        "/var/LIB",
        "/jb/",
        "unc0ver",
        "taurine",
        "odyssey",
        "chimera",
        "/usr/lib/frida",
        "/usr/lib/libfrida",
        "frida-server",
        "FridaGadget",
        "frida-agent",
        "/cores/binpack",
        "palera1n",
        "checkra1n",
        "Dopamine",
        "cydia://",
        "sileo://",
        "zbra://",
        "filza://",
        NULL
    };
    for (int i = 0; kDefault[i]; i++) {
        if (strstr(path, kDefault[i])) return YES;
    }
    @try {
        NSDictionary *jb = [IPFConfig shared].jailbreakHide;
        NSArray *paths = jb[@"paths"];
        if ([paths isKindOfClass:[NSArray class]]) {
            NSString *p = [NSString stringWithUTF8String:path];
            for (id x in paths) {
                NSString *s = [x description];
                if (!s.length) continue;
                if ([s.lowercaseString containsString:@"ipfaker"]) continue;
                if ([p rangeOfString:s].location != NSNotFound) return YES;
            }
        }
    } @catch (__unused NSException *ex) {}
    return NO;
}

static void IPFJBHideLogOnce(const char *api, const char *path) {
    static int n = 0;
    if (n >= 16) return;
    n++;
    IPFExTrace([NSString stringWithFormat:@"JBhide %s block %s", api, path ? path : "(null)"]);
}

static int (*orig_access)(const char *, int);
static int stub_access(const char *path, int mode) {
    if (IPFIsJBPath(path)) { IPFJBHideLogOnce("access", path); errno = ENOENT; return -1; }
    return orig_access ? orig_access(path, mode) : -1;
}
static int (*orig_stat)(const char *, struct stat *);
static int stub_stat(const char *path, struct stat *buf) {
    if (IPFIsJBPath(path)) { IPFJBHideLogOnce("stat", path); errno = ENOENT; return -1; }
    return orig_stat ? orig_stat(path, buf) : -1;
}
static int (*orig_lstat)(const char *, struct stat *);
static int stub_lstat(const char *path, struct stat *buf) {
    if (IPFIsJBPath(path)) { IPFJBHideLogOnce("lstat", path); errno = ENOENT; return -1; }
    return orig_lstat ? orig_lstat(path, buf) : -1;
}

// fopen / getenv / NSFileManager fileExists* live in iPFakerJB.dylib (split stack)

#pragma mark - canOpenURL (JB schemes + WebRTC disable)

static BOOL (*orig_canOpen)(id, SEL, NSURL *);
static BOOL stub_canOpen(id self, SEL _cmd, NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString ?: @"";
    if ([[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) {
        if ([s hasPrefix:@"cydia://"] || [s hasPrefix:@"sileo://"] || [s hasPrefix:@"zbra://"]
            || [s hasPrefix:@"filza://"] || [s hasPrefix:@"undecimus://"] || [s hasPrefix:@"activator://"]
            || [s hasPrefix:@"dopamine://"] || [s hasPrefix:@"ellekit://"]
            || [s hasPrefix:@"ssh://"] || [s hasPrefix:@"newterm://"]
            || [s hasPrefix:@"santander://"] || [s hasPrefix:@"trollstore://"]
            || [s hasPrefix:@"apt-repo://"] || [s hasPrefix:@"package://"]
            || [s hasPrefix:@"installer://"] || [s hasPrefix:@"palera1n://"]
            || [s hasPrefix:@"checkra1n://"] || [s hasPrefix:@"taurine://"]
            || [s hasPrefix:@"odyssey://"] || [s hasPrefix:@"unc0ver://"]) {
            IPFJBHideLogOnce("canOpenURL", s.UTF8String);
            return NO;
        }
    }
    if ([[IPFConfig shared] flag:@"DisableWebRTC" defaultYes:NO]) {
        if ([s containsString:@"webrtc"] || [s hasPrefix:@"rtc:"] || [s hasPrefix:@"stuns:"]
            || [s hasPrefix:@"turns:"]) {
            return NO;
        }
    }
    return orig_canOpen ? orig_canOpen(self, _cmd, url) : NO;
}

#pragma mark - User-Agent (FakeBrowser)

static NSDictionary *(*orig_allHTTP)(id, SEL);
static NSDictionary *stub_allHTTP(id self, SEL _cmd) {
    NSDictionary *h = orig_allHTTP ? orig_allHTTP(self, _cmd) : nil;
    if (![[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES]) return h;
    NSString *ua = [[IPFConfig shared] stringForKey:@"UserAgent"]
        ?: [[IPFConfig shared] stringForKey:@"HTTPUserAgent"];
    if (!ua.length) return h;
    NSMutableDictionary *m = h ? [h mutableCopy] : [NSMutableDictionary dictionary];
    m[@"User-Agent"] = ua;
    return m;
}

static NSString *(*orig_valueForHTTP)(id, SEL, NSString *);
static NSString *stub_valueForHTTP(id self, SEL _cmd, NSString *field) {
    if ([[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES]
        && field && [field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
        NSString *ua = [[IPFConfig shared] stringForKey:@"UserAgent"]
            ?: [[IPFConfig shared] stringForKey:@"HTTPUserAgent"];
        if (ua.length) return ua;
    }
    return orig_valueForHTTP ? orig_valueForHTTP(self, _cmd, field) : nil;
}

// Locale / TZ / Date / Location / Sensor → IPFHooksEnv.m (CT pack, AMFI)

#pragma mark - Hostname + getifaddrs (FakeDevice / FakeWifi)

/// Hostname-safe: ASCII letters, digits, hyphen; max 63 (DNS label / gethostname convention).
static NSString *IPFHostnameFromConfig(void) {
    IPFConfig *cfg = [IPFConfig shared];
    NSString *raw = [cfg stringForKey:@"Hostname"]
        ?: [cfg stringForKey:@"kern.hostname"]
        ?: [cfg stringForKey:@"UserAssignedDeviceName"]
        ?: [cfg stringForKey:@"DeviceName"]
        ?: @"iPhone";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN((NSUInteger)63, raw.length + 4)];
    for (NSUInteger i = 0; i < raw.length && out.length < 63; i++) {
        unichar c = [raw characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
            [out appendFormat:@"%C", c];
        } else if (c == ' ' || c == '_' || c == '.') {
            if (out.length && [out characterAtIndex:out.length - 1] != '-')
                [out appendString:@"-"];
        }
    }
    while (out.length && [out characterAtIndex:0] == '-')
        [out deleteCharactersInRange:NSMakeRange(0, 1)];
    while (out.length && [out characterAtIndex:out.length - 1] == '-')
        [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    if (out.length == 0) [out appendString:@"iPhone"];
    return [out copy];
}

static BOOL IPFParseMAC6(NSString *mac, uint8_t out[6]) {
    if (!mac.length || !out) return NO;
    NSArray *parts = [[mac uppercaseString] componentsSeparatedByString:@":"];
    if (parts.count != 6) {
        parts = [[mac uppercaseString] componentsSeparatedByString:@"-"];
    }
    if (parts.count != 6) return NO;
    for (int i = 0; i < 6; i++) {
        NSString *p = parts[i];
        if (p.length != 2) return NO;
        unsigned v = 0;
        NSScanner *sc = [NSScanner scannerWithString:p];
        if (![sc scanHexInt:&v] || v > 0xFF) return NO;
        out[i] = (uint8_t)v;
    }
    return YES;
}

static int (*orig_gethostname)(char *, size_t);
static int stub_gethostname(char *name, size_t namelen) {
    // POSIX gethostname — spoof only when FakeDevice or FakeNetwork on
    IPFConfig *cfg = [IPFConfig shared];
    BOOL on = [cfg flag:@"FakeDevice" defaultYes:YES] || [cfg flag:@"FakeNetwork" defaultYes:YES];
    if (!on || !name || namelen == 0)
        return orig_gethostname ? orig_gethostname(name, namelen) : -1;
    @autoreleasepool {
        NSString *hn = IPFHostnameFromConfig();
        const char *s = hn.UTF8String ?: "iPhone";
        size_t n = strlen(s);
        if (n + 1 > namelen) {
            // ERANGE if buffer too small (POSIX)
            if (namelen > 0) {
                memcpy(name, s, namelen - 1);
                name[namelen - 1] = '\0';
            }
            errno = ENAMETOOLONG;
            return -1;
        }
        memcpy(name, s, n + 1);
        IPFExTrace([NSString stringWithFormat:@"gethostname FAKE %@", hn]);
        return 0;
    }
}

static int (*orig_getifaddrs)(struct ifaddrs **);
static int stub_getifaddrs(struct ifaddrs **ifap) {
    int rc = orig_getifaddrs ? orig_getifaddrs(ifap) : -1;
    if (rc != 0 || !ifap || !*ifap) return rc;
    IPFConfig *cfg = [IPFConfig shared];
    // FakeWifi (default YES) — rewrite AF_LINK EUI-48 to config WifiAddress
    if (![cfg flag:@"FakeWifi" defaultYes:YES] && ![cfg flag:@"FakeNetwork" defaultYes:YES])
        return rc;
    @autoreleasepool {
        NSString *wifi = [cfg stringForKey:@"WifiAddress"]
            ?: [cfg mgValueForKey:@"WifiAddress"];
        uint8_t mac[6];
        if (!IPFParseMAC6(wifi, mac)) {
            IPFExTrace(@"getifaddrs skip (no valid WifiAddress in config)");
            return rc;
        }
        // Prefer en0 (Wi‑Fi) for stable path; also en1/awdl0/pdp_ip* only when name known.
        // Patching ALL AF_LINK with same MAC can break multi-interface fingerprint checks.
        int patched = 0;
        int patched_en0 = 0;
        for (struct ifaddrs *ifa = *ifap; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || !ifa->ifa_name) continue;
            if (ifa->ifa_addr->sa_family != AF_LINK) continue;
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            if (sdl->sdl_alen != 6) continue;
            const char *nm = ifa->ifa_name;
            // Primary Wi‑Fi + common cellular/wifi companions used by fingerprint libs
            BOOL isWifiFamily =
                (strcmp(nm, "en0") == 0) ||
                (strncmp(nm, "en0", 3) == 0) ||
                (strcmp(nm, "en1") == 0) ||
                (strncmp(nm, "awdl", 4) == 0) ||
                (strncmp(nm, "llw", 3) == 0);
            if (!isWifiFamily) continue;
            unsigned char *ll = (unsigned char *)LLADDR(sdl);
            if (!ll) continue;
            memcpy(ll, mac, 6);
            patched++;
            if (strcmp(nm, "en0") == 0) patched_en0 = 1;
        }
        // Fallback: if en0 missing, patch first AF_LINK with alen=6 (older iOS / sim)
        if (patched == 0) {
            for (struct ifaddrs *ifa = *ifap; ifa; ifa = ifa->ifa_next) {
                if (!ifa->ifa_addr) continue;
                if (ifa->ifa_addr->sa_family != AF_LINK) continue;
                struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
                if (sdl->sdl_alen != 6) continue;
                unsigned char *ll = (unsigned char *)LLADDR(sdl);
                if (!ll) continue;
                memcpy(ll, mac, 6);
                patched++;
                break;
            }
        }
        if (patched > 0)
            IPFExTrace([NSString stringWithFormat:
                @"getifaddrs FAKE MAC %@ ifaces=%d en0=%d", wifi, patched, patched_en0]);
    }
    return rc;
}

static NSString *(*orig_hostName)(id, SEL);
static NSString *stub_hostName(id self, SEL _cmd) {
    IPFConfig *cfg = [IPFConfig shared];
    if (![cfg flag:@"FakeDevice" defaultYes:YES] && ![cfg flag:@"FakeNetwork" defaultYes:YES])
        return orig_hostName ? orig_hostName(self, _cmd) : @"iPhone";
    NSString *hn = IPFHostnameFromConfig();
    IPFExTrace([NSString stringWithFormat:@"NSProcessInfo.hostName FAKE %@", hn]);
    return hn;
}

// NSProcessInfo OS string — must match UIDevice.systemVersion / ProductVersion
static NSString *(*orig_osVersionString)(id, SEL);
static NSString *stub_osVersionString(id self, SEL _cmd) {
    IPFConfig *cfg = [IPFConfig shared];
    if (![cfg flag:@"FakeSysOSVersion" defaultYes:YES])
        return orig_osVersionString ? orig_osVersionString(self, _cmd) : @"Version 17.0";
    NSString *pv = [cfg stringForKey:@"ProductVersion"] ?: @"17.0";
    NSString *bv = [cfg stringForKey:@"BuildVersion"]
        ?: [cfg stringForKey:@"ProductBuildVersion"]
        ?: @"";
    // Apple format: "Version 18.5 (Build 22F76)" — keep short if no build
    NSString *out = bv.length
        ? [NSString stringWithFormat:@"Version %@ (Build %@)", pv, bv]
        : [NSString stringWithFormat:@"Version %@", pv];
    IPFExTrace([NSString stringWithFormat:@"NSProcessInfo.operatingSystemVersionString FAKE %@", out]);
    return out;
}

// Note: do NOT MSHook operatingSystemVersion (returns struct — arm64 stret risk).
// Apps that need version numbers usually use UIDevice.systemVersion or the string form.

// Thermal — nominal when spoofing (host thermal leaks silicon load fingerprint)
static NSInteger (*orig_thermal)(id, SEL);
static NSInteger stub_thermal(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeHardware" defaultYes:YES]
        || [[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES]) {
        // NSProcessInfoThermalStateNominal = 0
        NSInteger t = (NSInteger)[[IPFConfig shared] doubleForKey:@"ThermalState" fallback:0];
        if (t < 0 || t > 3) t = 0;
        return t;
    }
    return orig_thermal ? orig_thermal(self, _cmd) : 0;
}

#pragma mark - CNCopyCurrentNetworkInfo (SSID / BSSID ≡ profile)

// Apple CaptiveNetwork (deprecated but still linked by many apps)
// https://developer.apple.com — CNCopyCurrentNetworkInfo returns CFDictionary:
//   kCNNetworkInfoKeySSID, kCNNetworkInfoKeyBSSID, kCNNetworkInfoKeySSIDData
typedef CFDictionaryRef (*CNCopyCurrentNetworkInfo_t)(CFStringRef interfaceName);
static CNCopyCurrentNetworkInfo_t orig_CNCopyCurrentNetworkInfo = NULL;

static CFDictionaryRef stub_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    CFDictionaryRef real = orig_CNCopyCurrentNetworkInfo
        ? orig_CNCopyCurrentNetworkInfo(interfaceName) : NULL;
    IPFConfig *cfg = [IPFConfig shared];
    if (![cfg flag:@"FakeWifi" defaultYes:YES] && ![cfg flag:@"FakeNetwork" defaultYes:YES])
        return real;
    @autoreleasepool {
        NSString *ssid = [cfg stringForKey:@"SSID"] ?: @"Viettel-WiFi";
        NSString *bssid = [cfg stringForKey:@"BSSID"]
            ?: [cfg stringForKey:@"WifiAddress"]
            ?: [cfg mgValueForKey:@"WifiAddress"];
        if (!bssid.length) {
            return real; // keep real if profile missing MAC
        }
        // CaptiveNetwork keys (historical): SSID, BSSID, SSIDDATA
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:4];
        m[@"SSID"] = ssid;
        m[@"BSSID"] = bssid;
        NSData *ssidData = [ssid dataUsingEncoding:NSUTF8StringEncoding];
        if (ssidData) m[@"SSIDDATA"] = ssidData;
        if (real) CFRelease(real);
        IPFExTrace([NSString stringWithFormat:@"CNCopyCurrentNetworkInfo FAKE SSID=%@ BSSID=%@", ssid, bssid]);
        return CFBridgingRetain(m);
    }
}

#pragma mark - WKWebView UA + JS screen spoof (FakeBrowser)
// Apple WebKit: WKWebView.customUserAgent, WKUserScript atDocumentStart
// MDN: screen.width/height, window.devicePixelRatio, navigator.userAgent
// Values MUST match UIScreen / catalog (LogicalScreen* + scale + UserAgent)

/// Safari Mobile UA from ProductVersion — always sync iOS version with catalog profile.
static NSString *IPFSafariUAFromProfile(void) {
    NSString *pv = [[IPFConfig shared] stringForKey:@"ProductVersion"] ?: @"18.5";
    NSString *osUnd = [pv stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSArray *parts = [pv componentsSeparatedByString:@"."];
    NSString *maj = parts.count ? parts[0] : @"18";
    NSString *min = parts.count > 1 ? parts[1] : @"0";
    return [NSString stringWithFormat:
        @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
        @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%@.%@ "
        @"Mobile/15E148 Safari/604.1",
        osUnd, maj, min];
}

static NSString *IPFWebUA(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    BOOL isZalo = [bid.lowercaseString containsString:@"zalo"]
        || [bid.lowercaseString containsString:@"zingalo"];
    // Prefer Safari-form HTTPUserAgent (sync ProductVersion)
    NSString *http = [[IPFConfig shared] stringForKey:@"HTTPUserAgent"];
    NSString *ua = [[IPFConfig shared] stringForKey:@"UserAgent"];
    NSString *zaloUA = [[IPFConfig shared] stringForKey:@"zalo_fakeWebViewUA"]
        ?: [[IPFConfig shared] stringForKey:@"ZaloWebViewUA"];
    NSString *safari = IPFSafariUAFromProfile();
    // HIOS: Zalo WebView UA must carry spoofed iOS + app marker
    if (isZalo) {
        if (zaloUA.length && [zaloUA containsString:@"iPhone OS"])
            return zaloUA;
        // Build Zalo-like UA on spoofed Safari base (OS version from profile)
        NSString *pv = [[IPFConfig shared] stringForKey:@"ProductVersion"] ?: @"15.8.8";
        return [NSString stringWithFormat:@"%@ Zaloios/%@ (iPFaker)", safari, pv];
    }
    if (http.length && [http.lowercaseString containsString:@"safari"]
        && [http containsString:@"iPhone OS"])
        return http;
    if (ua.length && [ua.lowercaseString containsString:@"safari"]
        && [ua containsString:@"iPhone OS"]
        && ![ua.lowercaseString containsString:@"zalo"])
        return ua;
    return safari;
}

static NSString *IPFJSEscape(NSString *s) {
    if (!s) return @"";
    NSString *o = s;
    o = [o stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    o = [o stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    o = [o stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    o = [o stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return o;
}

/// JS spoof: UA + screen + WebGL renderer + canvas micro-noise + hwConcurrency
/// (must stay in sync with UIScreen / MetalDeviceName / hw.ncpu / locale profile)
static NSString *IPFWebSpoofJS(void) {
    IPFConfig *cfg = [IPFConfig shared];
    NSString *ua = IPFJSEscape(IPFWebUA());
    // Logical CSS pixels (points) — same as UIScreen.bounds
    double lw = [cfg doubleForKey:@"LogicalScreenWidth" fallback:0];
    double lh = [cfg doubleForKey:@"LogicalScreenHeight" fallback:0];
    double sc = [cfg doubleForKey:@"main-screen-scale" fallback:0];
    double nw = [cfg doubleForKey:@"main-screen-width" fallback:0];
    double nh = [cfg doubleForKey:@"main-screen-height" fallback:0];
    if (sc < 1) sc = IPFScale();
    // Derive logical from native when missing — never hardcode one SKU (e.g. 15 Pro Max)
    if (lw < 1 && nw > 0 && sc > 0) lw = nw / sc;
    if (lh < 1 && nh > 0 && sc > 0) lh = nh / sc;
    if (lw < 1 || lh < 1) {
        CGSize n = IPFNativeSize();
        CGFloat sc2 = IPFScale();
        if (sc2 < 1) sc2 = 1;
        if (lw < 1) lw = n.width / sc2;
        if (lh < 1) lh = n.height / sc2;
    }
    int sw = (int)llround(lw);
    int sh = (int)llround(lh);
    int availH = sh > 44 ? sh - 0 : sh;
    // WebGL UNMASKED_RENDERER ≡ MetalDeviceName / GPUName (sync catalog chip)
    NSString *gpu = [cfg stringForKey:@"MetalDeviceName"]
        ?: [cfg stringForKey:@"GPUName"]
        ?: [cfg stringForKey:@"ChipName"]
        ?: @"Apple GPU";
    if ([gpu rangeOfString:@"GPU"].location == NSNotFound) {
        NSString *c = [gpu stringByReplacingOccurrencesOfString:@" Bionic" withString:@""];
        gpu = [NSString stringWithFormat:@"Apple %@ GPU", c];
    } else if (![gpu hasPrefix:@"Apple "]) {
        gpu = [@"Apple " stringByAppendingString:gpu];
    }
    NSString *gpuEsc = IPFJSEscape(gpu);
    int cores = (int)llround([cfg doubleForKey:@"hw.ncpu" fallback:0]);
    if (cores < 2) cores = (int)llround([cfg doubleForKey:@"hw.physicalcpu" fallback:6]);
    if (cores < 2) cores = 6;
    double ramMB = [cfg doubleForKey:@"PhysicalMemoryMB" fallback:0];
    if (ramMB < 1) {
        double bytes = [cfg doubleForKey:@"hw.memsize" fallback:0];
        if (bytes > 0) ramMB = bytes / (1024.0 * 1024.0);
    }
    // deviceMemory is GB (Chrome); Safari may ignore — still set for consistency
    int memGB = ramMB >= 1024 ? (int)llround(ramMB / 1024.0) : (ramMB >= 512 ? 1 : 0);
    if (memGB < 1) memGB = 4;
    NSString *lang = [cfg stringForKey:@"PreferredLanguage"]
        ?: [cfg stringForKey:@"LocaleIdentifier"]
        ?: @"vi-VN";
    lang = [lang stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSString *langEsc = IPFJSEscape(lang);
    NSString *tz = IPFJSEscape([cfg stringForKey:@"TimeZoneName"] ?: @"Asia/Ho_Chi_Minh");
    // Canvas seed from serial (stable per spoof profile)
    NSString *serial = [cfg stringForKey:@"SerialNumber"] ?: @"iPhone";
    uint32_t h = 2166136261u;
    const char *ss = serial.UTF8String ?: "x";
    for (const unsigned char *p = (const unsigned char *)ss; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    int seed = (int)(h & 0xFF);
    // Compact JS (MG AMFI size) — WebGL renderer + canvas seed + core navigator/screen
    return [NSString stringWithFormat:
        @"(function(){try{var ua='%@',sw=%d,sh=%d,dpr=%g,gpu='%@',hc=%d,lang='%@',tz='%@',s=%d;"
        @"var D=function(o,k,v){try{Object.defineProperty(o,k,{get:function(){return v},configurable:true})}catch(e){}};"
        @"D(navigator,'userAgent',ua);D(navigator,'platform','iPhone');D(navigator,'vendor','Apple Computer, Inc.');"
        @"D(navigator,'maxTouchPoints',5);D(navigator,'language',lang);D(navigator,'languages',[lang,'en-US']);"
        @"D(navigator,'hardwareConcurrency',hc);"
        @"try{var R=Intl.DateTimeFormat.prototype.resolvedOptions;Intl.DateTimeFormat.prototype.resolvedOptions=function(){var o=R.apply(this,arguments)||{};o.timeZone=tz;return o}}catch(e){}"
        @"D(screen,'width',sw);D(screen,'height',sh);D(screen,'availWidth',sw);D(screen,'availHeight',%d);"
        @"D(screen,'colorDepth',24);D(window,'devicePixelRatio',dpr);D(window,'innerWidth',sw);D(window,'innerHeight',sh);"
        @"var P=function(pr){if(!pr||!pr.getParameter)return;var g=pr.getParameter;pr.getParameter=function(p){"
        @"if(p===37445)return 'Apple Inc.';if(p===37446)return gpu;return g.apply(this,arguments)}};"
        @"try{P(WebGLRenderingContext.prototype)}catch(e){}try{P(WebGL2RenderingContext.prototype)}catch(e){}"
        @"try{var T=HTMLCanvasElement.prototype.toDataURL;HTMLCanvasElement.prototype.toDataURL=function(){try{"
        @"var c=this.getContext('2d');if(c&&this.width>16){var i=c.getImageData(s%%16,s%%16,1,1);i.data[0]=(i.data[0]+s)&255;c.putImageData(i,s%%16,s%%16)}}catch(e){}"
        @"return T.apply(this,arguments)}}catch(e){}"
        @"}catch(e){}})();",
        ua, sw, sh, sc, gpuEsc, cores, langEsc, tz, seed, availH];
}

// Runtime WebKit (no hard link) — lab flat UA + WKUserScript for screen JS
static void IPFAttachWebSpoofToConfig(id cfg) {
    if (!cfg) return;
    if (![[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES]) return;
    @try {
        Class CfgCls = objc_getClass("WKWebViewConfiguration");
        Class UCC = objc_getClass("WKUserContentController");
        Class US = objc_getClass("WKUserScript");
        if (!CfgCls || !UCC || !US) return;
        if (![cfg isKindOfClass:CfgCls]) return;
        id ucc = [cfg valueForKey:@"userContentController"];
        if (!ucc) {
            ucc = [[UCC alloc] init];
            [cfg setValue:ucc forKey:@"userContentController"];
        }
        NSString *js = IPFWebSpoofJS();
        if (!js.length) return;
        // injectionTime: 0 = AtDocumentStart, 1 = AtDocumentEnd (WKUserScriptInjectionTime)
        id scriptStart = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(
            [US alloc], @selector(initWithSource:injectionTime:forMainFrameOnly:),
            js, (NSInteger)0, NO);
        id scriptEnd = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(
            [US alloc], @selector(initWithSource:injectionTime:forMainFrameOnly:),
            js, (NSInteger)1, NO);
        if (scriptStart) [ucc performSelector:@selector(addUserScript:) withObject:scriptStart];
        if (scriptEnd) [ucc performSelector:@selector(addUserScript:) withObject:scriptEnd];
    } @catch (__unused NSException *ex) {}
}

static void IPFApplyWebViewUA(id web) {
    if (!web) return;
    if (![[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES]) return;
    NSString *ua = IPFWebUA();
    if (!ua.length) return;
    @try {
        if ([web respondsToSelector:@selector(setCustomUserAgent:)])
            [web performSelector:@selector(setCustomUserAgent:) withObject:ua];
    } @catch (__unused NSException *ex) {}
}

static NSString *(*orig_customUA)(id, SEL);
static NSString *stub_customUA(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES])
        return orig_customUA ? orig_customUA(self, _cmd) : nil;
    NSString *ua = IPFWebUA();
    if (ua.length) return ua;
    return orig_customUA ? orig_customUA(self, _cmd) : nil;
}

static void (*orig_setCustomUA)(id, SEL, NSString *);
static void stub_setCustomUA(id self, SEL _cmd, NSString *ua) {
    if ([[IPFConfig shared] flag:@"FakeBrowser" defaultYes:YES]) {
        NSString *forced = IPFWebUA();
        if (forced.length) {
            if (orig_setCustomUA) orig_setCustomUA(self, _cmd, forced);
            return;
        }
    }
    if (orig_setCustomUA) orig_setCustomUA(self, _cmd, ua);
}

static id (*orig_wkInitFrameConfig)(id, SEL, CGRect, id);
static id stub_wkInitFrameConfig(id self, SEL _cmd, CGRect frame, id configuration) {
    Class CfgCls = objc_getClass("WKWebViewConfiguration");
    id cfg = configuration;
    if (CfgCls && cfg && [cfg isKindOfClass:CfgCls]) {
        @try { cfg = [cfg copy]; } @catch (__unused NSException *ex) {}
    } else if (CfgCls) {
        cfg = [[CfgCls alloc] init];
    }
    IPFAttachWebSpoofToConfig(cfg);
    id web = orig_wkInitFrameConfig ? orig_wkInitFrameConfig(self, _cmd, frame, cfg) : nil;
    Class Wk = objc_getClass("WKWebView");
    if (Wk && web && [web isKindOfClass:Wk]) {
        IPFApplyWebViewUA(web);
        static int once = 0;
        if (!once) {
            once = 1;
            double lw = [[IPFConfig shared] doubleForKey:@"LogicalScreenWidth" fallback:0];
            double sc = [[IPFConfig shared] doubleForKey:@"main-screen-scale" fallback:0];
            if (lw < 1 || sc < 1) {
                CGSize n = IPFNativeSize();
                sc = IPFScale();
                if (sc < 1) sc = 1;
                lw = n.width / sc;
            }
            double lh = [[IPFConfig shared] doubleForKey:@"LogicalScreenHeight" fallback:0];
            if (lh < 1 && sc > 0) {
                CGSize n = IPFNativeSize();
                lh = n.height / sc;
            }
            NSString *uaShort = IPFWebUA();
            if (uaShort.length > 48)
                uaShort = [[uaShort substringToIndex:48] stringByAppendingString:@"…"];
            IPFExTrace([NSString stringWithFormat:
                @"WKWebView UA+JS injected sw=%.0f sh=%.0f dpr=%.1f ua=%@",
                lw, lh, sc, uaShort]);
            @try {
                NSString *row = [NSString stringWithFormat:
                    @"SURFACE WebView UA/JS screen: sw=%.0f sh=%.0f dpr=%.1f FakeBrowser=1\n",
                    lw, lh, sc];
                NSString *p = @"/var/mobile/Library/iPFaker/ipfaker_surfaces.log";
                NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
                if (h) { [h seekToEndOfFile]; [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
                else [row writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
            } @catch (__unused NSException *ex) {}
        }
    }
    return web;
}

static id (*orig_wkInitCoder)(id, SEL, id);
static id stub_wkInitCoder(id self, SEL _cmd, id coder) {
    id web = orig_wkInitCoder ? orig_wkInitCoder(self, _cmd, coder) : nil;
    Class Wk = objc_getClass("WKWebView");
    if (Wk && web && [web isKindOfClass:Wk]) {
        IPFApplyWebViewUA(web);
        @try {
            NSString *js = IPFWebSpoofJS();
            if (js.length && [web respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(
                    web, @selector(evaluateJavaScript:completionHandler:), js, nil);
            }
        } @catch (__unused NSException *ex) {}
    }
    return web;
}

// WebRTC / Proxy / AppAttest implementations → IPFHooksServer.m (CT pack, AMFI)

#pragma mark - Install

void IPFInstallExtraZaloSafeHooks(void) {
    // Only ProcessInfo — proven non-crash; ss spoof via CT Deep (NET), not UIScreen/MG dims.
    IPFResolve();
    IPFExTrace(@"IPFInstallExtraZaloSafeHooks begin");
    if (pMSHookMessageEx) {
        Class nspi = objc_getClass("NSProcessInfo");
        if (nspi) {
            if (class_getInstanceMethod(nspi, @selector(hostName))) {
                pMSHookMessageEx(nspi, @selector(hostName), (IMP)stub_hostName, (IMP *)&orig_hostName);
            }
            if (class_getInstanceMethod(nspi, @selector(operatingSystemVersionString))) {
                pMSHookMessageEx(nspi, @selector(operatingSystemVersionString),
                                 (IMP)stub_osVersionString, (IMP *)&orig_osVersionString);
            }
            IPFExTrace(@"Zalo-safe ProcessInfo OS+hostName OK");
        }
    }
    IPFExTrace(@"IPFInstallExtraZaloSafeHooks done");
}

void IPFInstallExtraNetLeanHooks(void) {
    // Non-Zalo lean: ProcessInfo + optional net hide. Never UIScreen (crash risk).
    IPFResolve();
    IPFExTrace(@"IPFInstallExtraNetLeanHooks begin");
    IPFInstallExtraZaloSafeHooks();
    if (pMSHookMessageEx) {
        Class app = objc_getClass("UIApplication");
        if (app && class_getInstanceMethod(app, @selector(canOpenURL:))) {
            pMSHookMessageEx(app, @selector(canOpenURL:), (IMP)stub_canOpen, (IMP *)&orig_canOpen);
            IPFExTrace(@"lean canOpenURL OK");
        }
    }
    if (pMSHookFunction) {
        void *gif = dlsym(RTLD_DEFAULT, "getifaddrs");
        if (gif) {
            pMSHookFunction(gif, (void *)stub_getifaddrs, (void **)&orig_getifaddrs);
            IPFExTrace(@"lean getifaddrs OK");
        }
        void *ghn = dlsym(RTLD_DEFAULT, "gethostname");
        if (ghn) {
            pMSHookFunction(ghn, (void *)stub_gethostname, (void **)&orig_gethostname);
            IPFExTrace(@"lean gethostname OK");
        }
    }
    IPFExTrace(@"IPFInstallExtraNetLeanHooks done (no UIScreen)");
}

void IPFInstallExtraHooks(void) {
    IPFResolve();
    IPFExTrace(@"IPFInstallExtraHooks begin");
    // Surface matrix (lab): UIScreen | WebView | Network iface | JB hide
    // + MobileGestalt/sysctl/UIDevice installed in IPFInstallMGHooks

    if (pMSHookMessageEx) {
        Class scr = objc_getClass("UIScreen");
        if (scr) {
            if (class_getInstanceMethod(scr, @selector(nativeBounds)))
                pMSHookMessageEx(scr, @selector(nativeBounds), (IMP)stub_nativeBounds, (IMP *)&orig_nativeBounds);
            if (class_getInstanceMethod(scr, @selector(scale)))
                pMSHookMessageEx(scr, @selector(scale), (IMP)stub_scale, (IMP *)&orig_scale);
            if (class_getInstanceMethod(scr, @selector(nativeScale)))
                pMSHookMessageEx(scr, @selector(nativeScale), (IMP)stub_nativeScale, (IMP *)&orig_nativeScale);
            if (class_getInstanceMethod(scr, @selector(bounds)))
                pMSHookMessageEx(scr, @selector(bounds), (IMP)stub_bounds, (IMP *)&orig_bounds);
            SEL mfp = @selector(maximumFramesPerSecond);
            if (class_getInstanceMethod(scr, mfp))
                pMSHookMessageEx(scr, mfp, (IMP)stub_maxFPS, (IMP *)&orig_maxFPS);
            IPFExTrace(@"UIScreen hooks OK");
        }

        Class fm = objc_getClass("NSFileManager");
        if (fm) {
            if (class_getInstanceMethod(fm, @selector(attributesOfFileSystemForPath:error:))) {
                pMSHookMessageEx(fm, @selector(attributesOfFileSystemForPath:error:),
                                 (IMP)stub_attrs, (IMP *)&orig_attrs);
                IPFExTrace(@"disk hooks OK");
            }
            // fileExists* → iPFakerJB (keeps MG lean / AMFI-safe)
        }

        Class app = objc_getClass("UIApplication");
        if (app && class_getInstanceMethod(app, @selector(canOpenURL:))) {
            pMSHookMessageEx(app, @selector(canOpenURL:), (IMP)stub_canOpen, (IMP *)&orig_canOpen);
            IPFExTrace(@"canOpenURL OK");
        }

        Class nreq = objc_getClass("NSURLRequest");
        if (nreq) {
            if (class_getInstanceMethod(nreq, @selector(allHTTPHeaderFields)))
                pMSHookMessageEx(nreq, @selector(allHTTPHeaderFields), (IMP)stub_allHTTP, (IMP *)&orig_allHTTP);
            if (class_getInstanceMethod(nreq, @selector(valueForHTTPHeaderField:)))
                pMSHookMessageEx(nreq, @selector(valueForHTTPHeaderField:), (IMP)stub_valueForHTTP, (IMP *)&orig_valueForHTTP);
            IPFExTrace(@"UA hooks OK");
        }
        // Locale/TZ/Date/Location/Sensor → IPFInstallEnvHooks (CT)
        // WebRTC ICE → IPFInstallServerHooks (CT)
    }

    if (pMSHookMessageEx) {
        // NSProcessInfo — hostName + OS version (sync UIDevice / ProductVersion)
        Class nspi = objc_getClass("NSProcessInfo");
        if (nspi) {
            if (class_getInstanceMethod(nspi, @selector(hostName)))
                pMSHookMessageEx(nspi, @selector(hostName), (IMP)stub_hostName, (IMP *)&orig_hostName);
            if (class_getInstanceMethod(nspi, @selector(operatingSystemVersionString)))
                pMSHookMessageEx(nspi, @selector(operatingSystemVersionString),
                                 (IMP)stub_osVersionString, (IMP *)&orig_osVersionString);
            if (class_getInstanceMethod(nspi, @selector(thermalState)))
                pMSHookMessageEx(nspi, @selector(thermalState), (IMP)stub_thermal, (IMP *)&orig_thermal);
            IPFExTrace(@"NSProcessInfo hostName/OS/thermal OK");
        }
    }

    if (pMSHookFunction) {
        void *a = dlsym(RTLD_DEFAULT, "access");
        if (a) pMSHookFunction(a, (void *)stub_access, (void **)&orig_access);
        void *st = dlsym(RTLD_DEFAULT, "stat");
        if (st) pMSHookFunction(st, (void *)stub_stat, (void **)&orig_stat);
        void *ls = dlsym(RTLD_DEFAULT, "lstat");
        if (ls) pMSHookFunction(ls, (void *)stub_lstat, (void **)&orig_lstat);
        // fopen/getenv → iPFakerJB.dylib
        IPFExTrace(@"access/stat/lstat JB hide OK");

        // libc network identity (lab-class surface)
        void *gif = dlsym(RTLD_DEFAULT, "getifaddrs");
        if (gif) {
            pMSHookFunction(gif, (void *)stub_getifaddrs, (void **)&orig_getifaddrs);
            IPFExTrace(@"getifaddrs OK");
        }
        void *ghn = dlsym(RTLD_DEFAULT, "gethostname");
        if (ghn) {
            pMSHookFunction(ghn, (void *)stub_gethostname, (void **)&orig_gethostname);
            IPFExTrace(@"gethostname OK");
        }
        void *sfs = dlsym(RTLD_DEFAULT, "statfs");
        if (sfs) {
            pMSHookFunction(sfs, (void *)stub_statfs, (void **)&orig_statfs);
            IPFExTrace(@"statfs OK");
        }

        // CaptiveNetwork — may live in SystemConfiguration
        void *cn = dlsym(RTLD_DEFAULT, "CNCopyCurrentNetworkInfo");
        if (!cn) {
            void *sc = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW);
            if (sc) cn = dlsym(sc, "CNCopyCurrentNetworkInfo");
        }
        if (cn) {
            pMSHookFunction(cn, (void *)stub_CNCopyCurrentNetworkInfo, (void **)&orig_CNCopyCurrentNetworkInfo);
            IPFExTrace(@"CNCopyCurrentNetworkInfo OK");
        }
    }

    // WKWebView: customUserAgent + init inject WKUserScript (UA + screen JS)
    if (pMSHookMessageEx) {
        Class wkw = objc_getClass("WKWebView");
        if (wkw) {
            if (class_getInstanceMethod(wkw, @selector(customUserAgent)))
                pMSHookMessageEx(wkw, @selector(customUserAgent), (IMP)stub_customUA, (IMP *)&orig_customUA);
            if (class_getInstanceMethod(wkw, @selector(setCustomUserAgent:)))
                pMSHookMessageEx(wkw, @selector(setCustomUserAgent:), (IMP)stub_setCustomUA, (IMP *)&orig_setCustomUA);
            SEL initCfg = @selector(initWithFrame:configuration:);
            if (class_getInstanceMethod(wkw, initCfg))
                pMSHookMessageEx(wkw, initCfg, (IMP)stub_wkInitFrameConfig, (IMP *)&orig_wkInitFrameConfig);
            if (class_getInstanceMethod(wkw, @selector(initWithCoder:)))
                pMSHookMessageEx(wkw, @selector(initWithCoder:), (IMP)stub_wkInitCoder, (IMP *)&orig_wkInitCoder);
            IPFExTrace(@"WKWebView UA+JS hooks OK");
        }
        // Proxy / AppAttest / WebRTC full hooks: IPFHooksServer.m
        // (pack into JB only if inject size allows; flags still dual-path config)
    }

    // Append Extra surfaces to matrix log (sync with MG SELFTEST)
    @try {
        IPFConfig *cfg = [IPFConfig shared];
        NSString *row = [NSString stringWithFormat:
            @"SURFACE UIScreen: FakeScreen=%d native=%@x%@ scale=%@\n"
            @"SURFACE WebView: FakeBrowser=%d UA/JS/WebGL/canvas inject\n"
            @"SURFACE Network: FakeWifi=%d getifaddrs/hostname\n"
            @"SURFACE JB hide: HideJailbreak=%d access/stat/lstat + JB dylib\n"
            @"SURFACE matrix OK (Extra)\n",
            [cfg flag:@"FakeScreen" defaultYes:YES] ? 1 : 0,
            [cfg stringForKey:@"main-screen-width"] ?: @"?",
            [cfg stringForKey:@"main-screen-height"] ?: @"?",
            [cfg stringForKey:@"main-screen-scale"] ?: @"?",
            [cfg flag:@"FakeBrowser" defaultYes:YES] ? 1 : 0,
            [cfg flag:@"FakeWifi" defaultYes:YES] ? 1 : 0,
            [cfg flag:@"HideJailbreak" defaultYes:YES] ? 1 : 0];
        NSString *path = @"/var/mobile/Library/iPFaker/ipfaker_surfaces.log";
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (h) {
            [h seekToEndOfFile];
            [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        } else {
            [row writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSString *home = NSHomeDirectory();
        if (home.length) {
            NSString *p2 = [home stringByAppendingPathComponent:@"Documents/ipfaker_surfaces.log"];
            NSFileHandle *h2 = [NSFileHandle fileHandleForWritingAtPath:p2];
            if (h2) {
                [h2 seekToEndOfFile];
                [h2 writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
                [h2 closeFile];
            } else {
                // Merge with MG selftest if present
                NSMutableString *m = [NSMutableString stringWithContentsOfFile:p2 encoding:NSUTF8StringEncoding error:nil]
                    ?: [NSMutableString string];
                [m appendString:row];
                [m writeToFile:p2 atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (__unused NSException *ex) {}
    IPFExTrace(@"IPFInstallExtraHooks done");
}
