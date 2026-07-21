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
        if (!pt.length && !hw.length) return data; // no profile → do not rewrite to a fixed SKU
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
            for (NSString *r in realPT) {
                if ([r isEqualToString:pt]) continue;
                if ([out rangeOfString:r].location != NSNotFound) {
                    out = [out stringByReplacingOccurrencesOfString:r withString:pt];
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
        NSString *mk = [[IPFConfig shared] mgValueForKey:@"MarketingName"];
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
        if (changed) {
            IPFLog([NSString stringWithFormat:@"NET rewrite body len %lu → fakePT=%@", (unsigned long)data.length, pt ?: @"(nil)"]);
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
        // Serial family — must match config SerialNumber (identity sync)
        if ([kl containsString:@"serial"]) {
            fake = [[IPFConfig shared] mgValueForKey:@"SerialNumber"]
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

#pragma mark - NSURLRequest body

static void (*orig_setHTTPBody)(id, SEL, NSData *);
static NSData *(*orig_HTTPBody)(id, SEL);

static void stub_setHTTPBody(id self, SEL _cmd, NSData *body) {
    NSData *b = IPFRewritePayload(body);
    if (orig_setHTTPBody) orig_setHTTPBody(self, _cmd, b);
}

static NSData *stub_HTTPBody(id self, SEL _cmd) {
    NSData *b = orig_HTTPBody ? orig_HTTPBody(self, _cmd) : nil;
    return IPFRewritePayload(b);
}

// NSURLSession uploadTaskWithRequest:fromData:
static id (*orig_uploadFromData)(id, SEL, id, NSData *, id);
static id stub_uploadFromData(id self, SEL _cmd, id req, NSData *data, id comp) {
    return orig_uploadFromData ? orig_uploadFromData(self, _cmd, req, IPFRewritePayload(data), comp) : nil;
}

static id (*orig_dataTaskReq)(id, SEL, id, id);
static id stub_dataTaskReq(id self, SEL _cmd, id req, id comp) {
    // request may already have body; try rewrite via mutable copy if possible
    @try {
        if ([req isKindOfClass:[NSMutableURLRequest class]]) {
            NSData *b = [(NSMutableURLRequest *)req HTTPBody];
            NSData *nb = IPFRewritePayload(b);
            if (nb != b && nb) [(NSMutableURLRequest *)req setHTTPBody:nb];
        } else if ([req isKindOfClass:[NSURLRequest class]]) {
            NSData *b = [(NSURLRequest *)req HTTPBody];
            NSData *nb = IPFRewritePayload(b);
            if (nb != b && nb) {
                NSMutableURLRequest *m = [(NSURLRequest *)req mutableCopy];
                [m setHTTPBody:nb];
                req = m;
            }
        }
    } @catch (__unused NSException *ex) {}
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
            IPFLog(@"NSMutableURLRequest setHTTPBody hooked");
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
            IPFLog(@"NSURLSession task hooks OK");
        }
    }
    IPFLog(@"IPFInstallDeepHooks done");
}
