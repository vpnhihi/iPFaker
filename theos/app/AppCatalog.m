#import "AppCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation AppCatalogItem
@end

@interface AppCatalog ()
@property (nonatomic, strong) NSArray<AppCatalogItem *> *apps;
@property (nonatomic, strong) NSArray<AppCatalogItem *> *spoofApps;
@end

@implementation AppCatalog

+ (instancetype)shared {
    static AppCatalog *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[AppCatalog alloc] init];
        [s reload];
    });
    return s;
}

/// Keep only: third-party (non com.apple.*) + Bản đồ + Thời tiết.
- (BOOL)shouldListBundleId:(NSString *)bid {
    if (!bid.length) return NO;
    if ([bid isEqualToString:@"com.apple.Maps"]) return YES;
    if ([bid isEqualToString:@"com.apple.weather"]) return YES;
    if ([bid isEqualToString:@"com.apple.mobilesafari"]) return YES;
    // Drop stock system apps; keep sideloaded / App Store third-party
    if ([bid hasPrefix:@"com.apple."]) return NO;
    // Skip common system-ish prefixes
    if ([bid hasPrefix:@"com.apple.WebKit"] || [bid hasPrefix:@"com.apple.UIKit"]) return NO;
    return YES;
}

- (void)reload {
    NSMutableDictionary<NSString *, AppCatalogItem *> *map = [NSMutableDictionary dictionary];

    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) {
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
            SEL allSel = NSSelectorFromString(@"allInstalledApplications");
            if (ws && [ws respondsToSelector:allSel]) {
                NSArray *list = ((id (*)(id, SEL))objc_msgSend)(ws, allSel);
                for (id proxy in list) {
                    NSString *bid = nil;
                    NSString *name = nil;
                    NSString *ver = nil;
                    NSString *exe = nil;
                    if ([proxy respondsToSelector:NSSelectorFromString(@"applicationIdentifier")])
                        bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"applicationIdentifier"));
                    if ([proxy respondsToSelector:NSSelectorFromString(@"localizedName")])
                        name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName"));
                    if (!name.length && [proxy respondsToSelector:NSSelectorFromString(@"itemName")])
                        name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"itemName"));
                    if ([proxy respondsToSelector:NSSelectorFromString(@"shortVersionString")])
                        ver = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"shortVersionString"));
                    if ([proxy respondsToSelector:NSSelectorFromString(@"bundleExecutable")])
                        exe = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleExecutable"));
                    if (![self shouldListBundleId:bid]) continue;
                    AppCatalogItem *it = [[AppCatalogItem alloc] init];
                    it.bundleId = bid;
                    it.name = name.length ? name : bid;
                    it.version = ver;
                    it.executable = exe;
                    it.systemApp = [bid hasPrefix:@"com.apple."];
                    map[bid] = it;
                }
            }
        }
    } @catch (__unused NSException *ex) {}

    // Always ensure Maps + Weather + Safari present
    for (NSArray *must in @[
        @[ @"com.apple.Maps", @"Bản đồ" ],
        @[ @"com.apple.weather", @"Thời tiết" ],
        @[ @"com.apple.mobilesafari", @"Safari" ],
    ]) {
        if (!map[must[0]]) {
            AppCatalogItem *it = [[AppCatalogItem alloc] init];
            it.bundleId = must[0];
            it.name = must[1];
            it.systemApp = YES;
            map[must[0]] = it;
        }
    }

    // Fallback if LS empty: Maps + Weather + Safari
    if (map.count == 0) {
        for (NSArray *row in @[
            @[ @"com.apple.Maps", @"Bản đồ" ],
            @[ @"com.apple.weather", @"Thời tiết" ],
            @[ @"com.apple.mobilesafari", @"Safari" ],
        ]) {
            AppCatalogItem *it = [[AppCatalogItem alloc] init];
            it.bundleId = row[0];
            it.name = row[1];
            it.systemApp = YES;
            map[it.bundleId] = it;
        }
    }

    NSArray *all = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(AppCatalogItem *a, AppCatalogItem *b) {
        NSInteger pa = [self pinRank:a.bundleId];
        NSInteger pb = [self pinRank:b.bundleId];
        if (pa != pb) return pa < pb ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    self.apps = all;
}

