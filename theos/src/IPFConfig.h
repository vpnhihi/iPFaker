// IPFConfig — lab dual-path: prefer config.plist flat keys at /var/jb/etc/ipfaker/config.plist

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IPFConfig : NSObject

@property (nonatomic, strong, readonly, nullable) NSDictionary *root;
@property (nonatomic, strong, readonly, nullable) NSDictionary *identity;
@property (nonatomic, strong, readonly, nullable) NSDictionary *model;
@property (nonatomic, strong, readonly, nullable) NSDictionary *os;
@property (nonatomic, strong, readonly, nullable) NSDictionary *uidevice;
@property (nonatomic, strong, readonly, nullable) NSDictionary *telephony;
@property (nonatomic, strong, readonly, nullable) NSDictionary *display;
@property (nonatomic, strong, readonly, nullable) NSDictionary *storage;
@property (nonatomic, strong, readonly, nullable) NSDictionary *mgMap;
@property (nonatomic, strong, readonly, nullable) NSDictionary *sysctlMap;
@property (nonatomic, strong, readonly, nullable) NSDictionary *jailbreakHide;
@property (nonatomic, strong, readonly, nullable) NSDictionary *webview;
@property (nonatomic, copy, readonly, nullable) NSString *profilePath;
@property (nonatomic, assign, readonly) BOOL loaded;
@property (nonatomic, assign, readonly) BOOL enabled;
/// Flat lab flat map (includes Fake* flags + locale/location extras).
@property (nonatomic, strong, readonly, nullable) NSDictionary *flat;

+ (instancetype)shared;
- (BOOL)reload;
- (nullable id)mgValueForKey:(NSString *)key;
- (nullable id)sysctlValueForName:(NSString *)name;
- (nullable NSString *)stringForKey:(NSString *)key;
/// Feature toggle from config.plist (FakeDevice, HideJailbreak, …). Missing → defaultYes.
- (BOOL)flag:(NSString *)key defaultYes:(BOOL)defaultYes;
- (double)doubleForKey:(NSString *)key fallback:(double)fb;

@end

NS_ASSUME_NONNULL_END
