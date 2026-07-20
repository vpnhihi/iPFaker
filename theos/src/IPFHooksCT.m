// iPFakerCT — CoreTelephony carrier spoof (ChangeInfo-style CT dylib)
// Values from IPFConfig.telephony

#import "IPFHooksCT.h"
#import "IPFConfig.h"

#import <objc/runtime.h>
#import <substrate.h>

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

static NSString *stub_carrierName(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].telephony[@"CarrierName"]);
    return v ?: (orig_carrierName ? orig_carrierName(self, _cmd) : nil);
}

static NSString *stub_mobileCountryCode(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].telephony[@"MobileCountryCode"]);
    return v ?: (orig_mobileCountryCode ? orig_mobileCountryCode(self, _cmd) : nil);
}

static NSString *stub_mobileNetworkCode(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].telephony[@"MobileNetworkCode"]);
    return v ?: (orig_mobileNetworkCode ? orig_mobileNetworkCode(self, _cmd) : nil);
}

static NSString *stub_isoCountryCode(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].telephony[@"ISOCountryCode"]);
    return v ?: (orig_isoCountryCode ? orig_isoCountryCode(self, _cmd) : nil);
}

static BOOL stub_allowsVOIP(id self, SEL _cmd) {
    id v = [IPFConfig shared].telephony[@"AllowsVOIP"];
    if (v != nil) return [v boolValue];
    return orig_allowsVOIP ? orig_allowsVOIP(self, _cmd) : YES;
}

static NSString *stub_currentRadioAccessTechnology(id self, SEL _cmd) {
    NSString *v = IPFString([IPFConfig shared].telephony[@"CurrentRadioAccessTechnology"]);
    if (!v) v = IPFString([IPFConfig shared].telephony[@"RadioAccessTechnology"]);
    return v ?: (orig_currentRadioAccessTechnology ? orig_currentRadioAccessTechnology(self, _cmd) : nil);
}

void IPFInstallCTHooks(void) {
    IPFConfig *cfg = [IPFConfig shared];
    if (!cfg.loaded || !cfg.enabled) {
        NSLog(@"[iPFakerCT] skip (loaded=%d enabled=%d)", cfg.loaded, cfg.enabled);
        return;
    }

    Class carrier = objc_getClass("CTCarrier");
    if (carrier) {
        MSHookMessageEx(carrier, @selector(carrierName), (IMP)stub_carrierName, (IMP *)&orig_carrierName);
        MSHookMessageEx(carrier, @selector(mobileCountryCode), (IMP)stub_mobileCountryCode, (IMP *)&orig_mobileCountryCode);
        MSHookMessageEx(carrier, @selector(mobileNetworkCode), (IMP)stub_mobileNetworkCode, (IMP *)&orig_mobileNetworkCode);
        MSHookMessageEx(carrier, @selector(isoCountryCode), (IMP)stub_isoCountryCode, (IMP *)&orig_isoCountryCode);
        MSHookMessageEx(carrier, @selector(allowsVOIP), (IMP)stub_allowsVOIP, (IMP *)&orig_allowsVOIP);
        NSLog(@"[iPFakerCT] CTCarrier hooks OK");
    } else {
        NSLog(@"[iPFakerCT] CTCarrier class missing (ok inside some daemons until linked)");
    }

    Class info = objc_getClass("CTTelephonyNetworkInfo");
    if (info) {
        MSHookMessageEx(info, @selector(currentRadioAccessTechnology),
                        (IMP)stub_currentRadioAccessTechnology,
                        (IMP *)&orig_currentRadioAccessTechnology);
        NSLog(@"[iPFakerCT] CTTelephonyNetworkInfo RAT hook OK");
    }

    NSLog(@"[iPFakerCT] ready carrier=%@ mcc=%@ mnc=%@",
          IPFString(cfg.telephony[@"CarrierName"]),
          IPFString(cfg.telephony[@"MobileCountryCode"]),
          IPFString(cfg.telephony[@"MobileNetworkCode"]));
}
