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
    if (strstr(path, "/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/private/var/jb/etc/ipfaker")) return YES;
    if (strstr(path, "/var/mobile/Library/iPFaker")) return YES;
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
        IPFJBTrace(@"fopen/getenv JB hide OK");
    }

    IPFJBTrace(@"IPFInstallJBHooks done");
}
