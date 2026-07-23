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
            if (wantEID.length && [t isEqualToString:wantEID]) return;
            if (wantSEID.length && [t caseInsensitiveCompare:wantSEID] == NSOrderedSame) return;
            if (wantIDFA.length && [t caseInsensitiveCompare:wantIDFA] == NSOrderedSame) return;
            if (wantIDFV.length && [t caseInsensitiveCompare:wantIDFV] == NSOrderedSame) return;
            if (wantBB.length && [t isEqualToString:wantBB]) return;

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
            // Baseband backup (AboutUI primary); skip if equals ProductVersion
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
                  @"washed %ld name=%@ mn=%@ sn=%@ eid=%@ seid=%@ idfa=%@ bb=%@",
                  (long)total, wantName, wantMN, wantSN,
                  wantEID.length ? @"Y" : @"-",
                  wantSEID.length ? @"Y" : @"-",
                  wantIDFA.length ? @"Y" : @"-",
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
