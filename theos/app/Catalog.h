#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Catalog : NSObject
+ (instancetype)shared;
- (BOOL)reload;
@property (nonatomic, readonly) NSArray<NSDictionary *> *devices;
@property (nonatomic, readonly) NSDictionary<NSString *, NSDictionary *> *iosReleases;
@property (nonatomic, readonly) NSArray<NSString *> *iosVersionsSorted;
- (nullable NSDictionary *)deviceWithId:(NSString *)deviceId;
/// iOS versions allowed for device (from supportedIOS matrix). Newest last.
- (NSArray<NSString *> *)supportedIOSForDevice:(NSDictionary *)device;
- (BOOL)device:(NSDictionary *)device supportsIOS:(NSString *)ios;
@end

NS_ASSUME_NONNULL_END
