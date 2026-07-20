#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared selection + apply pipeline used by Main / Select Devices / Wipe tabs.
@interface AppState : NSObject
+ (instancetype)shared;

@property (nonatomic, copy, nullable) NSString *selectedDeviceId;
@property (nonatomic, copy, nullable) NSString *selectedIOS;
@property (nonatomic, strong, nullable) NSDictionary *lastFlat;
@property (nonatomic, copy) NSString *statusText;

- (void)reloadFromDisk;
- (nullable NSDictionary *)currentDevice;
- (nullable NSDictionary *)currentIOSMeta;
- (void)ensureDefaults;

/// Apply current selection. reseedOnly keeps model/iOS and regenerates identity.
/// Returns result message for UI.
- (NSString *)applyReseedOnly:(BOOL)reseedOnly;
- (void)killZalo;
- (NSString *)wipeZaloLab;

/// Toggle prefs (NSUserDefaults). Keys match Settings UI.
- (BOOL)toggleForKey:(NSString *)key defaultOn:(BOOL)on;
- (void)setToggle:(BOOL)on forKey:(NSString *)key;

- (void)postDidChange;
@end

FOUNDATION_EXPORT NSNotificationName const AppStateDidChangeNotification;

NS_ASSUME_NONNULL_END
