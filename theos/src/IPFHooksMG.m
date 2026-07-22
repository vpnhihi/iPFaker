// IPFHooksMG — ElleKit MSHook absolute (stable on Dopamine).
// fishhook: SAFE FALLBACK only when MSHookFunction is missing (not used if ElleKit loads).
// Full always-on GOT rebind was removed (SIGBUS on Zalo DATA_CONST).

#import "IPFHooksMG.h"
#import "IPFConfig.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <pthread.h>

#if IPF_FISHHOOK_FALLBACK
#import "fishhook.h"
#endif

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction = NULL;
static MSHookMessageEx_t pMSHookMessageEx = NULL;

static pthread_mutex_t gLogMu = PTHREAD_MUTEX_INITIALIZER;
static int gLogCount = 0;

static void IPFTrace(NSString *line) {
    if (!line) return;
    pthread_mutex_lock(&gLogMu);
    gLogCount++;
    // Cap file growth during long sessions
    if (gLogCount > 4000) {
        pthread_mutex_unlock(&gLogMu);
        return;
    }
    NSString *home = NSHomeDirectory();
    NSArray *paths = @[
        home.length ? [home stringByAppendingPathComponent:@"Documents/ipfaker_trace.log"] : @"",
        @"/var/mobile/Library/iPFaker/logs/ipfaker_trace.log",
    ];
    NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), line];
    for (NSString *p in paths) {
        if (p.length == 0) continue;
        @try {
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
    pthread_mutex_unlock(&gLogMu);
}

static CFTypeRef IPFMakeCF(id v) {
    if (!v || v == [NSNull null]) return NULL;
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]])
        return CFBridgingRetain(v);
    return NULL;
}

static void IPFResolveSubstrate(void) {
    if (pMSHookFunction) return;
    const char *libs[] = {
        "/var/jb/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
        "/usr/lib/libsubstrate.dylib",
        NULL
    };
    for (int i = 0; libs[i]; i++) {
        void *h = dlopen(libs[i], RTLD_NOW);
        if (!h) continue;
        pMSHookFunction = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        pMSHookMessageEx = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
        if (pMSHookFunction) {
            IPFTrace([NSString stringWithFormat:@"substrate ok %s MSHook=%p Msg=%p", libs[i], pMSHookFunction, pMSHookMessageEx]);
            return;
        }
    }
    pMSHookFunction = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    pMSHookMessageEx = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    IPFTrace([NSString stringWithFormat:@"substrate RTLD MSHook=%p Msg=%p", pMSHookFunction, pMSHookMessageEx]);
}

#pragma mark - MG

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef (*orig_MGCopyAnswerWithError)(CFStringRef key, int *err);

