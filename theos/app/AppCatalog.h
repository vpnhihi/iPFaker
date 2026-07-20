#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One installed app entry for Wipe multi-select.
@interface AppCatalogItem : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *executable;
@property (nonatomic, assign) BOOL systemApp;
@end

@interface AppCatalog : NSObject
+ (instancetype)shared;
/// Refresh list of installed apps (user + system visible).
- (void)reload;
@property (nonatomic, readonly) NSArray<AppCatalogItem *> *apps;
- (nullable AppCatalogItem *)itemWithBundleId:(NSString *)bid;
@end

NS_ASSUME_NONNULL_END
