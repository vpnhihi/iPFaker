// iPFakerJB — expanded jailbreak hide only (pairs with iPFakerMG spoof)
#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksJB.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Zalo only — same filter as MG (product wall)
        if (bid.length > 0) {
            BOOL ok =
                [bid isEqualToString:@"vn.com.vng.zingalo"]
                || [bid isEqualToString:@"com.zing.zalo"];
            if (!ok) return;
        }
        // Config already loaded by MG when both inject; reload is cheap + consistent
        [[IPFConfig shared] reload];
        IPFInstallJBHooks();
    }
}
