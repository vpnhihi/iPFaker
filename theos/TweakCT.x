// iPFakerCT entry — CoreTelephony / carrier
// Filter: iPFakerCT.plist (Zalo + CommCenter)

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isZalo = [bid isEqualToString:@"com.zing.zalo"]
                   || [bid isEqualToString:@"vn.com.vng.zingalo"];
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        if (!isZalo && !isCT) {
            NSLog(@"[iPFakerCT] skip %@ / %@", bid, exec);
            return;
        }
        NSLog(@"[iPFakerCT] ctor bid=%@ exec=%@", bid, exec);
        [[IPFConfig shared] reload];
        IPFInstallCTHooks();
    }
}
