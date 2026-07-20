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
    return [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"iPhone16,1";
}
static NSString *IPFFakeHW(void) {
    return [[IPFConfig shared] mgValueForKey:@"HWModelStr"]
        ?: [[IPFConfig shared] mgValueForKey:@"HardwareModel"]
        ?: @"D83AP";
}

// Replace known real XS Max fingerprints in UTF-8 payloads
static NSData *IPFRewritePayload(NSData *data) {
    if (!data.length) return data;
    @autoreleasepool {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s) return data; // binary body — skip
        NSString *pt = IPFFakePT();
        NSString *hw = IPFFakeHW();
        NSString *out = s;
        BOOL changed = NO;
        NSArray *pairs = @[
            @[ @"iPhone11,6", pt ],
            @[ @"iPhone11,4", pt ],
            @[ @"D331pAP", hw ],
            @[ @"D331AP", hw ],
        ];
        for (NSArray *p in pairs) {
            if ([out rangeOfString:p[0]].location != NSNotFound) {
                out = [out stringByReplacingOccurrencesOfString:p[0] withString:p[1]];
                changed = YES;
            }
        }
        // model_code / "mod" JSON style already covered by iPhone11,6 replace
        if (changed) {
            IPFLog([NSString stringWithFormat:@"NET rewrite body len %lu → fakePT=%@", (unsigned long)data.length, pt]);
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
            [kl isEqualToString:@"hw.model"] ||
            [kl isEqualToString:@"product-name"] ||
            [kl isEqualToString:@"model-number"];
        if (!interesting) return value;

        NSString *fake = nil;
        if ([v hasPrefix:@"iPhone"] || [v rangeOfString:@"iPhone"].location != NSNotFound)
            fake = IPFFakePT();
        else if ([v containsString:@"D331"] || [kl containsString:@"model"])
            fake = IPFFakeHW();
        if (fake && ![fake isEqualToString:v]) {
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

    // IOKit hooks deferred — can crash Zalo on cold path; HTTP rewrite is primary Plan B.
    (void)pMSHookFunction;
    (void)stub_IORegCreate;
    (void)stub_IORegSearch;

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
