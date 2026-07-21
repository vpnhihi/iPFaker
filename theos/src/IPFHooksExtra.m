// Extra spoof surface for Zalo — gated by config Fake* flags:
//  FakeScreen / FakeRealScreen, FakeHardware (disk), HideJailbreak,
//  FakeBrowser (UA), FakeLocale (BCP-47 + IANA TZ), FakeDateTime,
//  FakeLocation (WGS84), FakeSensor, FakeWebRTC / DisableWebRTC,
//  FakeWifi: getifaddrs MAC; FakeDevice/FakeNetwork: gethostname + NSProcessInfo.hostName.
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
// Lab_Environment_Hardening.md + HIOS denylist. Fail = ENOENT / NO / NULL.
// MUST allow iPFaker config so spoof profile still loads inside Zalo.

#import <stdio.h>

static BOOL IPFIsAllowlistedPath(const char *path) {
    if (!path) return NO;
    if (strstr(path, "/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/private/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/var/mobile/Library/iPFaker")) return YES;
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

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *stub_fopen(const char *path, const char *mode) {
    if (IPFIsJBPath(path)) { IPFJBHideLogOnce("fopen", path); errno = ENOENT; return NULL; }
    return orig_fopen ? orig_fopen(path, mode) : NULL;
}

static char *(*orig_getenv)(const char *);
static char *stub_getenv(const char *name) {
    if (!name) return orig_getenv ? orig_getenv(name) : NULL;
    if (![[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES])
        return orig_getenv ? orig_getenv(name) : NULL;
    static const char *kEnv[] = {
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "DYLD_PRINT_TO_FILE",
        "_MSSafeMode",
        "SSLKEYLOGFILE",
        NULL
    };
    for (int i = 0; kEnv[i]; i++) {
        if (strcmp(name, kEnv[i]) == 0) {
            IPFJBHideLogOnce("getenv", name);
            return NULL;
        }
    }
    if (strncmp(name, "FRIDA", 5) == 0) {
        IPFJBHideLogOnce("getenv", name);
        return NULL;
    }
    return orig_getenv ? orig_getenv(name) : NULL;
}

static BOOL (*orig_fileExists)(id, SEL, NSString *);
static BOOL stub_fileExists(id self, SEL _cmd, NSString *path) {
    if (path.length && IPFIsJBPath(path.UTF8String)) {
        IPFJBHideLogOnce("fileExists", path.UTF8String);
        return NO;
    }
    return orig_fileExists ? orig_fileExists(self, _cmd, path) : NO;
}

static BOOL (*orig_fileExistsIsDir)(id, SEL, NSString *, BOOL *);
static BOOL stub_fileExistsIsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (path.length && IPFIsJBPath(path.UTF8String)) {
        IPFJBHideLogOnce("fileExists:isDir", path.UTF8String);
        if (isDir) *isDir = NO;
        return NO;
    }
    return orig_fileExistsIsDir ? orig_fileExistsIsDir(self, _cmd, path, isDir) : NO;
}

#pragma mark - canOpenURL (JB schemes + WebRTC disable)

static BOOL (*orig_canOpen)(id, SEL, NSURL *);
static BOOL stub_canOpen(id self, SEL _cmd, NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString ?: @"";
    if ([[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) {
        if ([s hasPrefix:@"cydia://"] || [s hasPrefix:@"sileo://"] || [s hasPrefix:@"zbra://"]
            || [s hasPrefix:@"filza://"] || [s hasPrefix:@"undecimus://"] || [s hasPrefix:@"activator://"]
            || [s hasPrefix:@"dopamine://"] || [s hasPrefix:@"ellekit://"]
            || [s hasPrefix:@"ssh://"] || [s hasPrefix:@"newterm://"]
            || [s hasPrefix:@"santander://"]) {
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

#pragma mark - Locale (BCP 47 / ISO 639-1 / ISO 3166-1) + IANA TZ

static NSArray *(*orig_preferredLanguages)(id, SEL);
static NSArray *stub_preferredLanguages(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES])
        return orig_preferredLanguages ? orig_preferredLanguages(self, _cmd) : nil;
    // AppleLanguages / BCP 47 — e.g. vi-VN, en-US (CLDR / Unicode Locale ID)
    NSString *lang = [[IPFConfig shared] stringForKey:@"PreferredLanguage"]
        ?: [[IPFConfig shared] stringForKey:@"LocaleIdentifier"]
        ?: [[IPFConfig shared] stringForKey:@"AppleLocale"];
    if (!lang.length) lang = @"vi-VN";
    // Apple often stores as vi_VN in AppleLocale; preferredLanguages wants BCP47 hyphen
    lang = [lang stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return @[ lang ];
}

static NSLocale *(*orig_currentLocale)(id, SEL);
static NSLocale *stub_currentLocale(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES])
        return orig_currentLocale ? orig_currentLocale(self, _cmd) : [NSLocale currentLocale];
    NSString *ident = [[IPFConfig shared] stringForKey:@"LocaleIdentifier"]
        ?: [[IPFConfig shared] stringForKey:@"AppleLocale"]
        ?: @"vi_VN";
    // NSLocale wants underscore form (Apple convention for locale identifiers)
    ident = [ident stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSLocale *loc = [[NSLocale alloc] initWithLocaleIdentifier:ident];
    return loc ?: (orig_currentLocale ? orig_currentLocale(self, _cmd) : nil);
}

static NSTimeZone *(*orig_systemTZ)(id, SEL);
static NSTimeZone *(*orig_defaultTZ)(id, SEL);
static NSTimeZone *(*orig_localTZ)(id, SEL);

static NSTimeZone *IPFTimeZone(void) {
    // IANA Time Zone Database — Asia/Ho_Chi_Minh (VN, no DST)
    NSString *name = [[IPFConfig shared] stringForKey:@"TimeZoneName"] ?: @"Asia/Ho_Chi_Minh";
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:name];
    if (!tz) tz = [NSTimeZone timeZoneWithName:@"Asia/Bangkok"]; // same UTC+7 fallback
    return tz ?: [NSTimeZone systemTimeZone];
}

static NSTimeZone *stub_systemTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_systemTZ ? orig_systemTZ(self, _cmd) : [NSTimeZone systemTimeZone];
    return IPFTimeZone();
}
static NSTimeZone *stub_defaultTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_defaultTZ ? orig_defaultTZ(self, _cmd) : [NSTimeZone defaultTimeZone];
    return IPFTimeZone();
}
static NSTimeZone *stub_localTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_localTZ ? orig_localTZ(self, _cmd) : [NSTimeZone localTimeZone];
    return IPFTimeZone();
}

