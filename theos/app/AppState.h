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
/// Lab-core preset: Zalo + Safari + Maps + Weather (+ WebKit helpers auto in filter).
- (void)applyLabCoreSpoofPreset;
/// Lab stock system apps (+ Zalo) multi-app list.
- (void)applyLabStockSpoofPreset;
/// Lab social multi-app: Zalo + FB/IG/TikTok/Shopee/Telegram + Safari/Maps…
- (void)applyLabSocialSpoofPreset;
/// Write ElleKit filter plists for MG/CT/JB from selected spoof apps.
- (NSString *)applySpoofAppFiltersProgress:(nullable void (^)(NSString *step))progress;
/// Bundle IDs for Lab-core spoof (synced identity across those apps).
+ (NSArray<NSString *> *)labCoreSpoofBundleIds;

- (NSArray<NSString *> *)compatibleIOSForSelectedDevices;
- (NSArray<NSString *> *)selectedIOSCompatibleWithDevice:(NSDictionary *)device;

- (NSString *)applyReseedOnly:(BOOL)reseedOnly;
- (NSString *)applyRandomFromPool;
/// «Đặt lại dữ liệu app» (1 chạm đầy đủ): Lab-core filter + mitigation flags + proxy/geo
/// random-in-city + spoof random + wipe full + kill + relaunch (mất đăng nhập).
- (NSString *)killZaloAndRandomizeFromPool;
- (NSString *)killZaloAndRandomizeFromPoolProgress:(nullable void (^)(NSString *step))progress;

/// 1 chạm «Đặt lại + Lưu»: backup session → random spoof → soft wipe+restore → geo → kill+relaunch (giữ đăng nhập).
- (NSString *)saveDataThenResetProgress:(nullable void (^)(NSString *step))progress;

/// Alias lịch sử → cùng «Đặt lại dữ liệu app» (full wall).
- (NSString *)vuotZaloOneTapProgress:(nullable void (^)(NSString *step))progress;

/// Parse paste `host:port:user:pass` (user/pass optional). Returns YES if host+port valid.
- (BOOL)applyProxyPasteLine:(NSString *)line error:(NSString * _Nullable * _Nullable)errOut;
/// Sync NSUserDefaults proxy fields from dual-path config.plist (device wall).
- (void)loadProxyFromDualPathConfig;

- (void)killZalo;
- (NSString *)wipeZaloLab;
/// Wipe all selected Wipe-tab apps with progress.
- (NSString *)wipeSelectedAppsProgress:(nullable void (^)(NSString *step))progress;

- (BOOL)toggleForKey:(NSString *)key defaultOn:(BOOL)on;
- (void)setToggle:(BOOL)on forKey:(NSString *)key;

#pragma mark - Proxy / AppAttest (lab flat)
- (BOOL)proxyEnabled;
- (void)setProxyEnabled:(BOOL)on;
- (NSString *)proxyHost;
- (void)setProxyHost:(NSString *)host;
- (NSInteger)proxyPort;
- (void)setProxyPort:(NSInteger)port;
- (NSString *)proxyType; // HTTP | SOCKS5
- (void)setProxyType:(NSString *)type;
- (NSString *)proxyUsername;
- (void)setProxyUsername:(NSString *)user;
- (NSString *)proxyPassword;
- (void)setProxyPassword:(NSString *)pass;
- (BOOL)disableAppAttest;
- (void)setDisableAppAttest:(BOOL)on;
- (void)saveProxyAppAttest;
- (BOOL)syncGeoFromProxyEnabled;
- (void)setSyncGeoFromProxyEnabled:(BOOL)on;
/// Merge proxy/AppAttest keys into config.plist dual-path for dylibs.
- (NSString *)applyProxyAppAttestToConfigProgress:(nullable void (^)(NSString *step))progress;
/// TCP/HTTP connectivity check through configured proxy.
- (NSString *)testProxyConnection;
/// Geo IP (lat/lon/IANA TZ/locale) via proxy egress — sync map/weather/time. Returns summary for UI.
/// Lat/lon are randomized inside city bounding box (Maps/Weather/spoof apps share same dual-path keys).
- (NSString *)syncTimeMapWeatherFromProxyProgress:(nullable void (^)(NSString *step))progress
                                      geoKeysOut:(NSDictionary * _Nullable * _Nullable)keysOut;

/// After «Đặt lại…»: if proxy ON, write proxy keys + random-in-city geo to dual-path config.
- (NSString *)attachProxyGeoRandomInCityProgress:(nullable void (^)(NSString *step))progress;

- (void)postDidChange;

- (NSString *)devicePoolSummary;
- (NSString *)iosPoolSummary;
@end

FOUNDATION_EXPORT NSNotificationName const AppStateDidChangeNotification;

NS_ASSUME_NONNULL_END
