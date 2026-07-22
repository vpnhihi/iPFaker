// iPFakerAboutUI — last-resort UI wash for Settings → About.
// Preferences only. Syncs host-cached UILabel text to dual-path config SoT:
//   ProductVersion, MarketingName, UserAssignedDeviceName (protect),
//   WifiAddress, BluetoothAddress, EID, SEID, BasebandVersion.
// Does NOT own ModelNumber/RegionInfo (iPFakerAbout MG when loaded).

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

/// Newest mtime wins; /var/jb preferred on tie (same rule as ProfileBuilder / IPFConfig).
static NSDictionary *IPFUIConfig(void) {
    NSArray *paths = @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *best = nil;
    NSDate *bestDate = [NSDate distantPast];
    NSString *bestPath = nil;
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
            bestPath = p;
        }
    }
    (void)bestPath;
    return best;
}

static BOOL IPFUIFlag(NSDictionary *cfg, NSString *key) {
    if (!cfg) return NO;
    id f = cfg[key];
    if ([f isKindOfClass:[NSNumber class]]) return [f boolValue];
    return YES; // missing → default ON (lab SoT)
}

static BOOL IPFUIEnabled(NSDictionary *cfg) {
    if (!cfg) return NO;
    id en = cfg[@"Enabled"];
    if ([en isKindOfClass:[NSNumber class]] && ![en boolValue]) return NO;
    return IPFUIFlag(cfg, @"FakeSysOSVersion")
        || IPFUIFlag(cfg, @"FakeWifi")
        || IPFUIFlag(cfg, @"FakeHardware")
        || IPFUIFlag(cfg, @"FakeDevice");
}

static NSArray<NSString *> *IPFUIHostVersionTokens(void) {
    return @[
        @"14.0", @"14.1", @"14.2", @"14.3", @"14.4", @"14.5", @"14.6", @"14.7", @"14.8",
        @"14.8.1",
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

/// Host modem firmware tokens (iPhone 7 / older baseband often shown in Settings About).
static NSArray<NSString *> *IPFUIHostBasebandTokens(void) {
    return @[
        @"9.61.00", @"9.60.00", @"9.51.00", @"9.40.01", @"9.30.00", @"9.01.00",
        @"8.50.01", @"8.40.01", @"8.30.01", @"7.80.04", @"7.01.00",
        @"6.01.00", @"5.00.00", @"4.00.00", @"3.00.00", @"2.00.00", @"1.00.00",
        @"1.14.00", @"1.15.00", @"1.23.00", @"1.40.00", @"1.55.00", @"1.70.00",
        @"2.23.02", @"2.40.00", @"2.50.05", @"2.60.00", @"2.68.01",
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

// Only wash real host marketing model labels → config MarketingName.
// MUST NOT touch UserAssignedDeviceName (Settings "Tên").
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
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
                             options:0 error:nil];
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
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
        if (!hex) return NO;
    }
    return YES;
}

static BOOL IPFUILooksLikeBaseband(NSString *t) {
    if (!t.length || t.length > 12) return NO;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"^\\d{1,2}\\.\\d{2}\\.\\d{2}$"
                             options:0 error:nil];
    return re && [re numberOfMatchesInString:t options:0 range:NSMakeRange(0, t.length)] > 0;
}

static BOOL IPFUIShouldReplaceBaseband(NSString *t, NSString *wantBB, NSArray *hosts, NSString *wantPV) {
    if (!t.length || !wantBB.length) return NO;
    if ([t isEqualToString:wantBB]) return NO;
    if (wantPV.length && [t isEqualToString:wantPV]) return NO; // never steal OS version cell
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
    }
    // Host modem firmware pattern X.YY.ZZ that is not our spoof
    if (IPFUILooksLikeBaseband(t)) return YES;
    return NO;
}

typedef struct {
    NSString *wantPV;
    NSString *wantMk;
    NSString *wantName;
    NSString *wantWifi;
    NSString *wantBT;
    NSString *wantEID;
    NSString *wantSEID;
    NSString *wantBB;
    NSArray *hostVers;
    NSArray *hostBB;
    BOOL doVer;
    BOOL doModel;
    BOOL doNet;
    BOOL doHW;
    NSInteger macSlot;
} IPFUIWashCtx;

