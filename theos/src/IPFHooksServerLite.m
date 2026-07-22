// Ultra-light Server mitigations WITHOUT IPFConfig.m (size for inject as own dylib).
// Reads dual-path config plists directly. AppAttest + Proxy string keys + WebRTC.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef void (*MSHookMessageEx_t)(Class, SEL, IMP, IMP *);
static MSHookMessageEx_t pMS = NULL;
static NSDictionary *gCfg = nil;

static void IPFLiteTrace(NSString *s) {
    @try {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/ipfaker_extra.log"];
        NSString *row = [NSString stringWithFormat:@"%0.3f [SV] %@\n", CFAbsoluteTimeGetCurrent(), s];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) [row writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else { [h seekToEndOfFile]; [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    } @catch (__unused NSException *ex) {}
}

static NSDictionary *IPFLiteCfg(void) {
    if (gCfg) return gCfg;
    NSArray *paths = @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count) { gCfg = d; break; }
    }
    if (!gCfg) gCfg = @{};
    return gCfg;
}

static BOOL IPFLiteFlag(NSString *k, BOOL def) {
    id v = IPFLiteCfg()[k];
    if (!v) return def;
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"yes"] || [s isEqualToString:@"true"] || [s isEqualToString:@"1"]) return YES;
        if ([s isEqualToString:@"no"] || [s isEqualToString:@"false"] || [s isEqualToString:@"0"]) return NO;
    }
    return def;
}

static NSString *IPFLiteStr(NSString *k, NSString *def) {
    id v = IPFLiteCfg()[k];
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return def;
}

// Lab default: block AppAttest/DeviceCheck (server risk graph binds host silicon)
static BOOL IPFLiteDisableAA(void) { return IPFLiteFlag(@"DisableAppAttest", YES); }

// --- AppAttest ---
static void (*o_genKey)(id, SEL, id);
static void s_genKey(id self, SEL _cmd, id completion) {
    if (IPFLiteDisableAA()) {
        IPFLiteTrace(@"AppAttest generateKey blocked");
        if (completion) {
            void (^cb)(id, id) = completion;
            cb(nil, [NSError errorWithDomain:@"DCErrorDomain" code:2 userInfo:@{NSLocalizedDescriptionKey:@"App Attest disabled"}]);
        }
        return;
    }
    if (o_genKey) o_genKey(self, _cmd, completion);
}
static BOOL (*o_isSup)(id, SEL);
static BOOL s_isSup(id self, SEL _cmd) {
    if (IPFLiteDisableAA()) { IPFLiteTrace(@"AppAttest isSupported→NO"); return NO; }
    return o_isSup ? o_isSup(self, _cmd) : NO;
}
static void (*o_attest)(id, SEL, id, id, id);
static void s_attest(id self, SEL _cmd, id a, id b, id c) {
    if (IPFLiteDisableAA()) {
        IPFLiteTrace(@"AppAttest attestKey blocked");
        if (c) { void (^cb)(id, id) = c; cb(nil, [NSError errorWithDomain:@"DCErrorDomain" code:2 userInfo:nil]); }
        return;
    }
    if (o_attest) o_attest(self, _cmd, a, b, c);
}
static void (*o_assert)(id, SEL, id, id, id);
static void s_assert(id self, SEL _cmd, id a, id b, id c) {
    if (IPFLiteDisableAA()) {
        if (c) { void (^cb)(id, id) = c; cb(nil, [NSError errorWithDomain:@"DCErrorDomain" code:2 userInfo:nil]); }
        return;
    }
    if (o_assert) o_assert(self, _cmd, a, b, c);
}
static void (*o_dcTok)(id, SEL, id);
static void s_dcTok(id self, SEL _cmd, id completion) {
    if (IPFLiteDisableAA()) {
        IPFLiteTrace(@"DeviceCheck token blocked");
        if (completion) { void (^cb)(id, id) = completion; cb(nil, [NSError errorWithDomain:@"DCErrorDomain" code:2 userInfo:nil]); }
        return;
    }
    if (o_dcTok) o_dcTok(self, _cmd, completion);
}
static BOOL (*o_dcSup)(id, SEL);
static BOOL s_dcSup(id self, SEL _cmd) {
    if (IPFLiteDisableAA()) return NO;
    return o_dcSup ? o_dcSup(self, _cmd) : NO;
}

// --- Proxy ---
static NSDictionary *IPFLiteProxy(void) {
    if (!IPFLiteFlag(@"EnableProxy", NO) && !IPFLiteFlag(@"FakeProxy", NO)) return nil;
    NSString *host = IPFLiteStr(@"ProxyHost", @"");
    if (!host.length) return nil;
    NSInteger port = IPFLiteStr(@"ProxyPort", @"0").integerValue;
    if (port <= 0) {
        id p = IPFLiteCfg()[@"ProxyPort"];
        if ([p respondsToSelector:@selector(integerValue)]) port = [p integerValue];
    }
    if (port <= 0 || port > 65535) return nil;
    NSString *type = [IPFLiteStr(@"ProxyType", @"HTTP") uppercaseString];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([type containsString:@"SOCKS"]) {
        d[@"SOCKSEnable"] = @YES; d[@"SOCKSProxy"] = host; d[@"SOCKSPort"] = @(port);
    } else {
        d[@"HTTPEnable"] = @YES; d[@"HTTPProxy"] = host; d[@"HTTPPort"] = @(port);
        d[@"HTTPSEnable"] = @YES; d[@"HTTPSProxy"] = host; d[@"HTTPSPort"] = @(port);
    }
    return d;
}
static NSDictionary *(*o_proxyGet)(id, SEL);
static NSDictionary *s_proxyGet(id self, SEL _cmd) {
    NSDictionary *f = IPFLiteProxy();
    return f ?: (o_proxyGet ? o_proxyGet(self, _cmd) : nil);
}
static void (*o_proxySet)(id, SEL, NSDictionary *);
static void s_proxySet(id self, SEL _cmd, NSDictionary *dict) {
    NSDictionary *f = IPFLiteProxy();
    if (f) { if (o_proxySet) o_proxySet(self, _cmd, f); return; }
    if (o_proxySet) o_proxySet(self, _cmd, dict);
}

