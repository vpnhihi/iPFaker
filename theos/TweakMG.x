// iPFakerMG — CRASH-SAFE product path for social apps
// Zalo/FB/TG/IG/Viber: ONLY MobileGestalt/UIDevice/sysctl identity.
// No UIScreen, no getifaddrs, no dyldHide, no fork, no IOKit, no SecItem wipe.
// Optional deep via config AllowDeepSocial=YES (default NO).

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"
#import "IPFHooksExtra.h"
#import "IPFHooksDeep.h"
#import "IPFHooksJB.h"

static void IPFMark(const char *msg) {
    // Minimal mark — avoid multi-path disk spam in %ctor (sandbox / launch races)
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";
    NSLog(@"[iPFakerMG] %s bid=%@", msg, bid);
    @try {
        NSString *body = [NSString stringWithFormat:@"%s bid=%@\n", msg, bid];
        [body writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_loaded.txt"
               atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused NSException *ex) {}
}

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

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        if ([bid hasPrefix:@"com.ipfaker"] || [bid containsString:@"ipfaker"]) {
            IPFMark("CTOR_SKIP_IPFAKER_APP");
            return;
        }
        if (!bid.length) {
            IPFMark("CTOR_SKIP_EMPTY_BID");
            return;
        }

        if ([bid isEqualToString:@"com.apple.Preferences"]) {
            BOOL okPrefs = [[IPFConfig shared] reload];
            if (!okPrefs || ![IPFConfig shared].enabled) {
                IPFMark("CTOR_PREFS_NO_CONFIG");
                return;
            }
            if (![[IPFConfig shared] flag:@"SpoofSettingsAbout" defaultYes:NO]) {
                IPFMark("CTOR_PREFS_FLAG_OFF");
                return;
            }
            @try { IPFInstallMGHooksLite(); } @catch (__unused NSException *ex) {}
            IPFMark("CTOR_PREFS_MG_LITE");
            return;
        }

        BOOL ok = [[IPFConfig shared] reload];
        if (!ok)
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");

        BOOL social = IPFIsSocialBid(bid);
        // Crash-safe is DEFAULT for social (and global unless AllowDeepSocial)
        BOOL crashSafe = social
            || [[IPFConfig shared] flag:@"CrashSafeMode" defaultYes:YES]
            || [[IPFConfig shared] flag:@"StableSocialHooks" defaultYes:YES];
        // Deep only if user explicitly opts in (default OFF — was still crashing when deferred)
        BOOL allowDeep = [[IPFConfig shared] flag:@"AllowDeepSocial" defaultYes:NO]
            && ![[IPFConfig shared] flag:@"CrashSafeMode" defaultYes:YES];

        if (crashSafe || social) {
            @try {
                // IDENTITY ONLY — proven least-crash path
                IPFInstallMGHooks();
                IPFMark(social ? "CTOR_SOCIAL_MG_ONLY" : "CTOR_SAFE_MG_ONLY");
            } @catch (NSException *ex) {
                NSString *m = [NSString stringWithFormat:@"CTOR_MG_EXC %@", ex.reason ?: @"?"];
                IPFMark(m.UTF8String);
                return;
            }

            if (allowDeep && social) {
                // Optional: net lean only, still no dyld/fork/IOKit
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try {
                        IPFInstallExtraNetLeanHooks();
                        IPFMark("CTOR_OPT_NET_LEAN");
                    } @catch (__unused NSException *ex) {}
                });
            }
            // Deep/JB NEVER auto on social — was crash source even when deferred
            return;
        }

        // Non-social rare path
        @try {
            IPFInstallMGHooks();
            IPFInstallExtraNetLeanHooks();
            IPFMark("CTOR_NONSOCIAL_LEAN");
        } @catch (NSException *ex) {
            NSString *m = [NSString stringWithFormat:@"CTOR_NS_EXC %@", ex.reason ?: @"?"];
            IPFMark(m.UTF8String);
        }
    }
}
