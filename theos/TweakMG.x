// iPFakerMG — lab reference-stackMG style entry
// Marker written FIRST so we can detect load vs config failure.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"
#import "IPFHooksExtra.h"

static void IPFMark(const char *msg) {
    // Sandbox-safe first (Zalo Documents/tmp), then jailbreak paths
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
        // C fallback (sometimes works when NS fails)
        FILE *f = fopen(p.UTF8String, "w");
        if (f) {
            fputs(body.UTF8String, f);
            fclose(f);
        }
    }
    NSLog(@"[iPFakerMG] %s bid=%@", msg, bid);
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Multi-app: ElleKit Filter.plist scopes inject.
        // Settings (Preferences): MG-only for Cài đặt → Cài đặt chung → Giới thiệu.
        // Skip Extra/WebKit/getifaddrs here — historical crash risk when full Extra runs in Settings.
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
            // Prefer Lite if ever injected into Preferences (full stack PAC-crashes CoreRepair)
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

        if (!ok) {
            // lab always has config.plist; still install embedded fallback hooks
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");
        }

        // Core spoof always (all rootless iPhones: A10 arm64 … A18 arm64e)
        IPFInstallMGHooks();

        // Extra (UIScreen/getifaddrs/WK/path-hide): crash/hang risk on some A10 apps (Zalo).
        // Default: skip Extra inside Zalo; keep Extra for Safari/WebKit when filter injects there.
        // Override: config SkipExtraForZalo=0 to force Extra in Zalo (lab stress).
        BOOL isZalo = [bid isEqualToString:@"vn.com.vng.zingalo"]
            || [bid isEqualToString:@"com.zing.zalo"]
            || [bid containsString:@"zingalo"];
        BOOL skipExtra = isZalo && [[IPFConfig shared] flag:@"SkipExtraForZalo" defaultYes:YES];
        if (!skipExtra) {
            IPFInstallExtraHooks();
            IPFMark("CTOR_MG_PLUS_EXTRA");
        } else {
            // Lean net only: getifaddrs + canOpenURL + hostname (checklist D/E medium).
            // Still skip UIScreen/WebKit/disk path-hide (A10 crash history).
            IPFInstallExtraNetLeanHooks();
            IPFMark("CTOR_MG_LEAN_NET_ZALO");
        }

        // Module cover: MG(+Extra) · CT+Deep · JB+Server
        @try {
            NSString *mod = [NSString stringWithFormat:
                @"MODULE IPFHooksMG: MGCopyAnswer(+Error) sysctl uname UIDevice IDFA/IDFV boottime Fake* gates; MSHook primary\n"
                @"MODULE IPFHooksExtra: %@\n"
                @"MODULE stack: MG%@ · CT+Deep · JB+Server · bid=%@\n",
                skipExtra ? @"(lean net: getifaddrs+canOpenURL+hostname — no UIScreen)" : @"UIScreen disk path-hide canOpenURL UA getifaddrs hostname WKWebView",
                skipExtra ? @" lean+net" : @"+Extra",
                bid];
            NSString *home = NSHomeDirectory();
            if (home.length)
                [mod writeToFile:[home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"]
                      atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [mod writeToFile:@"/var/mobile/Library/iPFaker/ipfaker_modules.log"
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (__unused NSException *ex) {}
        IPFMark("CTOR_HOOKS_DONE");
    }
}
