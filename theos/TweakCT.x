// iPFakerCT — entry (lab reference-stackCT style)
// Filter: Multi-app spoof bundles + CommCenter executables

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"
#import "IPFHooksDeep.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        // Multi-app: ElleKit filter scopes inject. Never Settings.
        if (bid.length && [bid isEqualToString:@"com.apple.Preferences"]) {
            NSLog(@"[iPFakerCT] skip Preferences");
            return;
        }

        NSLog(@"[iPFakerCT] ctor bid=%@ exec=%@ isCommCenter=%d", bid, exec, isCT ? 1 : 0);
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled) {
            NSLog(@"[iPFakerCT] no config — skip");
            return;
        }
        IPFInstallCTHooks();
        // Deep rewrite for app processes (not only Zalo) + empty bid CT helpers
        if (!isCT || bid.length == 0) {
            IPFInstallDeepHooks();
        }
        NSString *mark = [NSString stringWithFormat:
            @"iPFakerCT+Deep loaded isCT=%d bid=%@\n"
            @"MODULE IPFHooksCT: CTCarrier name/MCC/MNC/ISO/VoIP/radio · multi-SIM dict · CommCenter filter\n"
            @"MODULE IPFHooksDeep: HTTP body/query ProductType/HW rewrite · IOKit serial/model\n"
            @"SURFACE Carrier: CTCarrier+radio · CommCenter inject via filter\n",
            isCT ? 1 : 0, bid];
        NSString *home = NSHomeDirectory();
        if (home.length) {
            [mark writeToFile:[home stringByAppendingPathComponent:@"Documents/v3_ct_loaded.txt"]
                   atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSString *mp = [home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:mp];
            if (h) {
                [h seekToEndOfFile];
                [h writeData:[mark dataUsingEncoding:NSUTF8StringEncoding]];
                [h closeFile];
            } else {
                [mark writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        [mark writeToFile:@"/var/jb/etc/ipfaker/v3_ct_loaded.txt"
               atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