#pragma mark - Date offset (FakeDateTime) — optional, default off (TLS safety)

static NSDate *(*orig_date)(id, SEL);
static NSDate *stub_date(id self, SEL _cmd) {
    NSDate *real = orig_date ? orig_date(self, _cmd) : [NSDate date];
    if (![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO]) return real;
    double off = [[IPFConfig shared] doubleForKey:@"TimeOffsetSeconds" fallback:0];
    if (fabs(off) < 0.5) return real; // no offset → timezone-only spoof
    return [real dateByAddingTimeInterval:off];
}

#pragma mark - Location (WGS84)

static id (*orig_location)(id, SEL);
static id stub_location(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocation" defaultYes:NO])
        return orig_location ? orig_location(self, _cmd) : nil;
    @try {
        Class CLLoc = objc_getClass("CLLocation");
        if (!CLLoc) return orig_location ? orig_location(self, _cmd) : nil;
        // WGS84 decimal degrees (EPSG:4326) — default: Ho Chi Minh City
        // Source: approximate city center; apps expect CLLocation degrees.
        double lat = [[IPFConfig shared] doubleForKey:@"Latitude" fallback:10.8231];
        double lon = [[IPFConfig shared] doubleForKey:@"Longitude" fallback:106.6297];
        double acc = [[IPFConfig shared] doubleForKey:@"LocationAccuracy" fallback:10.0];
        SEL simple = NSSelectorFromString(@"initWithLatitude:longitude:");
        id loc = nil;
        if ([CLLoc instancesRespondToSelector:simple]) {
            id obj = [CLLoc alloc];
            loc = ((id (*)(id, SEL, double, double))objc_msgSend)(obj, simple, lat, lon);
        }
        if (loc) {
            IPFExTrace([NSString stringWithFormat:@"CLLocation FAKE lat=%.6f lon=%.6f acc=%.1f",
                        lat, lon, acc]);
            return loc;
        }
    } @catch (__unused NSException *ex) {}
    return orig_location ? orig_location(self, _cmd) : nil;
}

static void (*orig_startUpdating)(id, SEL);
static void stub_startUpdating(id self, SEL _cmd) {
    if (orig_startUpdating) orig_startUpdating(self, _cmd);
    if (![[IPFConfig shared] flag:@"FakeLocation" defaultYes:NO]) return;
    // Push fake location to delegate shortly after start
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            id del = nil;
            if ([self respondsToSelector:@selector(delegate)])
                del = [self performSelector:@selector(delegate)];
            id loc = stub_location(self, @selector(location));
            if (del && loc) {
                SEL s = NSSelectorFromString(@"locationManager:didUpdateLocations:");
                if ([del respondsToSelector:s]) {
                    NSMethodSignature *sig = [del methodSignatureForSelector:s];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setSelector:s];
                    [inv setTarget:del];
                    id mgr = self;
                    NSArray *arr = @[ loc ];
                    [inv setArgument:&mgr atIndex:2];
                    [inv setArgument:&arr atIndex:3];
                    [inv invoke];
                }
            }
        } @catch (__unused NSException *ex) {}
    });
}

