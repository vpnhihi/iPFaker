// iPFakerAboutUI — last-resort UI wash for Settings → About "Phiên bản phần mềm".
// Does NOT touch model number / RegionInfo (owned by iPFakerAbout).
//
// Evidence: MG + SystemVersion hooks already return spoof PV, but UI still shows host
// 15.5 → value was cached before tweaks or cell text set outside hooked APIs.
// This dylib only rewrites exact host version tokens on visible UILabels after delay.

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
    for (NSString *p in @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ]) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if ([d isKindOfClass:[NSDictionary class]] && d[@"ProductVersion"]) return d;
    }
    return nil;
}

static BOOL IPFUIEnabled(NSDictionary *cfg) {
    if (!cfg) return NO;
    id en = cfg[@"Enabled"];
    if ([en isKindOfClass:[NSNumber class]] && ![en boolValue]) return NO;
    id f = cfg[@"FakeSysOSVersion"];
    if ([f isKindOfClass:[NSNumber class]] && ![f boolValue]) return NO;
    return YES;
}

// Host iOS labels seen on jailbroken rootless phones (Dopamine 14.x–18.x / lab).
// UIDevice.systemVersion is also matched dynamically in IPFUIShouldReplaceVersion.
static NSArray<NSString *> *IPFUIHostVersionTokens(void) {
    return @[
        // iOS 14 (checkra1n / older rootless labs)
        @"14.0", @"14.1", @"14.2", @"14.3", @"14.4", @"14.5", @"14.6", @"14.7", @"14.8",
        @"14.8.1",
        // iOS 15 (A10–A11 common: 15.8.x)
        @"15.0", @"15.1", @"15.2", @"15.3", @"15.4", @"15.5", @"15.5.0", @"15.6", @"15.7",
        @"15.7.1", @"15.7.2", @"15.7.3", @"15.7.4", @"15.7.5", @"15.7.6", @"15.7.7", @"15.7.8", @"15.7.9",
        @"15.8", @"15.8.1", @"15.8.2", @"15.8.3", @"15.8.4", @"15.8.5",
        // iOS 16
        @"16.0", @"16.1", @"16.1.1", @"16.1.2", @"16.2", @"16.3", @"16.3.1", @"16.4", @"16.4.1",
        @"16.5", @"16.5.1", @"16.6", @"16.6.1", @"16.7", @"16.7.1", @"16.7.2", @"16.7.3",
        @"16.7.4", @"16.7.5", @"16.7.6", @"16.7.7", @"16.7.8", @"16.7.9",
        @"16.7.10", @"16.7.11", @"16.7.12", @"16.7.16",
        // iOS 17 (arm64e hosts)
        @"17.0", @"17.0.1", @"17.0.2", @"17.0.3", @"17.1", @"17.1.1", @"17.1.2",
        @"17.2", @"17.2.1", @"17.3", @"17.3.1", @"17.4", @"17.4.1", @"17.5", @"17.5.1",
        @"17.6", @"17.6.1", @"17.7", @"17.7.1", @"17.7.2",
        // iOS 18
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
    // UIDevice.currentDevice.systemVersion as host when != want
    @try {
        NSString *real = UIDevice.currentDevice.systemVersion;
        if (real.length && [t isEqualToString:real] && ![t isEqualToString:wantPV])
            return YES;
    } @catch (__unused NSException *ex) {}
    return NO;
}

// Only wash real host marketing model labels → config MarketingName.
// MUST NOT touch UserAssignedDeviceName (Settings "Tên") — custom names like
// "iPhone lock 🎮" / "vip chùa" used to match bare "iPhone" prefix and get replaced.
static BOOL IPFUIShouldReplaceModel(NSString *t, NSString *wantMk, NSString *wantName) {
    if (!t.length || !wantMk.length) return NO;
    if ([t isEqualToString:wantMk]) return NO;
    // Protect assigned device name (exact match)
    if (wantName.length && [t isEqualToString:wantName]) return NO;
    // Common host marketing labels on rootless JB hosts (any gen still used as host)
    // Exact match preferred; short regional suffix only for multi-token names (never bare "iPhone").
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
            // bare "iPhone" intentionally omitted — would wash custom UserAssignedDeviceName
        ];
    });
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
        // "iPhone 7 (GSM)" / regional suffixes — require real marketing base (≥ "iPhone N")
        if (h.length >= 8 && [t hasPrefix:h] && t.length < h.length + 14
            && ![t isEqualToString:wantName])
            return YES;
    }
    // Generic marketing line only: "iPhone" + SE/Air/digit/X… (not free-form custom names)
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

static NSInteger IPFUIWashView(UIView *root, NSString *wantPV, NSString *wantMk,
                               NSString *wantName, NSArray *hostVers) {
    if (!root || !wantPV.length) return 0;
    __block NSInteger n = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        void (^fixLabel)(UILabel *) = ^(UILabel *lab) {
            if (![lab isKindOfClass:[UILabel class]]) return;
            NSString *t = lab.text;
            if (![t isKindOfClass:[NSString class]] || !t.length) return;
            // Never rewrite the user-assigned name cell
            if (wantName.length && [t isEqualToString:wantName]) return;
            if (IPFUIShouldReplaceVersion(t, wantPV, hostVers)) {
                lab.text = wantPV;
                n++;
                IPFUILog([NSString stringWithFormat:@"label ver %@ => %@", t, wantPV]);
            } else if (wantMk.length && IPFUIShouldReplaceModel(t, wantMk, wantName)) {
                lab.text = wantMk;
                n++;
                IPFUILog([NSString stringWithFormat:@"label model %@ => %@", t, wantMk]);
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
    NSString *want = [cfg[@"ProductVersion"] description];
    if (!want.length) return;
    NSString *wantMk = [cfg[@"MarketingName"] description] ?: @"";
    NSString *wantName = [cfg[@"UserAssignedDeviceName"] description]
        ?: [cfg[@"DeviceName"] description] ?: @"";
    NSArray *hostVers = IPFUIHostVersionTokens();

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
        total += IPFUIWashView(w, want, wantMk, wantName, hostVers);
        UIViewController *r = w.rootViewController;
        if (r.view) total += IPFUIWashView(r.view, want, wantMk, wantName, hostVers);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view) total += IPFUIWashView(p.view, want, wantMk, wantName, hostVers);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFUILog([NSString stringWithFormat:@"washed %ld label(s) -> mk=%@ ver=%@ (name protected=%@)",
                  (long)total, wantMk, want, wantName.length ? wantName : @"-"]);
}

static void IPFUIScheduleWashes(void) {
    // Multiple passes: About table may populate late
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
        // Run after first runloop so windows exist
        dispatch_async(dispatch_get_main_queue(), ^{
            IPFUIScheduleWashes();
        });
        // Re-wash when app becomes active / About reopened
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetLocalCenter(),
            NULL,
            IPFUIOnActive,
            CFSTR("UIApplicationDidBecomeActiveNotification"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Also observe via NSNotificationCenter (more reliable for UIKit)
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
