#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared selection + apply pipeline used by Main / Select Devices / Wipe tabs.
@interface AppState : NSObject
+ (instancetype)shared;

/// Multi-select pools (persisted). At least one device + one iOS after ensureDefaults.
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedDeviceIds;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIOSList;

/// Active pair last applied / current primary (synced with pools).
@property (nonatomic, copy, nullable) NSString *selectedDeviceId;
@property (nonatomic, copy, nullable) NSString *selectedIOS;

@property (nonatomic, strong, nullable) NSDictionary *lastFlat;
@property (nonatomic, copy) NSString *statusText;

- (void)reloadFromDisk;
- (nullable NSDictionary *)currentDevice;
- (nullable NSDictionary *)currentIOSMeta;
- (void)ensureDefaults;

/// Persist multi-select pools to NSUserDefaults.
- (void)savePools;
- (void)loadPools;

/// Toggle device id in pool. Returns YES if now selected.
- (BOOL)toggleDeviceId:(NSString *)deviceId;
/// Toggle iOS version in pool (only if compatible with ≥1 selected device).
- (BOOL)toggleIOS:(NSString *)ios;
- (BOOL)isDeviceSelected:(NSString *)deviceId;
- (BOOL)isIOSSelected:(NSString *)ios;

/// iOS versions allowed for current multi-device selection (union of supportedIOS, newest last).
- (NSArray<NSString *> *)compatibleIOSForSelectedDevices;
/// iOS subset that is both in pool and valid for a given device.
- (NSArray<NSString *> *)selectedIOSCompatibleWithDevice:(NSDictionary *)device;

/// Apply: if randomFromPool, pick random valid (device,iOS) from pools then full identity.
/// reseedOnly ignored when randomFromPool (always full regen of identity fields).
- (NSString *)applyReseedOnly:(BOOL)reseedOnly;
- (NSString *)applyRandomFromPool;
/// Random from pool + write config + kill Zalo (user-requested flow).
- (NSString *)killZaloAndRandomizeFromPool;

- (void)killZalo;
- (NSString *)wipeZaloLab;

- (BOOL)toggleForKey:(NSString *)key defaultOn:(BOOL)on;
- (void)setToggle:(BOOL)on forKey:(NSString *)key;

- (void)postDidChange;

/// Human-readable pool summary for UI.
- (NSString *)devicePoolSummary;
- (NSString *)iosPoolSummary;
@end

FOUNDATION_EXPORT NSNotificationName const AppStateDidChangeNotification;

NS_ASSUME_NONNULL_END
