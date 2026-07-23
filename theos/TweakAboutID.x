// iPFakerAboutID — lean Preferences UILabel wash for identity rows:
//   Tên / Số máy / Số sê-ri / EID / SEID / IDFA / IDFV (+ BB backup).
// Kept separate from AboutUI so proven AboutUI stays loadable.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static void IPFIDLog(NSString *line) {
    if (!line) return;
    NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), line];
    NSString *p = @"/var/mobile/Library/iPFaker/logs/ipfaker_aboutid.log";
    @try {
        [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
        if (!h) [row writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else {
            [h seekToEndOfFile];
            [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (__unused NSException *ex) {}
}

static void IPFIDMark(const char *msg) {
    NSString *body = [NSString stringWithFormat:@"%s\n", msg];
    [body writeToFile:@"/var/mobile/Library/iPFaker/v3_aboutid_loaded.txt"
           atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSDictionary *IPFIDConfig(void) {
    NSArray *paths = @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *best = nil;
    NSDate *bestDate = [NSDate distantPast];
    for (NSString *p in paths) {
        if (![fm isReadableFileAtPath:p]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:p error:nil];
        NSDate *mod = attrs[NSFileModificationDate] ?: [NSDate distantPast];
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (![d isKindOfClass:[NSDictionary class]] || !d.count) continue;
        BOOL newer = [mod compare:bestDate] == NSOrderedDescending;
        BOOL tieJb = [mod isEqualToDate:bestDate] && [p containsString:@"/var/jb/"];
        if (!best || newer || tieJb) {
            best = d;
            bestDate = mod;
        }
    }
    return best;
}

static BOOL IPFIDAllDigits(NSString *t) {
    if (!t.length) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

/// Serial: 10–14 alnum with at least one letter (exclude pure-digit IMEI 14–15).
static BOOL IPFIDIsSerial(NSString *t) {
    if (t.length < 10 || t.length > 14) return NO;
    if ([t rangeOfString:@"/"].location != NSNotFound) return NO;
    if ([t rangeOfString:@":"].location != NSNotFound) return NO;
    if ([t rangeOfString:@" "].location != NSNotFound) return NO;
    if ([t rangeOfString:@"-"].location != NSNotFound) return NO;
    if (IPFIDAllDigits(t)) return NO; // IMEI / MEID numeric
    BOOL letter = NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) letter = YES;
        else if (!(c >= '0' && c <= '9')) return NO;
    }
    return letter;
}

static BOOL IPFIDIsRegAxxxx(NSString *t) {
    // Host regulatory e.g. A1660
    if (t.length != 5) return NO;
    if ([t characterAtIndex:0] != 'A' && [t characterAtIndex:0] != 'a') return NO;
    for (NSUInteger i = 1; i < 5; i++) {
        unichar c = [t characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

static BOOL IPFIDIsModelNum(NSString *t) {
    if (!t.length || t.length > 18) return NO;
    if ([t rangeOfString:@":"].location != NSNotFound) return NO;
    if ([t rangeOfString:@" "].location != NSNotFound) return NO;
    if (IPFIDIsRegAxxxx(t)) return NO; // handled as regulatory
    if ([t rangeOfString:@"/"].location != NSNotFound) {
        if (t.length < 5) return NO;
        BOOL digit = NO;
        for (NSUInteger i = 0; i < t.length; i++) {
            unichar c = [t characterAtIndex:i];
            if (c >= '0' && c <= '9') digit = YES;
        }
        return digit;
    }
    if (t.length < 4 || t.length > 8) return NO;
    BOOL digit = NO, letter = NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c >= '0' && c <= '9') digit = YES;
        else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) letter = YES;
        else return NO;
    }
    return digit && letter;
}

static BOOL IPFIDIsEID(NSString *t) {
    return t.length == 32 && IPFIDAllDigits(t);
}

static BOOL IPFIDIsSEID(NSString *t) {
    if (t.length != 40) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
        if (!hex) return NO;
    }
    return YES;
}

static BOOL IPFIDIsUUID(NSString *t) {
    // 8-4-4-4-12
    if (t.length != 36) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
            regularExpressionWithPattern:
                @"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
                                 options:0 error:nil];
    });
    return re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

static BOOL IPFIDIsBaseband(NSString *t) {
    if (!t.length || t.length > 12) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
            regularExpressionWithPattern:@"^\\d{1,2}\\.\\d{2}\\.\\d{2}$"
                                 options:0 error:nil];
    });
    return re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

