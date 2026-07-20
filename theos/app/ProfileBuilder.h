#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
/// Full wipe: kill + 100% data container + App Group + prefs + splash + keychain best-effort.
/// Returns status message (never nil on completion attempt).
+ (NSString *)wipeZaloFull;
/// Alias used by Wipe tab — same as wipeZaloFull.
+ (NSString *)wipeZaloLab;
@end

NS_ASSUME_NONNULL_END