#pragma mark - Sensors (CMAccelerometerData-like identity gravity)

static id (*orig_accelerometerData)(id, SEL);
static id stub_accelerometerData(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeSensor" defaultYes:NO])
        return orig_accelerometerData ? orig_accelerometerData(self, _cmd) : nil;
    // When spoofing sensors: prefer "device at rest, face up" if we can't inject CMAcceleration easily.
    // Returning real data when motion is needed is safer; for static fingerprinting, zero motion is fine.
    // Best-effort: return original if present else nil (avoid crash fabricating private CM structs).
    id real = orig_accelerometerData ? orig_accelerometerData(self, _cmd) : nil;
    return real; // structure layout is private — fingerprint often checks availability; gravity via gravity property
}

static id (*orig_gravity)(id, SEL);
// CMDeviceMotion.gravity — CMAcceleration {x,y,z} returned by value — hard to stub with MSHookMessageEx
// Hook isEnabled flags instead.

static BOOL (*orig_isAccelAvailable)(id, SEL);
static BOOL stub_isAccelAvailable(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeSensor" defaultYes:NO]) {
        // Report available (normal iPhone)
        return YES;
    }
    return orig_isAccelAvailable ? orig_isAccelAvailable(self, _cmd) : YES;
}

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
        int patched = 0;
        for (struct ifaddrs *ifa = *ifap; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr) continue;
            if (ifa->ifa_addr->sa_family != AF_LINK) continue;
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            // sdl_alen == 6 → Ethernet / Wi‑Fi link-layer address
            if (sdl->sdl_alen != 6) continue;
            // LLADDR points past interface name in sdl_data (BSD if_dl.h)
            unsigned char *ll = (unsigned char *)LLADDR(sdl);
            if (!ll) continue;
            memcpy(ll, mac, 6);
            patched++;
        }
        if (patched > 0)
            IPFExTrace([NSString stringWithFormat:@"getifaddrs FAKE MAC %@ on %d AF_LINK", wifi, patched]);
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

