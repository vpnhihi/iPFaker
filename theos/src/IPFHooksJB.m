// Expanded JB surface (lab HideJailbreak) — second dylib next to MG.
// Core access/stat/lstat + canOpenURL stay in IPFHooksExtra (proven webview stack).
// Standards: POSIX fopen/getenv; NSFileManager fileExists*; DYLD_* env denylist (Apple dyld).

#import "IPFHooksJB.h"
#import "IPFConfig.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import <unistd.h>
#import <fcntl.h>
#import <sys/types.h>

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction = NULL;
static MSHookMessageEx_t pMSHookMessageEx = NULL;

static void IPFJBTrace(NSString *s) {
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

static void IPFJBResolve(void) {
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

static BOOL IPFJBAllowlisted(const char *path) {
    if (!path) return NO;
    // iPFaker config + our own dylibs/plists + constructor markers must never be blocked.
    // CRITICAL: strstr("ipfaker") does NOT match "iPFaker" (case). If JB loads before MG
    // alphabetically, open() hide would block TweakInject/iPFakerMG.dylib and kill MG inject.
    if (strstr(path, "ipfaker") || strstr(path, "iPFaker") || strstr(path, "IPFaker")) return YES;
    if (strstr(path, "v3_mg_loaded")) return YES;
    if (strstr(path, "v3_mg_debug")) return YES;
    if (strstr(path, "/var/jb/etc/ipfaker") || strstr(path, "/var/jb/etc/iPFaker")) return YES;
    if (strstr(path, "/private/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/var/mobile/Library/iPFaker")) return YES;
    if (strstr(path, "/var/jb/tmp/")) return YES;
    if (strstr(path, "/private/var/jb/tmp/")) return YES;
    // Own inject payloads (even if product rename changes case again)
    if (strstr(path, "TweakInject/") && strstr(path, "iPF")) return YES;
    return NO;
}

// Same denylist family as Extra (catalog paths + active_profile jailbreak_hide.paths)
static BOOL IPFJBIsJBPath(const char *path) {
    if (path == NULL || path[0] == '\0') return NO;
    if (![[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) return NO;
    if (IPFJBAllowlisted(path)) return NO;

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
    if (n >= 24) return;
    n++;
    IPFJBTrace([NSString stringWithFormat:@"JBhide %s block %s", api, path ? path : "(null)"]);
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *stub_fopen(const char *path, const char *mode) {
    if (IPFJBIsJBPath(path)) {
        IPFJBHideLogOnce("fopen", path);
        errno = ENOENT;
        return NULL;
    }
    return orig_fopen ? orig_fopen(path, mode) : NULL;
}

static char *(*orig_getenv)(const char *);
static char *stub_getenv(const char *name) {
    if (!name) return orig_getenv ? orig_getenv(name) : NULL;
    if (![[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES])
        return orig_getenv ? orig_getenv(name) : NULL;
    // dyld(1) / Apple env surfaces used by injectors
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
    if (path.length && IPFJBIsJBPath(path.UTF8String)) {
        IPFJBHideLogOnce("fileExists", path.UTF8String);
        return NO;
    }
    return orig_fileExists ? orig_fileExists(self, _cmd, path) : NO;
}

static BOOL (*orig_fileExistsIsDir)(id, SEL, NSString *, BOOL *);
static BOOL stub_fileExistsIsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (path.length && IPFJBIsJBPath(path.UTF8String)) {
        IPFJBHideLogOnce("fileExists:isDir", path.UTF8String);
        if (isDir) *isDir = NO;
        return NO;
    }
    return orig_fileExistsIsDir ? orig_fileExistsIsDir(self, _cmd, path, isDir) : NO;
}

// POSIX open / openat — second path after access/stat for JB probes.
// ARM64: third arg (mode) always in register — use fixed 3-arg form (substrate-safe).
typedef int (*open_fn_t)(const char *, int, mode_t);
typedef int (*openat_fn_t)(int, const char *, int, mode_t);
static open_fn_t orig_open = NULL;
static openat_fn_t orig_openat = NULL;

static int stub_open(const char *path, int flags, mode_t mode) {
    if (IPFJBIsJBPath(path)) {
        IPFJBHideLogOnce("open", path);
        errno = ENOENT;
        return -1;
    }
    return orig_open ? orig_open(path, flags, mode) : -1;
}

static int stub_openat(int fd, const char *path, int flags, mode_t mode) {
    if (IPFJBIsJBPath(path)) {
        IPFJBHideLogOnce("openat", path);
        errno = ENOENT;
        return -1;
    }
    return orig_openat ? orig_openat(fd, path, flags, mode) : -1;
}

#pragma mark - dyldHide (HIOS) — hide JB images from dyld enumeration

#import <mach-o/dyld.h>

static BOOL IPFJBIsHiddenImagePath(const char *path) {
    if (!path || !path[0]) return NO;
    if (IPFJBAllowlisted(path)) return NO; // never hide our own dylibs
    static const char *kHide[] = {
        "TweakInject", "MobileSubstrate", "CydiaSubstrate", "libsubstrate",
        "libellekit", "ellekit", "substitute", "libhooker",
        "frida", "FridaGadget", "cynject", "libcycript",
        "/var/jb/", "/private/var/jb/",
        NULL
    };
    for (int i = 0; kHide[i]; i++) {
        if (strstr(path, kHide[i])) {
            // Still allow our own product path under TweakInject
            if (strstr(path, "iPFaker") || strstr(path, "ipfaker")) return NO;
            return YES;
        }
    }
    return NO;
}

static uint32_t (*orig_dyld_image_count)(void) = NULL;
static const char *(*orig_dyld_get_image_name)(uint32_t) = NULL;
static const struct mach_header *(*orig_dyld_get_image_header)(uint32_t) = NULL;
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t) = NULL;

// Map visible index → real dyld index (skip hidden)
static uint32_t IPFJBMapVisibleToReal(uint32_t vis) {
    if (!orig_dyld_image_count || !orig_dyld_get_image_name) return vis;
    uint32_t realCount = orig_dyld_image_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < realCount; i++) {
        const char *n = orig_dyld_get_image_name(i);
        if (IPFJBIsHiddenImagePath(n)) continue;
        if (seen == vis) return i;
        seen++;
    }
    return realCount; // OOB
}

static uint32_t stub_dyld_image_count(void) {
    if (!orig_dyld_image_count || !orig_dyld_get_image_name)
        return orig_dyld_image_count ? orig_dyld_image_count() : 0;
    uint32_t realCount = orig_dyld_image_count();
    uint32_t vis = 0;
    for (uint32_t i = 0; i < realCount; i++) {
        const char *n = orig_dyld_get_image_name(i);
        if (!IPFJBIsHiddenImagePath(n)) vis++;
    }
    return vis;
}

static const char *stub_dyld_get_image_name(uint32_t image_index) {
    if (!orig_dyld_get_image_name) return NULL;
    uint32_t real = IPFJBMapVisibleToReal(image_index);
    return orig_dyld_get_image_name(real);
}

static const struct mach_header *stub_dyld_get_image_header(uint32_t image_index) {
    if (!orig_dyld_get_image_header) return NULL;
    uint32_t real = IPFJBMapVisibleToReal(image_index);
    return orig_dyld_get_image_header(real);
}

static intptr_t stub_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    if (!orig_dyld_get_image_vmaddr_slide) return 0;
    uint32_t real = IPFJBMapVisibleToReal(image_index);
    return orig_dyld_get_image_vmaddr_slide(real);
}

#pragma mark - fork block (HIOS)

static pid_t (*orig_fork)(void) = NULL;
static pid_t (*orig_vfork)(void) = NULL;

static pid_t stub_fork(void) {
    if ([[IPFConfig shared] flag:@"BlockFork" defaultYes:YES]
        || [[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) {
        IPFJBTrace(@"fork blocked");
        errno = EPERM;
        return -1;
    }
    return orig_fork ? orig_fork() : -1;
}

static pid_t stub_vfork(void) {
    if ([[IPFConfig shared] flag:@"BlockFork" defaultYes:YES]
        || [[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) {
        IPFJBTrace(@"vfork blocked");
        errno = EPERM;
        return -1;
    }
    return orig_vfork ? orig_vfork() : -1;
}

void IPFInstallJBHooks(void) {
    IPFJBResolve();
    if (![[IPFConfig shared] flag:@"HideJailbreak" defaultYes:YES]) {
        IPFJBTrace(@"IPFInstallJBHooks skip (HideJailbreak off)");
        return;
    }
    IPFJBTrace(@"IPFInstallJBHooks begin");

    if (pMSHookMessageEx) {
        Class fm = objc_getClass("NSFileManager");
        if (fm) {
            if (class_getInstanceMethod(fm, @selector(fileExistsAtPath:))) {
                pMSHookMessageEx(fm, @selector(fileExistsAtPath:),
                                 (IMP)stub_fileExists, (IMP *)&orig_fileExists);
            }
            if (class_getInstanceMethod(fm, @selector(fileExistsAtPath:isDirectory:))) {
                pMSHookMessageEx(fm, @selector(fileExistsAtPath:isDirectory:),
                                 (IMP)stub_fileExistsIsDir, (IMP *)&orig_fileExistsIsDir);
            }
            IPFJBTrace(@"NSFileManager fileExists JB hide OK");
        }
    }

    if (pMSHookFunction) {
        void *fo = dlsym(RTLD_DEFAULT, "fopen");
        if (fo) pMSHookFunction(fo, (void *)stub_fopen, (void **)&orig_fopen);
        void *ge = dlsym(RTLD_DEFAULT, "getenv");
        if (ge) pMSHookFunction(ge, (void *)stub_getenv, (void **)&orig_getenv);
        void *op = dlsym(RTLD_DEFAULT, "open");
        if (op) pMSHookFunction(op, (void *)stub_open, (void **)&orig_open);
        void *oa = dlsym(RTLD_DEFAULT, "openat");
        if (oa) pMSHookFunction(oa, (void *)stub_openat, (void **)&orig_openat);

        // dyldHide
        void *dic = dlsym(RTLD_DEFAULT, "_dyld_image_count");
        void *din = dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
        void *dih = dlsym(RTLD_DEFAULT, "_dyld_get_image_header");
        void *dis = dlsym(RTLD_DEFAULT, "_dyld_get_image_vmaddr_slide");
        if (dic) pMSHookFunction(dic, (void *)stub_dyld_image_count, (void **)&orig_dyld_image_count);
        if (din) pMSHookFunction(din, (void *)stub_dyld_get_image_name, (void **)&orig_dyld_get_image_name);
        if (dih) pMSHookFunction(dih, (void *)stub_dyld_get_image_header, (void **)&orig_dyld_get_image_header);
        if (dis) pMSHookFunction(dis, (void *)stub_dyld_get_image_vmaddr_slide, (void **)&orig_dyld_get_image_vmaddr_slide);
        IPFJBTrace([NSString stringWithFormat:@"dyldHide cnt=%p name=%p", dic, din]);

        // fork block
        void *fk = dlsym(RTLD_DEFAULT, "fork");
        void *vf = dlsym(RTLD_DEFAULT, "vfork");
        if (fk) pMSHookFunction(fk, (void *)stub_fork, (void **)&orig_fork);
        if (vf) pMSHookFunction(vf, (void *)stub_vfork, (void **)&orig_vfork);
        IPFJBTrace([NSString stringWithFormat:@"fork blocked=%p", fk]);

        IPFJBTrace(@"fopen/getenv/open/openat JB hide OK");
    }

    IPFJBTrace(@"IPFInstallJBHooks done");
}
