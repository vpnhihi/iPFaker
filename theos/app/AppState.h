#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared selection + apply pipeline used by Main / Select Devices / Wipe tabs.
@interface AppState : NSObject
+ (instancetype)shared;

/// Multi-select pools (persisted). At least one device + one iOS after ensureDefaults.
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedDeviceIds;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIOSList;
/// Wipe tab multi-select (default: Maps + Weather).
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedWipeBundleIds;

/// Active pair last applied / current primary (synced with pools).
@property (nonatomic, copy, nullable) NSString *selectedDeviceId;
@property (nonatomic, copy, nullable) NSString *selectedIOS;

@property (nonatomic, strong, nullable) NSDictionary *lastFlat;
@property (nonatomic, copy) NSString *statusText;

- (void)reloadFromDisk;
- (nullable NSDictionary *)currentDevice;
- (nullable NSDictionary *)currentIOSMeta;
- (void)ensureDefaults;

- (void)savePools;
- (void)loadPools;

- (BOOL)toggleDeviceId:(NSString *)deviceId;
- (BOOL)toggleIOS:(NSString *)ios;
- (BOOL)isDeviceSelected:(NSString *)deviceId;
- (BOOL)isIOSSelected:(NSString *)ios;

- (BOOL)toggleWipeBundleId:(NSString *)bundleId;
- (BOOL)isWipeAppSelected:(NSString *)bundleId;
- (NSString *)wipeAppsSummary;

- (NSArray<NSString *> *)compatibleIOSForSelectedDevices;
- (NSArray<NSString *> *)selectedIOSCompatibleWithDevice:(NSDictionary *)device;

- (NSString *)applyReseedOnly:(BOOL)reseedOnly;
- (NSString *)applyRandomFromPool;
/// Random spoof + wipe Zalo with optional progress (step strings).
- (NSString *)killZaloAndRandomizeFromPool;
- (NSString *)killZaloAndRandomizeFromPoolProgress:(nullable void (^)(NSString *step))progress;

- (void)killZalo;
- (NSString *)wipeZaloLab;
/// Wipe all selected Wipe-tab apps with progress.
- (NSString *)wipeSelectedAppsProgress:(nullable void (^)(NSString *step))progress;

- (BOOL)toggleForKey:(NSString *)key defaultOn:(BOOL)on;
- (void)setToggle:(BOOL)on forKey:(NSString *)key;

- (void)postDidChange;

- (NSString *)devicePoolSummary;
- (NSString *)iosPoolSummary;
@end

FOUNDATION_EXPORT NSNotificationName const AppStateDidChangeNotification;

NS_ASSUME_NONNULL_END
