// iPFakerAboutVer — ultra-tiny SystemVersion-only hook for Settings About software version.
// Separate from iPFakerAbout (MG/model) so AMFI size/signature stays independent.
// Reads ProductVersion/BuildVersion from dual-path config.plist (no IPFConfig.m link).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static MSHookFunction_t pMSHookFunction;
static MSHookMessageEx_t pMSHookMessageEx;

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
        ([[f lowercaseString] isEqualToString:@"0"] || [[f lowercaseString] isEqualToString:@"false"]))
        return NO;
    return YES;
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
    NSString *pv = [cfg[@"ProductVersion"] description];
    NSString *bv = [cfg[@"BuildVersion"] description] ?: [cfg[@"ProductBuildVersion"] description];
    if (!pv.length) return real;
    NSMutableDictionary *m = [real mutableCopy];
    m[@"ProductVersion"] = pv;
    m[@"ProductVersionExtra"] = @"";
    if (bv.length) {
        m[@"ProductBuildVersion"] = bv;
        m[@"BuildVersion"] = bv;
    }
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

#pragma mark - hooks

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
        NSString *pv = [cfg[@"ProductVersion"] description];
        if (pv.length) return pv;
    }
    return orig_sysVer ? orig_sysVer(self, _cmd) : @"15.0";
}

static NSOperatingSystemVersion (*orig_osv)(id, SEL);
static NSOperatingSystemVersion stub_osv(id self, SEL _cmd) {
    NSOperatingSystemVersion v = {15, 0, 0};
    NSDictionary *cfg = IPFVerLoadConfig();
    if (IPFVerEnabled(cfg)) {
        NSString *pv = [cfg[@"ProductVersion"] description] ?: @"15.0";
        NSArray *p = [pv componentsSeparatedByString:@"."];
        if (p.count > 0) v.majorVersion = [p[0] integerValue];
        if (p.count > 1) v.minorVersion = [p[1] integerValue];
        if (p.count > 2) v.patchVersion = [p[2] integerValue];
        return v;
    }
    return orig_osv ? orig_osv(self, _cmd) : v;
}

static CFDictionaryRef (*orig_CFCopySysVer)(void);
static CFDictionaryRef stub_CFCopySysVer(void) {
    CFDictionaryRef real = orig_CFCopySysVer ? orig_CFCopySysVer() : NULL;
    if (!real) return real;
    NSDictionary *ns = CFBridgingRelease(real);
    return CFBridgingRetain(IPFVerSpoofDict(ns));
}

static void IPFVerResolve(void) {
    if (pMSHookFunction) return;
    for (const char *lib in (const char *[]){
        "/var/jb/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
        NULL
    }) {
        void *h = dlopen(lib, RTLD_NOW);
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
            if (nspi && class_getInstanceMethod(nspi, @selector(operatingSystemVersion)))
                pMSHookMessageEx(nspi, @selector(operatingSystemVersion),
                                 (IMP)stub_osv, (IMP *)&orig_osv);
        }
        if (pMSHookFunction) {
            void *cf = dlsym(RTLD_DEFAULT, "CFCopySystemVersionDictionary");
            if (!cf) {
                void *h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
                if (h) cf = dlsym(h, "CFCopySystemVersionDictionary");
            }
            if (cf)
                pMSHookFunction(cf, (void *)stub_CFCopySysVer, (void **)&orig_CFCopySysVer);
        }
        IPFVerMark("CTOR_OK");
    }
}
