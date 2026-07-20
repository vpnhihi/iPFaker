// iPFakerMG — HIOS ChangeInfoIosMG style entry
// Marker written FIRST so we can detect load vs config failure.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"

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
        @"/var/jb/etc/changeinfoios/v3_mg_loaded.txt",
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
