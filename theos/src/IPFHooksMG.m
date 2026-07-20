// IPFHooksMG — HIOS-style dual path:
//   1) fishhook rebind GOT (catches Zalo imports of MG/sysctl/uname)
//   2) MSHookFunction absolute (ElleKit)
// Plus per-call trace log for lab analysis (nông → sâu).

#import "IPFHooksMG.h"
#import "IPFConfig.h"
#import "fishhook.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <pthread.h>

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

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : @"(null)";
        id fake = key ? [[IPFConfig shared] mgValueForKey:k] : nil;
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
        id fake = key ? [[IPFConfig shared] mgValueForKey:k] : nil;
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
            id fake = [[IPFConfig shared] sysctlValueForName:n];
            if (!fake && [n isEqualToString:@"hw.machine"])
                fake = [[IPFConfig shared] mgValueForKey:@"ProductType"];
            if (!fake && [n isEqualToString:@"hw.model"])
                fake = [[IPFConfig shared] mgValueForKey:@"HWModelStr"];
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
            if ([n hasPrefix:@"hw."] || [n hasPrefix:@"kern.os"] || [n containsString:@"serial"]) {
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
        NSString *machine = [[IPFConfig shared] mgValueForKey:@"ProductType"];
        NSString *node = [[IPFConfig shared] stringForKey:@"UserAssignedDeviceName"];
        if ([machine isKindOfClass:[NSString class]]) {
            strlcpy(buf->machine, machine.UTF8String, sizeof(buf->machine));
            IPFTrace([NSString stringWithFormat:@"uname FAKE machine=%@", machine]);
        }
        if (node)
            strlcpy(buf->nodename, node.UTF8String, sizeof(buf->nodename));
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

static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_systemVersion)(id, SEL);
static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *(*orig_idfa)(id, SEL);

static NSString *stub_name(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"UserAssignedDeviceName"];
    if (v) IPFTrace([NSString stringWithFormat:@"UIDevice.name FAKE %@", v]);
    return v ?: (orig_name ? orig_name(self, _cmd) : @"iPhone");
}
static NSString *stub_model(id self, SEL _cmd) {
    IPFTrace(@"UIDevice.model FAKE iPhone");
    return @"iPhone";
}
static NSString *stub_systemVersion(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"ProductVersion"];
    return v ?: (orig_systemVersion ? orig_systemVersion(self, _cmd) : @"17.0");
}
static NSUUID *stub_idfv(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"IDFV"];
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_idfv ? orig_idfv(self, _cmd) : nil;
}
static NSUUID *stub_idfa(id self, SEL _cmd) {
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

    // --- fishhook first (HIOS path for apps that bind imports) ---
    struct rebinding rebs[5];
    int nreb = 0;
    rebs[nreb++] = (struct rebinding){ "MGCopyAnswer", (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer };
    rebs[nreb++] = (struct rebinding){ "sysctlbyname", (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname };
    rebs[nreb++] = (struct rebinding){ "uname", (void *)stub_uname, (void **)&orig_uname };
    rebs[nreb++] = (struct rebinding){ "sysctl", (void *)stub_sysctl, (void **)&orig_sysctl };
    int frc = rebind_symbols(rebs, nreb);
    IPFTrace([NSString stringWithFormat:@"fishhook rc=%d origMG=%p origSys=%p origUname=%p origSysctl=%p",
              frc, orig_MGCopyAnswer, orig_sysctlbyname, orig_uname, orig_sysctl]);

    // --- MSHook absolute (ElleKit) ---
    if (pMSHookFunction) {
        void *mg = IPFFindMG("MGCopyAnswer");
        if (mg) {
            // Only MSHook if fishhook didn't capture orig yet, or always reinforce
            if (!orig_MGCopyAnswer) {
                pMSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
                IPFTrace([NSString stringWithFormat:@"MSHook MGCopyAnswer %p orig=%p", mg, orig_MGCopyAnswer]);
            } else {
                // Still patch absolute for direct calls
                void *tmp = NULL;
                pMSHookFunction(mg, (void *)stub_MGCopyAnswer, &tmp);
                if (!orig_MGCopyAnswer && tmp) orig_MGCopyAnswer = tmp;
                IPFTrace([NSString stringWithFormat:@"MSHook reinforce MG %p tmp=%p", mg, tmp]);
            }
        } else {
            IPFTrace(@"WARN no MGCopyAnswer symbol");
        }
        void *mge = IPFFindMG("MGCopyAnswerWithError");
        if (mge)
            pMSHookFunction(mge, (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);

        void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (sys && !orig_sysctlbyname)
            pMSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);
        void *un = dlsym(RTLD_DEFAULT, "uname");
        if (un && !orig_uname)
            pMSHookFunction(un, (void *)stub_uname, (void **)&orig_uname);
        void *sc = dlsym(RTLD_DEFAULT, "sysctl");
        if (sc && !orig_sysctl)
            pMSHookFunction(sc, (void *)stub_sysctl, (void **)&orig_sysctl);
    } else {
        IPFTrace(@"WARN no MSHookFunction — fishhook only");
    }

    if (pMSHookMessageEx) {
        Class uid = objc_getClass("UIDevice");
        if (uid) {
            pMSHookMessageEx(uid, @selector(name), (IMP)stub_name, (IMP *)&orig_name);
            pMSHookMessageEx(uid, @selector(model), (IMP)stub_model, (IMP *)&orig_model);
            pMSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_systemVersion, (IMP *)&orig_systemVersion);
            pMSHookMessageEx(uid, @selector(identifierForVendor), (IMP)stub_idfv, (IMP *)&orig_idfv);
            IPFTrace(@"UIDevice hooks OK");
        }
        Class asid = objc_getClass("ASIdentifierManager");
        if (asid)
            pMSHookMessageEx(asid, @selector(advertisingIdentifier), (IMP)stub_idfa, (IMP *)&orig_idfa);
    }

    // Self-test: what does hooked MG return for ProductType?
    @autoreleasepool {
        NSString *cfgPT = [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"(nil)";
        NSString *cfgMK = [[IPFConfig shared] mgValueForKey:@"MarketingName"] ?: @"(nil)";
        CFStringRef k = CFSTR("ProductType");
        CFTypeRef ans = stub_MGCopyAnswer(k);
        NSString *got = ans ? [(__bridge id)ans description] : @"(null)";
        if (ans) CFRelease(ans);
        IPFTrace([NSString stringWithFormat:@"SELFTEST cfgPT=%@ cfgMK=%@ stubPT=%@", cfgPT, cfgMK, got]);
        NSString *dbg = [NSString stringWithFormat:
            @"hooks cfgPT=%@ cfgMK=%@ stubPT=%@ fishhook_rc=%d MSHook=%p\n",
            cfgPT, cfgMK, got, frc, pMSHookFunction];
        NSString *home = NSHomeDirectory();
        if (home.length)
            [dbg writeToFile:[home stringByAppendingPathComponent:@"Documents/v3_mg_debug.log"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    IPFTrace(@"IPFInstallMGHooks done");
}
