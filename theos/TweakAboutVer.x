// iPFakerAboutVer — Preferences-only software version spoof (Phiên bản phần mềm).
// Stays tiny (no IPFConfig.m). Complements iPFakerAbout (model# / marketing / MG surface).
//
// Root cause: Settings About often reads ProductVersion via obfuscated MG keys or
// host string "15.5", while plain MG "ProductVersion" is already faked by About.
// This dylib:
//   1) Hooks MGCopyAnswer for ProductVersion/BuildVersion (plain + known hashes)
//   2) Washes any MG string equal to host ProductVersion → spoof PV
//   3) Hooks SystemVersion.plist load paths + UIDevice/NSProcessInfo
//   4) CFCopySystemVersionDictionary when present

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction;
static MSHookMessageEx_t pMSHookMessageEx;
static NSString *gHostPV; // captured once from real MG

// Obfuscated MG keys (MD5("MGCopyAnswer"+name) base64 without ==)
static NSString *const kHashProductVersion = @"qNNddlUK+B/YlooNoymwgA";
static NSString *const kHashBuildVersion = @"mZfUC7qo4pURNhyMHZ62RQ";
static NSString *const kHashProductBuildVersion = @"FbsJngVSVXK87pG0SJtlNg";

static void IPFVerMark(const char *msg) {
    NSString *body = [NSString stringWithFormat:@"%s\n", msg];
    for (NSString *p in @[
        @"/var/mobile/Library/iPFaker/v3_aboutver_loaded.txt",
        @"/var/mobile/Documents/v3_aboutver_loaded.txt",
        @"/var/jb/tmp/v3_aboutver_loaded.txt",
    ]) {
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void IPFVerLog(NSString *line) {
    if (!line) return;
    NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), line];
    for (NSString *p in @[
        @"/var/mobile/Library/iPFaker/logs/ipfaker_aboutver.log",
        @"/var/mobile/Documents/ipfaker_aboutver.log",
    ]) {
        @try {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
            if (!h) {
                [[p stringByDeletingLastPathComponent] length]; // silence
                [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent]
                                         withIntermediateDirectories:YES attributes:nil error:nil];
                [row writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
            } else {
                [h seekToEndOfFile];
                [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
                [h closeFile];
            }
        } @catch (__unused NSException *ex) {}
    }
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
    IPFVerLog([NSString stringWithFormat:@"SystemVersion.dict FAKE iOS=%@ build=%@", pv, bv ?: @"?"]);
    return m;
}

static NSData *IPFVerSpoofData(NSData *real) {
    if (![real isKindOfClass:[NSData class]] || !real.length) return real;
    id obj = [NSPropertyListSerialization propertyListWithData:real options:0 format:NULL error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return real;
    NSDictionary *s = IPFVerSpoofDict(obj);
    if (s == obj) return real;
    return [NSPropertyListSerialization dataWithPropertyList:s
                                                      format:NSPropertyListXMLFormat_v1_0
                                                     options:0
                                                       error:NULL] ?: real;
}

#pragma mark - MGCopyAnswer (version keys + host wash)

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);

static BOOL IPFVerIsVersionKey(NSString *k) {
    if (!k.length) return NO;
    if ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:@"product-version"]
        || [k isEqualToString:kHashProductVersion])
        return YES;
    if ([k isEqualToString:@"BuildVersion"] || [k isEqualToString:@"build-version"]
        || [k isEqualToString:kHashBuildVersion])
        return YES;
    if ([k isEqualToString:@"ProductBuildVersion"] || [k isEqualToString:kHashProductBuildVersion])
        return YES;
    // os-version style
    if ([k.lowercaseString isEqualToString:@"os-version"])
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
            BOOL isBuild = [k isEqualToString:@"BuildVersion"] || [k isEqualToString:@"build-version"]
                || [k isEqualToString:kHashBuildVersion]
                || [k isEqualToString:@"ProductBuildVersion"]
                || [k isEqualToString:kHashProductBuildVersion];
            NSString *out = isBuild ? (bv.length ? bv : pv) : pv;
            if (out.length) {
                IPFVerLog([NSString stringWithFormat:@"MG FAKE %@ => %@", k, out]);
                return CFBridgingRetain(out);
            }
        }

        CFTypeRef real = orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;

        // Capture host PV once (from real path, plain key preferred)
        if (!gHostPV && real && CFGetTypeID(real) == CFStringGetTypeID()
            && ([k isEqualToString:@"ProductVersion"] || [k isEqualToString:kHashProductVersion])) {
            gHostPV = [[NSString alloc] initWithString:(__bridge NSString *)real];
        }

        // Host-value wash: ANY MG string that equals host OS version → spoof PV
        // Covers unknown/hashed keys Settings uses for "Phiên bản phần mềm"
        if (en && pv.length && real && CFGetTypeID(real) == CFStringGetTypeID()) {
            NSString *rs = (__bridge NSString *)real;
            BOOL isHost = NO;
            if (gHostPV.length && [rs isEqualToString:gHostPV]) isHost = YES;
            // Lab host is 15.5 — also match common host tokens
            if ([rs isEqualToString:@"15.5"] || [rs isEqualToString:@"15.5.0"]) isHost = YES;
            if (isHost && ![rs isEqualToString:pv]) {
                IPFVerLog([NSString stringWithFormat:@"MG WASH hostPV key=%@ %@ => %@", k, rs, pv]);
                CFRelease(real);
                return CFBridgingRetain(pv);
            }
            // Build host wash
            if (bv.length && ([rs isEqualToString:@"19F77"] /* host 15.5 build */)) {
                if ([k rangeOfString:@"[Bb]uild" options:NSRegularExpressionSearch].location != NSNotFound
                    || [k isEqualToString:kHashBuildVersion]
                    || [k isEqualToString:kHashProductBuildVersion]
                    || k.length >= 16) {
                    IPFVerLog([NSString stringWithFormat:@"MG WASH hostBV key=%@ %@ => %@", k, rs, bv]);
                    CFRelease(real);
                    return CFBridgingRetain(bv);
                }
            }
        }
        return real;
    }
}

