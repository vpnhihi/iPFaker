// Client mitigations for server-facing surfaces (NOT a full server bypass).
// NO hard CFNetwork link — string keys only (Dopamine AMFI/signature friendlier on JB).
// Packed in iPFakerJB after hide hooks.

#import "IPFHooksServer.h"
#import "IPFConfig.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);
static MSHookMessageEx_t pMSHookMessageExSV = NULL;

static void IPFSvTrace(NSString *s) {
    @try {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/ipfaker_extra.log"];
        NSString *row = [NSString stringWithFormat:@"%0.3f [Server] %@\n", CFAbsoluteTimeGetCurrent(), s];
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

#pragma mark - WebRTC ICE

static NSString *(*orig_iceCandidate)(id, SEL);
static NSString *stub_iceCandidate(id self, SEL _cmd) {
    NSString *real = orig_iceCandidate ? orig_iceCandidate(self, _cmd) : nil;
    if (!real) return real;
    @try {
        if ([[IPFConfig shared] flag:@"DisableWebRTC" defaultYes:NO]) {
            IPFSvTrace(@"WebRTC candidate blocked");
            return @"";
        }
        if (![[IPFConfig shared] flag:@"FakeWebRTC" defaultYes:NO]) return real;
        NSString *fakeIP = [[IPFConfig shared] stringForKey:@"WebRTCLocalIP"] ?: @"10.0.0.2";
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b" options:0 error:nil];
        if (!re) return real;
        NSString *out = [re stringByReplacingMatchesInString:real options:0
                                                       range:NSMakeRange(0, real.length)
                                                withTemplate:fakeIP];
        if (![out isEqualToString:real])
            IPFSvTrace([NSString stringWithFormat:@"WebRTC IP → %@", fakeIP]);
        return out;
    } @catch (__unused NSException *ex) {
        return real;
    }
}

#pragma mark - Proxy (string keys only — no CFNetwork link)

static BOOL IPFProxyOn(void) {
    return [[IPFConfig shared] flag:@"EnableProxy" defaultYes:NO]
        || [[IPFConfig shared] flag:@"FakeProxy" defaultYes:NO];
}

static NSDictionary *IPFProxyDictionary(void) {
    if (!IPFProxyOn()) return nil;
    NSString *host = [[IPFConfig shared] stringForKey:@"ProxyHost"];
    if (!host.length) return nil;
    NSInteger port = (NSInteger)[[IPFConfig shared] doubleForKey:@"ProxyPort" fallback:0];
    if (port <= 0) {
        NSString *ps = [[IPFConfig shared] stringForKey:@"ProxyPort"];
        port = ps.integerValue;
    }
    if (port <= 0 || port > 65535) return nil;
    NSString *type = ([[IPFConfig shared] stringForKey:@"ProxyType"] ?: @"HTTP").uppercaseString;
    NSString *user = [[IPFConfig shared] stringForKey:@"ProxyUsername"] ?: @"";
    NSString *pass = [[IPFConfig shared] stringForKey:@"ProxyPassword"] ?: @"";
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([type containsString:@"SOCKS"]) {
        // kCFStreamPropertySOCKS* as public string values (CFNetwork docs)
        d[@"SOCKSProxy"] = host;
        d[@"SOCKSPort"] = @(port);
        d[@"SOCKSEnable"] = @YES;
        if (user.length) {
            d[@"SOCKSUser"] = user;
            d[@"SOCKSPassword"] = pass;
        }
    } else {
        d[@"HTTPEnable"] = @YES;
        d[@"HTTPProxy"] = host;
        d[@"HTTPPort"] = @(port);
        d[@"HTTPSEnable"] = @YES;
        d[@"HTTPSProxy"] = host;
        d[@"HTTPSPort"] = @(port);
        if (user.length) {
            d[@"HTTPProxyUsername"] = user;
            d[@"HTTPProxyPassword"] = pass;
            d[@"HTTPSProxyUsername"] = user;
            d[@"HTTPSProxyPassword"] = pass;
        }
    }
    return d;
}

static NSDictionary *(*orig_connectionProxyDictionary)(id, SEL);
static NSDictionary *stub_connectionProxyDictionary(id self, SEL _cmd) {
    NSDictionary *forced = IPFProxyDictionary();
    if (forced) return forced;
    return orig_connectionProxyDictionary ? orig_connectionProxyDictionary(self, _cmd) : nil;
}

static void (*orig_setConnectionProxyDictionary)(id, SEL, NSDictionary *);
static void stub_setConnectionProxyDictionary(id self, SEL _cmd, NSDictionary *dict) {
    NSDictionary *forced = IPFProxyDictionary();
    if (forced) {
        if (orig_setConnectionProxyDictionary)
            orig_setConnectionProxyDictionary(self, _cmd, forced);
        return;
    }
    if (orig_setConnectionProxyDictionary)
        orig_setConnectionProxyDictionary(self, _cmd, dict);
}

#pragma mark - App Attest / DeviceCheck

static BOOL IPFDisableAppAttest(void) {
    // Lab default ON: block DeviceCheck/AppAttest tokens that bind host→server risk graph
    return [[IPFConfig shared] flag:@"DisableAppAttest" defaultYes:YES];
}

static void (*orig_attestGenerateKey)(id, SEL, id);
static void stub_attestGenerateKey(id self, SEL _cmd, id completion) {
    if (IPFDisableAppAttest()) {
        IPFSvTrace(@"AppAttest generateKey blocked");
        if (completion) {
            void (^cb)(id, id) = completion;
            NSError *err = [NSError errorWithDomain:@"DCErrorDomain" code:2
                                           userInfo:@{ NSLocalizedDescriptionKey: @"App Attest disabled (iPFaker)" }];
            cb(nil, err);
        }
        return;
    }
    if (orig_attestGenerateKey) orig_attestGenerateKey(self, _cmd, completion);
}

static void (*orig_attestKey)(id, SEL, id, id, id);
static void stub_attestKey(id self, SEL _cmd, id keyId, id hash, id completion) {
    if (IPFDisableAppAttest()) {
        IPFSvTrace(@"AppAttest attestKey blocked");
        if (completion) {
            void (^cb)(id, id) = completion;
            NSError *err = [NSError errorWithDomain:@"DCErrorDomain" code:2
                                           userInfo:@{ NSLocalizedDescriptionKey: @"App Attest disabled (iPFaker)" }];
            cb(nil, err);
        }
        return;
    }
    if (orig_attestKey) orig_attestKey(self, _cmd, keyId, hash, completion);
}

static void (*orig_attestAssertion)(id, SEL, id, id, id);
static void stub_attestAssertion(id self, SEL _cmd, id keyId, id hash, id completion) {
    if (IPFDisableAppAttest()) {
        IPFSvTrace(@"AppAttest assertion blocked");
        if (completion) {
            void (^cb)(id, id) = completion;
            NSError *err = [NSError errorWithDomain:@"DCErrorDomain" code:2
                                           userInfo:@{ NSLocalizedDescriptionKey: @"App Attest disabled (iPFaker)" }];
            cb(nil, err);
        }
        return;
    }
    if (orig_attestAssertion) orig_attestAssertion(self, _cmd, keyId, hash, completion);
}

static BOOL (*orig_attestIsSupported)(id, SEL);
static BOOL stub_attestIsSupported(id self, SEL _cmd) {
    if (IPFDisableAppAttest()) {
        IPFSvTrace(@"AppAttest isSupported → NO");
        return NO;
    }
    return orig_attestIsSupported ? orig_attestIsSupported(self, _cmd) : NO;
}

static void (*orig_dcGenerateToken)(id, SEL, id);
static void stub_dcGenerateToken(id self, SEL _cmd, id completion) {
    if (IPFDisableAppAttest()) {
        IPFSvTrace(@"DeviceCheck generateToken blocked");
        if (completion) {
            void (^cb)(id, id) = completion;
            NSError *err = [NSError errorWithDomain:@"DCErrorDomain" code:2
                                           userInfo:@{ NSLocalizedDescriptionKey: @"DeviceCheck disabled (iPFaker)" }];
            cb(nil, err);
        }
        return;
    }
    if (orig_dcGenerateToken) orig_dcGenerateToken(self, _cmd, completion);
}

static BOOL (*orig_dcSupported)(id, SEL);
static BOOL stub_dcSupported(id self, SEL _cmd) {
    if (IPFDisableAppAttest()) return NO;
    return orig_dcSupported ? orig_dcSupported(self, _cmd) : NO;
}

#pragma mark - Install

void IPFInstallServerHooks(void) {
    @try {
        if (!pMSHookMessageExSV) {
            void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
            if (!h) h = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
            if (h) pMSHookMessageExSV = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
            if (!pMSHookMessageExSV)
                pMSHookMessageExSV = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        }
        if (!pMSHookMessageExSV) {
            IPFSvTrace(@"IPFInstallServerHooks skip (no MSHook)");
            return;
        }
        IPFSvTrace(@"IPFInstallServerHooks begin");

        // WebRTC
        const char *rtcClasses[] = { "RTCIceCandidate", NULL };
        for (int i = 0; rtcClasses[i]; i++) {
            Class rc = objc_getClass(rtcClasses[i]);
            if (!rc) continue;
            if (class_getInstanceMethod(rc, @selector(sdp)))
                pMSHookMessageExSV(rc, @selector(sdp), (IMP)stub_iceCandidate, (IMP *)&orig_iceCandidate);
            IPFSvTrace(@"RTCIceCandidate hook OK");
            break;
        }

        // Proxy
        Class usc = objc_getClass("NSURLSessionConfiguration");
        if (usc) {
            if (class_getInstanceMethod(usc, @selector(connectionProxyDictionary)))
                pMSHookMessageExSV(usc, @selector(connectionProxyDictionary),
                                 (IMP)stub_connectionProxyDictionary, (IMP *)&orig_connectionProxyDictionary);
            if (class_getInstanceMethod(usc, @selector(setConnectionProxyDictionary:)))
                pMSHookMessageExSV(usc, @selector(setConnectionProxyDictionary:),
                                 (IMP)stub_setConnectionProxyDictionary, (IMP *)&orig_setConnectionProxyDictionary);
            IPFSvTrace(@"NSURLSessionConfiguration proxy OK");
        }

        // App Attest
        Class aas = objc_getClass("DCAppAttestService");
        if (aas) {
            SEL genKey = NSSelectorFromString(@"generateKeyWithCompletionHandler:");
            SEL attest = NSSelectorFromString(@"attestKey:clientDataHash:completionHandler:");
            SEL assertSel = NSSelectorFromString(@"generateAssertion:clientDataHash:completionHandler:");
            if (class_getInstanceMethod(aas, genKey))
                pMSHookMessageExSV(aas, genKey, (IMP)stub_attestGenerateKey, (IMP *)&orig_attestGenerateKey);
            if (class_getInstanceMethod(aas, attest))
                pMSHookMessageExSV(aas, attest, (IMP)stub_attestKey, (IMP *)&orig_attestKey);
            if (class_getInstanceMethod(aas, assertSel))
                pMSHookMessageExSV(aas, assertSel, (IMP)stub_attestAssertion, (IMP *)&orig_attestAssertion);
            if (class_getInstanceMethod(aas, @selector(isSupported)))
                pMSHookMessageExSV(aas, @selector(isSupported), (IMP)stub_attestIsSupported, (IMP *)&orig_attestIsSupported);
            Class aasMeta = object_getClass(aas);
            if (aasMeta && class_getInstanceMethod(aasMeta, @selector(isSupported)))
                pMSHookMessageExSV(aasMeta, @selector(isSupported), (IMP)stub_attestIsSupported, (IMP *)&orig_attestIsSupported);
            IPFSvTrace(@"DCAppAttestService hooks OK");
        }
        Class dcd = objc_getClass("DCDevice");
        if (dcd) {
            Class dcdMeta = object_getClass(dcd);
            SEL tok = NSSelectorFromString(@"generateTokenWithCompletionHandler:");
            if (class_getInstanceMethod(dcd, tok))
                pMSHookMessageExSV(dcd, tok, (IMP)stub_dcGenerateToken, (IMP *)&orig_dcGenerateToken);
            if (class_getInstanceMethod(dcd, @selector(isSupported)))
                pMSHookMessageExSV(dcd, @selector(isSupported), (IMP)stub_dcSupported, (IMP *)&orig_dcSupported);
            if (dcdMeta && class_getInstanceMethod(dcdMeta, @selector(isSupported)))
                pMSHookMessageExSV(dcdMeta, @selector(isSupported), (IMP)stub_dcSupported, (IMP *)&orig_dcSupported);
            IPFSvTrace(@"DCDevice hooks OK");
        }

        @try {
            NSString *row = @"MODULE IPFHooksServer: Proxy(string) · AppAttest/DeviceCheck · WebRTC private IP\n";
            NSString *home = NSHomeDirectory();
            if (home.length) {
                NSString *mp = [home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"];
                NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:mp];
                if (h) {
                    [h seekToEndOfFile];
                    [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
                    [h closeFile];
                } else {
                    [row writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        } @catch (__unused NSException *ex) {}

        IPFSvTrace(@"IPFInstallServerHooks done");
    } @catch (NSException *ex) {
        IPFSvTrace([NSString stringWithFormat:@"IPFInstallServerHooks EXC %@", ex.reason ?: @"?"]);
    }
}
