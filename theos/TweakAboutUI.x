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

static NSInteger IPFUIWashView(UIView *root, NSString *hostPV, NSString *wantPV) {
    if (!root || !wantPV.length) return 0;
    NSInteger n = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *lab = (UILabel *)v;
            NSString *t = lab.text;
            if (![t isKindOfClass:[NSString class]] || !t.length) {
                // fallthrough
            } else if ([t isEqualToString:@"15.5"] || [t isEqualToString:@"15.5.0"]
                       || (hostPV.length && [t isEqualToString:hostPV] && ![t isEqualToString:wantPV])) {
                lab.text = wantPV;
                n++;
                IPFUILog([NSString stringWithFormat:@"label %@ => %@", t, wantPV]);
            }
        }
        if ([v respondsToSelector:@selector(detailTextLabel)]) {
            UILabel *d = ((UILabel *(*)(id, SEL))objc_msgSend)(v, @selector(detailTextLabel));
            if ([d isKindOfClass:[UILabel class]]) {
                NSString *t = d.text;
                if ([t isEqualToString:@"15.5"] || [t isEqualToString:@"15.5.0"]
                    || (hostPV.length && [t isEqualToString:hostPV] && ![t isEqualToString:wantPV])) {
                    d.text = wantPV;
                    n++;
                    IPFUILog([NSString stringWithFormat:@"detail %@ => %@", t, wantPV]);
                }
            }
        }
        if (v.subviews.count) [stack addObjectsFromArray:v.subviews];
    }
    return n;
}

static void IPFUIWashAllWindows(void) {
    NSDictionary *cfg = IPFUIConfig();
    if (!IPFUIEnabled(cfg)) return;
    NSString *want = [cfg[@"ProductVersion"] description];
    if (!want.length || [want isEqualToString:@"15.5"]) return;
    // Host is always lab 15.5 for wash targets
    NSString *host = @"15.5";

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
        total += IPFUIWashView(w, host, want);
        // also key root VC view
        UIViewController *r = w.rootViewController;
        if (r.view) total += IPFUIWashView(r.view, host, want);
        // presented
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view) total += IPFUIWashView(p.view, host, want);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFUILog([NSString stringWithFormat:@"washed %ld label(s) -> %@", (long)total, want]);
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
