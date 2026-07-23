// iPFakerMG — HIOS-style deep spoof for social apps (Zalo/FB/IG/Telegram/Viber/…)
// Full MG + Extra identity stack. Screen spoof OFF by default (FakeScreen=NO) to avoid
// Zalo UIFont/IsCompactDevice crash; identity/network/sysctl still full.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"
#import "IPFHooksExtra.h"
#import "IPFHooksDeep.h"
#import "IPFHooksJB.h"
// ServerLite installs via its own constructor (IPFHooksServerLite.m)

static void IPFMark(const char *msg) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";
    NSString *body = [NSString stringWithFormat:@"%s bid=%@\n", msg, bid];
    NSMutableArray *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    NSString *tmp = NSTemporaryDirectory();
    if (home.length) {
        [paths addObject:[home stringByAppendingPathComponent:@"Documents/v3_mg_loaded.txt"]];
        [paths addObject:[home stringByAppendingPathComponent:@"Library/v3_mg_loaded.txt"]];
        [paths addObject:[home stringByAppendingPathComponent:@"tmp/v3_mg_loaded.txt"]];
    }
    if (tmp.length)
        [paths addObject:[tmp stringByAppendingPathComponent:@"v3_mg_loaded.txt"]];
    [paths addObjectsFromArray:@[
        @"/var/mobile/Library/iPFaker/v3_mg_loaded.txt",
        @"/var/jb/etc/ipfaker/v3_mg_loaded.txt",
        @"/var/jb/tmp/v3_mg_loaded.txt",
        @"/tmp/v3_mg_loaded.txt",
    ]];
    for (NSString *p in paths) {
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        FILE *f = fopen(p.UTF8String, "w");
        if (f) {
            fputs(body.UTF8String, f);
            fclose(f);
        }
    }
    NSLog(@"[iPFakerMG] %s bid=%@", msg, bid);
}

/// Apps that need full identity wall (HIOS target set)
static BOOL IPFIsDeepSpoofBid(NSString *bid) {
    if (!bid.length) return NO;
    static NSArray *kDeep;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kDeep = @[
            @"vn.com.vng.zingalo", @"com.zing.zalo",
            @"com.facebook.Facebook", @"com.facebook.Messenger",
            @"com.burbn.instagram",
            @"com.zhiliaoapp.musically", @"com.ss.iphone.ugc.Ame",
            @"ph.telegra.Telegraph",
            @"com.viber",
            @"com.shopee.vn", @"vn.shopee.vnapp", @"com.shopee.ShopeeVN", @"vn.shopee.app",
            @"com.apple.mobilesafari",
            @"com.apple.WebKit.WebContent",
            @"com.apple.Maps",
        ];
    });
    if ([kDeep containsObject:bid]) return YES;
    NSString *l = bid.lowercaseString;
    if ([l containsString:@"zingalo"] || [l containsString:@"zalo"]) return YES;
    if ([l containsString:@"facebook"] || [l containsString:@"instagram"]) return YES;
    if ([l containsString:@"telegram"] || [l containsString:@"viber"]) return YES;
    if ([l containsString:@"musically"] || [l containsString:@"tiktok"]) return YES;
    if ([l containsString:@"shopee"]) return YES;
    return NO;
}

static void IPFInstallDeepStack(const char *tag) {
    @autoreleasepool {
        @try {
            // Full MG (screen keys gated by FakeScreen / Zalo MG block)
            IPFInstallMGHooks();
            // Extra: ifaddrs/hostname/CNCopy/SCDynamic/WKWebView UA
            IPFInstallExtraHooks();
            // Deep: IOKit serial/MAC + HTTP rewrite
            IPFInstallDeepHooks();
            // JB: dyldHide + fork + fopen/getenv hide
            IPFInstallJBHooks();
            // SecItem/DeviceCheck/Proxy/WebRTC: ServerLite __attribute__((constructor))
            IPFMark(tag);
        } @catch (NSException *ex) {
            NSString *m = [NSString stringWithFormat:@"CTOR_DEEP_EXC %@", ex.reason ?: @"?"];
            IPFMark(m.UTF8String);
        }
    }
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        // Settings About optional — off by default (not product focus)
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"]) {
            BOOL okPrefs = [[IPFConfig shared] reload];
            if (!okPrefs || ![IPFConfig shared].enabled) {
                IPFMark("CTOR_PREFS_NO_CONFIG");
                return;
            }
            if (![[IPFConfig shared] flag:@"SpoofSettingsAbout" defaultYes:NO]) {
                IPFMark("CTOR_PREFS_FLAG_OFF");
                return;
            }
            IPFInstallMGHooksLite();
            IPFMark("CTOR_PREFS_MG_LITE");
            return;
        }

        BOOL ok = [[IPFConfig shared] reload];
        NSString *dbg = [NSString stringWithFormat:
            @"reload=%d path=%@ ProductType=%@ enabled=%d deep=%d\n",
            ok,
            [IPFConfig shared].profilePath ?: @"(none)",
            [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"(nil)",
            [IPFConfig shared].enabled,
            IPFIsDeepSpoofBid(bid)];
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [dbg writeToFile:@"/var/jb/etc/ipfaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];

        if (!ok)
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");

        // HIOS-style: full deep stack immediately for all injected apps (incl. Zalo)
        // No lean/delay path — that under-spoofed and failed app detection.
        IPFInstallDeepStack(IPFIsDeepSpoofBid(bid) ? "CTOR_DEEP_SOCIAL_OK" : "CTOR_DEEP_FULL_OK");
    }
}
