// iPFakerMG — multi-app deep spoof (Zalo/FB/IG/Telegram/Viber/…)
// Stability first: full Extra (UIScreen) + ctor-time SecItem wipe crashed social apps.
// Social path = MG identity + net lean + delayed Deep/JB. Screen spoof OFF.

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

/// Social / hybrid targets — never install UIScreen full Extra in %ctor
static BOOL IPFIsSocialBid(NSString *bid) {
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
    if ([l containsString:@"webkit"]) return YES;
    return NO;
}

/// Core stack that must be up before first network/device probe (safe enough for social).
static void IPFInstallStableCore(const char *tag) {
    @autoreleasepool {
        @try {
            IPFInstallMGHooks();
            // Net lean: ProcessInfo + getifaddrs/hostname/canOpenURL — NO UIScreen
            IPFInstallExtraNetLeanHooks();
            IPFMark(tag);
        } @catch (NSException *ex) {
            NSString *m = [NSString stringWithFormat:@"CTOR_CORE_EXC %@", ex.reason ?: @"?"];
            IPFMark(m.UTF8String);
        }
    }
}

/// Deeper hooks after app has finished early init (avoids launch SIGABRT).
static void IPFInstallDeferredDeep(void) {
    @autoreleasepool {
        @try {
            IPFInstallDeepHooks(); // IOKit + HTTP rewrite
            IPFInstallJBHooks();   // dyldHide / fork / path hide
            IPFMark("CTOR_DEFERRED_DEEP_JB_OK");
        } @catch (NSException *ex) {
            NSString *m = [NSString stringWithFormat:@"CTOR_DEFERRED_EXC %@", ex.reason ?: @"?"];
            IPFMark(m.UTF8String);
        }
    }
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        // Never inject crash stack into iPFaker.app itself
        if ([bid hasPrefix:@"com.ipfaker"] || [bid containsString:@"ipfaker"]) {
            IPFMark("CTOR_SKIP_IPFAKER_APP");
            return;
        }
        // Empty bid early in process spawn — skip (avoids hooking helper with no identity)
        if (!bid.length) {
            IPFMark("CTOR_SKIP_EMPTY_BID");
            return;
        }

        // Settings About optional — off by default
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
            @"reload=%d path=%@ ProductType=%@ enabled=%d social=%d\n",
            ok,
            [IPFConfig shared].profilePath ?: @"(none)",
            [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"(nil)",
            [IPFConfig shared].enabled,
            IPFIsSocialBid(bid)];
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [dbg writeToFile:@"/var/jb/etc/ipfaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];

        if (!ok)
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");

        BOOL social = IPFIsSocialBid(bid);
        // Force skip full Extra UIScreen for social even if old config said SkipExtraForZalo=NO
        BOOL forceLean = social
            || [[IPFConfig shared] flag:@"SkipExtraForZalo" defaultYes:YES]
            || [[IPFConfig shared] flag:@"StableSocialHooks" defaultYes:YES];

        if (forceLean || social) {
            IPFInstallStableCore(social ? "CTOR_SOCIAL_STABLE_OK" : "CTOR_LEAN_OK");
            // Defer crash-prone Deep/JB until after first runloop ticks
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                IPFInstallDeferredDeep();
            });
            // Second pass ~2s if first main queue was too early
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                static BOOL once = NO;
                if (once) return;
                once = YES;
                // Deep install is idempotent enough (double hook bad) — only mark
                IPFMark("CTOR_SOCIAL_SETTLE");
            });
        } else {
            // Non-social inject targets only: full Extra still allowed
            @try {
                IPFInstallMGHooks();
                IPFInstallExtraHooks();
                IPFInstallDeepHooks();
                IPFInstallJBHooks();
                IPFMark("CTOR_FULL_OK");
            } @catch (NSException *ex) {
                NSString *m = [NSString stringWithFormat:@"CTOR_FULL_EXC %@", ex.reason ?: @"?"];
                IPFMark(m.UTF8String);
            }
        }
    }
}