/// Gate MG key by Settings Fake* flags (written into config.plist on Apply).
static BOOL IPFAllowMGKey(NSString *k) {
    IPFConfig *c = [IPFConfig shared];
    if (!c.enabled) return NO;
    if (!k.length) return NO;
    NSString *lk = k.lowercaseString;
    // IDFA / IDFV — Apple advertisingIdentifier / identifierForVendor (UUID v4)
    if ([lk containsString:@"advertising"] || [lk isEqualToString:@"idfa"]
        || [lk containsString:@"identifierforvendor"] || [lk isEqualToString:@"idfv"])
        return [c flag:@"FakeAds" defaultYes:YES];
    // Wi‑Fi / BT MAC (IEEE 802 EUI-48)
    if ([lk containsString:@"wifi"] || [lk containsString:@"bluetooth"]
        || [lk containsString:@"ethernetmac"] || [lk isEqualToString:@"bssid"])
        return [c flag:@"FakeWifi" defaultYes:YES];
    // OS version / build
    if ([lk containsString:@"productversion"] || [lk containsString:@"buildversion"]
        || [lk containsString:@"productbuild"] || [lk isEqualToString:@"os-version"])
        return [c flag:@"FakeSysOSVersion" defaultYes:YES];
    // Screen MG keys
    if ([lk containsString:@"screen"] || [lk containsString:@"display"])
        return [c flag:@"FakeScreen" defaultYes:YES] || [c flag:@"FakeRealScreen" defaultYes:NO];
    // Hardware identity
    if ([lk containsString:@"serial"] || [lk containsString:@"unique"] || [lk containsString:@"chip"]
        || [lk containsString:@"imei"] || [lk containsString:@"meid"] || [lk containsString:@"eid"]
        || [lk containsString:@"baseband"] || [lk containsString:@"memsize"]
        || [lk containsString:@"physicalmemory"])
        return [c flag:@"FakeHardware" defaultYes:YES];
    // Device model / marketing (default device surface)
    return [c flag:@"FakeDevice" defaultYes:YES];
}

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : @"(null)";
        id fake = (key && IPFAllowMGKey(k)) ? [[IPFConfig shared] mgValueForKey:k] : nil;
        if (fake) {
            IPFTrace([NSString stringWithFormat:@"MG FAKE %@ => %@", k, fake]);
            CFTypeRef cf = IPFMakeCF(fake);
            if (cf) return cf;
        }
        CFTypeRef real = orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
        NSString *rv = @"(nil)";
        if (real) {
            id o = (__bridge id)real;
            rv = [o description] ?: @"?";
            if (rv.length > 120) rv = [[rv substringToIndex:120] stringByAppendingString:@"…"];
        }
        // Log interesting real hits so we see what Zalo probes
        if ([k rangeOfString:@"Product" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Serial" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Unique" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"HWModel" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Device" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Marketing" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Build" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Version" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Wifi" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Blue" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Chip" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"Region" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"screen" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [k rangeOfString:@"model" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            IPFTrace([NSString stringWithFormat:@"MG REAL %@ => %@", k, rv]);
        }
        return real;
    }
}

static CFTypeRef stub_MGCopyAnswerWithError(CFStringRef key, int *err) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : @"(null)";
        id fake = (key && IPFAllowMGKey(k)) ? [[IPFConfig shared] mgValueForKey:k] : nil;
        if (fake) {
            if (err) *err = 0;
            IPFTrace([NSString stringWithFormat:@"MGe FAKE %@ => %@", k, fake]);
            CFTypeRef cf = IPFMakeCF(fake);
            if (cf) return cf;
        }
    }
    return orig_MGCopyAnswerWithError ? orig_MGCopyAnswerWithError(key, err) : NULL;
}

#pragma mark - sysctl / uname

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);