#pragma mark - SystemVersion file paths

static id (*orig_dictFile)(Class, SEL, NSString *);
static id stub_dictFile(Class c, SEL s, NSString *path) {
    id real = orig_dictFile ? orig_dictFile(c, s, path) : nil;
    return IPFVerIsSysPath(path) ? IPFVerSpoofDict(real) : real;
}

static id (*orig_dictURL)(Class, SEL, NSURL *);
static id stub_dictURL(Class c, SEL s, NSURL *url) {
    id real = orig_dictURL ? orig_dictURL(c, s, url) : nil;
    return IPFVerIsSysPath(url) ? IPFVerSpoofDict(real) : real;
}

static id (*orig_dataFile)(Class, SEL, NSString *);
static id stub_dataFile(Class c, SEL s, NSString *path) {
    id real = orig_dataFile ? orig_dataFile(c, s, path) : nil;
    return IPFVerIsSysPath(path) ? IPFVerSpoofData(real) : real;
}

static id (*orig_dataURL)(Class, SEL, NSURL *);
static id stub_dataURL(Class c, SEL s, NSURL *url) {
    id real = orig_dataURL ? orig_dataURL(c, s, url) : nil;
    return IPFVerIsSysPath(url) ? IPFVerSpoofData(real) : real;
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
        IPFVerLog([NSString stringWithFormat:@"NSProcessInfo.operatingSystemVersion FAKE %ld.%ld.%ld",
                   (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion]);
        return v;
    }
    return orig_osv ? orig_osv(self, _cmd) : v;
}