/// Host iOS tokens + real UIDevice — so Settings «Phiên bản iOS» syncs without AboutVer.
static BOOL IPFIDShouldReplaceVersion(NSString *t, NSString *wantPV) {
    if (!t.length || !wantPV.length) return NO;
    if ([t isEqualToString:wantPV]) return NO;
    static NSArray *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = @[
            @"14.0", @"14.1", @"14.2", @"14.3", @"14.4", @"14.5", @"14.6", @"14.7", @"14.8", @"14.8.1",
            @"15.0", @"15.1", @"15.2", @"15.3", @"15.4", @"15.5", @"15.6", @"15.7", @"15.8",
            @"15.8.1", @"15.8.2", @"15.8.3", @"15.8.4", @"15.8.5", @"15.8.6", @"15.8.7", @"15.8.8",
            @"16.0", @"16.1", @"16.2", @"16.3", @"16.4", @"16.5", @"16.6", @"16.7",
            @"16.7.1", @"16.7.2", @"16.7.3", @"16.7.4", @"16.7.5", @"16.7.6", @"16.7.7", @"16.7.8",
            @"16.7.9", @"16.7.10", @"16.7.11", @"16.7.12", @"16.7.16",
            @"17.0", @"17.1", @"17.2", @"17.3", @"17.4", @"17.5", @"17.6", @"17.7",
            @"18.0", @"18.1", @"18.2", @"18.3", @"18.4", @"18.5", @"18.6", @"18.7",
        ];
    });
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
    }
    @try {
        NSString *real = UIDevice.currentDevice.systemVersion;
        if (real.length && [t isEqualToString:real] && ![t isEqualToString:wantPV])
            return YES;
    } @catch (__unused NSException *ex) {}
    // bare X.Y / X.Y.Z pattern not equal want
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"^\\d{1,2}\\.\\d{1,2}(\\.\\d{1,2})?$" options:0 error:nil];
    if (re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0
        && ![t isEqualToString:wantPV] && t.length <= 10)
        return YES;
    return NO;
}

/// Host marketing names → spoof MarketingName (iPhone X → iPhone 7 Plus, etc.)
static BOOL IPFIDShouldReplaceModel(NSString *t, NSString *wantMk, NSString *wantName) {
    if (!t.length || !wantMk.length) return NO;
    if ([t isEqualToString:wantMk]) return NO;
    if (wantName.length && [t isEqualToString:wantName]) return NO;
    static NSArray *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = @[
            @"iPhone 6", @"iPhone 6s", @"iPhone 6s Plus",
            @"iPhone 7", @"iPhone 7 Plus",
            @"iPhone 8", @"iPhone 8 Plus",
            @"iPhone X", @"iPhone XR", @"iPhone XS", @"iPhone XS Max",
            @"iPhone 11", @"iPhone 11 Pro", @"iPhone 11 Pro Max",
            @"iPhone 12", @"iPhone 12 mini", @"iPhone 12 Pro", @"iPhone 12 Pro Max",
            @"iPhone 13", @"iPhone 13 mini", @"iPhone 13 Pro", @"iPhone 13 Pro Max",
            @"iPhone 14", @"iPhone 14 Plus", @"iPhone 14 Pro", @"iPhone 14 Pro Max",
            @"iPhone 15", @"iPhone 15 Plus", @"iPhone 15 Pro", @"iPhone 15 Pro Max",
            @"iPhone 16", @"iPhone 16 Plus", @"iPhone 16 Pro", @"iPhone 16 Pro Max", @"iPhone 16e",
            @"iPhone SE", @"iPhone SE (2nd generation)", @"iPhone SE (3rd generation)",
        ];
    });
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
        if (h.length >= 8 && [t hasPrefix:h] && t.length < h.length + 14
            && ![t isEqualToString:wantName])
            return YES;
    }
    if ([t hasPrefix:@"iPhone"] && t.length >= 8 && t.length <= 36
        && [t rangeOfString:@"/"].location == NSNotFound
        && [t rangeOfString:@"@"].location == NSNotFound) {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"^iPhone\\s+(SE|Air|\\d+e?|X[RS]?)(\\s+.*)?$"
                                 options:0 error:nil];
        if (re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0)
            return YES;
    }
    return NO;
}

static NSInteger gIPFIDUuidSlot = 0;