// --- WebRTC ---
static NSString *(*o_ice)(id, SEL);
static NSString *s_ice(id self, SEL _cmd) {
    NSString *real = o_ice ? o_ice(self, _cmd) : nil;
    if (!real) return real;
    if (IPFLiteFlag(@"DisableWebRTC", NO)) return @"";
    if (!IPFLiteFlag(@"FakeWebRTC", NO)) return real;
    NSString *ip = IPFLiteStr(@"WebRTCLocalIP", @"10.0.0.2");
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b" options:0 error:nil];
    if (!re) return real;
    return [re stringByReplacingMatchesInString:real options:0 range:NSMakeRange(0, real.length) withTemplate:ip];
}

__attribute__((constructor))
static void IPFServerLiteCtor(void) {
    @autoreleasepool {
        @try {
            NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
            if ([bid isEqualToString:@"com.apple.Preferences"]) return;
            (void)IPFLiteCfg();
            void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
            if (!h) h = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
            if (h) pMS = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
            if (!pMS) pMS = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
            if (!pMS) { IPFLiteTrace(@"no MSHook"); return; }
            IPFLiteTrace(@"ServerLite begin");

            // DeviceCheck/AppAttest frameworks may load after first UIKit tick
            void (^installAA)(void) = ^{
                Class aas = objc_getClass("DCAppAttestService");
                if (!aas) {
                    // force-load DeviceCheck.framework
                    dlopen("/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck", RTLD_NOW);
                    aas = objc_getClass("DCAppAttestService");
                }
                if (aas) {
                    SEL genKey = NSSelectorFromString(@"generateKeyWithCompletionHandler:");
                    SEL attest = NSSelectorFromString(@"attestKey:clientDataHash:completionHandler:");
                    SEL asrt = NSSelectorFromString(@"generateAssertion:clientDataHash:completionHandler:");
                    if (class_getInstanceMethod(aas, genKey))
                        pMS(aas, genKey, (IMP)s_genKey, (IMP *)&o_genKey);
                    if (class_getInstanceMethod(aas, attest))
                        pMS(aas, attest, (IMP)s_attest, (IMP *)&o_attest);
                    if (class_getInstanceMethod(aas, asrt))
                        pMS(aas, asrt, (IMP)s_assert, (IMP *)&o_assert);
                    if (class_getInstanceMethod(aas, @selector(isSupported)))
                        pMS(aas, @selector(isSupported), (IMP)s_isSup, (IMP *)&o_isSup);
                    Class meta = object_getClass(aas);
                    if (meta && class_getInstanceMethod(meta, @selector(isSupported)))
                        pMS(meta, @selector(isSupported), (IMP)s_isSup, (IMP *)&o_isSup);
                    IPFLiteTrace(@"AppAttest OK");
                } else {
                    IPFLiteTrace(@"AppAttest class nil");
                }
                Class dcd = objc_getClass("DCDevice");
                if (dcd) {
                    SEL tok = NSSelectorFromString(@"generateTokenWithCompletionHandler:");
                    if (class_getInstanceMethod(dcd, tok))
                        pMS(dcd, tok, (IMP)s_dcTok, (IMP *)&o_dcTok);
                    if (class_getInstanceMethod(dcd, @selector(isSupported)))
                        pMS(dcd, @selector(isSupported), (IMP)s_dcSup, (IMP *)&o_dcSup);
                    Class meta = object_getClass(dcd);
                    if (meta && class_getInstanceMethod(meta, @selector(isSupported)))
                        pMS(meta, @selector(isSupported), (IMP)s_dcSup, (IMP *)&o_dcSup);
                    IPFLiteTrace(@"DeviceCheck OK");
                }
            };
            installAA();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), installAA);
            Class usc = objc_getClass("NSURLSessionConfiguration");
            if (usc) {
                if (class_getInstanceMethod(usc, @selector(connectionProxyDictionary)))
                    pMS(usc, @selector(connectionProxyDictionary), (IMP)s_proxyGet, (IMP *)&o_proxyGet);
                if (class_getInstanceMethod(usc, @selector(setConnectionProxyDictionary:)))
                    pMS(usc, @selector(setConnectionProxyDictionary:), (IMP)s_proxySet, (IMP *)&o_proxySet);
                IPFLiteTrace(@"Proxy OK");
            }
            Class rc = objc_getClass("RTCIceCandidate");
            if (rc && class_getInstanceMethod(rc, @selector(sdp)))
                pMS(rc, @selector(sdp), (IMP)s_ice, (IMP *)&o_ice);

            IPFLiteTrace(@"ServerLite done");
            NSString *home = NSHomeDirectory();
            if (home.length) {
                NSString *row = @"MODULE IPFHooksServerLite: AppAttest · Proxy · WebRTC (lite dylib)\n";
                NSString *mp = [home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"];
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:mp];
                if (fh) { [fh seekToEndOfFile]; [fh writeData:[row dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
                else [row writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        } @catch (NSException *ex) {
            IPFLiteTrace([NSString stringWithFormat:@"EXC %@", ex.reason ?: @"?"]);
        }
    }
}
