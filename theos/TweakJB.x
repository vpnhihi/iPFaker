// iPFakerJB — expanded jailbreak hide + Server mitigations (Proxy/AA/WebRTC)
// Env (locale/location) lives in MG. Load order: CT → JB → MG.
#import <Foundation/Foundation.h>
#import "IPFConfig.h"
#import "IPFHooksJB.h"
#import "IPFHooksServer.h"

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (bid.length > 0 && [bid isEqualToString:@"com.apple.Preferences"])
            return;
        [[IPFConfig shared] reload];
        IPFInstallJBHooks();
        IPFInstallServerHooks();
        @try {
            NSString *row =
                @"MODULE IPFHooksJB: fopen/getenv/open/fileExists hide + allowlist iPFaker\n"
                @"MODULE IPFHooksServer: Proxy · AppAttest/DeviceCheck · WebRTC private IP\n";
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
