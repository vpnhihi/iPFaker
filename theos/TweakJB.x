// iPFakerJB — expanded jailbreak hide only (Server mitigations → iPFakerAA)
#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksJB.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"])
            return;
        [[IPFConfig shared] reload];
        IPFInstallJBHooks();
    }
}