static NSInteger IPFIDWash(UIView *root,
                           NSString *wantName, NSString *wantMN, NSString *wantSN,
                           NSString *wantMk, NSString *wantReg,
                           NSString *wantEID, NSString *wantSEID,
                           NSString *wantIDFA, NSString *wantIDFV,
                           NSString *wantBB, NSString *wantPV) {
    if (!root) return 0;
    __block NSInteger n = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        void (^fix)(UILabel *) = ^(UILabel *lab) {
            if (![lab isKindOfClass:[UILabel class]]) return;
            NSString *t = lab.text;
            if (![t isKindOfClass:[NSString class]] || !t.length) return;
            if (wantName.length && [t isEqualToString:wantName]) return;
            if (wantMN.length && [t isEqualToString:wantMN]) return;
            if (wantSN.length && [t isEqualToString:wantSN]) return;
            if (wantMk.length && [t isEqualToString:wantMk]) return;
            if (wantReg.length && [t isEqualToString:wantReg]) return;
            if (wantPV.length && [t isEqualToString:wantPV]) return;
            if (wantEID.length && [t isEqualToString:wantEID]) return;
            if (wantSEID.length && [t caseInsensitiveCompare:wantSEID] == NSOrderedSame) return;
            if (wantIDFA.length && [t caseInsensitiveCompare:wantIDFA] == NSOrderedSame) return;
            if (wantIDFV.length && [t caseInsensitiveCompare:wantIDFV] == NSOrderedSame) return;
            if (wantBB.length && [t isEqualToString:wantBB]) return;

            // 1) Marketing name + iOS version FIRST (customer Settings sync — was AboutUI-only)
            if (wantPV.length && IPFIDShouldReplaceVersion(t, wantPV)) {
                lab.text = wantPV;
                n++;
                IPFIDLog([NSString stringWithFormat:@"ver %@ => %@", t, wantPV]);
                return;
            }
            if (wantMk.length && IPFIDShouldReplaceModel(t, wantMk, wantName)) {
                lab.text = wantMk;
                n++;
                IPFIDLog([NSString stringWithFormat:@"model %@ => %@", t, wantMk]);
                return;
            }

            // EID before serial (32 digits)
            if (wantEID.length && IPFIDIsEID(t)) {
                lab.text = wantEID;
                n++;
                IPFIDLog([NSString stringWithFormat:@"eid %@ => %@", t, wantEID]);
                return;
            }
            if (wantSEID.length && IPFIDIsSEID(t)) {
                lab.text = wantSEID;
                n++;
                IPFIDLog([NSString stringWithFormat:@"seid %@ => %@", t, wantSEID]);
                return;
            }
            if ((wantIDFA.length || wantIDFV.length) && IPFIDIsUUID(t)) {
                NSString *repl = nil;
                if (gIPFIDUuidSlot == 0 && wantIDFA.length) repl = wantIDFA;
                else if (wantIDFV.length) repl = wantIDFV;
                else if (wantIDFA.length) repl = wantIDFA;
                if (repl.length) {
                    lab.text = repl;
                    n++;
                    gIPFIDUuidSlot++;
                    IPFIDLog([NSString stringWithFormat:@"uuid %@ => %@", t, repl]);
                }
                return;
            }
            if (wantSN.length && IPFIDIsSerial(t)) {
                lab.text = wantSN;
                n++;
                IPFIDLog([NSString stringWithFormat:@"sn %@ => %@", t, wantSN]);
                return;
            }
            if (wantReg.length && IPFIDIsRegAxxxx(t)) {
                lab.text = wantReg;
                n++;
                IPFIDLog([NSString stringWithFormat:@"reg %@ => %@", t, wantReg]);
                return;
            }
            if (wantMN.length && IPFIDIsModelNum(t)) {
                lab.text = wantMN;
                n++;
                IPFIDLog([NSString stringWithFormat:@"mn %@ => %@", t, wantMN]);
                return;
            }
            if (wantName.length && [t isEqualToString:@"iPhone"]
                && ![wantName isEqualToString:@"iPhone"]) {
                lab.text = wantName;
                n++;
                IPFIDLog([NSString stringWithFormat:@"name %@ => %@", t, wantName]);
                return;
            }
            // Baseband backup; skip if equals ProductVersion
            if (wantBB.length && IPFIDIsBaseband(t)
                && !(wantPV.length && [t isEqualToString:wantPV])) {
                lab.text = wantBB;
                n++;
                IPFIDLog([NSString stringWithFormat:@"bb %@ => %@", t, wantBB]);
                return;
            }
        };
        if ([v isKindOfClass:[UILabel class]]) fix((UILabel *)v);
        if ([v respondsToSelector:@selector(detailTextLabel)]) {
            UILabel *d = ((UILabel *(*)(id, SEL))objc_msgSend)(v, @selector(detailTextLabel));
            fix(d);
        }
        if (v.subviews.count) [stack addObjectsFromArray:v.subviews];
    }
    return n;
}

