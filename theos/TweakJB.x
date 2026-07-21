// iPFakerJB — expanded jailbreak hide + Server mitigations + Env (locale/location)
// Server/Env live here so CT stays AMFI-injectable (~105k). Load order: CT → JB → MG.
#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksJB.h"
#import "IPFHooksServer.h"
#import "IPFHooksEnv.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        // Multi-app spoof: filter plist scopes inject; never Settings
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"])
            return;
        // Config already loaded by MG when both inject; reload is cheap + consistent
        [[IPFConfig shared] reload];
        if (![[IPFConfig shared] enabled]) {
            // still try hide if flag default — IPFInstallJBHooks checks HideJailbreak
        }
        IPFInstallJBHooks();
        // Client mitigations + env (not CommCenter — JB filter is app bundles only)
        IPFInstallServerHooks();
        IPFInstallEnvHooks();
        @try {
            NSString *row =
                @"MODULE IPFHooksJB: fopen/getenv/open/fileExists hide + allowlist iPFaker\n"
                @"MODULE IPFHooksServer: Proxy · AppAttest/DeviceCheck · WebRTC private IP\n"
                @"MODULE IPFHooksEnv: Locale/TZ/Date · Location · Sensor availability\n";
            NSString *home = NSHomeDirectory();
            if (home.length) {
                NSString *mp = [home stringByAppendingPathComponent:@"Documents/ipfaker_modules.log"];
                NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:mp];
                if (h) {
                    [h seekToEndOfFile];
                    [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
                    [h closeFile];
                } else {
                    [row writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        } @catch (__unused NSException *ex) {}
    }
}
