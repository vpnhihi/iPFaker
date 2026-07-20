// Extra spoof surface for Zalo:
//  - UIScreen nativeBounds / scale / nativeScale / maximumFramesPerSecond
//  - NSFileManager disk capacity / free
//  - access/stat/lstat hide jailbreak paths
//  - UIApplication canOpenURL block (cydia://, sileo://, …)
//  - WKWebView custom User-Agent (best-effort)
// Complements IPFHooksMG / CT / Deep. Keep defensive — never crash Zalo.

#import "IPFHooksExtra.h"
#import "IPFConfig.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/stat.h>
#import <string.h>

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

static CGFloat IPFScale(void) {
    id v = [[IPFConfig shared] stringForKey:@"main-screen-scale"]
        ?: [[IPFConfig shared] mgValueForKey:@"main-screen-scale"];
    if ([v respondsToSelector:@selector(doubleValue)]) return (CGFloat)[v doubleValue];
    return 3.0;
}

static CGSize IPFNativeSize(void) {
    id w = [[IPFConfig shared] stringForKey:@"main-screen-width"]
        ?: [[IPFConfig shared] mgValueForKey:@"main-screen-width"];
    id h = [[IPFConfig shared] stringForKey:@"main-screen-height"]
        ?: [[IPFConfig shared] mgValueForKey:@"main-screen-height"];
    CGFloat ww = [w respondsToSelector:@selector(doubleValue)] ? [w doubleValue] : 1179;
    CGFloat hh = [h respondsToSelector:@selector(doubleValue)] ? [h doubleValue] : 2556;
    return CGSizeMake(ww, hh);
}

static NSInteger IPFMaxFPS(void) {
    id v = [[IPFConfig shared] stringForKey:@"MaxRefreshHz"]
        ?: [[IPFConfig shared] mgValueForKey:@"MaxRefreshHz"];
    if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    return 60;
}

#pragma mark - UIScreen

static CGRect (*orig_nativeBounds)(id, SEL);
static CGFloat (*orig_scale)(id, SEL);
static CGFloat (*orig_nativeScale)(id, SEL);
static NSInteger (*orig_maxFPS)(id, SEL);
static CGRect (*orig_bounds)(id, SEL);

static CGRect stub_nativeBounds(id self, SEL _cmd) {
    CGSize s = IPFNativeSize();
    return CGRectMake(0, 0, s.width, s.height);
}
static CGFloat stub_scale(id self, SEL _cmd) {
    return IPFScale();
}
static CGFloat stub_nativeScale(id self, SEL _cmd) {
    return IPFScale();
}
static NSInteger stub_maxFPS(id self, SEL _cmd) {
    return IPFMaxFPS();
}
static CGRect stub_bounds(id self, SEL _cmd) {
    CGSize n = IPFNativeSize();
    CGFloat sc = IPFScale();
    if (sc < 1) sc = 1;
    return CGRectMake(0, 0, n.width / sc, n.height / sc);
}

#pragma mark - Disk

static NSDictionary *(*orig_attrs)(id, SEL, NSString *, NSError **);
static NSDictionary *stub_attrs(id self, SEL _cmd, NSString *path, NSError **err) {
    NSDictionary *real = orig_attrs ? orig_attrs(self, _cmd, path, err) : nil;
    if (!real) return real;
    @try {
        id total = [[IPFConfig shared] stringForKey:@"TotalDiskCapacity"]
            ?: [[IPFConfig shared] mgValueForKey:@"TotalDiskCapacity"];
        id freev = [[IPFConfig shared] stringForKey:@"FreeDiskSpace"]
            ?: [[IPFConfig shared] mgValueForKey:@"FreeDiskSpace"];
        if (!total && !freev) return real;
        NSMutableDictionary *m = [real mutableCopy];
        if (total) {
            long long t = [total longLongValue];
            if (t > 0) {
                m[NSFileSystemSize] = @(t);
                m[@"NSFileSystemSize"] = @(t);
            }
        }
        if (freev) {
            long long fr = [freev longLongValue];
            if (fr > 0) {
                m[NSFileSystemFreeSize] = @(fr);
                m[@"NSFileSystemFreeSize"] = @(fr);
            }
        }
        IPFExTrace([NSString stringWithFormat:@"disk attrs FAKE total=%@ free=%@", total, freev]);
        return m;
    } @catch (__unused NSException *ex) {
        return real;
    }
}

