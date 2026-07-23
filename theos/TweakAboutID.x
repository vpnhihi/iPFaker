// iPFakerAboutID — tiny Preferences UILabel wash for Tên / Số máy / Số sê-ri only.
// Kept separate from AboutUI so the proven AboutUI binary stays AMFI-loadable.

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

static BOOL IPFIDIsSerial(NSString *t) {
    if (t.length < 10 || t.length > 14) return NO;
    if ([t rangeOfString:@"/"].location != NSNotFound) return NO;
    if ([t rangeOfString:@":"].location != NSNotFound) return NO;
    if ([t rangeOfString:@" "].location != NSNotFound) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')))
            return NO;
    }
    return YES;
}

static BOOL IPFIDIsModelNum(NSString *t) {
    if (!t.length || t.length > 18) return NO;
    if ([t rangeOfString:@":"].location != NSNotFound) return NO;
    if ([t rangeOfString:@" "].location != NSNotFound) return NO;
    if ([t rangeOfString:@"/"].location != NSNotFound) return t.length >= 5;
    if (t.length < 4 || t.length > 8) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')))
            return NO;
    }
    return YES;
}

static NSInteger IPFIDWash(UIView *root, NSString *wantName, NSString *wantMN,
                           NSString *wantSN, NSString *wantMk) {
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

            if (wantSN.length && IPFIDIsSerial(t)) {
                lab.text = wantSN;
                n++;
                IPFIDLog([NSString stringWithFormat:@"sn %@ => %@", t, wantSN]);
                return;
            }
            if (wantMN.length && IPFIDIsModelNum(t)) {
                lab.text = wantMN;
                n++;
                IPFIDLog([NSString stringWithFormat:@"mn %@ => %@", t, wantMN]);
                return;
            }
            // Host default name is bare "iPhone"
            if (wantName.length && [t isEqualToString:@"iPhone"]
                && ![wantName isEqualToString:@"iPhone"]) {
                lab.text = wantName;
                n++;
                IPFIDLog([NSString stringWithFormat:@"name %@ => %@", t, wantName]);
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
    if (!wantName.length && !wantMN.length && !wantSN.length) return;

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
        total += IPFIDWash(w, wantName, wantMN, wantSN, wantMk);
        UIViewController *r = w.rootViewController;
        if (r.view) total += IPFIDWash(r.view, wantName, wantMN, wantSN, wantMk);
        UIViewController *p = r.presentedViewController;
        while (p) {
            if (p.view) total += IPFIDWash(p.view, wantName, wantMN, wantSN, wantMk);
            p = p.presentedViewController;
        }
    }
    if (total > 0)
        IPFIDLog([NSString stringWithFormat:@"washed %ld name=%@ mn=%@ sn=%@",
                  (long)total, wantName, wantMN, wantSN]);
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
