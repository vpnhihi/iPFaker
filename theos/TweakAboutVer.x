// iPFakerAboutVer — Preferences software version (Phiên bản phần mềm).
// Tiny, no IPFConfig.m. Complements iPFakerAbout (model# stays there — do not break).
//
// Strategy (layered):
//  1) open/openat: redirect SystemVersion.plist → writable fake plist (synced to config)
//  2) MGCopyAnswer: ProductVersion/BuildVersion plain + obfuscated + host "15.5" wash
//  3) NSDictionary/NSData SystemVersion load APIs
//  4) UIDevice.systemVersion / NSProcessInfo / sysctl / CFCopySystemVersionDictionary
//
// Deploy note: device `ldid -S` + jbctl trustcache (CI ad-hoc alone may not inject).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>
#import <fcntl.h>
#import <stdarg.h>
#import <unistd.h>

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction;
static MSHookMessageEx_t pMSHookMessageEx;
static NSString *gHostPV;

static NSString *const kHashProductVersion = @"qNNddlUK+B/YlooNoymwgA";
static NSString *const kHashBuildVersion = @"mZfUC7qo4pURNhyMHZ62RQ";
static NSString *const kHashProductBuildVersion = @"FbsJngVSVXK87pG0SJtlNg";
static const char *kSysVerPath = "/System/Library/CoreServices/SystemVersion.plist";
static const char *kFakeSysVerPath = "/var/mobile/Library/iPFaker/SystemVersion.fake.plist";

static void IPFVerMark(const char *msg) {
    NSString *body = [NSString stringWithFormat:@"%s\n", msg];
    for (NSString *p in @[
        @"/var/mobile/Library/iPFaker/v3_aboutver_loaded.txt",
        @"/var/mobile/Documents/v3_aboutver_loaded.txt",
    ]) {
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void IPFVerLog(NSString *line) {
    if (!line) return;
    NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), line];
    NSString *p = @"/var/mobile/Library/iPFaker/logs/ipfaker_aboutver.log";
    @try {
        [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
        if (!h) {
            [row writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [h seekToEndOfFile];
            [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (__unused NSException *ex) {}
}

static NSDictionary *IPFVerLoadConfig(void) {
    for (NSString *p in @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ]) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if ([d isKindOfClass:[NSDictionary class]] && d[@"ProductVersion"])
            return d;
    }
    return nil;
}

static BOOL IPFVerEnabled(NSDictionary *cfg) {
    if (!cfg) return NO;
    id en = cfg[@"Enabled"];
    if ([en isKindOfClass:[NSNumber class]] && ![en boolValue]) return NO;
    id f = cfg[@"FakeSysOSVersion"];
    if ([f isKindOfClass:[NSNumber class]] && ![f boolValue]) return NO;
    if ([f isKindOfClass:[NSString class]] &&
        ([[(NSString *)f lowercaseString] isEqualToString:@"0"]
         || [[(NSString *)f lowercaseString] isEqualToString:@"false"]))
        return NO;
    return YES;
}

static NSString *IPFVerPV(NSDictionary *cfg) {
    return cfg ? [cfg[@"ProductVersion"] description] : nil;
}
static NSString *IPFVerBV(NSDictionary *cfg) {
    if (!cfg) return nil;
    id b = cfg[@"BuildVersion"] ?: cfg[@"ProductBuildVersion"];
    return b ? [b description] : nil;
}

/// Write fake SystemVersion.plist used by open() redirect.
static void IPFVerWriteFakeSystemVersion(void) {
    NSDictionary *cfg = IPFVerLoadConfig();
    if (!IPFVerEnabled(cfg)) return;
    NSString *pv = IPFVerPV(cfg);
    NSString *bv = IPFVerBV(cfg);
    if (!pv.length) return;

    // Base from real file via raw NSData (before our open hook is active / after using real open through orig)
    NSData *raw = nil;
    // Prefer pre-copied real template
    raw = [NSData dataWithContentsOfFile:@"/var/mobile/Library/iPFaker/SystemVersion.real.plist"];
    if (!raw.length)
        raw = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:kSysVerPath]];
    NSMutableDictionary *m = nil;
    if (raw.length) {
        id obj = [NSPropertyListSerialization propertyListWithData:raw options:0 format:NULL error:NULL];
        if ([obj isKindOfClass:[NSDictionary class]])
            m = [obj mutableCopy];
    }
    if (!m) m = [NSMutableDictionary dictionary];
    m[@"ProductVersion"] = pv;
    m[@"ProductVersionExtra"] = @"";
    if (bv.length) {
        m[@"ProductBuildVersion"] = bv;
        m[@"BuildVersion"] = bv;
    }
    if (!m[@"ProductName"]) m[@"ProductName"] = @"iPhone OS";
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:m
                                                             format:NSPropertyListXMLFormat_v1_0
                                                            options:0
                                                              error:NULL];
    if (out)
        [out writeToFile:[NSString stringWithUTF8String:kFakeSysVerPath] atomically:YES];
    IPFVerLog([NSString stringWithFormat:@"wrote fake SystemVersion PV=%@ BV=%@", pv, bv ?: @"?"]);
}

