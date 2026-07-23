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

#pragma mark - Keychain (HIOS-style SecItem) — spoof identity tokens + scrub host fingerprints

#import <Security/Security.h>

typedef OSStatus (*SecItemCopyMatching_t)(CFDictionaryRef, CFTypeRef *);
typedef OSStatus (*SecItemAdd_t)(CFDictionaryRef, CFTypeRef *);
typedef OSStatus (*SecItemUpdate_t)(CFDictionaryRef, CFDictionaryRef);
typedef OSStatus (*SecItemDelete_t)(CFDictionaryRef);
static SecItemCopyMatching_t o_SecCopy = NULL;
static SecItemAdd_t o_SecAdd = NULL;
static SecItemUpdate_t o_SecUpd = NULL;
static SecItemDelete_t o_SecDel = NULL;

static BOOL IPFLiteFakeAds(void) {
    return IPFLiteFlag(@"FakeAds", YES) || IPFLiteFlag(@"FakeDevice", YES);
}

static BOOL IPFLiteUUIDLike(NSString *s) {
    if (s.length != 36) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
                                                       options:0 error:nil];
    });
    return re && [re numberOfMatchesInString:s options:0 range:NSMakeRange(0, s.length)] > 0;
}

static NSString *IPFLiteWantIDFA(void) {
    NSString *v = IPFLiteStr(@"IDFA", nil) ?: IPFLiteStr(@"AdvertisingIdentifier", nil);
    return v.length ? v.uppercaseString : nil;
}
static NSString *IPFLiteWantIDFV(void) {
    NSString *v = IPFLiteStr(@"IDFV", nil) ?: IPFLiteStr(@"identifierForVendor", nil);
    return v.length ? v.uppercaseString : nil;
}

/// Agrp / svce / acct that carry device fingerprint for social apps (Zalo team + generic)
static BOOL IPFLiteSensitiveQuery(CFDictionaryRef query) {
    if (!query) return NO;
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSString *agrp = [q[(__bridge id)kSecAttrAccessGroup] description] ?: @"";
    NSString *svce = [q[(__bridge id)kSecAttrService] description] ?: @"";
    NSString *acct = [q[(__bridge id)kSecAttrAccount] description] ?: @"";
    NSString *blob = [[NSString stringWithFormat:@"%@ %@ %@", agrp, svce, acct] lowercaseString];
    if ([blob containsString:@"zalo"] || [blob containsString:@"zingalo"] || [blob containsString:@"vng.zalo"])
        return YES;
    if ([blob containsString:@"facebook"] || [blob containsString:@"instagram"] || [blob containsString:@"burbn"])
        return YES;
    if ([blob containsString:@"telegram"] || [blob containsString:@"telegra"] || [blob containsString:@"viber"])
        return YES;
    if ([blob containsString:@"device"] || [blob containsString:@"idfa"] || [blob containsString:@"idfv"]
        || [blob containsString:@"uuid"] || [blob containsString:@"advertising"] || [blob containsString:@"vendor"])
        return YES;
    if ([blob containsString:@"devicecheck"] || [blob containsString:@"appattest"] || [blob containsString:@"attest"])
        return YES;
    return NO;
}

