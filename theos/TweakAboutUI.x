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

// Host iOS labels seen on jailbroken lab phones (any major still on device)
static NSArray<NSString *> *IPFUIHostVersionTokens(void) {
    return @[
        @"15.5", @"15.5.0", @"15.8", @"15.8.1", @"15.8.2", @"15.8.3", @"15.8.4", @"15.8.5",
        @"16.0", @"16.1", @"16.2", @"16.3", @"16.4", @"16.5", @"16.6", @"16.7",
        @"16.7.10", @"16.7.11", @"16.7.12", @"16.7.16",
        @"18.0", @"18.1", @"18.5", @"18.6", @"18.7", @"18.7.9",
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

static BOOL IPFUIShouldReplaceModel(NSString *t, NSString *wantMk) {
    if (!t.length || !wantMk.length) return NO;
    if ([t isEqualToString:wantMk]) return NO;
    // Common host marketing labels on old jailbreaks
    static NSArray *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = @[
            @"iPhone 6", @"iPhone 6s", @"iPhone 6s Plus", @"iPhone 7", @"iPhone 7 Plus",
            @"iPhone 8", @"iPhone 8 Plus", @"iPhone X", @"iPhone XR", @"iPhone XS", @"iPhone XS Max",
            @"iPhone SE", @"iPhone",
        ];
    });
    for (NSString *h in hosts) {
        if ([t isEqualToString:h]) return YES;
        // "iPhone 7 (GSM)" etc.
        if ([t hasPrefix:h] && t.length < h.length + 12) return YES;
    }
    return NO;
}

static NSInteger IPFUIWashView(UIView *root, NSString *wantPV, NSString *wantMk, NSArray *hostVers) {
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
            if (IPFUIShouldReplaceVersion(t, wantPV, hostVers)) {
                lab.text = wantPV;
                n++;
                IPFUILog([NSString stringWithFormat:@"label ver %@ => %@", t, wantPV]);
            } else if (wantMk.length && IPFUIShouldReplaceModel(t, wantMk)) {
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
        total += IPFUIWashView(w, want, wantMk, hostVers);
        UIViewController *r = w.rootViewController;
        if (r.view) total += IPFUIWashView(r.view, want, wantMk, hostVers);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view) total += IPFUIWashView(p.view, want, wantMk, hostVers);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFUILog([NSString stringWithFormat:@"washed %ld label(s) -> %@ / %@", (long)total, wantMk, want]);
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