static BOOL IPFVerIsSysVerPathC(const char *path) {
    if (!path) return NO;
    return strstr(path, "SystemVersion.plist") != NULL;
}

#pragma mark - open/openat redirect

static int (*orig_open)(const char *path, int flags, ...);
static int stub_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    if (IPFVerIsSysVerPathC(path) && IPFVerEnabled(IPFVerLoadConfig())) {
        // Ensure fake is fresh
        IPFVerWriteFakeSystemVersion();
        path = kFakeSysVerPath;
        IPFVerLog(@"open() redirect SystemVersion.plist");
    }
    if (flags & O_CREAT)
        return orig_open ? orig_open(path, flags, mode) : -1;
    return orig_open ? orig_open(path, flags) : -1;
}

static int (*orig_openat)(int fd, const char *path, int flags, ...);
static int stub_openat(int fd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    if (IPFVerIsSysVerPathC(path) && IPFVerEnabled(IPFVerLoadConfig())) {
        IPFVerWriteFakeSystemVersion();
        path = kFakeSysVerPath;
        fd = AT_FDCWD;
        IPFVerLog(@"openat() redirect SystemVersion.plist");
    }
    if (flags & O_CREAT)
        return orig_openat ? orig_openat(fd, path, flags, mode) : -1;
    return orig_openat ? orig_openat(fd, path, flags) : -1;
}

#pragma mark - MG

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);

static BOOL IPFVerIsVersionKey(NSString *k) {
    if (!k.length) return NO;
    if ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:@"product-version"]
        || [k isEqualToString:kHashProductVersion] || [k.lowercaseString isEqualToString:@"os-version"])
        return YES;
    if ([k isEqualToString:@"BuildVersion"] || [k isEqualToString:@"build-version"]
        || [k isEqualToString:kHashBuildVersion] || [k isEqualToString:@"ProductBuildVersion"]
        || [k isEqualToString:kHashProductBuildVersion])
        return YES;
    return NO;
}

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : @"";
        NSDictionary *cfg = IPFVerLoadConfig();
        BOOL en = IPFVerEnabled(cfg);
        NSString *pv = en ? IPFVerPV(cfg) : nil;
        NSString *bv = en ? IPFVerBV(cfg) : nil;

        if (en && IPFVerIsVersionKey(k)) {
            BOOL isBuild = [k rangeOfString:@"[Bb]uild" options:NSRegularExpressionSearch].location != NSNotFound
                || [k isEqualToString:kHashBuildVersion]
                || [k isEqualToString:kHashProductBuildVersion];
            NSString *out = isBuild ? (bv.length ? bv : pv) : pv;
            if (out.length) {
                IPFVerLog([NSString stringWithFormat:@"MG FAKE %@ => %@", k, out]);
                return CFBridgingRetain(out);
            }
        }

        CFTypeRef real = orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
        if (en && pv.length && real && CFGetTypeID(real) == CFStringGetTypeID()) {
            NSString *rs = (__bridge NSString *)real;
            if ([rs isEqualToString:@"15.5"] || [rs isEqualToString:@"15.5.0"]
                || (gHostPV.length && [rs isEqualToString:gHostPV] && ![rs isEqualToString:pv])) {
                IPFVerLog([NSString stringWithFormat:@"MG WASH %@ %@ => %@", k, rs, pv]);
                CFRelease(real);
                return CFBridgingRetain(pv);
            }
            if (bv.length && [rs isEqualToString:@"19F77"]) {
                IPFVerLog([NSString stringWithFormat:@"MG WASH BV %@ => %@", rs, bv]);
                CFRelease(real);
                return CFBridgingRetain(bv);
            }
        }
        return real;
    }
}