static void IPFIDWashAll(void) {
    NSDictionary *cfg = IPFIDConfig();
    if (!cfg) return;
    id en = cfg[@"Enabled"];
    if ([en isKindOfClass:[NSNumber class]] && ![en boolValue]) return;

    NSString *wantName = [cfg[@"UserAssignedDeviceName"] description]
        ?: [cfg[@"DeviceName"] description] ?: @"";
    NSString *wantMN = [cfg[@"ModelNumber"] description]
        ?: [cfg[@"PartNumber"] description] ?: @"";
    NSString *wantSN = [cfg[@"SerialNumber"] description] ?: @"";
    NSString *wantMk = [cfg[@"MarketingName"] description] ?: @"";
    NSString *wantReg = [cfg[@"RegulatoryModelNumber"] description]
        ?: [cfg[@"ModelNumberAxxxx"] description] ?: @"";
    NSString *wantEID = [cfg[@"EID"] description] ?: @"";
    NSString *wantSEID = [cfg[@"SEID"] description]
        ?: [cfg[@"SecureElementID"] description] ?: @"";
    NSString *wantIDFA = [cfg[@"IDFA"] description]
        ?: [cfg[@"AdvertisingIdentifier"] description] ?: @"";
    NSString *wantIDFV = [cfg[@"IDFV"] description]
        ?: [cfg[@"identifierForVendor"] description] ?: @"";
    NSString *wantBB = [cfg[@"BasebandVersion"] description] ?: @"";
    NSString *wantPV = [cfg[@"ProductVersion"] description] ?: @"";

    if (!wantName.length && !wantMN.length && !wantSN.length
        && !wantMk.length && !wantPV.length
        && !wantEID.length && !wantSEID.length
        && !wantIDFA.length && !wantIDFV.length && !wantBB.length)
        return;

    gIPFIDUuidSlot = 0;
    NSInteger total = 0;
    NSArray *windows = nil;
    if (@available(iOS 13.0, *)) {
        NSMutableArray *ws = [NSMutableArray array];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows)
                [ws addObject:w];
        }
        windows = ws;
    }
    if (!windows.count) windows = UIApplication.sharedApplication.windows;
    for (UIWindow *w in windows) {
        total += IPFIDWash(w, wantName, wantMN, wantSN, wantMk, wantReg,
                           wantEID, wantSEID, wantIDFA, wantIDFV, wantBB, wantPV);
        UIViewController *r = w.rootViewController;
        if (r.view)
            total += IPFIDWash(r.view, wantName, wantMN, wantSN, wantMk, wantReg,
                               wantEID, wantSEID, wantIDFA, wantIDFV, wantBB, wantPV);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view)
                total += IPFIDWash(p.view, wantName, wantMN, wantSN, wantMk, wantReg,
                                   wantEID, wantSEID, wantIDFA, wantIDFV, wantBB, wantPV);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFIDLog([NSString stringWithFormat:
                  @"washed %ld name=%@ mk=%@ pv=%@ mn=%@ sn=%@ eid=%@ bb=%@",
                  (long)total, wantName, wantMk, wantPV, wantMN, wantSN,
                  wantEID.length ? @"Y" : @"-",
                  wantBB.length ? wantBB : @"-"]);
}

static void IPFIDSchedule(void) {
    for (NSNumber *d in @[ @0.4, @1.0, @2.0, @3.5, @5.5, @8.0, @12.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ IPFIDWashAll(); });
    }
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (![bid isEqualToString:@"com.apple.Preferences"]) {
            IPFIDMark("SKIP");
            return;
        }
        IPFIDMark("OK");
        IPFIDLog(@"AboutID ready");
        dispatch_async(dispatch_get_main_queue(), ^{ IPFIDSchedule(); });
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:nil
                    usingBlock:^(__unused NSNotification *n) { IPFIDSchedule(); }];
    }
}
