#import "AppCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation AppCatalogItem
@end

@interface AppCatalog ()
@property (nonatomic, strong) NSArray<AppCatalogItem *> *apps;
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

    // Always ensure Maps + Weather present
    for (NSArray *must in @[
        @[ @"com.apple.Maps", @"Bản đồ" ],
        @[ @"com.apple.weather", @"Thời tiết" ],
    ]) {
        if (!map[must[0]]) {
            AppCatalogItem *it = [[AppCatalogItem alloc] init];
            it.bundleId = must[0];
            it.name = must[1];
            it.systemApp = YES;
            map[must[0]] = it;
        }
    }

    // Fallback if LS empty: only Maps + Weather
    if (map.count == 0) {
        for (NSArray *row in @[
            @[ @"com.apple.Maps", @"Bản đồ" ],
            @[ @"com.apple.weather", @"Thời tiết" ],
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
    return 20;
}

- (AppCatalogItem *)itemWithBundleId:(NSString *)bid {
    for (AppCatalogItem *it in self.apps)
        if ([it.bundleId isEqualToString:bid]) return it;
    return nil;
}

@end