static NSInteger IPFUIWashView(UIView *root, IPFUIWashCtx *ctx) {
    if (!root || !ctx) return 0;
    __block NSInteger n = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        void (^fixLabel)(UILabel *) = ^(UILabel *lab) {
            if (![lab isKindOfClass:[UILabel class]]) return;
            NSString *t = lab.text;
            if (![t isKindOfClass:[NSString class]] || !t.length) return;
            if (ctx->wantName.length && [t isEqualToString:ctx->wantName]) return;

            if (ctx->doVer && IPFUIShouldReplaceVersion(t, ctx->wantPV, ctx->hostVers)) {
                lab.text = ctx->wantPV;
                n++;
                IPFUILog([NSString stringWithFormat:@"label ver %@ => %@", t, ctx->wantPV]);
                return;
            }
            if (ctx->doModel && ctx->wantMk.length
                && IPFUIShouldReplaceModel(t, ctx->wantMk, ctx->wantName)) {
                lab.text = ctx->wantMk;
                n++;
                IPFUILog([NSString stringWithFormat:@"label model %@ => %@", t, ctx->wantMk]);
                return;
            }
            if (ctx->doNet && IPFUIIsMAC(t)) {
                BOOL isWifi = ctx->wantWifi.length
                    && [t caseInsensitiveCompare:ctx->wantWifi] == NSOrderedSame;
                BOOL isBT = ctx->wantBT.length
                    && [t caseInsensitiveCompare:ctx->wantBT] == NSOrderedSame;
                if (isWifi || isBT) return;
                NSString *repl = nil;
                if (ctx->macSlot == 0 && ctx->wantWifi.length)
                    repl = ctx->wantWifi;
                else if (ctx->wantBT.length)
                    repl = ctx->wantBT;
                else if (ctx->wantWifi.length)
                    repl = ctx->wantWifi;
                if (repl.length && [t caseInsensitiveCompare:repl] != NSOrderedSame) {
                    lab.text = repl;
                    n++;
                    ctx->macSlot++;
                    IPFUILog([NSString stringWithFormat:@"label mac %@ => %@ (slot %ld)",
                              t, repl, (long)ctx->macSlot]);
                }
                return;
            }
            if (ctx->doHW && ctx->wantEID.length && IPFUIIsEID(t)
                && ![t isEqualToString:ctx->wantEID]) {
                lab.text = ctx->wantEID;
                n++;
                IPFUILog([NSString stringWithFormat:@"label EID %@ => %@", t, ctx->wantEID]);
                return;
            }
            if (ctx->doHW && ctx->wantSEID.length && IPFUIIsSEID(t)
                && [t caseInsensitiveCompare:ctx->wantSEID] != NSOrderedSame) {
                lab.text = ctx->wantSEID;
                n++;
                IPFUILog([NSString stringWithFormat:@"label SEID %@ => %@", t, ctx->wantSEID]);
                return;
            }
            if (ctx->doHW && IPFUIShouldReplaceBaseband(t, ctx->wantBB, ctx->hostBB, ctx->wantPV)) {
                lab.text = ctx->wantBB;
                n++;
                IPFUILog([NSString stringWithFormat:@"label bb %@ => %@", t, ctx->wantBB]);
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

    IPFUIWashCtx ctx = {0};
    ctx.wantPV = [cfg[@"ProductVersion"] description] ?: @"";
    ctx.wantMk = [cfg[@"MarketingName"] description] ?: @"";
    ctx.wantName = [cfg[@"UserAssignedDeviceName"] description]
        ?: [cfg[@"DeviceName"] description] ?: @"";
    ctx.wantWifi = [cfg[@"WifiAddress"] description] ?: @"";
    ctx.wantBT = [cfg[@"BluetoothAddress"] description] ?: @"";
    ctx.wantEID = [cfg[@"EID"] description] ?: @"";
    ctx.wantSEID = [cfg[@"SEID"] description]
        ?: [cfg[@"SecureElementID"] description] ?: @"";
    ctx.wantBB = [cfg[@"BasebandVersion"] description] ?: @"";
    ctx.hostVers = IPFUIHostVersionTokens();
    ctx.hostBB = IPFUIHostBasebandTokens();
    ctx.doVer = ctx.wantPV.length > 0 && IPFUIFlag(cfg, @"FakeSysOSVersion");
    ctx.doModel = ctx.wantMk.length > 0 && IPFUIFlag(cfg, @"FakeDevice");
    ctx.doNet = (ctx.wantWifi.length > 0 || ctx.wantBT.length > 0) && IPFUIFlag(cfg, @"FakeWifi");
    ctx.doHW = IPFUIFlag(cfg, @"FakeHardware")
        && (ctx.wantEID.length || ctx.wantSEID.length || ctx.wantBB.length);
    ctx.macSlot = 0;

    if (!ctx.doVer && !ctx.doModel && !ctx.doNet && !ctx.doHW) return;

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
        total += IPFUIWashView(w, &ctx);
        UIViewController *r = w.rootViewController;
        if (r.view) total += IPFUIWashView(r.view, &ctx);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view) total += IPFUIWashView(p.view, &ctx);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFUILog([NSString stringWithFormat:
                  @"washed %ld label(s) mk=%@ ver=%@ wifi=%@ bt=%@ eid=%@ seid=%@ bb=%@ name=%@",
                  (long)total, ctx.wantMk, ctx.wantPV,
                  ctx.wantWifi.length ? ctx.wantWifi : @"-",
                  ctx.wantBT.length ? ctx.wantBT : @"-",
                  ctx.wantEID.length ? @"yes" : @"-",
                  ctx.wantSEID.length ? @"yes" : @"-",
                  ctx.wantBB.length ? ctx.wantBB : @"-",
                  ctx.wantName.length ? ctx.wantName : @"-"]);
}

static void IPFUIScheduleWashes(void) {
    NSArray *delays = @[ @0.3, @0.8, @1.5, @2.5, @4.0, @6.0 ];
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
        IPFUILog(@"AboutUI ready (ver+model+net+modem)");
    }
}
