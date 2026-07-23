#import "IPFRRS.h"

@implementation IPFRRS

+ (NSString *)rrsRoot {
    return @"/var/mobile/Library/iPFaker/rrs";
}

+ (NSArray<NSString *> *)containerRootsForBundle:(NSString *)bid {
    NSMutableArray *out = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *bases = @[
        @"/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Shared/AppGroup",
        @"/var/mobile/Containers/Data/PluginKitPlugin",
    ];
    for (NSString *base in bases) {
        NSArray *kids = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *kid in kids) {
            NSString *meta = [base stringByAppendingPathComponent:
                              [kid stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:meta];
            NSString *m = [d[@"MCMMetadataIdentifier"] description] ?: @"";
            if ([m isEqualToString:bid] || [m containsString:bid]) {
                [out addObject:[base stringByAppendingPathComponent:kid]];
            }
        }
    }
    return out;
}

+ (NSString *)backupBundles:(NSArray<NSString *> *)bundleIds progress:(void (^)(NSString *))progress {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *ts = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *dir = [[self rrsRoot] stringByAppendingPathComponent:ts];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    if (progress) progress(@"RRS Step 0: backup config + containers…");

    // Device config dual-path + HIOS changeinfoios (engine config)
    for (NSString *src in @[
             @"/var/jb/etc/ipfaker/config.plist",
             @"/var/mobile/Library/iPFaker/config.plist",
             @"/var/jb/etc/ipfaker/active_profile.json",
             @"/var/mobile/Library/iPFaker/active_profile.json",
             @"/var/jb/etc/changeinfoios/config.plist",
             @"/var/mobile/Library/Preferences/com.changeinfoios.plist",
         ]) {
        if (![fm fileExistsAtPath:src]) continue;
        NSString *dst = [dir stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"device_%@", src.lastPathComponent]];
        [fm copyItemAtPath:src toPath:dst error:nil];
    }

    NSUInteger nCont = 0;
    for (NSString *bid in bundleIds) {
        if (!bid.length || [bid hasPrefix:@"com.apple."]) continue;
        NSString *bdir = [dir stringByAppendingPathComponent:bid];
        [fm createDirectoryAtPath:bdir withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *root in [self containerRootsForBundle:bid]) {
            NSString *name = root.lastPathComponent;
            NSString *dst = [bdir stringByAppendingPathComponent:name];
            // Prefer tar via shell for speed/size — fallback copy Documents/Library prefs
            NSString *docs = [root stringByAppendingPathComponent:@"Documents"];
            NSString *lib = [root stringByAppendingPathComponent:@"Library"];
            for (NSString *sub in @[ docs, lib ]) {
                if (![fm fileExistsAtPath:sub]) continue;
                NSString *sd = [dst stringByAppendingPathComponent:sub.lastPathComponent];
                [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:sd error:nil];
                if ([fm copyItemAtPath:sub toPath:sd error:nil]) nCont++;
            }
        }
    }

    NSDictionary *meta = @{
        @"schema": @"ipfaker.rrs/1",
        @"ts": @((NSInteger)ts.longLongValue),
        @"bundles": bundleIds ?: @[],
        @"containersCopied": @(nCont),
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[dir stringByAppendingPathComponent:@"rrs_meta.json"] atomically:YES];
    // latest pointer
    [ts writeToFile:[[self rrsRoot] stringByAppendingPathComponent:@"LATEST"]
         atomically:YES encoding:NSUTF8StringEncoding error:nil];

    return [NSString stringWithFormat:@"RRS backup OK ts=%@ containers~%lu path=%@",
            ts, (unsigned long)nCont, dir];
}

+ (NSString *)restoreLatestProgress:(void (^)(NSString *))progress {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *ts = [NSString stringWithContentsOfFile:[[self rrsRoot] stringByAppendingPathComponent:@"LATEST"]
                                             encoding:NSUTF8StringEncoding error:nil];
    ts = [ts stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!ts.length) return @"RRS restore: no LATEST";
    NSString *dir = [[self rrsRoot] stringByAppendingPathComponent:ts];
    if (![fm fileExistsAtPath:dir]) return [NSString stringWithFormat:@"RRS restore: missing %@", dir];
    if (progress) progress(@"RRS restore config + containers…");

    // Restore config
    for (NSString *name in @[ @"config.plist", @"active_profile.json" ]) {
        NSString *src = [dir stringByAppendingPathComponent:[@"device_" stringByAppendingString:name]];
        if (![fm fileExistsAtPath:src]) continue;
        for (NSString *dst in @[
                 [@"/var/jb/etc/ipfaker/" stringByAppendingString:name],
                 [@"/var/mobile/Library/iPFaker/" stringByAppendingString:name],
             ]) {
            [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent
          withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:nil];
        }
    }

    NSUInteger restored = 0;
    NSArray *kids = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *bid in kids) {
        if ([bid hasPrefix:@"device_"] || [bid hasSuffix:@".json"]) continue;
        NSString *bdir = [dir stringByAppendingPathComponent:bid];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:bdir isDirectory:&isDir] || !isDir) continue;
        NSArray *roots = [self containerRootsForBundle:bid];
        if (!roots.count) continue;
        // Restore into first matching data container
        NSString *target = nil;
        for (NSString *r in roots) {
            if ([r containsString:@"/Data/Application/"]) { target = r; break; }
        }
        if (!target) target = roots.firstObject;
        for (NSString *subName in @[ @"Documents", @"Library" ]) {
            NSString *src = [bdir stringByAppendingPathComponent:subName];
            if (![fm fileExistsAtPath:src]) continue;
            NSString *dst = [target stringByAppendingPathComponent:subName];
            [fm removeItemAtPath:dst error:nil];
            if ([fm copyItemAtPath:src toPath:dst error:nil]) restored++;
        }
        // Keychain restore flag (apps re-read on next open)
        NSString *flag = [NSString stringWithFormat:
                          @"/var/mobile/Library/iPFaker/hios_keychain_restore_%@.flag", bid];
        [@"1" writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSString stringWithFormat:@"RRS restore ts=%@ parts~%lu", ts, (unsigned long)restored];
}

+ (void)writeWipeMarkerForBundles:(NSArray<NSString *> *)bundleIds {
    NSInteger ts = (NSInteger)[[NSDate date] timeIntervalSince1970];
    NSString *body = [NSString stringWithFormat:@"%ld\n", (long)ts];
    for (NSString *p in @[
             @"/var/mobile/Library/iPFaker/.ipf_last_wipe",
             @"/var/jb/etc/ipfaker/.ipf_last_wipe",
             [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/.ipf_last_wipe"],
         ]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:p.stringByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        [body writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSDictionary *snap = @{
        @"ts": @(ts),
        @"bundles": bundleIds ?: @[],
        @"schema": @"ipfaker.last_wipe/1",
    };
    NSData *j = [NSJSONSerialization dataWithJSONObject:snap options:0 error:nil];
    [j writeToFile:@"/var/mobile/Library/iPFaker/last_wipe.json" atomically:YES];
}

@end
