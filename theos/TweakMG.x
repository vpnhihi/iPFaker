// iPFakerMG — entry (HIOS ChangeInfoIosMG style)
// Filter plist limits inject; do NOT skip when bundle id is still empty at %ctor.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"

static void IPFWriteLoadedMarker(void) {
    // HIOS writes /var/jb/etc/changeinfoios/v3_mg_loaded.txt
    NSString *path = @"/var/jb/etc/ipfaker/v3_mg_loaded.txt";
    NSString *body = [NSString stringWithFormat:@"iPFakerMG loaded bid=%@ path=%@\n",
                      [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)",
                      [IPFConfig shared].profilePath ?: @"(none)"];
    [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Only skip if we KNOW we are in a non-Zalo process.
        // Empty bid at early ctor is common — HIOS filter already scopes inject.
        if (bid.length > 0) {
            BOOL ok = [bid isEqualToString:@"vn.com.vng.zingalo"]
                   || [bid isEqualToString:@"com.zing.zalo"];
            if (!ok) {
                NSLog(@"[iPFakerMG] skip non-zalo bid=%@", bid);
                return;
            }
        }

        NSLog(@"[iPFakerMG] ctor start bid=%@", bid.length ? bid : @"(empty-early)");
        BOOL loaded = [[IPFConfig shared] reload];
        NSLog(@"[iPFakerMG] config loaded=%d path=%@ mg=%lu",
              loaded,
              [IPFConfig shared].profilePath,
              (unsigned long)[IPFConfig shared].mgMap.count);

        if (!loaded || ![IPFConfig shared].enabled) {
            NSLog(@"[iPFakerMG] abort hooks — no config (expected /var/jb/etc/ipfaker/config.plist)");
            return;
        }

        IPFInstallMGHooks();
        IPFWriteLoadedMarker();
        NSLog(@"[iPFakerMG] hooks installed ProductType=%@",
              [[IPFConfig shared] mgValueForKey:@"ProductType"] ?: @"(nil)");
    }
}
