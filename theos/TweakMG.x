// iPFakerMG entry — MobileGestalt / sysctl / UIDevice / IDFA
// Filter: iPFakerMG.plist (Zalo bundles)

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"

static BOOL IPFIsAllowedBundle(NSString *bid) {
    if (!bid.length) return NO;
    return [bid isEqualToString:@"com.zing.zalo"]
        || [bid isEqualToString:@"vn.com.vng.zingalo"];
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (!IPFIsAllowedBundle(bid)) {
            // Still allow if filter already limited; extra safety for mis-load
            NSLog(@"[iPFakerMG] skip bundle %@", bid);
            return;
        }
        NSLog(@"[iPFakerMG] ctor in %@", bid);
        [[IPFConfig shared] reload];
        IPFInstallMGHooks();
    }
}
