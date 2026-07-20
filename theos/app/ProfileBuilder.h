#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IPFWipeProgress)(NSString *step);

@interface ProfileBuilder : NSObject
/// Build flat HIOS-style config dict for MG/CT dylibs.
+ (NSDictionary *)flatProfileForDevice:(NSDictionary *)device
                                   ios:(NSString *)iosVer
                               iosMeta:(NSDictionary *)iosMeta
                              deviceName:(nullable NSString *)name;

/// Write config.plist + active_profile.json to lab paths. Returns error message or nil.
+ (nullable NSString *)applyFlatProfile:(NSDictionary *)flat deviceId:(NSString *)deviceId ios:(NSString *)ios;

+ (nullable NSDictionary *)loadCurrentFlat;
/// Force-quit Zalo processes only (no data wipe).
+ (void)killZalo;
/// Kill process(es) for a bundle id (best-effort by name / executable).
+ (void)killAppBundleId:(NSString *)bundleId executable:(nullable NSString *)exe;

/// Full wipe for one or many apps. progress may be called off-main (caller dispatches UI).
+ (NSString *)wipeApps:(NSArray<NSString *> *)bundleIds
              progress:(nullable IPFWipeProgress)progress;

/// Full wipe Zalo only.
+ (NSString *)wipeZaloFull;
+ (NSString *)wipeZaloLab;
@end

NS_ASSUME_NONNULL_END
