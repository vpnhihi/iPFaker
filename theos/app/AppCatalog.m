#import "AppCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>

@implementation AppCatalogItem
@end

@interface AppCatalog ()
@property (nonatomic, strong) NSArray<AppCatalogItem *> *apps;
@property (nonatomic, strong) NSArray<AppCatalogItem *> *spoofApps;
@property (nonatomic, strong) NSMutableSet<NSString *> *installedIds;
@end

@implementation AppCatalog

+ (instancetype)shared {
    static AppCatalog *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[AppCatalog alloc] init];
        s.installedIds = [NSMutableSet set];
        [s reload];
    });
    return s;
}

- (BOOL)shouldListThirdPartyBundleId:(NSString *)bid {
    if (!bid.length) return NO;
    if ([bid isEqualToString:@"com.apple.Preferences"]) return NO;
    if ([bid hasPrefix:@"com.apple."]) return NO;
    if ([bid hasPrefix:@"com.apple.WebKit"] || [bid hasPrefix:@"com.apple.UIKit"]) return NO;
    // Skip empty / system-ish
    if ([bid hasPrefix:@"com.apple"]) return NO;
    return YES;
}

/// Load home-screen style icon for installed app (private LS / UIImage helpers).
+ (UIImage *)iconForProxy:(id)proxy bundleId:(NSString *)bid {
    UIImage *icon = nil;
    @try {
        // LSApplicationProxy iconDataForVariant: (2 ≈ 60pt home)
        SEL iconSel = NSSelectorFromString(@"iconDataForVariant:");
        if (proxy && [proxy respondsToSelector:iconSel]) {
            for (NSInteger variant = 2; variant >= 0 && !icon; variant--) {
                NSData *data = ((id (*)(id, SEL, NSInteger))objc_msgSend)(proxy, iconSel, variant);
                if ([data isKindOfClass:[NSData class]] && data.length > 32)
                    icon = [UIImage imageWithData:data];
            }
        }
        if (!icon) {
            // UIImage private: _applicationIconImageForBundleIdentifier:format:scale:
            SEL uiSel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
            if ([UIImage respondsToSelector:uiSel]) {
                CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 2.0;
                icon = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(
                    (id)[UIImage class], uiSel, bid, 0, scale);
            }
        }
    } @catch (__unused NSException *ex) {}
    return icon;
}

- (void)reload {
    NSMutableDictionary<NSString *, AppCatalogItem *> *map = [NSMutableDictionary dictionary];
    NSMutableSet *installed = [NSMutableSet set];

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
                    if (!bid.length) continue;
                    [installed addObject:bid];

                    if ([proxy respondsToSelector:NSSelectorFromString(@"localizedName")])
                        name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName"));
                    if (!name.length && [proxy respondsToSelector:NSSelectorFromString(@"itemName")])
                        name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"itemName"));
                    if ([proxy respondsToSelector:NSSelectorFromString(@"shortVersionString")])
                        ver = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"shortVersionString"));
                    if ([proxy respondsToSelector:NSSelectorFromString(@"bundleExecutable")])
                        exe = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleExecutable"));

                    // Store all non-Preferences for installed set; apps list = third-party for lab
                    if ([bid isEqualToString:@"com.apple.Preferences"]) continue;
                    BOOL isTP = [self shouldListThirdPartyBundleId:bid];
                    if (!isTP) continue;

                    AppCatalogItem *it = [[AppCatalogItem alloc] init];
                    it.bundleId = bid;
                    it.name = name.length ? name : bid;
                    it.version = ver;
                    it.executable = exe;
                    it.systemApp = NO;
                    it.icon = [AppCatalog iconForProxy:proxy bundleId:bid];
                    map[bid] = it;
                }
            }
        }
    } @catch (__unused NSException *ex) {}

    self.installedIds = installed;

    NSArray *all = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(AppCatalogItem *a, AppCatalogItem *b) {
        BOOL az = [a.bundleId.lowercaseString containsString:@"zalo"] || [a.bundleId.lowercaseString containsString:@"zing"];
        BOOL bz = [b.bundleId.lowercaseString containsString:@"zalo"] || [b.bundleId.lowercaseString containsString:@"zing"];
        if (az != bz) return az ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    self.apps = all;
    // spoofApps default = same as installed third-party
    self.spoofApps = all;
}

- (BOOL)isInstalledBundleId:(NSString *)bid {
    if (!bid.length) return NO;
    if ([self.installedIds containsObject:bid]) return YES;
    // Fallback scan
    for (AppCatalogItem *it in self.apps)
        if ([it.bundleId isEqualToString:bid]) return YES;
    return NO;
}

- (AppCatalogItem *)itemWithBundleId:(NSString *)bid {
    for (AppCatalogItem *it in self.apps)
        if ([it.bundleId isEqualToString:bid]) return it;
    for (AppCatalogItem *it in self.spoofApps)
        if ([it.bundleId isEqualToString:bid]) return it;
    return nil;
}

+ (NSArray<NSArray *> *)labStockSpoofApps {
    return @[
        @[ @"vn.com.vng.zingalo", @"Zalo" ],
        @[ @"com.zing.zalo", @"Zalo (alt)" ],
    ];
}

+ (NSArray<NSArray *> *)labSocialSpoofApps {
    return @[
        @[ @"vn.com.vng.zingalo", @"Zalo" ],
        @[ @"com.zing.zalo", @"Zalo (alt)" ],
        @[ @"com.facebook.Facebook", @"Facebook" ],
        @[ @"com.facebook.Messenger", @"Messenger" ],
        @[ @"com.burbn.instagram", @"Instagram" ],
        @[ @"com.zhiliaoapp.musically", @"TikTok" ],
        @[ @"com.ss.iphone.ugc.Ame", @"TikTok (Asia)" ],
        @[ @"vn.shopee.app", @"Shopee VN" ],
        @[ @"com.shopee.ShopeeVN", @"Shopee VN (alt)" ],
        @[ @"ph.telegra.Telegraph", @"Telegram" ],
        @[ @"net.whatsapp.WhatsApp", @"WhatsApp" ],
        @[ @"com.google.ios.youtube", @"YouTube" ],
    ];
}

- (void)reloadSpoofCatalog {
    // Picker = only apps actually installed (from LS), third-party only
    [self reload];
    self.spoofApps = self.apps ?: @[];
}

@end
