// iPFakerCT — CoreTelephony carrier spoof (split-stack CT dylib)
// Values from IPFConfig.telephony — CTCarrier + radio + CommCenter inject via filter

#import "IPFHooksCT.h"
#import "IPFConfig.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);
static MSHookMessageEx_t pMSHookMessageExCT;

static NSString *IPFString(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

static NSString *(*orig_carrierName)(id, SEL);
static NSString *(*orig_mobileCountryCode)(id, SEL);
static NSString *(*orig_mobileNetworkCode)(id, SEL);
static NSString *(*orig_isoCountryCode)(id, SEL);
static BOOL (*orig_allowsVOIP)(id, SEL);
static NSString *(*orig_currentRadioAccessTechnology)(id, SEL);
static id (*orig_subscriberCellularProvider)(id, SEL);
static NSDictionary *(*orig_serviceSubscriberCellularProviders)(id, SEL);
static NSDictionary *(*orig_serviceCurrentRadioAccessTechnology)(id, SEL);

static BOOL IPFNetOn(void) {
    return [[IPFConfig shared] flag:@"FakeNetwork" defaultYes:YES];
}

static NSDictionary *IPFTel(void) {
    return [IPFConfig shared].telephony ?: @{};
}

static NSString *stub_carrierName(id self, SEL _cmd) {
    if (!IPFNetOn()) return orig_carrierName ? orig_carrierName(self, _cmd) : nil;
    // ITU E.212 / CTCarrier — name display string
    NSString *v = IPFString(IPFTel()[@"CarrierName"]);
    return v ?: (orig_carrierName ? orig_carrierName(self, _cmd) : nil);
}

static NSString *stub_mobileCountryCode(id self, SEL _cmd) {
    if (!IPFNetOn()) return orig_mobileCountryCode ? orig_mobileCountryCode(self, _cmd) : nil;
    // ITU-T E.212 MCC (3 digits) — VN = 452
    NSString *v = IPFString(IPFTel()[@"MobileCountryCode"]);
    return v ?: (orig_mobileCountryCode ? orig_mobileCountryCode(self, _cmd) : nil);
}

static NSString *stub_mobileNetworkCode(id self, SEL _cmd) {
    if (!IPFNetOn()) return orig_mobileNetworkCode ? orig_mobileNetworkCode(self, _cmd) : nil;
    // ITU-T E.212 MNC — Viettel 04
    NSString *v = IPFString(IPFTel()[@"MobileNetworkCode"]);
    return v ?: (orig_mobileNetworkCode ? orig_mobileNetworkCode(self, _cmd) : nil);
}

static NSString *stub_isoCountryCode(id self, SEL _cmd) {
    if (!IPFNetOn()) return orig_isoCountryCode ? orig_isoCountryCode(self, _cmd) : nil;
    // ISO 3166-1 alpha-2 lowercase (CTCarrier convention)
    NSString *v = IPFString(IPFTel()[@"ISOCountryCode"]);
    return v ?: (orig_isoCountryCode ? orig_isoCountryCode(self, _cmd) : nil);
}

static BOOL stub_allowsVOIP(id self, SEL _cmd) {
    if (!IPFNetOn()) return orig_allowsVOIP ? orig_allowsVOIP(self, _cmd) : YES;
    id v = IPFTel()[@"AllowsVOIP"];
    if (v != nil) return [v boolValue];
    return orig_allowsVOIP ? orig_allowsVOIP(self, _cmd) : YES;
}

static NSString *IPFRadioTech(void) {
    NSString *v = IPFString(IPFTel()[@"CurrentRadioAccessTechnology"]);
    if (!v) v = IPFString(IPFTel()[@"RadioAccessTechnology"]);
    // Apple CTRadioAccessTechnology* constant strings
    return v.length ? v : @"CTRadioAccessTechnologyNR";
}

static NSString *stub_currentRadioAccessTechnology(id self, SEL _cmd) {
    if (!IPFNetOn())
        return orig_currentRadioAccessTechnology ? orig_currentRadioAccessTechnology(self, _cmd) : nil;
    return IPFRadioTech();
}

// Legacy single-SIM accessor — returns CTCarrier (instance methods hooked above)
static id stub_subscriberCellularProvider(id self, SEL _cmd) {
    id real = orig_subscriberCellularProvider ? orig_subscriberCellularProvider(self, _cmd) : nil;
    // If nil (no SIM) but FakeNetwork on, still return real nil — CTCarrier hooks apply when non-nil
    return real;
}

// iOS 12+ multi-SIM: NSDictionary <NSString*, CTCarrier*>
static NSDictionary *stub_serviceSubscriberCellularProviders(id self, SEL _cmd) {
    NSDictionary *real = orig_serviceSubscriberCellularProviders
        ? orig_serviceSubscriberCellularProviders(self, _cmd) : nil;
    if (!IPFNetOn()) return real;
    // Carriers in dict are CTCarrier — method hooks apply when apps read MCC/MNC/ISO/name
    return real;
}

// iOS 12+ radio per service: NSDictionary <NSString*, NSString* tech>
static NSDictionary *stub_serviceCurrentRadioAccessTechnology(id self, SEL _cmd) {
    if (!IPFNetOn())
        return orig_serviceCurrentRadioAccessTechnology
            ? orig_serviceCurrentRadioAccessTechnology(self, _cmd) : nil;
    NSDictionary *real = orig_serviceCurrentRadioAccessTechnology
        ? orig_serviceCurrentRadioAccessTechnology(self, _cmd) : nil;
    NSString *tech = IPFRadioTech();
    if (real.count) {
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:real.count];
        for (id k in real) m[k] = tech;
        return m;
    }
    // No services reported — synthesize one entry so apps see NR/LTE spoof
    return @{ @"0000000100000001": tech };
}