static NSString *(*orig_osvString)(id, SEL);
static NSString *stub_osvString(id self, SEL _cmd) {
    NSDictionary *cfg = IPFVerLoadConfig();
    if (IPFVerEnabled(cfg)) {
        NSString *pv = IPFVerPV(cfg) ?: @"15.0";
        NSString *bv = IPFVerBV(cfg) ?: @"";
        NSString *out = bv.length
            ? [NSString stringWithFormat:@"Version %@ (Build %@)", pv, bv]
            : [NSString stringWithFormat:@"Version %@", pv];
        IPFVerLog([NSString stringWithFormat:@"NSProcessInfo.OSVersionString FAKE %@", out]);
        return out;
    }
    return orig_osvString ? orig_osvString(self, _cmd) : @"Version 15.0";
}

static CFDictionaryRef (*orig_CFCopySysVer)(void);
static CFDictionaryRef stub_CFCopySysVer(void) {
    CFDictionaryRef real = orig_CFCopySysVer ? orig_CFCopySysVer() : NULL;
    if (!real) return real;
    NSDictionary *ns = CFBridgingRelease(real);
    return CFBridgingRetain(IPFVerSpoofDict(ns));
}

// sysctl kern.osproductversion / kern.osversion
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int stub_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldp && oldlenp && *oldlenp > 0) {
        NSDictionary *cfg = IPFVerLoadConfig();
        if (IPFVerEnabled(cfg)) {
            NSString *fake = nil;
            if (strcmp(name, "kern.osproductversion") == 0)
                fake = IPFVerPV(cfg);
            else if (strcmp(name, "kern.osversion") == 0)
                fake = IPFVerBV(cfg);
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

// UI last resort: Preferences About cell may set detail text "15.5" without re-querying MG.
// Only replace exact host version tokens; reentrancy-guarded.
static BOOL gInUIText;
static NSString *IPFVerWashHostText(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length) return text;
    NSDictionary *cfg = IPFVerLoadConfig();
    if (!IPFVerEnabled(cfg)) return text;
    NSString *pv = IPFVerPV(cfg);
    if (!pv.length || [pv isEqualToString:text]) return text;
    // Exact host tokens only (never broad replace)
    if ([text isEqualToString:@"15.5"] || [text isEqualToString:@"15.5.0"]
        || (gHostPV.length && [text isEqualToString:gHostPV])) {
        IPFVerLog([NSString stringWithFormat:@"UI WASH %@ => %@", text, pv]);
        return pv;
    }
    return text;
}

static void (*orig_labelSetText)(id, SEL, NSString *);
static void stub_labelSetText(id self, SEL _cmd, NSString *text) {
    if (!gInUIText) {
        gInUIText = YES;
        text = IPFVerWashHostText(text);
        gInUIText = NO;
    }
    if (orig_labelSetText) orig_labelSetText(self, _cmd, text);
}

static void (*orig_cellSetValue)(id, SEL, id);
static void stub_cellSetValue(id self, SEL _cmd, id value) {
    if ([value isKindOfClass:[NSString class]] && !gInUIText) {
        gInUIText = YES;
        value = IPFVerWashHostText((NSString *)value);
        gInUIText = NO;
    }
    if (orig_cellSetValue) orig_cellSetValue(self, _cmd, value);
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

static void *IPFFindMG(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt", RTLD_NOW);
    if (h) p = dlsym(h, name);
    return p;
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

        // Capture REAL host PV from SystemVersion.plist BEFORE our hooks.
        // Use NSData (About 2109 only hooks NSDictionary file APIs — not NSData).
        // Avoid NSDictionary dictionaryWithContentsOfFile — may already be hooked by About.
        if (!gHostPV) {
            NSData *raw = [NSData dataWithContentsOfFile:
                           @"/System/Library/CoreServices/SystemVersion.plist"];
            NSString *hp = nil;
            if (raw.length) {
                id obj = [NSPropertyListSerialization propertyListWithData:raw
                                                                   options:0
                                                                    format:NULL
                                                                     error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]])
                    hp = [obj[@"ProductVersion"] description];
            }
            gHostPV = hp.length ? [hp copy] : @"15.5";
            IPFVerLog([NSString stringWithFormat:@"hostPV=%@", gHostPV]);
        }

        if (pMSHookFunction) {
            // Hook AFTER About's hook when possible: load order About then AboutVer alphabetically
            // so our stub sits outermost and can wash host values About misses (hashed keys).
            void *mg = IPFFindMG("MGCopyAnswer");
            if (mg) {
                pMSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
                IPFVerLog([NSString stringWithFormat:@"MSHook MGCopyAnswer %p", mg]);
            }
            void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
            if (sys)
                pMSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);
            void *cf = dlsym(RTLD_DEFAULT, "CFCopySystemVersionDictionary");
            if (!cf) {
                void *h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
                if (h) cf = dlsym(h, "CFCopySystemVersionDictionary");
            }
            if (cf)
                pMSHookFunction(cf, (void *)stub_CFCopySysVer, (void **)&orig_CFCopySysVer);
        }

        if (pMSHookMessageEx) {
            Class dm = objc_getMetaClass("NSDictionary");
            if (dm) {
                if (class_getClassMethod(dm, @selector(dictionaryWithContentsOfFile:)))
                    pMSHookMessageEx(dm, @selector(dictionaryWithContentsOfFile:),
                                     (IMP)stub_dictFile, (IMP *)&orig_dictFile);
                if (class_getClassMethod(dm, @selector(dictionaryWithContentsOfURL:)))
                    pMSHookMessageEx(dm, @selector(dictionaryWithContentsOfURL:),
                                     (IMP)stub_dictURL, (IMP *)&orig_dictURL);
            }
            Class ndm = objc_getMetaClass("NSData");
            if (ndm) {
                if (class_getClassMethod(ndm, @selector(dataWithContentsOfFile:)))
                    pMSHookMessageEx(ndm, @selector(dataWithContentsOfFile:),
                                     (IMP)stub_dataFile, (IMP *)&orig_dataFile);
                if (class_getClassMethod(ndm, @selector(dataWithContentsOfURL:)))
                    pMSHookMessageEx(ndm, @selector(dataWithContentsOfURL:),
                                     (IMP)stub_dataURL, (IMP *)&orig_dataURL);
            }
            Class uid = objc_getClass("UIDevice");
            if (uid && class_getInstanceMethod(uid, @selector(systemVersion)))
                pMSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_sysVer, (IMP *)&orig_sysVer);
            Class nspi = objc_getClass("NSProcessInfo");
            if (nspi) {
                if (class_getInstanceMethod(nspi, @selector(operatingSystemVersion)))
                    pMSHookMessageEx(nspi, @selector(operatingSystemVersion),
                                     (IMP)stub_osv, (IMP *)&orig_osv);
                if (class_getInstanceMethod(nspi, @selector(operatingSystemVersionString)))
                    pMSHookMessageEx(nspi, @selector(operatingSystemVersionString),
                                     (IMP)stub_osvString, (IMP *)&orig_osvString);
            }
            // UI wash: exact host version only (Preferences About detail)
            Class uil = objc_getClass("UILabel");
            if (uil && class_getInstanceMethod(uil, @selector(setText:)))
                pMSHookMessageEx(uil, @selector(setText:), (IMP)stub_labelSetText, (IMP *)&orig_labelSetText);
            Class psc = objc_getClass("PSTableCell");
            if (psc && class_getInstanceMethod(psc, @selector(setValue:)))
                pMSHookMessageEx(psc, @selector(setValue:), (IMP)stub_cellSetValue, (IMP *)&orig_cellSetValue);
        }

        NSDictionary *cfg = IPFVerLoadConfig();
        IPFVerLog([NSString stringWithFormat:@"ready PV=%@ BV=%@ hostPV=%@",
                   IPFVerPV(cfg) ?: @"?", IPFVerBV(cfg) ?: @"?", gHostPV ?: @"?"]);
        IPFVerMark("CTOR_OK");
    }
}
