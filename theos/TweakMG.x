// iPFakerMG — HIOS ChangeInfoIosMG style entry
// Marker written FIRST so we can detect load vs config failure.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"

static void IPFMark(const char *msg) {
    // Prefer mobile-writable path (always visible); also try /var/jb
    NSArray *paths = @[
        @"/var/mobile/Library/iPFaker/v3_mg_loaded.txt",
        @"/var/jb/etc/ipfaker/v3_mg_loaded.txt",
    ];
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";
    NSString *body = [NSString stringWithFormat:@"%s bid=%@\n", msg, bid];
    for (NSString *p in paths) {
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSLog(@"[iPFakerMG] %s bid=%@", msg, bid);
}

%ctor {
    @autoreleasepool {
        IPFMark("CTOR_ENTER");

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Filter already scopes inject. Only refuse known non-targets.
        if (bid.length > 0) {
            BOOL zalo = [bid isEqualToString:@"vn.com.vng.zingalo"]
                     || [bid isEqualToString:@"com.zing.zalo"];
            if (!zalo) {
                IPFMark("CTOR_SKIP_BID");
                return;
            }
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
            // HIOS always has config.plist; still install embedded fallback hooks
            IPFMark("CTOR_NO_FILE_CONFIG_USE_EMBED");
        }

        IPFInstallMGHooks();
        IPFMark("CTOR_HOOKS_DONE");
    }
}