#pragma mark - high-level APIs

static BOOL IPFVerIsSysPath(id pathOrURL) {
    NSString *path = nil;
    if ([pathOrURL isKindOfClass:[NSString class]]) path = pathOrURL;
    else if ([pathOrURL isKindOfClass:[NSURL class]]) path = [(NSURL *)pathOrURL path];
    if (!path.length) return NO;
    return [path rangeOfString:@"SystemVersion.plist" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSDictionary *IPFVerSpoofDict(NSDictionary *real) {
    if (![real isKindOfClass:[NSDictionary class]]) return real;
    NSDictionary *cfg = IPFVerLoadConfig();
    if (!IPFVerEnabled(cfg)) return real;
    NSString *pv = IPFVerPV(cfg);
    NSString *bv = IPFVerBV(cfg);
    if (!pv.length) return real;
    NSMutableDictionary *m = [real mutableCopy];
    m[@"ProductVersion"] = pv;
    m[@"ProductVersionExtra"] = @"";
    if (bv.length) {
        m[@"ProductBuildVersion"] = bv;
        m[@"BuildVersion"] = bv;
    }
    IPFVerLog([NSString stringWithFormat:@"SystemVersion.dict FAKE iOS=%@", pv]);
    return m;
}

static NSData *IPFVerSpoofData(NSData *real) {
    if (![real isKindOfClass:[NSData class]] || !real.length) return real;
    id obj = [NSPropertyListSerialization propertyListWithData:real options:0 format:NULL error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return real;
    NSDictionary *s = IPFVerSpoofDict(obj);
    if (s == obj) return real;
    return [NSPropertyListSerialization dataWithPropertyList:s format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] ?: real;
}

static id (*orig_dictFile)(Class, SEL, NSString *);
static id stub_dictFile(Class c, SEL s, NSString *path) {
    id real = orig_dictFile ? orig_dictFile(c, s, path) : nil;
    return IPFVerIsSysPath(path) ? IPFVerSpoofDict(real) : real;
}
static id (*orig_dataFile)(Class, SEL, NSString *);
static id stub_dataFile(Class c, SEL s, NSString *path) {
    id real = orig_dataFile ? orig_dataFile(c, s, path) : nil;
    return IPFVerIsSysPath(path) ? IPFVerSpoofData(real) : real;
}

static NSString *(*orig_sysVer)(id, SEL);
static NSString *stub_sysVer(id self, SEL _cmd) {
    NSDictionary *cfg = IPFVerLoadConfig();
    if (IPFVerEnabled(cfg)) {
        NSString *pv = IPFVerPV(cfg);
        if (pv.length) {
            IPFVerLog([NSString stringWithFormat:@"UIDevice.systemVersion FAKE %@", pv]);
            return pv;
        }
    }
    return orig_sysVer ? orig_sysVer(self, _cmd) : @"15.0";
}

static NSOperatingSystemVersion (*orig_osv)(id, SEL);
static NSOperatingSystemVersion stub_osv(id self, SEL _cmd) {
    NSOperatingSystemVersion v = {15, 0, 0};
    NSDictionary *cfg = IPFVerLoadConfig();
    if (IPFVerEnabled(cfg)) {
        NSString *pv = IPFVerPV(cfg) ?: @"15.0";
        NSArray *p = [pv componentsSeparatedByString:@"."];
        if (p.count > 0) v.majorVersion = [p[0] integerValue];
        if (p.count > 1) v.minorVersion = [p[1] integerValue];
        if (p.count > 2) v.patchVersion = [p[2] integerValue];
        return v;
    }
    return orig_osv ? orig_osv(self, _cmd) : v;
}

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int stub_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldp && oldlenp && *oldlenp > 0) {
        NSDictionary *cfg = IPFVerLoadConfig();
        if (IPFVerEnabled(cfg)) {
            NSString *fake = nil;
            if (strcmp(name, "kern.osproductversion") == 0) fake = IPFVerPV(cfg);
            else if (strcmp(name, "kern.osversion") == 0) fake = IPFVerBV(cfg);
            if (fake.length) {
                const char *s = fake.UTF8String;
                size_t need = strlen(s) + 1;
                if (*oldlenp >= need) {
                    memcpy(oldp, s, need);
                    *oldlenp = need;
                    IPFVerLog([NSString stringWithFormat:@"sysctl FAKE %s => %@", name, fake]);
                    return 0;
                }
            }
        }
    }
    return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
}

static CFDictionaryRef (*orig_CFCopySysVer)(void);
static CFDictionaryRef stub_CFCopySysVer(void) {
    CFDictionaryRef real = orig_CFCopySysVer ? orig_CFCopySysVer() : NULL;
    if (!real) return real;
    NSDictionary *ns = CFBridgingRelease(real);
    return CFBridgingRetain(IPFVerSpoofDict(ns));
}

static void *IPFFindMG(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt", RTLD_NOW);
    if (h) p = dlsym(h, name);
    return p;
}

static void IPFVerResolve(void) {
    if (pMSHookFunction) return;
    const char *libs[] = {
        "/var/jb/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
    };
    for (size_t i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) {
        void *h = dlopen(libs[i], RTLD_NOW);
        if (!h) continue;
        pMSHookFunction = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        pMSHookMessageEx = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
        if (pMSHookFunction) return;
    }
    pMSHookFunction = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    pMSHookMessageEx = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (![bid isEqualToString:@"com.apple.Preferences"]) {
            IPFVerMark("CTOR_SKIP");
            return;
        }
        IPFVerMark("CTOR_ENTER");
        IPFVerResolve();

        // Real host PV from pre-copied real template or disk via NSData (before open hook)
        if (!gHostPV) {
            NSData *raw = [NSData dataWithContentsOfFile:@"/var/mobile/Library/iPFaker/SystemVersion.real.plist"];
            if (!raw.length)
                raw = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:kSysVerPath]];
            NSString *hp = nil;
            if (raw.length) {
                id obj = [NSPropertyListSerialization propertyListWithData:raw options:0 format:NULL error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]])
                    hp = [obj[@"ProductVersion"] description];
            }
            gHostPV = hp.length ? [hp copy] : @"15.5";
            IPFVerLog([NSString stringWithFormat:@"hostPV=%@", gHostPV]);
        }

        IPFVerWriteFakeSystemVersion();

        if (pMSHookFunction) {
            void *op = dlsym(RTLD_DEFAULT, "open");
            if (op) pMSHookFunction(op, (void *)stub_open, (void **)&orig_open);
            void *oa = dlsym(RTLD_DEFAULT, "openat");
            if (oa) pMSHookFunction(oa, (void *)stub_openat, (void **)&orig_openat);

            void *mg = IPFFindMG("MGCopyAnswer");
            if (mg) pMSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);

            void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
            if (sys) pMSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);

            void *cf = dlsym(RTLD_DEFAULT, "CFCopySystemVersionDictionary");
            if (!cf) {
                void *h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
                if (h) cf = dlsym(h, "CFCopySystemVersionDictionary");
            }
            if (cf) pMSHookFunction(cf, (void *)stub_CFCopySysVer, (void **)&orig_CFCopySysVer);
            IPFVerLog(@"hooks C open/MG/sysctl installed");
        }

        if (pMSHookMessageEx) {
            Class dm = objc_getMetaClass("NSDictionary");
            if (dm && class_getClassMethod(dm, @selector(dictionaryWithContentsOfFile:)))
                pMSHookMessageEx(dm, @selector(dictionaryWithContentsOfFile:),
                                 (IMP)stub_dictFile, (IMP *)&orig_dictFile);
            Class ndm = objc_getMetaClass("NSData");
            if (ndm && class_getClassMethod(ndm, @selector(dataWithContentsOfFile:)))
                pMSHookMessageEx(ndm, @selector(dataWithContentsOfFile:),
                                 (IMP)stub_dataFile, (IMP *)&orig_dataFile);
            Class uid = objc_getClass("UIDevice");
            if (uid && class_getInstanceMethod(uid, @selector(systemVersion)))
                pMSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_sysVer, (IMP *)&orig_sysVer);
            Class nspi = objc_getClass("NSProcessInfo");
            if (nspi && class_getInstanceMethod(nspi, @selector(operatingSystemVersion)))
                pMSHookMessageEx(nspi, @selector(operatingSystemVersion),
                                 (IMP)stub_osv, (IMP *)&orig_osv);
        }

        NSDictionary *cfg = IPFVerLoadConfig();
        IPFVerLog([NSString stringWithFormat:@"ready PV=%@ BV=%@ hostPV=%@",
                   IPFVerPV(cfg) ?: @"?", IPFVerBV(cfg) ?: @"?", gHostPV ?: @"?"]);
        IPFVerMark("CTOR_OK");
    }
}
