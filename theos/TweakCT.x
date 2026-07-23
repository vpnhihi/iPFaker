// iPFakerCT — HIOS ChangeInfoIosCT parity: telephony + CommCenter
// Env (locale/location/sensor) for app processes (HIOS MG has CLLocation; we put Env in CT)

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

        if ([bid isEqualToString:@"com.apple.Preferences"])
            return;
        if ([bid hasPrefix:@"com.ipfaker"] || [bid containsString:@"ipfaker"])
            return;
        if (![[IPFConfig shared] reload] || ![IPFConfig shared].enabled)
            return;

        @try {
            IPFInstallCTHooks();
        } @catch (__unused NSException *ex) {}

        // HIOS: location surfaces on app side — Env for non-CommCenter
        if (!isCT && ![[IPFConfig shared] flag:@"CrashSafeMode" defaultYes:NO]) {
            @try { IPFInstallEnvHooks(); } @catch (__unused NSException *ex) {}
        }
    }
}