#pragma mark - Jailbreak path hide

static BOOL IPFIsJBPath(const char *path) {
    if (!path) return NO;
    // Default denylist + config jailbreak_hide.paths
    static const char *kDefault[] = {
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Applications/Installer.app",
        "/Library/MobileSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/TweakInject",
        "/var/jb",
        "/var/LIB",
        "/var/binpack",
        "/private/var/lib/cydia",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/.bootstrapped_electra",
        "/usr/lib/frida",
        "/usr/lib/libfrida",
        "FridaGadget",
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
                if (s.length && [p rangeOfString:s].location != NSNotFound) return YES;
            }
        }
    } @catch (__unused NSException *ex) {}
    return NO;
}

static int (*orig_access)(const char *, int);
static int stub_access(const char *path, int mode) {
    if (IPFIsJBPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access ? orig_access(path, mode) : -1;
}

static int (*orig_stat)(const char *, struct stat *);
static int stub_stat(const char *path, struct stat *buf) {
    if (IPFIsJBPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat ? orig_stat(path, buf) : -1;
}

static int (*orig_lstat)(const char *, struct stat *);
static int stub_lstat(const char *path, struct stat *buf) {
    if (IPFIsJBPath(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat ? orig_lstat(path, buf) : -1;
}

#pragma mark - canOpenURL

static BOOL (*orig_canOpen)(id, SEL, NSURL *);
static BOOL stub_canOpen(id self, SEL _cmd, NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString ?: @"";
    if ([s hasPrefix:@"cydia://"] || [s hasPrefix:@"sileo://"] || [s hasPrefix:@"zbra://"]
        || [s hasPrefix:@"filza://"] || [s hasPrefix:@"undecimus://"] || [s hasPrefix:@"activator://"]) {
        return NO;
    }
    return orig_canOpen ? orig_canOpen(self, _cmd, url) : NO;
}

#pragma mark - User-Agent (NSURLRequest)

static NSDictionary *(*orig_allHTTP)(id, SEL);
static NSDictionary *stub_allHTTP(id self, SEL _cmd) {
    NSDictionary *h = orig_allHTTP ? orig_allHTTP(self, _cmd) : nil;
    NSString *ua = [[IPFConfig shared] stringForKey:@"UserAgent"]
        ?: [[IPFConfig shared] stringForKey:@"HTTPUserAgent"];
    if (!ua.length) return h;
    NSMutableDictionary *m = h ? [h mutableCopy] : [NSMutableDictionary dictionary];
    m[@"User-Agent"] = ua;
    return m;
}

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
        if (fm && class_getInstanceMethod(fm, @selector(attributesOfFileSystemForPath:error:))) {
            pMSHookMessageEx(fm, @selector(attributesOfFileSystemForPath:error:),
                             (IMP)stub_attrs, (IMP *)&orig_attrs);
            IPFExTrace(@"NSFileManager disk hooks OK");
        }

        Class app = objc_getClass("UIApplication");
        if (app && class_getInstanceMethod(app, @selector(canOpenURL:))) {
            pMSHookMessageEx(app, @selector(canOpenURL:), (IMP)stub_canOpen, (IMP *)&orig_canOpen);
            IPFExTrace(@"canOpenURL hide JB URL schemes OK");
        }

        Class nreq = objc_getClass("NSURLRequest");
        if (nreq && class_getInstanceMethod(nreq, @selector(allHTTPHeaderFields))) {
            pMSHookMessageEx(nreq, @selector(allHTTPHeaderFields), (IMP)stub_allHTTP, (IMP *)&orig_allHTTP);
            IPFExTrace(@"NSURLRequest UA hook OK");
        }
    }

    if (pMSHookFunction) {
        void *a = dlsym(RTLD_DEFAULT, "access");
        if (a) pMSHookFunction(a, (void *)stub_access, (void **)&orig_access);
        void *st = dlsym(RTLD_DEFAULT, "stat");
        if (st) pMSHookFunction(st, (void *)stub_stat, (void **)&orig_stat);
        void *ls = dlsym(RTLD_DEFAULT, "lstat");
        if (ls) pMSHookFunction(ls, (void *)stub_lstat, (void **)&orig_lstat);
        IPFExTrace(@"access/stat/lstat JB hide OK");
    }

    IPFExTrace(@"IPFInstallExtraHooks done");
}
