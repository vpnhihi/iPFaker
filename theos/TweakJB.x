// iPFakerJB — expanded jailbreak hide only (pairs with iPFakerMG spoof)
#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksJB.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Multi-app spoof: filter plist scopes inject; never Settings
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"])
            return;
        // Config already loaded by MG when both inject; reload is cheap + consistent
        [[IPFConfig shared] reload];
        IPFInstallJBHooks();
    }
}