static id IPFLiteRewriteIdentityValue(id val) {
    if (!IPFLiteFakeAds()) return val;
    NSString *idfa = IPFLiteWantIDFA();
    NSString *idfv = IPFLiteWantIDFV();
    if ([val isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)val;
        if (IPFLiteUUIDLike(s)) {
            // Prefer IDFA for first rewrite slot style; alternate unknown UUIDs → IDFV
            if (idfa.length) return idfa;
            if (idfv.length) return idfv;
        }
        return val;
    }
    if ([val isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:(NSData *)val encoding:NSUTF8StringEncoding];
        if (s.length && IPFLiteUUIDLike(s)) {
            NSString *repl = idfa.length ? idfa : idfv;
            if (repl.length)
                return [repl dataUsingEncoding:NSUTF8StringEncoding] ?: val;
        }
        return val;
    }
    if ([val isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *m = [((NSDictionary *)val) mutableCopy];
        for (id k in m.allKeys) {
            m[k] = IPFLiteRewriteIdentityValue(m[k]);
        }
        return m;
    }
    if ([val isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id x in (NSArray *)val)
            [a addObject:IPFLiteRewriteIdentityValue(x) ?: [NSNull null]];
        return a;
    }
    return val;
}

static OSStatus s_SecCopy(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus st = o_SecCopy ? o_SecCopy(query, result) : errSecUnimplemented;
    if (st != errSecSuccess || !result || !*result) return st;
    if (!IPFLiteFakeAds() && !IPFLiteDisableAA()) return st;
    @try {
        // Block App Attest / DeviceCheck keychain material when disabled
        if (IPFLiteDisableAA() && IPFLiteSensitiveQuery(query)) {
            NSDictionary *q = (__bridge NSDictionary *)query;
            NSString *blob = [[NSString stringWithFormat:@"%@ %@",
                               q[(__bridge id)kSecAttrService] ?: @"",
                               q[(__bridge id)kSecAttrAccount] ?: @""] lowercaseString];
            if ([blob containsString:@"attest"] || [blob containsString:@"devicecheck"]
                || [blob containsString:@"dcapp"] || [blob containsString:@"generatetoken"]) {
                if (*result) {
                    CFRelease(*result);
                    *result = NULL;
                }
                IPFLiteTrace(@"SecItemCopyMatching blocked attest/dc");
                return errSecItemNotFound;
            }
        }
        id rewritten = IPFLiteRewriteIdentityValue((__bridge id)(*result));
        if (rewritten && rewritten != (__bridge id)(*result)) {
            CFRelease(*result);
            *result = CFBridgingRetain(rewritten);
            IPFLiteTrace(@"SecItemCopyMatching identity rewrite");
        }
    } @catch (__unused NSException *ex) {}
    return st;
}

static OSStatus s_SecAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!o_SecAdd) return errSecUnimplemented;
    if (!IPFLiteFakeAds() || !attributes) return o_SecAdd(attributes, result);
    @try {
        NSDictionary *a = (__bridge NSDictionary *)attributes;
        id val = a[(__bridge id)kSecValueData] ?: a[(__bridge id)kSecValueRef];
        id nv = IPFLiteRewriteIdentityValue(val);
        if (nv && nv != val) {
            NSMutableDictionary *m = [a mutableCopy];
            if (a[(__bridge id)kSecValueData])
                m[(__bridge id)kSecValueData] = nv;
            IPFLiteTrace(@"SecItemAdd identity rewrite");
            return o_SecAdd((__bridge CFDictionaryRef)m, result);
        }
    } @catch (__unused NSException *ex) {}
    return o_SecAdd(attributes, result);
}

static OSStatus s_SecUpd(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!o_SecUpd) return errSecUnimplemented;
    if (!IPFLiteFakeAds() || !attributesToUpdate) return o_SecUpd(query, attributesToUpdate);
    @try {
        NSDictionary *a = (__bridge NSDictionary *)attributesToUpdate;
        id val = a[(__bridge id)kSecValueData];
        id nv = IPFLiteRewriteIdentityValue(val);
        if (nv && nv != val) {
            NSMutableDictionary *m = [a mutableCopy];
            m[(__bridge id)kSecValueData] = nv;
            IPFLiteTrace(@"SecItemUpdate identity rewrite");
            return o_SecUpd(query, (__bridge CFDictionaryRef)m);
        }
    } @catch (__unused NSException *ex) {}
    return o_SecUpd(query, attributesToUpdate);
}

static OSStatus s_SecDel(CFDictionaryRef query) {
    return o_SecDel ? o_SecDel(query) : errSecUnimplemented;
}

