// iPFakerCT — entry (lab reference-stackCT style)
// Filter: Multi-app spoof bundles + CommCenter executables

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"
#import "IPFHooksDeep.h"
#import "IPFHooksEnv.h"
%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        // Multi-app: ElleKit filter scopes inject. Never Settings.
        if (bid.length && [bid isEqualToString:@"com.apple.Preferences"]) {
            return;
        }

        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled) {
            return;
        }
        IPFInstallCTHooks();
        // Deep + Env for app processes (not CommCenter daemon)
        if (!isCT) {
            IPFInstallDeepHooks();
            IPFInstallEnvHooks(); // locale/TZ/location/sensor — was never linked before
        } else if (bid.length == 0) {
            IPFInstallDeepHooks();
        }
    }
}
