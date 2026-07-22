// iPFakerAbout — tiny MG-only inject for Settings → General → About (Giới thiệu).
// Platform apps (Preferences) reject large MG (~138k) with SIGKILL CODESIGNING.
// This dylib is Config + IPFHooksMG only (no Extra/WebKit) so AMFI accepts it.

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "IPFConfig.h"
#import "IPFHooksMG.h"

static void IPFAboutMark(const char *msg) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";
    NSString *body = [NSString stringWithFormat:@"%s bid=%@\n", msg, bid];
    NSArray *paths = @[
        @"/var/mobile/Library/iPFaker/v3_about_loaded.txt",
        @"/var/jb/etc/ipfaker/v3_about_loaded.txt",
        @"/var/jb/tmp/v3_about_loaded.txt",
        @"/var/mobile/Documents/v3_about_loaded.txt",
        @"/tmp/v3_about_loaded.txt",
    ];
    NSString *home = NSHomeDirectory();
    if (home.length) {
        paths = [paths arrayByAddingObjectsFromArray:@[
            [home stringByAppendingPathComponent:@"Documents/v3_about_loaded.txt"],
            [home stringByAppendingPathComponent:@"Library/v3_about_loaded.txt"],
            [home stringByAppendingPathComponent:@"tmp/v3_about_loaded.txt"],
        ]];
    }
    for (NSString *p in paths) {
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
        FILE *f = fopen(p.UTF8String, "w");
        if (f) {
            fputs(body.UTF8String, f);
            fclose(f);
        }
    }
    NSLog(@"[iPFakerAbout] %s bid=%@", msg, bid);
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (bid.length == 0 || ![bid isEqualToString:@"com.apple.Preferences"]) {
            IPFAboutMark("CTOR_SKIP_NOT_PREFS");
            return;
        }
        IPFAboutMark("CTOR_ENTER");
        BOOL ok = [[IPFConfig shared] reload];
        if (!ok || ![IPFConfig shared].enabled) {
            IPFAboutMark("CTOR_NO_CONFIG");
            return;
        }
        if (![[IPFConfig shared] flag:@"SpoofSettingsAbout" defaultYes:YES]) {
            IPFAboutMark("CTOR_FLAG_OFF");
            return;
        }
        IPFInstallMGHooks(); // MGCopyAnswer / UIDevice / sysctl / uname — About page fields
        IPFAboutMark("CTOR_PREFS_MG_ONLY");
    }
}
