// iPFakerCT — entry (lab reference-stackCT style)
// Filter: Multi-app spoof bundles + CommCenter executables

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"
#import "IPFHooksEnv.h"
%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        if (bid.length && [bid isEqualToString:@"com.apple.Preferences"]) {
            return;
        }
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled) {
            return;
        }
        IPFInstallCTHooks();
        // Deep/IOKit/HTTP live in MG (2-dylib HIOS layout). Env for app processes only.
        if (!isCT) {
            IPFInstallEnvHooks();
        }
    }
}
