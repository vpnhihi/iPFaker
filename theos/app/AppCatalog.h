#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One installed app entry for Wipe / Multi-app spoof multi-select.
@interface AppCatalogItem : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *executable;
@property (nonatomic, assign) BOOL systemApp;
@end

@interface AppCatalog : NSObject
+ (instancetype)shared;
/// Refresh wipe list (third-party + Maps/Weather/Safari).
- (void)reload;
/// lab flat Multi-app spoof catalog (stock + third-party).
- (void)reloadSpoofCatalog;
/// Stock rows: @[ bundleId, name ] (lab Multi-app list, no Preferences).
+ (NSArray<NSArray *> *)labStockSpoofApps;
/// FB/IG/TikTok/Shopee/Telegram + Zalo multi-app rows.
+ (NSArray<NSArray *> *)labSocialSpoofApps;
@property (nonatomic, readonly) NSArray<AppCatalogItem *> *apps;
@property (nonatomic, readonly) NSArray<AppCatalogItem *> *spoofApps;
- (nullable AppCatalogItem *)itemWithBundleId:(NSString *)bid;
@end

NS_ASSUME_NONNULL_END