static void IPFCTLogSurface(void) {
    @try {
        NSDictionary *t = IPFTel();
        NSString *line = [NSString stringWithFormat:
            @"SURFACE Carrier: name=%@ MCC=%@ MNC=%@ ISO=%@ radio=%@ FakeNetwork=%d CommCenterFilter=ON\n",
            t[@"CarrierName"] ?: @"?",
            t[@"MobileCountryCode"] ?: @"?",
            t[@"MobileNetworkCode"] ?: @"?",
            t[@"ISOCountryCode"] ?: @"?",
            IPFRadioTech(),
            IPFNetOn() ? 1 : 0];
        NSString *home = NSHomeDirectory();
        if (home.length) {
            NSString *p = [home stringByAppendingPathComponent:@"Documents/ipfaker_surfaces.log"];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
            if (h) { [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
            else [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [line writeToFile:@"/var/mobile/Library/iPFaker/ipfaker_surfaces.log"
               atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[iPFakerCT] %@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
    } @catch (__unused NSException *ex) {}
}

void IPFInstallCTHooks(void) {
    static BOOL s_ctOnce = NO;
    if (s_ctOnce) return;
    IPFConfig *cfg = [IPFConfig shared];
    if (!cfg.loaded || !cfg.enabled) {
        NSLog(@"[iPFakerCT] skip (loaded=%d enabled=%d)", cfg.loaded, cfg.enabled);
        return;
    }
    s_ctOnce = YES;

    if (!pMSHookMessageExCT) {
        void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
        if (h) pMSHookMessageExCT = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
        if (!pMSHookMessageExCT)
            pMSHookMessageExCT = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    }
    if (!pMSHookMessageExCT) {
        NSLog(@"[iPFakerCT] MSHookMessageEx missing");
        return;
    }

    Class carrier = objc_getClass("CTCarrier");
    if (carrier) {
        pMSHookMessageExCT(carrier, @selector(carrierName), (IMP)stub_carrierName, (IMP *)&orig_carrierName);
        pMSHookMessageExCT(carrier, @selector(mobileCountryCode), (IMP)stub_mobileCountryCode, (IMP *)&orig_mobileCountryCode);
        pMSHookMessageExCT(carrier, @selector(mobileNetworkCode), (IMP)stub_mobileNetworkCode, (IMP *)&orig_mobileNetworkCode);
        pMSHookMessageExCT(carrier, @selector(isoCountryCode), (IMP)stub_isoCountryCode, (IMP *)&orig_isoCountryCode);
        pMSHookMessageExCT(carrier, @selector(allowsVOIP), (IMP)stub_allowsVOIP, (IMP *)&orig_allowsVOIP);
        NSLog(@"[iPFakerCT] CTCarrier hooks OK (name/MCC/MNC/ISO/VOIP)");
    }

    Class info = objc_getClass("CTTelephonyNetworkInfo");
    if (info) {
        if (class_getInstanceMethod(info, @selector(currentRadioAccessTechnology)))
            pMSHookMessageExCT(info, @selector(currentRadioAccessTechnology),
                            (IMP)stub_currentRadioAccessTechnology,
                            (IMP *)&orig_currentRadioAccessTechnology);
        // Legacy single provider
        SEL subSel = @selector(subscriberCellularProvider);
        if (class_getInstanceMethod(info, subSel))
            pMSHookMessageExCT(info, subSel, (IMP)stub_subscriberCellularProvider,
                            (IMP *)&orig_subscriberCellularProvider);
        // Multi-SIM dictionaries (iOS 12+)
        SEL svcProv = NSSelectorFromString(@"serviceSubscriberCellularProviders");
        if (class_getInstanceMethod(info, svcProv))
            pMSHookMessageExCT(info, svcProv, (IMP)stub_serviceSubscriberCellularProviders,
                            (IMP *)&orig_serviceSubscriberCellularProviders);
        SEL svcRadio = NSSelectorFromString(@"serviceCurrentRadioAccessTechnology");
        if (class_getInstanceMethod(info, svcRadio))
            pMSHookMessageExCT(info, svcRadio, (IMP)stub_serviceCurrentRadioAccessTechnology,
                            (IMP *)&orig_serviceCurrentRadioAccessTechnology);
        NSLog(@"[iPFakerCT] CTTelephonyNetworkInfo radio/providers OK");
    }

    IPFCTLogSurface();
}
