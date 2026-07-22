// iPFakerAboutUI — Preferences-only UILabel wash for Settings → About.
// Syncs host UI text to dual-path config SoT (version, model, name protect,
// Wi‑Fi / Bluetooth MAC, EID, SEID, BasebandVersion).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void IPFUIMark(const char *msg) {
    NSString *body = [NSString stringWithFormat:@"%s\n", msg];
    [body writeToFile:@"/var/mobile/Library/iPFaker/v3_aboutui_loaded.txt"
           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [body writeToFile:@"/var/mobile/Documents/v3_aboutui_loaded.txt"
           atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void IPFUILog(NSString *line) {
    if (!line) return;
    NSString *row = [NSString stringWithFormat:@"%0.3f %@\n", CFAbsoluteTimeGetCurrent(), line];
    NSString *p = @"/var/mobile/Library/iPFaker/logs/ipfaker_aboutui.log";
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

static NSDictionary *IPFUIConfig(void) {
    // Newest mtime wins; jb preferred on tie
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
        if (![d isKindOfClass:[NSDictionary class]] || !d[@"ProductVersion"]) continue;
        BOOL newer = [mod compare:bestDate] == NSOrderedDescending;
        BOOL tieJb = [mod isEqualToDate:bestDate] && [p containsString:@"/var/jb/"];
        if (!best || newer || tieJb) {
            best = d;
            bestDate = mod;
        }
    }
    return best;
}

static BOOL IPFUIEnabled(NSDictionary *cfg) {
    if (!cfg) return NO;
    id en = cfg[@"Enabled"];
    if ([en isKindOfClass:[NSNumber class]] && ![en boolValue]) return NO;
    return YES;
}

static NSArray<NSString *> *IPFUIHostVersionTokens(void) {
    return @[
        @"14.0", @"14.1", @"14.2", @"14.3", @"14.4", @"14.5", @"14.6", @"14.7", @"14.8", @"14.8.1",
        @"15.0", @"15.1", @"15.2", @"15.3", @"15.4", @"15.5", @"15.5.0", @"15.6", @"15.7",
        @"15.7.1", @"15.7.2", @"15.7.3", @"15.7.4", @"15.7.5", @"15.7.6", @"15.7.7", @"15.7.8", @"15.7.9",
        @"15.8", @"15.8.1", @"15.8.2", @"15.8.3", @"15.8.4", @"15.8.5",
        @"16.0", @"16.1", @"16.1.1", @"16.1.2", @"16.2", @"16.3", @"16.3.1", @"16.4", @"16.4.1",
        @"16.5", @"16.5.1", @"16.6", @"16.6.1", @"16.7", @"16.7.1", @"16.7.2", @"16.7.3",
        @"16.7.4", @"16.7.5", @"16.7.6", @"16.7.7", @"16.7.8", @"16.7.9",
        @"16.7.10", @"16.7.11", @"16.7.12", @"16.7.16",
        @"17.0", @"17.0.1", @"17.0.2", @"17.0.3", @"17.1", @"17.1.1", @"17.1.2",
        @"17.2", @"17.2.1", @"17.3", @"17.3.1", @"17.4", @"17.4.1", @"17.5", @"17.5.1",
        @"17.6", @"17.6.1", @"17.7", @"17.7.1", @"17.7.2",
        @"18.0", @"18.0.1", @"18.1", @"18.1.1", @"18.2", @"18.2.1", @"18.3", @"18.3.1", @"18.3.2",
        @"18.4", @"18.4.1", @"18.5", @"18.6", @"18.6.1", @"18.6.2", @"18.7", @"18.7.1", @"18.7.2",
        @"18.7.9",
    ];
}

static BOOL IPFUIShouldReplaceVersion(NSString *t, NSString *wantPV, NSArray *hosts) {
    if (!t.length || !wantPV.length) return NO;
    if ([t isEqualToString:wantPV]) return NO;
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
    }
    @try {
        NSString *real = UIDevice.currentDevice.systemVersion;
        if (real.length && [t isEqualToString:real] && ![t isEqualToString:wantPV])
            return YES;
    } @catch (__unused NSException *ex) {}
    return NO;
}

static BOOL IPFUIShouldReplaceModel(NSString *t, NSString *wantMk, NSString *wantName) {
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

static BOOL IPFUIIsMAC(NSString *t) {
    if (t.length != 17) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
            regularExpressionWithPattern:@"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
                                 options:0 error:nil];
    });
    return re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

