// iPFakerCT — entry (HIOS ChangeInfoIosCT style)
// Filter: Zalo bundles + CommCenter executables

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isZalo = [bid isEqualToString:@"vn.com.vng.zingalo"]
                   || [bid isEqualToString:@"com.zing.zalo"];
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        // Empty bid + not CT: still allow (filter-scoped); only skip known non-targets
        if (bid.length && !isZalo && !isCT) {
            NSLog(@"[iPFakerCT] skip bid=%@ exec=%@", bid, exec);
            return;
        }

        NSLog(@"[iPFakerCT] ctor bid=%@ exec=%@", bid, exec);
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled) {
            NSLog(@"[iPFakerCT] no config — skip");
            return;
        }
        IPFInstallCTHooks();
        NSString *path = @"/var/jb/etc/ipfaker/v3_ct_loaded.txt";
        [@"iPFakerCT loaded\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
