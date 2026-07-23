// iPFakerMG — rootless Dopamine, all arm64/arm64e iPhones
// Zalo: delayed MG install + ProcessInfo-only lean (no UIScreen / no MG screen dims)

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"
#import "IPFHooksExtra.h"

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

static BOOL IPFIsZaloBid(NSString *bid) {
    if (!bid.length) return NO;
    return [bid isEqualToString:@"vn.com.vng.zingalo"]
        || [bid isEqualToString:@"com.zing.zalo"]
        || [bid containsString:@"zingalo"];
}

static void IPFInstallZaloStack(void) {
    @autoreleasepool {
        @try {
            // Core identity: MG + UIDevice + sysctl/uname (no screen dims — see IPFAllowMGKey)
            IPFInstallMGHooks();
            // ProcessInfo OS string only (no UIScreen / getifaddrs)
            IPFInstallExtraZaloSafeHooks();
            IPFMark("CTOR_ZALO_MG_LEAN_OK");
        } @catch (NSException *ex) {
            IPFMark([[NSString stringWithFormat:@"CTOR_ZALO_EXC %@", ex.reason ?: @"?"] UTF8String]);
        }
    }
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        // Settings → About: lite only
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"]) {
            BOOL okPrefs = [[IPFConfig shared] reload];
            if (!okPrefs || ![IPFConfig shared].enabled) {
                IPFMark("CTOR_PREFS_NO_CONFIG");
                return;
            }
            if (![[IPFConfig shared] flag:@"SpoofSettingsAbout" defaultYes:YES]) {
                IPFMark("CTOR_PREFS_FLAG_OFF");
                return;
            }
            IPFInstallMGHooksLite();
            IPFMark("CTOR_PREFS_MG_LITE");
            return;
        }

        BOOL ok = [[IPFConfig shared] reload];
        NSString *dbg = [NSString stringWithFormat:
            @"reload=%d path=%@ ProductType=%@ enabled=%d\n",
            ok,
            [IPFConfig shared].profilePath ?: @"(none)",
            [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"(nil)",
            [IPFConfig shared].enabled];
        [dbg writeToFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [dbg writeToFile:@"/var/jb/etc/ipfaker/v3_mg_debug.log"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];

        if (!ok)
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");

        // ─── Zalo: delay hooks until after first UI frame (avoids launch SIGABRT) ───
        if (IPFIsZaloBid(bid)) {
            BOOL skipExtra = [[IPFConfig shared] flag:@"SkipExtraForZalo" defaultYes:YES];
            (void)skipExtra;
            IPFMark("CTOR_ZALO_DELAY_SCHEDULE");
            // 400ms: past scene connect / nav bar init that crashed with screen spoof
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                IPFInstallZaloStack();
            });
            return;
        }

        // ─── Other apps (Safari, etc.): immediate full stack ───
        IPFInstallMGHooks();
        IPFInstallExtraHooks();
        IPFMark("CTOR_MG_PLUS_EXTRA");
    }
}