static NSString *IPFWebUA(void) {
    NSString *ua = [[IPFConfig shared] stringForKey:@"UserAgent"]
        ?: [[IPFConfig shared] stringForKey:@"HTTPUserAgent"];
    if (ua.length) return ua;
    // Fallback from ProductVersion — Safari Mobile form (WebView_Surface.md)
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

static NSString *IPFJSEscape(NSString *s) {
    if (!s) return @"";
    NSString *o = s;
    o = [o stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    o = [o stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    o = [o stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    o = [o stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return o;
}

/// JS spoof: navigator.userAgent + screen metrics + devicePixelRatio (sync catalog)
static NSString *IPFWebSpoofJS(void) {
    NSString *ua = IPFJSEscape(IPFWebUA());
    // Logical CSS pixels (points) — same as UIScreen.bounds
    double lw = [[IPFConfig shared] doubleForKey:@"LogicalScreenWidth" fallback:0];
    double lh = [[IPFConfig shared] doubleForKey:@"LogicalScreenHeight" fallback:0];
    double sc = [[IPFConfig shared] doubleForKey:@"main-screen-scale" fallback:0];
    double nw = [[IPFConfig shared] doubleForKey:@"main-screen-width" fallback:0];
    double nh = [[IPFConfig shared] doubleForKey:@"main-screen-height" fallback:0];
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
    // devicePixelRatio ≡ scale (MDN / CSS pixels vs device pixels)
    int sw = (int)llround(lw);
    int sh = (int)llround(lh);
    // availHeight slightly less than height (status bar lab ~ never 0)
    int availH = sh > 44 ? sh - 0 : sh;
    return [NSString stringWithFormat:
        @"(function(){try{"
        @"var ua='%@';"
        @"var sw=%d,sh=%d,dpr=%g;"
        @"var d=function(o,k,v){try{Object.defineProperty(o,k,{get:function(){return v},configurable:true});}catch(e){}};"
        @"try{d(Navigator.prototype,'userAgent',ua);}catch(e){}"
        @"try{d(navigator,'userAgent',ua);}catch(e){}"
        @"try{d(Navigator.prototype,'appVersion',ua.replace(/^Mozilla\\//,''));}catch(e){}"
        @"try{d(navigator,'platform','iPhone');}catch(e){}"
        @"try{d(navigator,'vendor','Apple Computer, Inc.');}catch(e){}"
        @"d(screen,'width',sw);d(screen,'height',sh);"
        @"d(screen,'availWidth',sw);d(screen,'availHeight',%d);"
        @"d(screen,'colorDepth',24);d(screen,'pixelDepth',24);"
        @"d(window,'devicePixelRatio',dpr);"
        @"d(window,'innerWidth',sw);d(window,'innerHeight',sh);"
        @"d(window,'outerWidth',sw);d(window,'outerHeight',sh);"
        @"}catch(e){}})();",
        ua, sw, sh, sc, availH];
}

// Runtime WebKit (no hard link) — HIOS-style UA + WKUserScript for screen JS
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
            IPFExTrace([NSString stringWithFormat:
                @"WKWebView UA+JS injected sw=%.0f dpr=%.1f", lw, sc]);
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

#pragma mark - WebRTC local IP rewrite (FakeWebRTC)

static NSString *(*orig_description_rtc)(id, SEL);
// Hook SDP-ish strings is fragile. Instead rewrite common local-IP patterns in NSString if FakeWebRTC.
// Safer: intercept RTCIceCandidate candidate property if class exists.

static NSString *(*orig_iceCandidate)(id, SEL);
static NSString *stub_iceCandidate(id self, SEL _cmd) {
    NSString *real = orig_iceCandidate ? orig_iceCandidate(self, _cmd) : nil;
    if (!real) return real;
    if ([[IPFConfig shared] flag:@"DisableWebRTC" defaultYes:NO]) {
        IPFExTrace(@"WebRTC candidate blocked (DisableWebRTC)");
        return @"";
    }
    if (![[IPFConfig shared] flag:@"FakeWebRTC" defaultYes:NO]) return real;
    // Replace host candidates' IPv4 with RFC1918 lab IP (not a public leak)
    NSString *fakeIP = [[IPFConfig shared] stringForKey:@"WebRTCLocalIP"] ?: @"10.0.0.2";
    // candidate:... <ip> ...
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"
                             options:0 error:&err];
    if (!re) return real;
    NSString *out = [re stringByReplacingMatchesInString:real
                                                 options:0
                                                   range:NSMakeRange(0, real.length)
                                            withTemplate:fakeIP];
    if (![out isEqualToString:real])
        IPFExTrace([NSString stringWithFormat:@"WebRTC candidate IP → %@", fakeIP]);
    return out;
}

#pragma mark - Install

void IPFInstallExtraHooks(void) {
    IPFResolve();
    IPFExTrace(@"IPFInstallExtraHooks begin");

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
            if (class_getInstanceMethod(fm, @selector(fileExistsAtPath:))) {
                pMSHookMessageEx(fm, @selector(fileExistsAtPath:),
                                 (IMP)stub_fileExists, (IMP *)&orig_fileExists);
            }
            if (class_getInstanceMethod(fm, @selector(fileExistsAtPath:isDirectory:))) {
                pMSHookMessageEx(fm, @selector(fileExistsAtPath:isDirectory:),
                                 (IMP)stub_fileExistsIsDir, (IMP *)&orig_fileExistsIsDir);
            }
            IPFExTrace(@"NSFileManager fileExists JB hide OK");
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

        // Locale
        Class nsl = object_getClass(objc_getClass("NSLocale")); // metaclass for class methods
        if (nsl) {
            if (class_getClassMethod(objc_getClass("NSLocale"), @selector(preferredLanguages)))
                pMSHookMessageEx(nsl, @selector(preferredLanguages), (IMP)stub_preferredLanguages, (IMP *)&orig_preferredLanguages);
            if (class_getClassMethod(objc_getClass("NSLocale"), @selector(currentLocale)))
                pMSHookMessageEx(nsl, @selector(currentLocale), (IMP)stub_currentLocale, (IMP *)&orig_currentLocale);
            if (class_getClassMethod(objc_getClass("NSLocale"), @selector(autoupdatingCurrentLocale)))
                pMSHookMessageEx(nsl, @selector(autoupdatingCurrentLocale), (IMP)stub_currentLocale, (IMP *)&orig_currentLocale);
            IPFExTrace(@"NSLocale hooks OK");
        }

        Class ntz = object_getClass(objc_getClass("NSTimeZone"));
        if (ntz) {
            if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(systemTimeZone)))
                pMSHookMessageEx(ntz, @selector(systemTimeZone), (IMP)stub_systemTZ, (IMP *)&orig_systemTZ);
            if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(defaultTimeZone)))
                pMSHookMessageEx(ntz, @selector(defaultTimeZone), (IMP)stub_defaultTZ, (IMP *)&orig_defaultTZ);
            if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(localTimeZone)))
                pMSHookMessageEx(ntz, @selector(localTimeZone), (IMP)stub_localTZ, (IMP *)&orig_localTZ);
            IPFExTrace(@"NSTimeZone hooks OK");
        }

        Class nd = object_getClass(objc_getClass("NSDate"));
        if (nd && class_getClassMethod(objc_getClass("NSDate"), @selector(date))) {
            pMSHookMessageEx(nd, @selector(date), (IMP)stub_date, (IMP *)&orig_date);
            IPFExTrace(@"NSDate.date hook OK");
        }

        // CoreLocation
        Class clm = objc_getClass("CLLocationManager");
        if (clm) {
            if (class_getInstanceMethod(clm, @selector(location)))
                pMSHookMessageEx(clm, @selector(location), (IMP)stub_location, (IMP *)&orig_location);
            if (class_getInstanceMethod(clm, @selector(startUpdatingLocation)))
                pMSHookMessageEx(clm, @selector(startUpdatingLocation), (IMP)stub_startUpdating, (IMP *)&orig_startUpdating);
            IPFExTrace(@"CLLocationManager hooks OK");
        }

        // CoreMotion availability
        Class cmm = objc_getClass("CMMotionManager");
        if (cmm) {
            if (class_getInstanceMethod(cmm, @selector(isAccelerometerAvailable)))
                pMSHookMessageEx(cmm, @selector(isAccelerometerAvailable), (IMP)stub_isAccelAvailable, (IMP *)&orig_isAccelAvailable);
            if (class_getInstanceMethod(cmm, @selector(accelerometerData)))
                pMSHookMessageEx(cmm, @selector(accelerometerData), (IMP)stub_accelerometerData, (IMP *)&orig_accelerometerData);
            IPFExTrace(@"CMMotionManager hooks OK");
        }

        // WebRTC ICE candidate (WebRTC.framework / GoogleWebRTC if linked)
        const char *rtcClasses[] = {
            "RTCIceCandidate", "RTC_OBJC_TYPE(RTCIceCandidate)", NULL
        };
        for (int i = 0; rtcClasses[i]; i++) {
            Class rc = objc_getClass(rtcClasses[i]);
            if (!rc) continue;
            if (class_getInstanceMethod(rc, @selector(sdp)))
                pMSHookMessageEx(rc, @selector(sdp), (IMP)stub_iceCandidate, (IMP *)&orig_iceCandidate);
            SEL cand = NSSelectorFromString(@"candidate"); // some versions
            if (class_getInstanceMethod(rc, cand))
                pMSHookMessageEx(rc, cand, (IMP)stub_iceCandidate, (IMP *)&orig_iceCandidate);
            IPFExTrace([NSString stringWithFormat:@"RTCIceCandidate hook on %s", rtcClasses[i]]);
            break;
        }
    }

    if (pMSHookMessageEx) {
        // NSProcessInfo.hostName — same value as gethostname / kern.hostname
        Class nspi = objc_getClass("NSProcessInfo");
        if (nspi && class_getInstanceMethod(nspi, @selector(hostName))) {
            pMSHookMessageEx(nspi, @selector(hostName), (IMP)stub_hostName, (IMP *)&orig_hostName);
            IPFExTrace(@"NSProcessInfo.hostName OK");
        }
    }

    if (pMSHookFunction) {
        void *a = dlsym(RTLD_DEFAULT, "access");
        if (a) pMSHookFunction(a, (void *)stub_access, (void **)&orig_access);
        void *st = dlsym(RTLD_DEFAULT, "stat");
        if (st) pMSHookFunction(st, (void *)stub_stat, (void **)&orig_stat);
        void *ls = dlsym(RTLD_DEFAULT, "lstat");
        if (ls) pMSHookFunction(ls, (void *)stub_lstat, (void **)&orig_lstat);
        void *fo = dlsym(RTLD_DEFAULT, "fopen");
        if (fo) pMSHookFunction(fo, (void *)stub_fopen, (void **)&orig_fopen);
        void *ge = dlsym(RTLD_DEFAULT, "getenv");
        if (ge) pMSHookFunction(ge, (void *)stub_getenv, (void **)&orig_getenv);
        IPFExTrace(@"access/stat/lstat/fopen/getenv JB hide OK");

        // libc network identity (HIOS-class surface)
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
    }

    IPFExTrace(@"IPFInstallExtraHooks done");
}
