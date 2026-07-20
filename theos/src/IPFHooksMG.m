// IPFHooksMG.m — mirror ChangeInfoIosMG technique:
//   MSHookFunction(MGCopyAnswer), MSHookMessageEx(UIDevice), MSHookFunction(sysctlbyname/uname)
// Values from IPFConfig (config.plist like HIOS /var/jb/etc/changeinfoios/config.plist)

#import "IPFHooksMG.h"
#import "IPFConfig.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <string.h>
#import <substrate.h>

static NSString *IPFString(id v) {
    if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

// HIOS returns CFType that caller may CFRelease — use CFBridgingRetain for owned returns
static CFTypeRef IPFMakeCF(id v) {
    if (!v || v == [NSNull null]) return NULL;
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) {
        return CFBridgingRetain(v);
    }
    return NULL;
}

#pragma mark - MGCopyAnswer (libMobileGestalt)

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef (*orig_MGCopyAnswerWithError)(CFStringRef key, int *err);

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : nil;
        if (k) {
            id fake = [[IPFConfig shared] mgValueForKey:k];
            if (fake) {
                CFTypeRef cf = IPFMakeCF(fake);
                if (cf) return cf;
            }
        }
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
}

static CFTypeRef stub_MGCopyAnswerWithError(CFStringRef key, int *err) {
    @autoreleasepool {
        NSString *k = key ? (__bridge NSString *)key : nil;
        if (k) {
            id fake = [[IPFConfig shared] mgValueForKey:k];
            if (fake) {
                if (err) *err = 0;
                CFTypeRef cf = IPFMakeCF(fake);
                if (cf) return cf;
            }
        }
    }
    return orig_MGCopyAnswerWithError ? orig_MGCopyAnswerWithError(key, err) : NULL;
}

#pragma mark - sysctlbyname

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static int stub_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldp && oldlenp && *oldlenp > 0) {
        @autoreleasepool {
            NSString *n = [NSString stringWithUTF8String:name];
            id fake = [[IPFConfig shared] sysctlValueForName:n];
            // also allow mg ProductType via hw.machine
            if (!fake && n && [n isEqualToString:@"hw.machine"]) {
                fake = [[IPFConfig shared] mgValueForKey:@"ProductType"];
            }
            if ([fake isKindOfClass:[NSString class]]) {
                const char *s = [(NSString *)fake UTF8String];
                size_t need = strlen(s) + 1;
                if (*oldlenp >= need) {
                    memcpy(oldp, s, need);
                    *oldlenp = need;
                    return 0;
                }
            } else if ([fake isKindOfClass:[NSNumber class]]) {
                unsigned long long v = [(NSNumber *)fake unsignedLongLongValue];
                if (*oldlenp >= sizeof(uint64_t)) {
                    *(uint64_t *)oldp = (uint64_t)v;
                    *oldlenp = sizeof(uint64_t);
                    return 0;
                }
                if (*oldlenp >= sizeof(uint32_t)) {
                    *(uint32_t *)oldp = (uint32_t)v;
                    *oldlenp = sizeof(uint32_t);
                    return 0;
                }
            }
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - uname

static int (*orig_uname)(struct utsname *);

static int stub_uname(struct utsname *buf) {
    int rc = orig_uname ? orig_uname(buf) : -1;
    if (rc != 0 || !buf) return rc;
    @autoreleasepool {
        IPFConfig *c = [IPFConfig shared];
        NSString *machine = IPFString(c.model[@"ProductType"]) ?: IPFString([c mgValueForKey:@"ProductType"]);
        NSString *node = IPFString(c.os[@"Hostname"]) ?: IPFString([c mgValueForKey:@"UserAssignedDeviceName"]);
        if (machine) strlcpy(buf->machine, machine.UTF8String, sizeof(buf->machine));
        if (node) strlcpy(buf->nodename, node.UTF8String, sizeof(buf->nodename));
    }
    return rc;
}

#pragma mark - UIDevice (HIOS hooks name/model/systemVersion/IDFV)

static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_localizedModel)(id, SEL);
static NSString *(*orig_systemVersion)(id, SEL);
static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *(*orig_idfa)(id, SEL);

static NSString *stub_name(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"UserAssignedDeviceName"];
    if (!v) v = IPFString([IPFConfig shared].uidevice[@"name"]);
    return v ?: (orig_name ? orig_name(self, _cmd) : @"iPhone");
}

