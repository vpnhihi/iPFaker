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
        // Filter scopes inject; allow Zalo + Settings (About / Giới thiệu).
        // Multi-app spoof: ElleKit Filter.plist decides inject targets.
        // Hard-block Settings (historical crash). Do not second-guess other bundles.
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"]) {
            IPFMark("CTOR_SKIP_PREFS");
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

        IPFInstallMGHooks();
        IPFInstallExtraHooks();
        // Module cover matrix (MG + Extra always co-loaded in this dylib)
        @try {
            NSString *mod = [NSString stringWithFormat:
                @"MODULE IPFHooksMG: MGCopyAnswer(+Error) sysctl uname UIDevice IDFA/IDFV boottime Fake* gates; MSHook primary (fishhook fallback only if miss)\n"
                @"MODULE IPFHooksExtra: UIScreen disk path-hide canOpenURL UA locale/TZ location getifaddrs hostname WKWebView\n"
                @"MODULE stack: MG+Extra in iPFakerMG.dylib · CT+Deep in iPFakerCT · JB hide in iPFakerJB · bid=%@\n",
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
