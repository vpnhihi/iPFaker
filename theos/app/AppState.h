#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared selection + apply pipeline used by Main / Select Devices / Wipe tabs.
@interface AppState : NSObject
+ (instancetype)shared;

/// Multi-select pools (persisted). At least one device + one iOS after ensureDefaults.
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedDeviceIds;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIOSList;
/// Wipe tab multi-select (default: Maps + Weather + Safari).
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedWipeBundleIds;
/// Multi-app spoof inject targets (default: Zalo). Written to TweakInject filter plists.
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedSpoofBundleIds;

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
/// Select all devices in catalog.
- (void)selectAllDevices;
/// Select all iOS versions compatible with current device pool.
- (void)selectAllIOS;

- (BOOL)toggleWipeBundleId:(NSString *)bundleId;
- (BOOL)isWipeAppSelected:(NSString *)bundleId;
- (NSString *)wipeAppsSummary;

- (BOOL)toggleSpoofBundleId:(NSString *)bundleId;
- (BOOL)isSpoofAppSelected:(NSString *)bundleId;
- (NSString *)spoofAppsSummary;
- (void)selectAllSpoofAppsFromCatalog:(NSArray *)items;
- (void)deselectAllSpoofAppsKeepingZalo:(BOOL)keepZalo;
/// Write ElleKit filter plists for MG/CT/JB from selected spoof apps.
- (NSString *)applySpoofAppFiltersProgress:(nullable void (^)(NSString *step))progress;

- (NSArray<NSString *> *)compatibleIOSForSelectedDevices;
- (NSArray<NSString *> *)selectedIOSCompatibleWithDevice:(NSDictionary *)device;

- (NSString *)applyReseedOnly:(BOOL)reseedOnly;
- (NSString *)applyRandomFromPool;
/// Random spoof + wipe data (không giữ đăng nhập).
- (NSString *)killZaloAndRandomizeFromPool;
- (NSString *)killZaloAndRandomizeFromPoolProgress:(nullable void (^)(NSString *step))progress;

/// Đặt lại + Lưu: lưu 100% thông số máy + data app (giữ phiên đăng nhập) → random máy → xóa → khôi phục data.
- (NSString *)saveDataThenResetProgress:(nullable void (^)(NSString *step))progress;

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
