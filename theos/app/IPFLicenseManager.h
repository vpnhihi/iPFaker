#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IPFLicenseStatus) {
    IPFLicenseStatusUnknown = 0,
    IPFLicenseStatusActive,   // Chạy
    IPFLicenseStatusPaused,   // Dừng
    IPFLicenseStatusOut,      // Out
    IPFLicenseStatusInvalid,
};

@interface IPFLicenseManager : NSObject
+ (instancetype)shared;

/// Local lab id (optional UI / license.json only — not required on Sheet).
- (NSString *)deviceId;

/// Local session currently unlocked for use.
- (BOOL)isSessionActive;

/// Human status for UI.
- (NSString *)statusSummary;

/// Last error / message from check.
@property (nonatomic, copy, nullable) NSString *lastMessage;

/// Days remaining (frozen while paused). 0 = hết hạn; unlimited sheet days → large remaining.
- (NSInteger)daysRemaining;

/**
 Activate with key from Sheet:
 - Cột B = Key (bắt buộc)
 - Cột E = Tình trạng: Chạy / Dừng / Out (bắt buộc)
 - Cột C (Hạn) và D (ID máy) không bắt buộc — bỏ check ID máy.
 */
- (void)activateWithKey:(NSString *)key
             completion:(void (^)(BOOL ok, NSString *message))completion;

/// Re-check sheet (status/days). Call on launch if session exists.
- (void)revalidateWithCompletion:(void (^)(BOOL ok, NSString *message))completion;

/// Local logout (also used for Out / Dừng).
- (void)logout;

/// Force clear all license local state.
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
