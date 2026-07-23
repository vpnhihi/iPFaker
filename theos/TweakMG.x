// iPFakerMG — HIOS ChangeInfoIosMG parity (4.2.6 feature set)
// Ships: MG identity + Extra (UIScreen/net/WK) + Deep IOKit/HTTP + JB dyld/hide
//         + ServerLite (SecItem/DeviceCheck) via IPFHooksServerLite.m
// UI remains iPFaker.app (not HIOS UI). Settings About optional only.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"
#import "IPFHooksExtra.h"
#import "IPFHooksDeep.h"
#import "IPFHooksJB.h"

static void IPFMark(const char *msg) {
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
        // Match HIOS ChangeInfoIosMG.plist filter set
        kDeep = @[
            @"vn.com.vng.zingalo", @"com.zing.zalo",
            @"com.facebook.Facebook", @"com.facebook.Messenger",
            @"com.burbn.instagram",
            @"com.zhiliaoapp.musically", @"com.ss.iphone.ugc.Ame",
            @"ph.telegra.Telegraph",
            @"com.viber",
            @"com.shopee.vn", @"vn.shopee.vnapp",
            @"com.apple.mobilesafari",
            @"com.apple.WebKit.WebContent",
            @"com.apple.Maps",
            @"com.apple.weather",
        ];
    });
    if ([kDeep containsObject:bid]) return YES;
    NSString *l = bid.lowercaseString;
    if ([l containsString:@"zingalo"] || [l containsString:@"zalo"]) return YES;
    if ([l containsString:@"facebook"] || [l containsString:@"instagram"]) return YES;
    if ([l containsString:@"telegram"] || [l containsString:@"viber"]) return YES;
    if ([l containsString:@"musically"] || [l containsString:@"tiktok"]) return YES;
    if ([l containsString:@"shopee"] || [l containsString:@"webkit"]) return YES;
    return NO;
}

/// HIOS MG wall — install once, ordered like ChangeInfoIosMG surface set
static void IPFInstallHIOSMGWall(const char *tag) {
    @autoreleasepool {
        @try {
            IPFInstallMGHooks();       // MGCopyAnswer / UIDevice / sysctl / IDFA
            IPFInstallExtraHooks();    // UIScreen, getifaddrs, CNCopy, SCDynamic, WK UA
            IPFInstallDeepHooks();     // IOKit registry + HTTP body rewrite
            IPFInstallJBHooks();       // dyld hide, fopen/access, fork block
            // SecItem + DeviceCheck: ServerLite constructor (same dylib)
            IPFMark(tag);
        } @catch (NSException *ex) {
            NSString *m = [NSString stringWithFormat:@"CTOR_HIOS_EXC %@", ex.reason ?: @"?"];
            IPFMark(m.UTF8String);
        }
    }
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        // Keep iPFaker.app clean (our UI only)
        if ([bid hasPrefix:@"com.ipfaker"] || [bid containsString:@"ipfaker"]) {
            IPFMark("CTOR_SKIP_IPFAKER_APP");
            return;
        }
        if (!bid.length) {
            IPFMark("CTOR_SKIP_EMPTY_BID");
            return;
        }

        // Settings → Giới thiệu: optional (iPFaker keeps own About lab UI)
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

        // HIOS parity default: full wall for all injected targets
        // CrashSafeMode only if user explicitly re-enables it
        BOOL crashSafe = [[IPFConfig shared] flag:@"CrashSafeMode" defaultYes:NO];
        if (crashSafe) {
            @try {
                IPFInstallMGHooks();
                IPFMark("CTOR_CRASHSAFE_MG_ONLY");
            } @catch (__unused NSException *ex) {}
            return;
        }

        BOOL social = IPFIsSocialBid(bid);
        // Immediate HIOS wall (HIOS does not use "lean only" for Zalo)
        // Once-guards inside each Install* prevent double hook
        IPFInstallHIOSMGWall(social ? "CTOR_HIOS_SOCIAL_OK" : "CTOR_HIOS_FULL_OK");
    }
}