static BOOL IPFUIIsEID(NSString *t) {
    if (t.length != 32) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

static BOOL IPFUIIsSEID(NSString *t) {
    if (t.length != 40) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
        if (!ok) return NO;
    }
    return YES;
}

static BOOL IPFUIIsBaseband(NSString *t) {
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

// macSlot: 0 → next host MAC becomes Wifi, 1 → BT (Settings row order)
static NSInteger gIPFUIMacSlot = 0;

static NSInteger IPFUIWashView(UIView *root,
                               NSString *wantPV, NSString *wantMk, NSString *wantName,
                               NSString *wantWifi, NSString *wantBT,
                               NSString *wantEID, NSString *wantSEID, NSString *wantBB,
                               NSArray *hostVers) {
    if (!root) return 0;
    __block NSInteger n = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        void (^fixLabel)(UILabel *) = ^(UILabel *lab) {
            if (![lab isKindOfClass:[UILabel class]]) return;
            NSString *t = lab.text;
            if (![t isKindOfClass:[NSString class]] || !t.length) return;
            if (wantName.length && [t isEqualToString:wantName]) return;

            if (wantPV.length && IPFUIShouldReplaceVersion(t, wantPV, hostVers)) {
                lab.text = wantPV;
                n++;
                IPFUILog([NSString stringWithFormat:@"label ver %@ => %@", t, wantPV]);
                return;
            }
            if (wantMk.length && IPFUIShouldReplaceModel(t, wantMk, wantName)) {
                lab.text = wantMk;
                n++;
                IPFUILog([NSString stringWithFormat:@"label model %@ => %@", t, wantMk]);
                return;
            }
            if ((wantWifi.length || wantBT.length) && IPFUIIsMAC(t)) {
                if (wantWifi.length && [t caseInsensitiveCompare:wantWifi] == NSOrderedSame) return;
                if (wantBT.length && [t caseInsensitiveCompare:wantBT] == NSOrderedSame) return;
                NSString *repl = nil;
                if (gIPFUIMacSlot == 0 && wantWifi.length) repl = wantWifi;
                else if (wantBT.length) repl = wantBT;
                else if (wantWifi.length) repl = wantWifi;
                if (repl.length) {
                    lab.text = repl;
                    n++;
                    gIPFUIMacSlot++;
                    IPFUILog([NSString stringWithFormat:@"label mac %@ => %@", t, repl]);
                }
                return;
            }
            if (wantEID.length && IPFUIIsEID(t) && ![t isEqualToString:wantEID]) {
                lab.text = wantEID;
                n++;
                IPFUILog([NSString stringWithFormat:@"label EID %@ => %@", t, wantEID]);
                return;
            }
            if (wantSEID.length && IPFUIIsSEID(t)
                && [t caseInsensitiveCompare:wantSEID] != NSOrderedSame) {
                lab.text = wantSEID;
                n++;
                IPFUILog([NSString stringWithFormat:@"label SEID %@ => %@", t, wantSEID]);
                return;
            }
            if (wantBB.length && IPFUIIsBaseband(t) && ![t isEqualToString:wantBB]
                && !(wantPV.length && [t isEqualToString:wantPV])) {
                // host modem firmware e.g. 9.61.00 → spoof
                lab.text = wantBB;
                n++;
                IPFUILog([NSString stringWithFormat:@"label bb %@ => %@", t, wantBB]);
                return;
            }
        };
        if ([v isKindOfClass:[UILabel class]])
            fixLabel((UILabel *)v);
        if ([v respondsToSelector:@selector(detailTextLabel)]) {
            UILabel *d = ((UILabel *(*)(id, SEL))objc_msgSend)(v, @selector(detailTextLabel));
            fixLabel(d);
        }
        if (v.subviews.count) [stack addObjectsFromArray:v.subviews];
    }
    return n;
}