- (NSInteger)pinRank:(NSString *)bid {
    if ([bid isEqualToString:@"com.apple.Maps"]) return 0;
    if ([bid isEqualToString:@"com.apple.weather"]) return 1;
    if ([bid isEqualToString:@"com.apple.mobilesafari"]) return 2;
    return 20;
}

- (AppCatalogItem *)itemWithBundleId:(NSString *)bid {
    for (AppCatalogItem *it in self.apps)
        if ([it.bundleId isEqualToString:bid]) return it;
    for (AppCatalogItem *it in self.spoofApps)
        if ([it.bundleId isEqualToString:bid]) return it;
    return nil;
}

/// Stock apps shown in HIOS Multi-app spoof (exclude Preferences — inject crash).
+ (NSArray<NSArray *> *)hiosStockSpoofApps {
    return @[
        @[ @"com.apple.AppStore", @"App Store" ],
        @[ @"com.apple.calculator", @"Calculator" ],
        @[ @"com.apple.camera", @"Camera" ],
        @[ @"com.apple.mobiletimer", @"Clock" ],
        @[ @"com.apple.MobileAddressBook", @"Contacts" ],
        @[ @"com.apple.facetime", @"FaceTime" ],
        @[ @"com.apple.DocumentsApp", @"Files" ],
        @[ @"com.apple.findmy", @"Find My" ],
        @[ @"com.apple.Health", @"Health" ],
        @[ @"com.apple.Home", @"Home" ],
        @[ @"com.apple.MobileStore", @"iTunes Store" ],
        @[ @"com.apple.Maps", @"Maps" ],
        @[ @"com.apple.measure", @"Measure" ],
        @[ @"com.apple.MobileSMS", @"Messages" ],
        @[ @"com.apple.Music", @"Music" ],
        @[ @"com.apple.news", @"News" ],
        @[ @"com.apple.mobilenotes", @"Notes" ],
        @[ @"com.apple.mobilephone", @"Phone" ],
        @[ @"com.apple.mobileslideshow", @"Photos" ],
        @[ @"com.apple.podcasts", @"Podcasts" ],
        @[ @"com.apple.reminders", @"Reminders" ],
        @[ @"com.apple.mobilesafari", @"Safari" ],
        @[ @"com.apple.shortcuts", @"Shortcuts" ],
        @[ @"com.apple.stocks", @"Stocks" ],
        @[ @"com.apple.tips", @"Tips" ],
        @[ @"com.apple.tv", @"TV" ],
        @[ @"com.apple.VoiceMemos", @"Voice Memos" ],
        @[ @"com.apple.Passbook", @"Wallet" ],
        @[ @"com.apple.Bridge", @"Watch" ],
        @[ @"com.apple.weather", @"Weather" ],
        @[ @"com.apple.iBooks", @"Books" ],
        @[ @"vn.com.vng.zingalo", @"Zalo" ],
        @[ @"com.zing.zalo", @"Zalo (alt)" ],
    ];
}

- (void)reloadSpoofCatalog {
    NSMutableDictionary<NSString *, AppCatalogItem *> *map = [NSMutableDictionary dictionary];

    // 1) Stock HIOS-like list
    for (NSArray *row in [AppCatalog hiosStockSpoofApps]) {
        AppCatalogItem *it = [[AppCatalogItem alloc] init];
        it.bundleId = row[0];
        it.name = row[1];
        it.systemApp = ![it.bundleId containsString:@"zalo"] && ![it.bundleId containsString:@"zing"];
        map[it.bundleId] = it;
    }

    // 2) Merge third-party from LS (reuse wipe scan via temporary reload of apps)
    [self reload];
    for (AppCatalogItem *it in self.apps) {
        if (!it.bundleId.length) continue;
        if ([it.bundleId isEqualToString:@"com.apple.Preferences"]) continue;
        if (!map[it.bundleId]) {
            map[it.bundleId] = it;
        } else if (it.name.length) {
            map[it.bundleId].name = it.name;
            map[it.bundleId].version = it.version;
        }
    }

    NSArray *all = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(AppCatalogItem *a, AppCatalogItem *b) {
        // Zalo first, then alpha
        BOOL az = [a.bundleId.lowercaseString containsString:@"zalo"] || [a.bundleId.lowercaseString containsString:@"zing"];
        BOOL bz = [b.bundleId.lowercaseString containsString:@"zalo"] || [b.bundleId.lowercaseString containsString:@"zing"];
        if (az != bz) return az ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    self.spoofApps = all;
}

@end