// HIOS: UIDevice.model — often "iPhone"; marketing name is separate
// Zalo device list uses ProductType→marketing map; still spoof model consistently
static NSString *stub_model(id self, SEL _cmd) {
    // Prefer MarketingName if present so UI is not real "iPhone" only
    // Some apps show model as marketing string via other APIs; keep "iPhone" like real UIDevice.model
    return @"iPhone";
}

static NSString *stub_localizedModel(id self, SEL _cmd) {
    return @"iPhone";
}

static NSString *stub_systemVersion(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"ProductVersion"];
    if (!v) v = IPFString([IPFConfig shared].uidevice[@"systemVersion"]);
    return v ?: (orig_systemVersion ? orig_systemVersion(self, _cmd) : @"17.0");
}

static NSUUID *stub_idfv(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"IDFV"];
    if (!v) v = IPFString([IPFConfig shared].identity[@"IDFV"]);
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_idfv ? orig_idfv(self, _cmd) : nil;
}

static NSUUID *stub_idfa(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"IDFA"];
    if (!v) v = IPFString([IPFConfig shared].identity[@"IDFA"]);
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_idfa ? orig_idfa(self, _cmd) : nil;
}

#pragma mark - install (HIOS: dlsym + MSHookFunction)

static void *IPFFindSym(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt", RTLD_NOW);
    if (h) p = dlsym(h, name);
    return p;
}

void IPFInstallMGHooks(void) {
    IPFConfig *cfg = [IPFConfig shared];
    if (!cfg.loaded || !cfg.enabled) {
        NSLog(@"[iPFakerMG] skip install loaded=%d enabled=%d", cfg.loaded, cfg.enabled);
        return;
    }

    // MGCopyAnswer — HIOS: MSHookFunction after resolve
    void *mg = IPFFindSym("MGCopyAnswer");
    if (mg) {
        MSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
        NSLog(@"[iPFakerMG] MSHook MGCopyAnswer ok ProductType=%@",
              [cfg mgValueForKey:@"ProductType"]);
    } else {
        NSLog(@"[iPFakerMG] WARN: no MGCopyAnswer (like HIOS log)");
    }

    void *mge = IPFFindSym("MGCopyAnswerWithError");
    if (mge) {
        MSHookFunction(mge, (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);
    }

    void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
    if (sys) {
        MSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);
        NSLog(@"[iPFakerMG] MSHook sysctlbyname ok");
    }

    void *un = dlsym(RTLD_DEFAULT, "uname");
    if (un) {
        MSHookFunction(un, (void *)stub_uname, (void **)&orig_uname);
    }

    Class uid = objc_getClass("UIDevice");
    if (uid) {
        MSHookMessageEx(uid, @selector(name), (IMP)stub_name, (IMP *)&orig_name);
        MSHookMessageEx(uid, @selector(model), (IMP)stub_model, (IMP *)&orig_model);
        MSHookMessageEx(uid, @selector(localizedModel), (IMP)stub_localizedModel, (IMP *)&orig_localizedModel);
        MSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_systemVersion, (IMP *)&orig_systemVersion);
        MSHookMessageEx(uid, @selector(identifierForVendor), (IMP)stub_idfv, (IMP *)&orig_idfv);
        NSLog(@"[iPFakerMG] UIDevice hooks ok name=%@", [cfg stringForKey:@"UserAssignedDeviceName"]);
    }

    Class asid = objc_getClass("ASIdentifierManager");
    if (asid) {
        MSHookMessageEx(asid, @selector(advertisingIdentifier), (IMP)stub_idfa, (IMP *)&orig_idfa);
    }

    // Debug log path like HIOS v3_mg_debug.log
    NSString *dbg = [NSString stringWithFormat:
        @"MG ProductType=%@ Marketing=%@ Serial=%@ IDFV=%@\n",
        [cfg mgValueForKey:@"ProductType"],
        [cfg mgValueForKey:@"MarketingName"],
        [cfg mgValueForKey:@"SerialNumber"],
        [cfg stringForKey:@"IDFV"]];
    [dbg writeToFile:@"/var/jb/etc/ipfaker/v3_mg_debug.log"
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
