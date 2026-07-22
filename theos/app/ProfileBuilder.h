#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IPFWipeProgress)(NSString *step);

@interface ProfileBuilder : NSObject
/// Build flat lab flat config dict for MG/CT dylibs.
+ (NSDictionary *)flatProfileForDevice:(NSDictionary *)device
                                   ios:(NSString *)iosVer
                               iosMeta:(NSDictionary *)iosMeta
                              deviceName:(nullable NSString *)name;

/// Host ProductVersion (SystemVersion.plist / UIDevice).
+ (NSString *)hostSystemVersion;
/// Host ProductType (sysctl hw.machine).
+ (NSString *)hostProductType;
/// Compare dotted versions: NSOrderedAscending if a < b.
+ (NSComparisonResult)compareVersion:(NSString *)a toVersion:(NSString *)b;
/// Darwin kern.osrelease + kern.version for spoof iOS (realistic map).
+ (NSDictionary *)darwinKernelKeysForIOS:(NSString *)iosVer board:(nullable NSString *)board;
/// Lab warnings: spoof iOS > host, model ≠ host, etc.
+ (NSString *)labMismatchWarningForSpoofIOS:(NSString *)spoofIOS
                                 productType:(nullable NSString *)productType;
/// Soft host prefer (2.10.7): empty → host; otherwise keep spoof (no hard rewrite).
+ (NSString *)clampSpoofIOSToHost:(NSString *)spoofIOS;
/// Prefer min(spoof, host) when a “at most host” choice is needed (optional helper).
+ (NSString *)preferIOSAtMostHost:(NSString *)spoofIOS;
/// Random Settings device name from lab pool (iPhone / iPhone vip / iPhone của Linh…).
+ (NSString *)randomUserDeviceName;
/// Radio RAT string matching device year (no NR on pre-5G phones).
+ (NSString *)radioAccessTechnologyForDevice:(NSDictionary *)device;
/// Short honest claim footer (what lab can / cannot claim).
+ (NSString *)labHonestClaimFooter;
/// Realism score 0–100: higher = closer to host (still allows full-catalog spoof via weighted pick).
+ (NSInteger)labRealismScoreForProductType:(nullable NSString *)productType
                                      ios:(nullable NSString *)ios;
/// Parse iPhoneN from ProductType (iPhone11,6 → 11). 0 if unknown.
+ (NSInteger)productTypeGeneration:(nullable NSString *)productType;

/// Write config.plist + active_profile.json to lab paths. Returns error message or nil.
+ (nullable NSString *)applyFlatProfile:(NSDictionary *)flat deviceId:(NSString *)deviceId ios:(NSString *)ios;

+ (nullable NSDictionary *)loadCurrentFlat;
/// Force-quit Zalo processes only (no data wipe).
+ (void)killZalo;
/// Kill process(es) for a bundle id (best-effort by name / executable).
+ (void)killAppBundleId:(NSString *)bundleId executable:(nullable NSString *)exe;

/// Relaunch apps after wipe/apply (uiopen + LSApplicationWorkspace). Returns short log.
+ (NSString *)relaunchAppsWithBundleIds:(NSArray<NSString *> *)bundleIds;

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

/// Schema lock: only known config keys (no random/unknown plist pollution).
+ (NSSet<NSString *> *)knownConfigKeySet;
/// Filter flat dict to known keys only (drops unknown).
+ (NSDictionary *)schemaLockedFlat:(NSDictionary *)flat dropped:(NSUInteger *)droppedOut;
@end

NS_ASSUME_NONNULL_END