/// wipe_gen / explicit clear only — NEVER wipe every launch via fake_keychain.
/// (fake_keychain default YES + clearEvery crashed Zalo/FB/TG/iPFaker-related sessions.)
static void IPFLiteMaybeWipeKeychainOnLaunch(void) {
    @try {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (!bid.length) return;
        // fake_keychain = rewrite SecItem values only (hooks above). NOT purge-every-launch.
        BOOL clearEvery = IPFLiteFlag(@"ClearKeychainOnLaunch", NO)
            || IPFLiteFlag(@"keychainReset", NO);
        NSString *genPath = @"/var/mobile/Library/iPFaker/wipe_gen";
        NSString *seenPath = [NSString stringWithFormat:
            @"/var/mobile/Library/iPFaker/wipe_gen_seen/%@", bid];
        NSString *gen = [NSString stringWithContentsOfFile:genPath encoding:NSUTF8StringEncoding error:nil] ?: @"0";
        gen = [gen stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *dir = [seenPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *seen = [NSString stringWithContentsOfFile:seenPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
        seen = [seen stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL genBumped = gen.length && ![gen isEqualToString:seen];
        if (!clearEvery && !genBumped) return;

        // SecItemDelete for this bundle + known social agrp patterns
        NSArray *groups = @[
            bid,
            [NSString stringWithFormat:@"group.%@", bid],
            @"CVB6BX97VM.group.keychain.vn.com.vng.zalo",
            @"69V327AA4Z.group.viber.share.keychain",
        ];
        for (NSString *g in groups) {
            NSDictionary *q = @{
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrAccessGroup: g,
            };
            if (o_SecDel) o_SecDel((__bridge CFDictionaryRef)q);
            // also without agrp — match service containing bid
            NSDictionary *q2 = @{
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService: bid,
            };
            if (o_SecDel) o_SecDel((__bridge CFDictionaryRef)q2);
        }
        // Broad match via account/service like (best-effort)
        NSDictionary *qAll = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes: @YES,
        };
        CFTypeRef res = NULL;
        if (o_SecCopy && o_SecCopy((__bridge CFDictionaryRef)qAll, &res) == errSecSuccess && res) {
            NSArray *items = CFBridgingRelease(res);
            if ([items isKindOfClass:[NSArray class]]) {
                NSString *bl = bid.lowercaseString;
                for (NSDictionary *it in items) {
                    NSString *blob = [[NSString stringWithFormat:@"%@ %@ %@",
                                      it[(__bridge id)kSecAttrAccessGroup] ?: @"",
                                      it[(__bridge id)kSecAttrService] ?: @"",
                                      it[(__bridge id)kSecAttrAccount] ?: @""] lowercaseString];
                    if ([blob containsString:bl] || [blob containsString:@"zalo"]
                        || [blob containsString:@"zingalo"] || [blob containsString:@"facebook"]
                        || [blob containsString:@"instagram"] || [blob containsString:@"telegram"]
                        || [blob containsString:@"viber"] || [blob containsString:@"devicecheck"]
                        || [blob containsString:@"appattest"]) {
                        if (o_SecDel) o_SecDel((__bridge CFDictionaryRef)it);
                    }
                }
            }
        }
        [gen writeToFile:seenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        IPFLiteTrace([NSString stringWithFormat:@"wipeZaloKC/wipe_gen gen=%@ clearEvery=%d", gen, clearEvery ? 1 : 0]);
    } @catch (__unused NSException *ex) {}
}

static void IPFLiteInstallSecItem(void) {
    typedef void (*MSHookFunction_t)(void *, void *, void **);
    MSHookFunction_t pHF = NULL;
    void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
    if (!h) h = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
    if (h) pHF = (MSHookFunction_t)dlsym(h, "MSHookFunction");
    if (!pHF) pHF = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!pHF) { IPFLiteTrace(@"SecItem no MSHookFunction"); return; }
    void *pCopy = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    void *pAdd = dlsym(RTLD_DEFAULT, "SecItemAdd");
    void *pUpd = dlsym(RTLD_DEFAULT, "SecItemUpdate");
    void *pDel = dlsym(RTLD_DEFAULT, "SecItemDelete");
    if (pCopy) pHF(pCopy, (void *)s_SecCopy, (void **)&o_SecCopy);
    if (pAdd) pHF(pAdd, (void *)s_SecAdd, (void **)&o_SecAdd);
    if (pUpd) pHF(pUpd, (void *)s_SecUpd, (void **)&o_SecUpd);
    if (pDel) pHF(pDel, (void *)s_SecDel, (void **)&o_SecDel);
    IPFLiteTrace([NSString stringWithFormat:@"SecItem hooks copy=%p add=%p upd=%p", pCopy, pAdd, pUpd]);
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

            // DeviceCheck/AppAttest — install once only (multi MSHook = crash)
            void (^installAA)(void) = ^{
                static BOOL s_aaOnce = NO;
                if (s_aaOnce) return;
                s_aaOnce = YES;
                dlopen("/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck", RTLD_NOW);
                Class aas = objc_getClass("DCAppAttestService");
                if (aas) {
                    SEL genKey = NSSelectorFromString(@"generateKeyWithCompletionHandler:");
                    SEL attest = NSSelectorFromString(@"attestKey:clientDataHash:completionHandler:");
                    SEL asrt = NSSelectorFromString(@"generateAssertion:clientDataHash:completionHandler:");
                    if (class_getInstanceMethod(aas, genKey) && !o_genKey)
                        pMS(aas, genKey, (IMP)s_genKey, (IMP *)&o_genKey);
                    if (class_getInstanceMethod(aas, attest) && !o_attest)
                        pMS(aas, attest, (IMP)s_attest, (IMP *)&o_attest);
                    if (class_getInstanceMethod(aas, asrt) && !o_assert)
                        pMS(aas, asrt, (IMP)s_assert, (IMP *)&o_assert);
                    if (class_getInstanceMethod(aas, @selector(isSupported)) && !o_isSup)
                        pMS(aas, @selector(isSupported), (IMP)s_isSup, (IMP *)&o_isSup);
                    Class meta = object_getClass(aas);
                    if (meta && class_getInstanceMethod(meta, @selector(isSupported)) && !o_isSup)
                        pMS(meta, @selector(isSupported), (IMP)s_isSup, (IMP *)&o_isSup);
                    IPFLiteTrace(@"AppAttest OK");
                } else {
                    IPFLiteTrace(@"AppAttest class nil");
                    s_aaOnce = NO; // retry later if class loads late
                }
                Class dcd = objc_getClass("DCDevice");
                if (dcd) {
                    Class meta = object_getClass(dcd);
                    SEL tok = NSSelectorFromString(@"generateTokenWithCompletionHandler:");
                    if (class_getInstanceMethod(dcd, tok) && !o_dcTok)
                        pMS(dcd, tok, (IMP)s_dcTok, (IMP *)&o_dcTok);
                    if (class_getInstanceMethod(dcd, @selector(isSupported)) && !o_dcSup)
                        pMS(dcd, @selector(isSupported), (IMP)s_dcSup, (IMP *)&o_dcSup);
                    if (meta && class_getInstanceMethod(meta, @selector(isSupported)) && !o_dcSup)
                        pMS(meta, @selector(isSupported), (IMP)s_dcSup, (IMP *)&o_dcSup);
                    IPFLiteTrace(@"DeviceCheck OK");
                }
            };
            // Defer heavy work off %ctor — SecItem wipe every launch crashed Zalo/FB/TG
            void (^installRest)(void) = ^{
                static BOOL didRest = NO;
                if (didRest) return;
                didRest = YES;
                @try {
                    installAA();
                    IPFLiteInstallSecItem();
                    IPFLiteMaybeWipeKeychainOnLaunch();

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
                    IPFLiteTrace(@"ServerLite done (DC+SecItem+Proxy+WebRTC deferred)");
                } @catch (NSException *ex) {
                    IPFLiteTrace([NSString stringWithFormat:@"installRest EXC %@", ex.reason ?: @"?"]);
                }
            };
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), installRest);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), installAA);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), installAA);

            IPFLiteTrace(@"ServerLite scheduled (no sync wipe in ctor)");
            NSString *home = NSHomeDirectory();
            if (home.length) {
                NSString *row = @"MODULE IPFHooksServerLite: AppAttest · DeviceCheck · SecItem · Proxy · WebRTC\n";
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