static void IPFUIWashAllWindows(void) {
    NSDictionary *cfg = IPFUIConfig();
    if (!IPFUIEnabled(cfg)) return;
    NSString *wantPV = [cfg[@"ProductVersion"] description] ?: @"";
    NSString *wantMk = [cfg[@"MarketingName"] description] ?: @"";
    NSString *wantName = [cfg[@"UserAssignedDeviceName"] description]
        ?: [cfg[@"DeviceName"] description] ?: @"";
    NSString *wantWifi = [cfg[@"WifiAddress"] description] ?: @"";
    NSString *wantBT = [cfg[@"BluetoothAddress"] description] ?: @"";
    NSString *wantEID = [cfg[@"EID"] description] ?: @"";
    NSString *wantSEID = [cfg[@"SEID"] description]
        ?: [cfg[@"SecureElementID"] description] ?: @"";
    NSString *wantBB = [cfg[@"BasebandVersion"] description] ?: @"";
    if (!wantPV.length && !wantWifi.length && !wantBT.length && !wantBB.length) return;

    NSArray *hostVers = IPFUIHostVersionTokens();
    gIPFUIMacSlot = 0;

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
    if (!windows.count)
        windows = UIApplication.sharedApplication.windows;
    for (UIWindow *w in windows) {
        total += IPFUIWashView(w, wantPV, wantMk, wantName, wantWifi, wantBT,
                              wantEID, wantSEID, wantBB, hostVers);
        UIViewController *r = w.rootViewController;
        if (r.view)
            total += IPFUIWashView(r.view, wantPV, wantMk, wantName, wantWifi, wantBT,
                                  wantEID, wantSEID, wantBB, hostVers);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view)
                total += IPFUIWashView(p.view, wantPV, wantMk, wantName, wantWifi, wantBT,
                                      wantEID, wantSEID, wantBB, hostVers);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFUILog([NSString stringWithFormat:
                  @"washed %ld -> ver=%@ mk=%@ wifi=%@ bt=%@ bb=%@ name=%@",
                  (long)total, wantPV, wantMk,
                  wantWifi.length ? wantWifi : @"-",
                  wantBT.length ? wantBT : @"-",
                  wantBB.length ? wantBB : @"-",
                  wantName.length ? wantName : @"-"]);
}

static void IPFUIScheduleWashes(void) {
    // Longer passes: Wi‑Fi/BT/modem rows appear after user scrolls About
    NSArray *delays = @[ @0.3, @0.8, @1.5, @2.5, @4.0, @6.0, @10.0, @15.0, @20.0 ];
    for (NSNumber *d in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            IPFUIWashAllWindows();
        });
    }
}

static void IPFUIOnActive(CFNotificationCenterRef center, void *observer,
                          CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    IPFUIScheduleWashes();
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (![bid isEqualToString:@"com.apple.Preferences"]) {
            IPFUIMark("CTOR_SKIP");
            return;
        }
        IPFUIMark("CTOR_ENTER");
        dispatch_async(dispatch_get_main_queue(), ^{
            IPFUIScheduleWashes();
        });
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetLocalCenter(),
            NULL,
            IPFUIOnActive,
            CFSTR("UIApplicationDidBecomeActiveNotification"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *note) {
                        IPFUIScheduleWashes();
                    }];
        IPFUIMark("CTOR_OK");
        IPFUILog(@"AboutUI ready");
    }
}
