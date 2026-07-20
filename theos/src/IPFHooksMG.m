// iPFakerMG — P0: MGCopyAnswer, sysctlbyname, uname, UIDevice, IDFA
// Config: IPFConfig (active_profile.json) — same idea as ChangeInfo MG dylib

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
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

static CFTypeRef IPFCFFromJSON(id v) {
    if (!v || v == [NSNull null]) return NULL;
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]
        || [v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSArray class]]) {
        return CFBridgingRetain(v);
    }
    return NULL;
}

#pragma mark - MGCopyAnswer

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef (*orig_MGCopyAnswerWithError)(CFStringRef key, int *err);

static CFTypeRef stub_MGCopyAnswer(CFStringRef key) {
    NSString *k = (__bridge NSString *)key;
    id fake = [[IPFConfig shared] mgValueForKey:k];
    if (fake) {
        CFTypeRef cf = IPFCFFromJSON(fake);
        if (cf) return cf;
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
}

static CFTypeRef stub_MGCopyAnswerWithError(CFStringRef key, int *err) {
    NSString *k = (__bridge NSString *)key;
    id fake = [[IPFConfig shared] mgValueForKey:k];
    if (fake) {
        if (err) *err = 0;
        CFTypeRef cf = IPFCFFromJSON(fake);
        if (cf) return cf;
    }
    return orig_MGCopyAnswerWithError ? orig_MGCopyAnswerWithError(key, err) : NULL;
}

#pragma mark - sysctlbyname

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static int stub_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldp && oldlenp) {
        NSString *n = [NSString stringWithUTF8String:name];
        id fake = [[IPFConfig shared] sysctlValueForName:n];
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
            } else if (*oldlenp >= sizeof(uint32_t)) {
                *(uint32_t *)oldp = (uint32_t)v;
                *oldlenp = sizeof(uint32_t);
                return 0;
            }
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - uname

static int (*orig_uname)(struct utsname *);

static int stub_uname(struct utsname *buf) {
    int rc = orig_uname(buf);
    if (rc != 0 || !buf) return rc;
    IPFConfig *c = [IPFConfig shared];
    NSString *machine = IPFString(c.model[@"hw.machine"]) ?: IPFString(c.model[@"ProductType"]);
    NSString *node = IPFString(c.os[@"Hostname"]) ?: IPFString(c.os[@"kern.hostname"]);
    NSString *rel = IPFString(c.os[@"uname.release"]) ?: IPFString(c.os[@"OSRelease"]);
    if (machine) strlcpy(buf->machine, machine.UTF8String, sizeof(buf->machine));
    if (node) strlcpy(buf->nodename, node.UTF8String, sizeof(buf->nodename));
    if (rel) strlcpy(buf->release, rel.UTF8String, sizeof(buf->release));
    return rc;
}

#pragma mark - UIDevice / IDFA

static NSString *(*orig_UIDevice_name)(id, SEL);
static NSString *(*orig_UIDevice_model)(id, SEL);
static NSString *(*orig_UIDevice_systemVersion)(id, SEL);
static NSUUID *(*orig_UIDevice_identifierForVendor)(id, SEL);
static NSUUID *(*orig_ASId_advertisingIdentifier)(id, SEL);

static NSString *stub_UIDevice_name(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].uidevice[@"name"]);
    if (!v) v = IPFString([IPFConfig shared].model[@"UserAssignedDeviceName"]);
    return v ?: orig_UIDevice_name(self, _cmd);
}

static NSString *stub_UIDevice_model(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].uidevice[@"model"]);
    if (!v) v = IPFString([IPFConfig shared].model[@"DeviceName"]);
    return v ?: orig_UIDevice_model(self, _cmd);
}

static NSString *stub_UIDevice_systemVersion(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].uidevice[@"systemVersion"]);
    if (!v) v = IPFString([IPFConfig shared].os[@"ProductVersion"]);
    return v ?: orig_UIDevice_systemVersion(self, _cmd);
}

static NSUUID *stub_UIDevice_identifierForVendor(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].uidevice[@"identifierForVendor"]);
    if (!v) v = IPFString([IPFConfig shared].identity[@"IDFV"]);
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_UIDevice_identifierForVendor(self, _cmd);
}

static NSUUID *stub_ASId_advertisingIdentifier(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].identity[@"IDFA"]);
    if (v) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:v];
        if (u) return u;
    }
    return orig_ASId_advertisingIdentifier ? orig_ASId_advertisingIdentifier(self, _cmd) : nil;
}

static void IPFHookSymbol(const char *name, void *replace, void **original) {
    void *sym = dlsym(RTLD_DEFAULT, name);
    if (!sym) {
        NSLog(@"[iPFakerMG] missing symbol %s", name);
        return;
    }
    MSHookFunction(sym, replace, original);
    NSLog(@"[iPFakerMG] hooked %s", name);
}

void IPFInstallMGHooks(void) {
    IPFConfig *cfg = [IPFConfig shared];
    if (!cfg.loaded || !cfg.enabled) {
        NSLog(@"[iPFakerMG] skip (loaded=%d enabled=%d)", cfg.loaded, cfg.enabled);
        return;
    }

    IPFHookSymbol("MGCopyAnswer", (void *)stub_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
    IPFHookSymbol("MGCopyAnswerWithError", (void *)stub_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);
    IPFHookSymbol("sysctlbyname", (void *)stub_sysctlbyname, (void **)&orig_sysctlbyname);
    IPFHookSymbol("uname", (void *)stub_uname, (void **)&orig_uname);

    Class uid = objc_getClass("UIDevice");
    if (uid) {
        MSHookMessageEx(uid, @selector(name), (IMP)stub_UIDevice_name, (IMP *)&orig_UIDevice_name);
        MSHookMessageEx(uid, @selector(model), (IMP)stub_UIDevice_model, (IMP *)&orig_UIDevice_model);
        MSHookMessageEx(uid, @selector(systemVersion), (IMP)stub_UIDevice_systemVersion, (IMP *)&orig_UIDevice_systemVersion);
        MSHookMessageEx(uid, @selector(identifierForVendor), (IMP)stub_UIDevice_identifierForVendor, (IMP *)&orig_UIDevice_identifierForVendor);
    }

    Class asid = objc_getClass("ASIdentifierManager");
    if (asid) {
        MSHookMessageEx(asid, @selector(advertisingIdentifier), (IMP)stub_ASId_advertisingIdentifier, (IMP *)&orig_ASId_advertisingIdentifier);
    }

    NSLog(@"[iPFakerMG] ready profile=%@", cfg.profilePath);
}
