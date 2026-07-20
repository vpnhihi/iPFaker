#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Catalog : NSObject
+ (instancetype)shared;
- (BOOL)reload;
@property (nonatomic, readonly) NSArray<NSDictionary *> *devices;
@property (nonatomic, readonly) NSDictionary<NSString *, NSDictionary *> *iosReleases;
@property (nonatomic, readonly) NSArray<NSString *> *iosVersionsSorted;
- (nullable NSDictionary *)deviceWithId:(NSString *)deviceId;
@end

NS_ASSUME_NONNULL_END
