// Deep hooks (Plan B):
//  1) IOKit registry model strings
//  2) Rewrite HTTP body / URL query: iPhone11,6 → fake ProductType, D331pAP → HWModelStr
// Complements MG/sysctl hooks when Zalo caches or bypasses gestalt.

#import "IPFHooksDeep.h"
#import "IPFConfig.h"

#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>
#import <mach/mach.h>

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

// Soft-import IOKit types (avoid hard IOKit header dependency issues)
typedef mach_port_t io_object_t;
typedef io_object_t io_registry_entry_t;
typedef char io_name_t[128];
typedef uint32_t IOOptionBits;

static MSHookFunction_t pMSHookFunction = NULL;
static MSHookMessageEx_t pMSHookMessageEx = NULL;

static void IPFLog(NSString *s) {
    @try {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/ipfaker_trace.log"];
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

static NSString *IPFFakePT(void) {
    // Must come from active profile (any catalog device) — no fixed 15 Pro default
    NSString *pt = [[IPFConfig shared] mgValueForKey:@"ProductType"]
        ?: [[IPFConfig shared] stringForKey:@"ProductType"];
    return pt.length ? pt : nil;
}
static NSString *IPFFakeHW(void) {
    NSString *hw = [[IPFConfig shared] mgValueForKey:@"HWModelStr"]
        ?: [[IPFConfig shared] mgValueForKey:@"HardwareModel"]
        ?: [[IPFConfig shared] stringForKey:@"HWModelStr"];
    return hw.length ? hw : nil;
}

// Replace known real XS Max fingerprints in UTF-8 payloads
static NSData *IPFRewritePayload(NSData *data) {
    if (!data.length) return data;
    @autoreleasepool {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s) return data; // binary body — skip
        NSString *pt = IPFFakePT();
        NSString *hw = IPFFakeHW();
        // One-profile SoT: osv / ss / ProductVersion from same config as MG
        IPFConfig *cfg = [IPFConfig shared];
        NSString *osv = [cfg stringForKey:@"osv"]
            ?: [cfg stringForKey:@"ProductVersion"]
            ?: [cfg stringForKey:@"AnalyticsOsv"];
        NSString *ss = [cfg stringForKey:@"ss"]
            ?: [cfg stringForKey:@"AnalyticsSs"]
            ?: [cfg stringForKey:@"ScreenSizeString"];
        if (!ss.length) {
            NSString *nw = [cfg stringForKey:@"main-screen-width"];
            NSString *nh = [cfg stringForKey:@"main-screen-height"];
            if (nw.length && nh.length)
                ss = [NSString stringWithFormat:@"%@x%@", nw, nh];
        }
        if (!pt.length && !hw.length && !osv.length && !ss.length)
            return data; // no profile → do not rewrite to a fixed SKU
        NSString *out = s;
        BOOL changed = NO;
        // Rewrite common real fingerprints → current profile ProductType / board (any device)
        NSArray *realPT = @[
            @"iPhone7,1", @"iPhone7,2", @"iPhone8,1", @"iPhone8,2", @"iPhone8,4",
            @"iPhone9,1", @"iPhone9,2", @"iPhone9,3", @"iPhone9,4",
            @"iPhone10,1", @"iPhone10,2", @"iPhone10,3", @"iPhone10,4", @"iPhone10,5", @"iPhone10,6",
            @"iPhone11,2", @"iPhone11,4", @"iPhone11,6", @"iPhone11,8",
            @"iPhone12,1", @"iPhone12,3", @"iPhone12,5", @"iPhone12,8",
            @"iPhone13,1", @"iPhone13,2", @"iPhone13,3", @"iPhone13,4",
            @"iPhone14,2", @"iPhone14,3", @"iPhone14,4", @"iPhone14,5", @"iPhone14,6",
            @"iPhone14,7", @"iPhone14,8", @"iPhone15,2", @"iPhone15,3",
            @"iPhone15,4", @"iPhone15,5", @"iPhone16,1", @"iPhone16,2",
            @"iPhone17,1", @"iPhone17,2", @"iPhone17,3", @"iPhone17,4", @"iPhone17,5",
            @"iPhone18,1", @"iPhone18,2", @"iPhone18,3", @"iPhone18,4", @"iPhone18,5",
        ];
        NSArray *realHW = @[
            @"N61AP", @"N56AP", @"N71AP", @"N66AP", @"D10AP", @"D11AP",
            @"D20AP", @"D21AP", @"D22AP", @"N841AP", @"D321AP", @"D331pAP", @"D331AP",
            @"N104AP", @"D421AP", @"D431AP", @"D79AP",
            @"D52gAP", @"D53gAP", @"D53pAP", @"D54pAP",
            @"D16AP", @"D17AP", @"D63AP", @"D64AP", @"D49AP",
            @"D27AP", @"D28AP", @"D73AP", @"D74AP",
            @"D37AP", @"D38AP", @"D83AP", @"D84AP",
            @"D47AP", @"D48AP", @"D93AP", @"D94AP", @"D23AP",
        ];
        if (pt.length) {
            // Plain + URL-encoded (Zalo: data=%7B...iPhone9%2C1...) — one-profile SoT
            NSString *ptEnc = [pt stringByReplacingOccurrencesOfString:@"," withString:@"%2C"];
            NSString *ptEncLower = [pt stringByReplacingOccurrencesOfString:@"," withString:@"%2c"];
            for (NSString *r in realPT) {
                if ([r isEqualToString:pt]) continue;
                if ([out rangeOfString:r].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:r withString:pt];
                    changed = YES;
                }
                NSString *rEnc = [r stringByReplacingOccurrencesOfString:@"," withString:@"%2C"];
                NSString *rEncL = [r stringByReplacingOccurrencesOfString:@"," withString:@"%2c"];
                if (rEnc.length && ![rEnc isEqualToString:ptEnc] && [out rangeOfString:rEnc].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:rEnc withString:ptEnc];
                    changed = YES;
                }
                if (rEncL.length && ![rEncL isEqualToString:ptEncLower]
                    && [out rangeOfString:rEncL].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:rEncL withString:ptEncLower];
                    changed = YES;
                }
            }
        }
        if (hw.length) {
            for (NSString *r in realHW) {
                if ([r isEqualToString:hw]) continue;
                if ([out rangeOfString:r].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:r withString:hw];
                    changed = YES;
                }
            }
        }
        NSString *mk = [cfg mgValueForKey:@"MarketingName"];
        if (mk.length) {
            // Rewrite any common marketing names → current fake (incl. prior spoof names)
            NSArray *realNames = @[
                @"iPhone XS Max", @"iPhone Xs Max", @"iPhone XR",
                @"iPhone 11", @"iPhone 11 Pro", @"iPhone 11 Pro Max",
                @"iPhone 12", @"iPhone 12 mini", @"iPhone 12 Pro", @"iPhone 12 Pro Max",
                @"iPhone 13", @"iPhone 13 mini", @"iPhone 13 Pro", @"iPhone 13 Pro Max",
                @"iPhone 14", @"iPhone 14 Plus", @"iPhone 14 Pro", @"iPhone 14 Pro Max",
                @"iPhone 15", @"iPhone 15 Plus", @"iPhone 15 Pro", @"iPhone 15 Pro Max",
                @"iPhone 16", @"iPhone 16 Plus", @"iPhone 16 Pro", @"iPhone 16 Pro Max",
                @"iPhone 16e", @"iPhone 17", @"iPhone 17 Pro", @"iPhone 17 Pro Max", @"iPhone Air",
            ];
            for (NSString *rn in realNames) {
                if ([rn isEqualToString:mk]) continue;
                if ([out rangeOfString:rn].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:rn withString:mk];
                    changed = YES;
                }
            }
        }
        // ── Point 3 (lab): API spoof = body mạng spoof ─────────────────────
        // UIDevice/MG alone still fails: Zalo centralized sends mod/osv/ss in body.
        // Force-rewrite those fields to one-profile SoT whenever analytics-ish.
        BOOL analyticsish =
            [out rangeOfString:@"osv"].location != NSNotFound
            || [out rangeOfString:@"%22osv%22"].location != NSNotFound
            || [out rangeOfString:@"centralized"].location != NSNotFound
            || [out rangeOfString:@"deviceUUID"].location != NSNotFound
            || [out rangeOfString:@"deviceUUID" options:NSCaseInsensitiveSearch].location != NSNotFound
            || [out rangeOfString:@"mod="].location != NSNotFound
            || [out rangeOfString:@"%22mod%22"].location != NSNotFound
            || [out rangeOfString:@"\"mod\""].location != NSNotFound
            || [out rangeOfString:@"\"ss\""].location != NSNotFound
            || [out rangeOfString:@"%22ss%22"].location != NSNotFound
            || [out rangeOfString:@"zaloapp.com"].location != NSNotFound;

        // Force "mod" / mod= → profile ProductType (even if host PT not in realPT list)
        if (analyticsish && pt.length) {
            NSString *safeMod = [[pt componentsSeparatedByCharactersInSet:
                [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,"] invertedSet]]
                componentsJoinedByString:@""];
            if (!safeMod.length) safeMod = pt;
            NSString *modEnc = [safeMod stringByReplacingOccurrencesOfString:@"," withString:@"%2C"];
            NSRegularExpression *reModJson = [NSRegularExpression
                regularExpressionWithPattern:@"\"mod\"\\s*:\\s*\"[^\"]+\""
                                     options:0 error:nil];
            if (reModJson) {
                NSString *repl = [NSString stringWithFormat:@"\"mod\":\"%@\"", safeMod];
                NSString *tmp = [reModJson stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            NSRegularExpression *reModForm = [NSRegularExpression
                regularExpressionWithPattern:@"mod=iPhone[0-9,]+" options:0 error:nil];
            if (reModForm) {
                NSString *repl = [NSString stringWithFormat:@"mod=%@", safeMod];
                NSString *tmp = [reModForm stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            // URL-encoded: %22mod%22%3A%22iPhone9%2C1%22
            NSRegularExpression *reModPct = [NSRegularExpression
                regularExpressionWithPattern:@"%22mod%22%3A%22iPhone[^%\"&]+%22"
                                     options:NSRegularExpressionCaseInsensitive error:nil];
            if (reModPct) {
                NSString *repl = [NSString stringWithFormat:@"%%22mod%%22%%3A%%22%@%%22", modEnc];
                NSString *tmp = [reModPct stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
        }

        // Force "osv" → profile ProductVersion
        if (analyticsish && osv.length) {
            NSString *safeOsv = [[osv componentsSeparatedByCharactersInSet:
                [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]]
                componentsJoinedByString:@""];
            if (!safeOsv.length) safeOsv = osv;
            // Plain JSON: "osv":"15.8.4"
            NSRegularExpression *reOsvJson = [NSRegularExpression
                regularExpressionWithPattern:@"\"osv\"\\s*:\\s*\"[0-9.]+\""
                                     options:0 error:nil];
            if (reOsvJson) {
                NSString *repl = [NSString stringWithFormat:@"\"osv\":\"%@\"", safeOsv];
                NSString *tmp = [reOsvJson stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            // form: osv=15.8.4
            NSRegularExpression *reOsvForm = [NSRegularExpression
                regularExpressionWithPattern:@"osv=[0-9.]+" options:0 error:nil];
            if (reOsvForm) {
                NSString *repl = [NSString stringWithFormat:@"osv=%@", safeOsv];
                NSString *tmp = [reOsvForm stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            // URL-encoded JSON fragment: %22osv%22%3A%2215.8.4%22
            NSRegularExpression *reOsvPct = [NSRegularExpression
                regularExpressionWithPattern:@"%22osv%22%3A%22[0-9.]+%22"
                                     options:NSRegularExpressionCaseInsensitive error:nil];
            if (reOsvPct) {
                NSString *repl = [NSString stringWithFormat:@"%%22osv%%22%%3A%%22%@%%22", safeOsv];
                NSString *tmp = [reOsvPct stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
        }
        // Force "ss" → native WxH from profile
        if (analyticsish && ss.length) {
            NSString *safeSs = [[ss componentsSeparatedByCharactersInSet:
                [[NSCharacterSet characterSetWithCharactersInString:@"0123456789xX"] invertedSet]]
                componentsJoinedByString:@""];
            if (!safeSs.length) safeSs = ss;
            NSRegularExpression *reSsJson = [NSRegularExpression
                regularExpressionWithPattern:@"\"ss\"\\s*:\\s*\"[0-9]+x[0-9]+\""
                                     options:0 error:nil];
            if (reSsJson) {
                NSString *repl = [NSString stringWithFormat:@"\"ss\":\"%@\"", safeSs];
                NSString *tmp = [reSsJson stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            NSRegularExpression *reSsForm = [NSRegularExpression
                regularExpressionWithPattern:@"ss=[0-9]+x[0-9]+" options:0 error:nil];
            if (reSsForm) {
                NSString *repl = [NSString stringWithFormat:@"ss=%@", safeSs];
                NSString *tmp = [reSsForm stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
            NSRegularExpression *reSsPct = [NSRegularExpression
                regularExpressionWithPattern:@"%22ss%22%3A%22[0-9]+x[0-9]+%22"
                                     options:NSRegularExpressionCaseInsensitive error:nil];
            if (reSsPct) {
                NSString *repl = [NSString stringWithFormat:@"%%22ss%%22%%3A%%22%@%%22", safeSs];
                NSString *tmp = [reSsPct stringByReplacingMatchesInString:out options:0
                    range:NSMakeRange(0, out.length) withTemplate:repl];
                if (tmp && ![tmp isEqualToString:out]) { out = tmp; changed = YES; }
            }
        }
        if (changed) {
            IPFLog([NSString stringWithFormat:@"NET rewrite body len %lu → PT=%@ osv=%@ ss=%@",
                    (unsigned long)data.length, pt ?: @"?", osv ?: @"?", ss ?: @"?"]);
            return [out dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    return data;
}

#pragma mark - IOKit

static CFTypeRef (*orig_IORegCreate)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);
static CFTypeRef (*orig_IORegSearch)(io_registry_entry_t entry, const io_name_t plane, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);

static CFTypeRef IPFMaybeSpoofIOKitValue(CFStringRef key, CFTypeRef value) {
    if (!key || !value) return value;
    if (CFGetTypeID(value) != CFStringGetTypeID()) return value;
    @autoreleasepool {
        NSString *k = (__bridge NSString *)key;
        NSString *v = (__bridge NSString *)value;
        NSString *kl = k.lowercaseString;
        BOOL interesting =
            [kl containsString:@"model"] ||
            [kl containsString:@"product"] ||
            [kl containsString:@"machine"] ||
            [kl containsString:@"serial"] ||
            [kl isEqualToString:@"hw.model"] ||
            [kl isEqualToString:@"product-name"] ||
            [kl isEqualToString:@"model-number"] ||
            [kl isEqualToString:@"ioplatformserialnumber"] ||
            [kl isEqualToString:@"mlb-serial-number"];
        if (!interesting) return value;

        NSString *fake = nil;
        // Multi-source serial (identity sync):
        //  - IOPlatformSerialNumber / serial-number → SerialNumber
        //  - mlb-serial-number / MLBSerialNumber → MLBSerialNumber (≡ Serial in lab schema)
        //  - generic *serial* → SerialNumber
        if ([kl isEqualToString:@"mlb-serial-number"] || [kl isEqualToString:@"mlbserialnumber"]
            || [kl containsString:@"mlb"]) {
            fake = [[IPFConfig shared] mgValueForKey:@"MLBSerialNumber"]
                ?: [[IPFConfig shared] stringForKey:@"MLBSerialNumber"]
                ?: [[IPFConfig shared] mgValueForKey:@"SerialNumber"]
                ?: [[IPFConfig shared] stringForKey:@"SerialNumber"];
        } else if ([kl isEqualToString:@"ioplatformserialnumber"]
                   || [kl isEqualToString:@"serial-number"]
                   || [kl isEqualToString:@"serialnumber"]
                   || [kl containsString:@"serial"]) {
            fake = [[IPFConfig shared] mgValueForKey:@"IOPlatformSerialNumber"]
                ?: [[IPFConfig shared] stringForKey:@"IOPlatformSerialNumber"]
                ?: [[IPFConfig shared] mgValueForKey:@"SerialNumber"]
                ?: [[IPFConfig shared] stringForKey:@"SerialNumber"];
        } else if ([v hasPrefix:@"iPhone"] || [v rangeOfString:@"iPhone"].location != NSNotFound)
            fake = IPFFakePT();
        else if ([v containsString:@"D331"] || [kl containsString:@"model"])
            fake = IPFFakeHW();
        if (fake.length && ![fake isEqualToString:v]) {
            IPFLog([NSString stringWithFormat:@"IOKit FAKE %@ : %@ => %@", k, v, fake]);
            return CFBridgingRetain(fake);
        }
    }
    return value;
}

static CFTypeRef stub_IORegCreate(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    CFTypeRef r = orig_IORegCreate ? orig_IORegCreate(entry, key, allocator, options) : NULL;
    CFTypeRef s = IPFMaybeSpoofIOKitValue(key, r);
    if (s != r && r) CFRelease(r);
    return s;
}

static CFTypeRef stub_IORegSearch(io_registry_entry_t entry, const io_name_t plane, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    CFTypeRef r = orig_IORegSearch ? orig_IORegSearch(entry, plane, key, allocator, options) : NULL;
    CFTypeRef s = IPFMaybeSpoofIOKitValue(key, r);
    if (s != r && r) CFRelease(r);
    return s;
}

#pragma mark - NSURLRequest body + URL query rewrite (ProductType / HW)

static NSURL *IPFRewriteURL(NSURL *url) {
    if (!url) return url;
    @try {
        NSString *s = url.absoluteString;
        if (!s.length) return url;
        NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
        NSData *nd = IPFRewritePayload(d);
        if (!nd || nd == d) return url;
        NSString *ns = [[NSString alloc] initWithData:nd encoding:NSUTF8StringEncoding];
        if (!ns.length) return url;
        NSURL *nu = [NSURL URLWithString:ns];
        if (nu && ![nu.absoluteString isEqualToString:s]) {
            IPFLog([NSString stringWithFormat:@"NET rewrite URL query/path → fake model"]);
            return nu;
        }
    } @catch (__unused NSException *ex) {}
    return url;
}

static id IPFRewriteRequest(id req) {
    if (!req) return req;
    @try {
        if ([req isKindOfClass:[NSMutableURLRequest class]]) {
            NSMutableURLRequest *m = (NSMutableURLRequest *)req;
            NSURL *u = IPFRewriteURL(m.URL);
            if (u) m.URL = u;
            NSData *b = m.HTTPBody;
            NSData *nb = IPFRewritePayload(b);
            if (nb != b && nb) m.HTTPBody = nb;
            return m;
        }
        if ([req isKindOfClass:[NSURLRequest class]]) {
            NSURLRequest *r = (NSURLRequest *)req;
            NSURL *u = IPFRewriteURL(r.URL);
            NSData *b = r.HTTPBody;
            NSData *nb = IPFRewritePayload(b);
            BOOL urlCh = u && ![u.absoluteString isEqualToString:r.URL.absoluteString];
            BOOL bodyCh = nb && nb != b;
            if (urlCh || bodyCh) {
                NSMutableURLRequest *m = [r mutableCopy];
                if (urlCh) m.URL = u;
                if (bodyCh) m.HTTPBody = nb;
                return m;
            }
        }
    } @catch (__unused NSException *ex) {}
    return req;
}

static void (*orig_setHTTPBody)(id, SEL, NSData *);
static NSData *(*orig_HTTPBody)(id, SEL);
static void (*orig_setURL)(id, SEL, NSURL *);

static void stub_setHTTPBody(id self, SEL _cmd, NSData *body) {
    NSData *b = IPFRewritePayload(body);
    if (orig_setHTTPBody) orig_setHTTPBody(self, _cmd, b);
}

static NSData *stub_HTTPBody(id self, SEL _cmd) {
    NSData *b = orig_HTTPBody ? orig_HTTPBody(self, _cmd) : nil;
    return IPFRewritePayload(b);
}

static void stub_setURL(id self, SEL _cmd, NSURL *url) {
    if (orig_setURL) orig_setURL(self, _cmd, IPFRewriteURL(url));
}

// NSURLSession uploadTaskWithRequest:fromData:
static id (*orig_uploadFromData)(id, SEL, id, NSData *, id);
static id stub_uploadFromData(id self, SEL _cmd, id req, NSData *data, id comp) {
    req = IPFRewriteRequest(req);
    return orig_uploadFromData ? orig_uploadFromData(self, _cmd, req, IPFRewritePayload(data), comp) : nil;
}

static id (*orig_dataTaskReq)(id, SEL, id, id);
static id stub_dataTaskReq(id self, SEL _cmd, id req, id comp) {
    req = IPFRewriteRequest(req);
    return orig_dataTaskReq ? orig_dataTaskReq(self, _cmd, req, comp) : nil;
}

void IPFInstallDeepHooks(void) {
    IPFResolve();
    IPFLog(@"IPFInstallDeepHooks begin");

    // IOKit property spoof — only rewrites model/serial keys (see IPFMaybeSpoofIOKitValue).
    // Fail-soft: if symbols missing, HTTP rewrite still covers Zalo payloads.
    if (pMSHookFunction) {
        void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!io) io = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_NOW);
        void *c1 = io ? dlsym(io, "IORegistryEntryCreateCFProperty") : dlsym(RTLD_DEFAULT, "IORegistryEntryCreateCFProperty");
        void *c2 = io ? dlsym(io, "IORegistryEntrySearchCFProperty") : dlsym(RTLD_DEFAULT, "IORegistryEntrySearchCFProperty");
        if (c1) {
            pMSHookFunction(c1, (void *)stub_IORegCreate, (void **)&orig_IORegCreate);
            IPFLog(@"IORegistryEntryCreateCFProperty hooked");
        }
        if (c2) {
            pMSHookFunction(c2, (void *)stub_IORegSearch, (void **)&orig_IORegSearch);
            IPFLog(@"IORegistryEntrySearchCFProperty hooked");
        }
    }

    if (pMSHookMessageEx) {
        Class req = objc_getClass("NSMutableURLRequest");
        if (req) {
            pMSHookMessageEx(req, @selector(setHTTPBody:), (IMP)stub_setHTTPBody, (IMP *)&orig_setHTTPBody);
            if (class_getInstanceMethod(req, @selector(setURL:)))
                pMSHookMessageEx(req, @selector(setURL:), (IMP)stub_setURL, (IMP *)&orig_setURL);
            IPFLog(@"NSMutableURLRequest body+URL rewrite hooked");
        }
        Class ureq = objc_getClass("NSURLRequest");
        if (ureq) {
            pMSHookMessageEx(ureq, @selector(HTTPBody), (IMP)stub_HTTPBody, (IMP *)&orig_HTTPBody);
        }
        Class sess = objc_getClass("NSURLSession");
        if (sess) {
            SEL s1 = @selector(dataTaskWithRequest:completionHandler:);
            SEL s2 = @selector(uploadTaskWithRequest:fromData:completionHandler:);
            if (class_getInstanceMethod(sess, s1))
                pMSHookMessageEx(sess, s1, (IMP)stub_dataTaskReq, (IMP *)&orig_dataTaskReq);
            if (class_getInstanceMethod(sess, s2))
                pMSHookMessageEx(sess, s2, (IMP)stub_uploadFromData, (IMP *)&orig_uploadFromData);
            IPFLog(@"NSURLSession task hooks OK (body+query)");
        }
    }
    // Module cover marker
    @try {
        NSString *line =
            @"MODULE IPFHooksDeep: HTTP body/query ProductType/HW rewrite + IOKit serial/model\n";
        NSString *home = NSHomeDirectory();
        if (home.length) {
            NSString *p = [home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
            if (h) { [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
            else [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [line writeToFile:@"/var/mobile/Library/iPFaker/ipfaker_modules.log"
               atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused NSException *ex) {}
    IPFLog(@"IPFInstallDeepHooks done");
}