static int stub_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldp && oldlenp && *oldlenp > 0) {
        @autoreleasepool {
            NSString *n = [NSString stringWithUTF8String:name];
            IPFConfig *cfg = [IPFConfig shared];
            BOOL allowSys = [cfg flag:@"FakeSysctl" defaultYes:YES];
            BOOL allowOS = [cfg flag:@"FakeSysOSVersion" defaultYes:YES];
            BOOL allowDev = [cfg flag:@"FakeDevice" defaultYes:YES];
            BOOL allowHW = [cfg flag:@"FakeHardware" defaultYes:YES];
            BOOL allowDT = [cfg flag:@"FakeDateTime" defaultYes:NO];
            if ([n hasPrefix:@"kern.os"] && !allowOS) {
                return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
            }
            if ([n isEqualToString:@"kern.boottime"] && !allowDT) {
                return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
            }
            if (([n isEqualToString:@"hw.machine"] || [n isEqualToString:@"hw.model"]) && !allowDev)
                return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
            if (([n hasPrefix:@"hw.mem"] || [n hasPrefix:@"hw.ncpu"] || [n hasPrefix:@"hw.physical"]
                 || [n hasPrefix:@"hw.logical"]) && !allowHW)
                return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
            BOOL isSerialCtl = [n isEqualToString:@"hw.serialnumber"]
                || [n isEqualToString:@"kern.serialnumber"];
            if (!allowSys && ![n isEqualToString:@"kern.boottime"] && ![n hasPrefix:@"kern.os"]
                && ![n isEqualToString:@"hw.machine"] && ![n isEqualToString:@"hw.model"]
                && !(isSerialCtl && allowHW))
                return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;

            id fake = [cfg sysctlValueForName:n];
            if (!fake && [n isEqualToString:@"hw.machine"] && allowDev)
                fake = [cfg mgValueForKey:@"ProductType"];
            if (!fake && [n isEqualToString:@"hw.model"] && allowDev)
                fake = [cfg mgValueForKey:@"HWModelStr"];
            // serial board / hw.serialnumber ≡ SerialNumber (identity sync)
            if (!fake && allowHW && isSerialCtl) {
                fake = [cfg mgValueForKey:@"SerialNumber"]
                    ?: [cfg stringForKey:@"SerialNumber"]
                    ?: [cfg stringForKey:@"IOPlatformSerialNumber"];
            }
            if ([fake isKindOfClass:[NSString class]]) {
                const char *s = [(NSString *)fake UTF8String];
                size_t need = strlen(s) + 1;
                if (*oldlenp >= need) {
                    memcpy(oldp, s, need);
                    *oldlenp = need;
                    IPFTrace([NSString stringWithFormat:@"sysctl FAKE %s => %@", name, fake]);
                    return 0;
                }
            }
            // kern.boottime → struct timeval { tv_sec, tv_usec }
            if ([n isEqualToString:@"kern.boottime"]) {
                id bt = fake ?: [[IPFConfig shared] stringForKey:@"BootTimeUnix"]
                    ?: [[IPFConfig shared] stringForKey:@"kern.boottime"];
                if (bt) {
                    long long sec = [bt longLongValue];
                    if (sec > 0 && *oldlenp >= sizeof(struct timeval)) {
                        struct timeval tv;
                        tv.tv_sec = (time_t)sec;
                        tv.tv_usec = 0;
                        memcpy(oldp, &tv, sizeof(tv));
                        *oldlenp = sizeof(tv);
                        IPFTrace([NSString stringWithFormat:@"sysctl FAKE kern.boottime => %lld", sec]);
                        return 0;
                    }
                }
            }
            // integer sysctls: hw.memsize, hw.ncpu, ...
            if ([fake isKindOfClass:[NSNumber class]]) {
                if (*oldlenp >= sizeof(int64_t)) {
                    int64_t v = [(NSNumber *)fake longLongValue];
                    // prefer native size requested by caller
                    if (*oldlenp >= sizeof(int64_t)) {
                        *(int64_t *)oldp = v;
                        *oldlenp = sizeof(int64_t);
                    } else if (*oldlenp >= sizeof(int32_t)) {
                        *(int32_t *)oldp = (int32_t)v;
                        *oldlenp = sizeof(int32_t);
                    }
                    IPFTrace([NSString stringWithFormat:@"sysctl FAKE %s => %lld", name, (long long)v]);
                    return 0;
                }
            }
            if ([n hasPrefix:@"hw."] || [n hasPrefix:@"kern.os"] || [n hasPrefix:@"kern.boot"]
                || [n containsString:@"serial"]) {
                IPFTrace([NSString stringWithFormat:@"sysctl PASS %@", n]);
            }
        }
    }
    return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
}

