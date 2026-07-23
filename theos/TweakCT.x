// iPFakerCT — telephony. Crash-safe: social apps get CTCarrier only (no Env GPS/sensor).

#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksCT.h"
#import "IPFHooksEnv.h"

static BOOL IPFCTIsSocial(NSString *bid) {
    if (!bid.length) return NO;
    NSString *l = bid.lowercaseString;
    if ([l containsString:@"zalo"] || [l containsString:@"zingalo"]) return YES;
    if ([l containsString:@"facebook"] || [l containsString:@"instagram"]) return YES;
    if ([l containsString:@"telegram"] || [l containsString:@"viber"]) return YES;
    if ([l containsString:@"musically"] || [l containsString:@"tiktok"]) return YES;
    if ([l containsString:@"shopee"] || [l containsString:@"webkit"]) return YES;
    return NO;
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *exec = [[NSProcessInfo processInfo] processName] ?: @"";
        BOOL isCT = [exec.lowercaseString containsString:@"commcenter"]
                 || [exec.lowercaseString containsString:@"coretelephony"];
        if (bid.length && [bid isEqualToString:@"com.apple.Preferences"])
            return;
        if ([bid hasPrefix:@"com.ipfaker"] || [bid containsString:@"ipfaker"])
            return;
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled)
            return;

        @try {
            IPFInstallCTHooks();
        } @catch (__unused NSException *ex) {}

        // Env (locale/GPS/sensor) crashes some social builds — skip unless opt-in
        BOOL social = IPFCTIsSocial(bid);
        BOOL crashSafe = social || [[IPFConfig shared] flag:@"CrashSafeMode" defaultYes:YES];
        if (!isCT && !crashSafe) {
            @try { IPFInstallEnvHooks(); } @catch (__unused NSException *ex) {}
        } else if (!isCT && [[IPFConfig shared] flag:@"AllowEnvSocial" defaultYes:NO]) {
            @try { IPFInstallEnvHooks(); } @catch (__unused NSException *ex) {}
        }
    }
}
