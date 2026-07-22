#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// One installed app entry for App lab multi-select.
@interface AppCatalogItem : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *executable;
@property (nonatomic, assign) BOOL systemApp;
@property (nonatomic, strong, nullable) UIImage *icon;
@end

@interface AppCatalog : NSObject
+ (instancetype)shared;
/// Refresh installed apps from LaunchServices (third-party + optional system pins).
- (void)reload;
/// Lab picker: **chỉ app third-party đã cài** (không list app chưa tải).
- (void)reloadSpoofCatalog;
/// Stock rows (legacy presets — not used for picker list).
+ (NSArray<NSArray *> *)labStockSpoofApps;
/// Social bundle ids (preset only selects if installed).
+ (NSArray<NSArray *> *)labSocialSpoofApps;
@property (nonatomic, readonly) NSArray<AppCatalogItem *> *apps;
@property (nonatomic, readonly) NSArray<AppCatalogItem *> *spoofApps;
- (nullable AppCatalogItem *)itemWithBundleId:(NSString *)bid;
/// YES if bundle is installed (seen by LS).
- (BOOL)isInstalledBundleId:(NSString *)bid;
@end

NS_ASSUME_NONNULL_END
