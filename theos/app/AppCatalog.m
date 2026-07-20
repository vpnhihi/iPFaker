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

- (void)reload {
    NSMutableDictionary<NSString *, AppCatalogItem *> *map = [NSMutableDictionary dictionary];

    // 1) LSApplicationWorkspace (private, works on JB with no-sandbox)
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
                    if (!bid.length) continue;
                    // Skip junk / hidden placeholders
                    if ([bid hasPrefix:@"com.apple.WebKit"] || [bid hasPrefix:@"com.apple.UIKit"]) continue;
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

    // 2) Fallback seed list if LS empty (still show useful targets)
    if (map.count == 0) {
        NSArray *seed = @[
            @[ @"com.apple.Maps", @"Bản đồ" ],
            @[ @"com.apple.weather", @"Thời tiết" ],
            @[ @"com.apple.mobilesafari", @"Safari" ],
            @[ @"com.apple.mobilecal", @"Lịch" ],
            @[ @"com.apple.MobileSMS", @"Tin nhắn" ],
            @[ @"com.apple.mobilemail", @"Mail" ],
            @[ @"com.apple.Preferences", @"Cài đặt" ],
            @[ @"com.apple.AppStore", @"App Store" ],
            @[ @"com.apple.camera", @"Camera" ],
            @[ @"com.apple.mobileslideshow", @"Ảnh" ],
            @[ @"com.apple.Music", @"Nhạc" ],
            @[ @"vn.com.vng.zingalo", @"Zalo" ],
            @[ @"com.zing.zalo", @"Zalo (alt)" ],
        ];
        for (NSArray *row in seed) {
            AppCatalogItem *it = [[AppCatalogItem alloc] init];
            it.bundleId = row[0];
            it.name = row[1];
            it.systemApp = [it.bundleId hasPrefix:@"com.apple."];
            map[it.bundleId] = it;
        }
    }

    // Ensure Maps + Weather always present
    for (NSArray *must in @[
        @[ @"com.apple.Maps", @"Bản đồ" ],
        @[ @"com.apple.weather", @"Thời tiết" ],
        @[ @"vn.com.vng.zingalo", @"Zalo" ],
    ]) {
        if (!map[must[0]]) {
            AppCatalogItem *it = [[AppCatalogItem alloc] init];
            it.bundleId = must[0];
            it.name = must[1];
            it.systemApp = [must[0] hasPrefix:@"com.apple."];
            map[must[0]] = it;
        }
    }

    NSArray *all = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(AppCatalogItem *a, AppCatalogItem *b) {
        // Defaults first-ish: Maps, Weather, then name
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
    if ([bid isEqualToString:@"vn.com.vng.zingalo"] || [bid isEqualToString:@"com.zing.zalo"]) return 2;
    if ([bid hasPrefix:@"com.apple."]) return 10;
    return 20;
}

- (AppCatalogItem *)itemWithBundleId:(NSString *)bid {
    for (AppCatalogItem *it in self.apps)
        if ([it.bundleId isEqualToString:bid]) return it;
    return nil;
}

@end