static int stub_uname(struct utsname *buf) {
    int rc = orig_uname ? orig_uname(buf) : -1;
    if (rc != 0 || !buf) return rc;
    @autoreleasepool {
        IPFConfig *cfg = [IPFConfig shared];
        if ([cfg flag:@"FakeDevice" defaultYes:YES]) {
            NSString *machine = [cfg mgValueForKey:@"ProductType"];
            // nodename ≡ gethostname ≡ Hostname (must match Extra hooks)
            NSString *node = [cfg stringForKey:@"Hostname"]
                ?: [cfg stringForKey:@"kern.hostname"]
                ?: [cfg stringForKey:@"UserAssignedDeviceName"];
            if ([machine isKindOfClass:[NSString class]]) {
                strlcpy(buf->machine, machine.UTF8String, sizeof(buf->machine));
                IPFTrace([NSString stringWithFormat:@"uname FAKE machine=%@", machine]);
            }
            if (node.length)
                strlcpy(buf->nodename, node.UTF8String, sizeof(buf->nodename));
        }
        if ([cfg flag:@"FakeSysOSVersion" defaultYes:YES] || [cfg flag:@"FakeSysctl" defaultYes:YES]) {
            // Prefer map from IPFConfig (kern.osrelease/version); never leave host Darwin on mismatch spoof
            id rel = [cfg sysctlValueForName:@"kern.osrelease"] ?: [cfg stringForKey:@"kern.osrelease"];
            id kver = [cfg sysctlValueForName:@"kern.version"] ?: [cfg stringForKey:@"kern.version"];
            if ([rel isKindOfClass:[NSString class]] && [(NSString *)rel length])
                strlcpy(buf->release, [(NSString *)rel UTF8String], sizeof(buf->release));
            if ([kver isKindOfClass:[NSString class]] && [(NSString *)kver length])
                strlcpy(buf->version, [(NSString *)kver UTF8String], sizeof(buf->version));
        }
    }
    return rc;
}

// raw sysctl CTL_HW / HW_MACHINE
static int stub_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen >= 2 && oldp && oldlenp && *oldlenp > 0) {
        // CTL_HW=6, HW_MACHINE=1, HW_MODEL=2
        if (name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_MODEL)) {
            @autoreleasepool {
                id fake = nil;
                if (name[1] == HW_MACHINE)
                    fake = [[IPFConfig shared] mgValueForKey:@"ProductType"];
                else
                    fake = [[IPFConfig shared] mgValueForKey:@"HWModelStr"];
                if ([fake isKindOfClass:[NSString class]]) {
                    const char *s = [(NSString *)fake UTF8String];
                    size_t need = strlen(s) + 1;
                    if (*oldlenp >= need) {
                        memcpy(oldp, s, need);
                        *oldlenp = need;
                        IPFTrace([NSString stringWithFormat:@"sysctl_raw FAKE mib=%d,%d => %@", name[0], name[1], fake]);
                        return 0;
                    }
                }
            }
        }
    }
    return orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
}

#pragma mark - UIDevice
// Surface matrix: name / model / localizedModel / systemName / systemVersion + IDFV (log spoof)

static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_localizedModel)(id, SEL);
static NSString *(*orig_systemName)(id, SEL);
static NSString *(*orig_systemVersion)(id, SEL);
static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *(*orig_idfa)(id, SEL);

static NSString *stub_name(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES])
        return orig_name ? orig_name(self, _cmd) : @"iPhone";
    NSString *v = [[IPFConfig shared] stringForKey:@"UserAssignedDeviceName"];
    if (v) IPFTrace([NSString stringWithFormat:@"UIDevice.name FAKE %@", v]);
    return v ?: (orig_name ? orig_name(self, _cmd) : @"iPhone");
}
static NSString *stub_model(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES])
        return orig_model ? orig_model(self, _cmd) : @"iPhone";
    // Apple API: model is always "iPhone" / "iPad" class string (not ProductType)
    IPFTrace(@"UIDevice.model FAKE iPhone");
    return @"iPhone";
}
static NSString *stub_localizedModel(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES])
        return orig_localizedModel ? orig_localizedModel(self, _cmd) : @"iPhone";
    // Keep in sync with model (localized hardware family)
    return @"iPhone";
}
static NSString *stub_systemName(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeSysOSVersion" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES])
        return orig_systemName ? orig_systemName(self, _cmd) : @"iOS";
    return @"iOS";
}
static NSString *stub_systemVersion(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeSysOSVersion" defaultYes:YES])
        return orig_systemVersion ? orig_systemVersion(self, _cmd) : @"17.0";
    NSString *v = [[IPFConfig shared] stringForKey:@"ProductVersion"];
    if (v.length) IPFTrace([NSString stringWithFormat:@"UIDevice.systemVersion FAKE %@", v]);
    return v ?: (orig_systemVersion ? orig_systemVersion(self, _cmd) : @"17.0");
}
static NSUUID *stub_idfv(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeAds" defaultYes:YES])
        return orig_idfv ? orig_idfv(self, _cmd) : nil;
    NSString *v = [[IPFConfig shared] stringForKey:@"IDFV"];
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_idfv ? orig_idfv(self, _cmd) : nil;
}
static NSUUID *stub_idfa(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeAds" defaultYes:YES])
        return orig_idfa ? orig_idfa(self, _cmd) : nil;
    NSString *v = [[IPFConfig shared] stringForKey:@"IDFA"];
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_idfa ? orig_idfa(self, _cmd) : nil;
}

