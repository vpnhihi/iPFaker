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

/// Wipe with options: skipKeychain / skipScript (BOOL in options).
+ (NSString *)wipeApps:(NSArray<NSString *> *)bundleIds
              progress:(nullable IPFWipeProgress)progress
               options:(nullable NSDictionary *)options;

/// Backup app data containers (+ app groups) for selected bundles. Returns backup root path or error prefix "ERR:".
+ (NSString *)backupApps:(NSArray<NSString *> *)bundleIds
              backupRoot:(nullable NSString *)backupRoot
                progress:(nullable IPFWipeProgress)progress;

/// Restore app data from a previous backup root (keeps login session files).
+ (NSString *)restoreApps:(NSArray<NSString *> *)bundleIds
             fromBackupRoot:(NSString *)backupRoot
                  progress:(nullable IPFWipeProgress)progress;

/// Copy current device config.plist + active_profile.json into backupRoot/device/
+ (BOOL)backupCurrentDeviceProfileTo:(NSString *)backupRoot error:(NSString * _Nullable * _Nullable)errOut;

/// Default backup base: /var/mobile/Library/iPFaker/backups
+ (NSString *)defaultBackupBase;

/// Full wipe Zalo only.
+ (NSString *)wipeZaloFull;
+ (NSString *)wipeZaloLab;

/// Multi-app spoof: write ElleKit filter plists for MG/CT/JB from selected bundle IDs.
+ (NSString *)applySpoofFiltersForBundles:(NSArray<NSString *> *)bundleIds
                                 progress:(nullable IPFWipeProgress)progress;

/// Merge flat keys into existing config.plist (both dual paths) without regenerating identity.
+ (NSString *)mergeKeysIntoConfig:(NSDictionary *)keys
                         progress:(nullable IPFWipeProgress)progress;
@end

NS_ASSUME_NONNULL_END
