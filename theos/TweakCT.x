// iPFakerCT — entry (HIOS ChangeInfoIosCT style)
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

        NSLog(@"[iPFakerCT] ctor bid=%@ exec=%@", bid, exec);
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled) {
            NSLog(@"[iPFakerCT] no config — skip");
            return;
        }
        IPFInstallCTHooks();
        // Deep rewrite for app processes (not only Zalo) + empty bid CT helpers
        if (!isCT || bid.length == 0) {
            IPFInstallDeepHooks();
        }
        NSString *home = NSHomeDirectory();
        if (home.length) {
            [@"iPFakerCT+Deep loaded\n" writeToFile:[home stringByAppendingPathComponent:@"Documents/v3_ct_loaded.txt"]
                                         atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [@"iPFakerCT+Deep loaded\n" writeToFile:@"/var/jb/etc/ipfaker/v3_ct_loaded.txt"
                                      atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
