// IPFHooksMG — HIOS ChangeInfoIosMG technique:
//   dlsym MGCopyAnswer + MSHookFunction (from ElleKit/libsubstrate via dlsym)
//   MSHookMessageEx UIDevice
//   MSHookFunction sysctlbyname / uname
// Does NOT hard-link substrate (avoids load failure); resolves at runtime like robust tweaks.

#import "IPFHooksMG.h"
#import "IPFConfig.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <string.h>

// Substrate API typedefs (resolved via dlsym — HIOS uses MSHook*)
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction = NULL;
static MSHookMessageEx_t pMSHookMessageEx = NULL;

static NSString *IPFString(id v) {
    if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
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
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        NULL
    };
    for (int i = 0; libs[i]; i++) {
        void *h = dlopen(libs[i], RTLD_NOW);
        if (!h) continue;
        pMSHookFunction = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        pMSHookMessageEx = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
        if (pMSHookFunction) {
            NSLog(@"[iPFakerMG] substrate from %s", libs[i]);
            return;
        }
    }
    // Already loaded in process
    pMSHookFunction = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    pMSHookMessageEx = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    NSLog(@"[iPFakerMG] MSHookFunction=%p MSHookMessageEx=%p", pMSHookFunction, pMSHookMessageEx);
}

#pragma mark - MG

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef (*orig_MGCopyAnswerWithError)(CFStringRef key, int *err);

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        if (key) {
            NSString *k = (__bridge NSString *)key;
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
        if (key) {
            NSString *k = (__bridge NSString *)key;
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

#pragma mark - sysctl / uname

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);

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
                    return 0;
                }
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
        if ([machine isKindOfClass:[NSString class]])
            strlcpy(buf->machine, machine.UTF8String, sizeof(buf->machine));
        if (node)
            strlcpy(buf->nodename, node.UTF8String, sizeof(buf->nodename));
    }
    return rc;
}

#pragma mark - UIDevice

static NSString *(*orig_name)(id, SEL);
static NSString *(*orig_model)(id, SEL);
static NSString *(*orig_systemVersion)(id, SEL);
static NSUUID *(*orig_idfv)(id, SEL);
static NSUUID *(*orig_idfa)(id, SEL);

static NSString *stub_name(id self, SEL _cmd) {
    NSString *v = [[IPFConfig shared] stringForKey:@"UserAssignedDeviceName"];
    return v ?: (orig_name ? orig_name(self, _cmd) : @"iPhone");
}
static NSString *stub_model(id self, SEL _cmd) { return @"iPhone"; }
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
    IPFResolveSubstrate();
    if (!pMSHookFunction) {
        NSLog(@"[iPFakerMG] FATAL: MSHookFunction not found — dylib inject env broken");
        return;
    }

    void *mg = IPFFindMG("MGCopyAnswer");
    if (mg) {
        pMSHookFunction(mg, (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
        NSLog(@"[iPFakerMG] hooked MGCopyAnswer");
    } else {
        NSLog(@"[iPFakerMG] WARN: no MGCopyAnswer");
    }
    void *mge = IPFFindMG("MGCopyAnswerWithError");
    if (mge && pMSHookFunction)
        pMSHookFunction(mge, (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);

    void *sys = dlsym(RTLD_DEFAULT, "sysctlbyname");
    if (sys) pMSHookFunction(sys, (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);

    void *un = dlsym(RTLD_DEFAULT, "uname");
    if (un) pMSHookFunction(un, (void *)stub_uname, (void **)&orig_uname);

    if (pMSHookMessageEx) {
        Class uid = objc_getClass("UIDevice");
        if (uid) {
            pMSHookMessageEx(uid, @selector(name), (IMP)stub_name, (IMP *)&orig_name);
            pMSHookMessageEx(uid, @selector(model), (IMP)stub_model, (IMP *)&orig_model);
            pMSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_systemVersion, (IMP *)&orig_systemVersion);
            pMSHookMessageEx(uid, @selector(identifierForVendor), (IMP)stub_idfv, (IMP *)&orig_idfv);
        }
        Class asid = objc_getClass("ASIdentifierManager");
        if (asid)
            pMSHookMessageEx(asid, @selector(advertisingIdentifier), (IMP)stub_idfa, (IMP *)&orig_idfa);
    }

    NSString *dbg = [NSString stringWithFormat:
        @"hooks ProductType=%@ Marketing=%@ Serial=%@\n",
        [[IPFConfig shared] mgValueForKey:@"ProductType"],
        [[IPFConfig shared] mgValueForKey:@"MarketingName"],
        [[IPFConfig shared] mgValueForKey:@"SerialNumber"]];
    [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