static void *IPFFindMG(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt", RTLD_NOW);
    if (h) p = dlsym(h, name);
    return p;
}

void IPFInstallMGHooks(void) {
    IPFTrace(@"IPFInstallMGHooks begin");
    IPFResolveSubstrate();

    int fishhook_rc = -3; // -3 = not needed (MSHook used) / disabled
    // ElleKit MSHook absolute preferred (stable when injected on Dopamine)
    if (pMSHookFunction) {
        void *mg = IPFFindMG("MGCopyAnswer");
        if (mg) {
            pMSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            IPFTrace([NSString stringWithFormat:@"MSHook MGCopyAnswer %p orig=%p", mg, orig_MGCopyAnswer]);
        } else {
            IPFTrace(@"WARN no MGCopyAnswer symbol");
        }
        void *mge = IPFFindMG("MGCopyAnswerWithError");
        if (mge)
            pMSHookFunction(mge, (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);

        void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (sys)
            pMSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);
        void *un = dlsym(RTLD_DEFAULT, "uname");
        if (un)
            pMSHookFunction(un, (void *)stub_uname, (void **)&orig_uname);
        void *sc = dlsym(RTLD_DEFAULT, "sysctl");
        if (sc)
            pMSHookFunction(sc, (void *)stub_sysctl, (void **)&orig_sysctl);
        fishhook_rc = -3; // MSHook path — fishhook idle
    } else {
        // SAFE fishhook fallback: only when MSHook missing (rare on Dopamine+ElleKit).
        // Do NOT call rebind when MSHook works — avoids prior SIGBUS on DATA_CONST.
        IPFTrace(@"WARN no MSHookFunction — try fishhook fallback");
#if IPF_FISHHOOK_FALLBACK
        struct rebinding rbs[] = {
            {"MGCopyAnswer", (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer},
            {"MGCopyAnswerWithError", (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError},
            {"sysctlbyname", (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname},
            {"uname", (void *)stub_uname, (void **)&orig_uname},
            {"sysctl", (void *)stub_sysctl, (void **)&orig_sysctl},
        };
        @try {
            fishhook_rc = rebind_symbols(rbs, sizeof(rbs) / sizeof(rbs[0]));
            IPFTrace([NSString stringWithFormat:@"fishhook fallback rc=%d", fishhook_rc]);
        } @catch (__unused NSException *ex) {
            fishhook_rc = -2;
            IPFTrace(@"fishhook fallback EXCEPTION — spoof C hooks inactive");
        }
#else
        fishhook_rc = -1;
        IPFTrace(@"WARN fishhook fallback compiled out");
#endif
    }

    if (pMSHookMessageEx) {
        Class uid = objc_getClass("UIDevice");
        if (uid) {
            pMSHookMessageEx(uid, @selector(name), (IMP)stub_name, (IMP *)&orig_name);
            pMSHookMessageEx(uid, @selector(model), (IMP)stub_model, (IMP *)&orig_model);
            if (class_getInstanceMethod(uid, @selector(localizedModel)))
                pMSHookMessageEx(uid, @selector(localizedModel), (IMP)stub_localizedModel, (IMP *)&orig_localizedModel);
            if (class_getInstanceMethod(uid, @selector(systemName)))
                pMSHookMessageEx(uid, @selector(systemName), (IMP)stub_systemName, (IMP *)&orig_systemName);
            pMSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_systemVersion, (IMP *)&orig_systemVersion);
            pMSHookMessageEx(uid, @selector(identifierForVendor), (IMP)stub_idfv, (IMP *)&orig_idfv);
            IPFTrace(@"UIDevice hooks OK (name/model/localizedModel/systemName/systemVersion/idfv)");
        }
        Class asid = objc_getClass("ASIdentifierManager");
        if (asid)
            pMSHookMessageEx(asid, @selector(advertisingIdentifier), (IMP)stub_idfa, (IMP *)&orig_idfa);
    }

    // Self-test + 7-surface matrix markers (synced with Extra surfaces)
    @autoreleasepool {
        IPFConfig *cfg = [IPFConfig shared];
        NSString *cfgPT = [cfg mgValueForKey:@"ProductType"] ?: @"(nil)";
        NSString *cfgMK = [cfg mgValueForKey:@"MarketingName"] ?: @"(nil)";
        NSString *cfgSN = [cfg mgValueForKey:@"SerialNumber"] ?: @"(nil)";
        NSString *cfgVer = [cfg stringForKey:@"ProductVersion"] ?: @"(nil)";
        NSString *cfgBuild = [cfg stringForKey:@"BuildVersion"] ?: @"(nil)";
        NSString *cfgIDFA = [cfg stringForKey:@"IDFA"] ?: @"(nil)";
        CFStringRef k = CFSTR("ProductType");
        CFTypeRef ans = stub_MGCopyAnswer(k);
        NSString *got = ans ? [(__bridge id)ans description] : @"(null)";
        if (ans) CFRelease(ans);
        IPFTrace([NSString stringWithFormat:@"SELFTEST cfgPT=%@ cfgMK=%@ stubPT=%@", cfgPT, cfgMK, got]);
        // Dual path: MSHook primary; fishhook only when MSHook miss (rc!=-3)
        NSString *mspath = pMSHookFunction ? @"MSHook=ON" : @"MSHook=OFF";
        NSString *fhpath = (fishhook_rc == -3) ? @"fishhook=IDLE(MSHook)"
            : (fishhook_rc == 0) ? @"fishhook=ON(fallback)"
            : [NSString stringWithFormat:@"fishhook=FAIL(rc=%d)", fishhook_rc];
        NSString *dbg = [NSString stringWithFormat:
            @"hooks cfgPT=%@ cfgMK=%@ stubPT=%@ fishhook_rc=%d MSHook=%p\n"
            @"SURFACE dual_hook: %@ · %@ (ctor log both paths)\n"
            @"SURFACE MobileGestalt: ProductType=%@ Version=%@ Build=%@ Serial=%@ IDFA=%@\n"
            @"SURFACE sysctl/uname: hw.machine=%@ FakeSysctl=%d\n"
            @"SURFACE UIDevice: name/model/systemVersion/idfv (log spoof)\n",
            cfgPT, cfgMK, got, fishhook_rc, pMSHookFunction,
            mspath, fhpath,
            cfgPT, cfgVer, cfgBuild, cfgSN, cfgIDFA,
            cfgPT, [cfg flag:@"FakeSysctl" defaultYes:YES] ? 1 : 0];
        NSString *home = NSHomeDirectory();
        if (home.length) {
            [dbg writeToFile:[home stringByAppendingPathComponent:@"Documents/v3_mg_debug.log"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [dbg writeToFile:[home stringByAppendingPathComponent:@"Documents/ipfaker_surfaces.log"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/ipfaker_surfaces.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    IPFTrace(@"IPFInstallMGHooks done");
}
