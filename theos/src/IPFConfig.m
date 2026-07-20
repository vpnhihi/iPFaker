// IPFConfig.m — read merged active_profile from disk

#import "IPFConfig.h"

static NSArray<NSString *> *IPFProfileCandidates(void) {
    // Order: ChangeInfo-style /var/jb/etc first when tweak runs with jb visibility,
    // then mobile Library (RootHide app-readable for Frida / sandboxed process).
    return @[
        @"/var/jb/etc/ipfaker/active_profile.json",
        @"/var/jb/etc/ipfaker/device_profile.json",
        @"/var/mobile/Library/iPFaker/active_profile.json",
        @"/var/mobile/Library/iPFaker/device_profile.json",
        @"/var/jb/iPFaker/config/active_profile.json",
        @"/var/jb/iPFaker/config/device_profile.json",
        @"/etc/ipfaker/active_profile.json",
    ];
}

@interface IPFConfig ()
@property (nonatomic, strong, readwrite, nullable) NSDictionary *root;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *identity;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *model;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *os;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *uidevice;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *telephony;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *display;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *storage;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *mgMap;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *sysctlMap;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *jailbreakHide;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *webview;
@property (nonatomic, copy, readwrite, nullable) NSString *profilePath;
@property (nonatomic, assign, readwrite) BOOL loaded;
@property (nonatomic, assign, readwrite) BOOL enabled;
@end

@implementation IPFConfig

+ (instancetype)shared {
    static IPFConfig *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[IPFConfig alloc] init];
        [s reload];
    });
    return s;
}

- (BOOL)reload {
    self.loaded = NO;
    self.enabled = NO;
    self.root = nil;
    self.profilePath = nil;

    for (NSString *path in IPFProfileCandidates()) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *root = (NSDictionary *)obj;
        self.root = root;
        self.profilePath = path;
        self.identity = root[@"identity"];
        self.model = root[@"model"];
        self.os = root[@"os"];
        self.uidevice = root[@"uidevice"];
        self.telephony = root[@"telephony"];
        self.display = root[@"display"];
        self.storage = root[@"storage"];
        self.jailbreakHide = root[@"jailbreak_hide"];
        self.webview = root[@"webview"];

        NSDictionary *hooks = root[@"hooks"];
        if ([hooks isKindOfClass:[NSDictionary class]]) {
            self.mgMap = hooks[@"mobilegestalt"];
            self.sysctlMap = hooks[@"sysctl"];
        }
        if (!self.mgMap) self.mgMap = root[@"mobilegestalt_map"];
        if (!self.sysctlMap) self.sysctlMap = root[@"sysctl_map"];

        NSDictionary *apply = root[@"apply"];
        BOOL applyEnabled = YES;
        if ([apply isKindOfClass:[NSDictionary class]] && apply[@"enabled"] != nil) {
            applyEnabled = [apply[@"enabled"] boolValue];
        }
        self.enabled = applyEnabled;
        self.loaded = YES;
        NSLog(@"[iPFaker] config loaded: %@ enabled=%d mg=%lu sys=%lu",
              path, self.enabled,
              (unsigned long)self.mgMap.count,
              (unsigned long)self.sysctlMap.count);
        return YES;
    }

    NSLog(@"[iPFaker] config NOT found in candidate paths");
    return NO;
}

- (nullable id)mgValueForKey:(NSString *)key {
    if (!key || !self.mgMap) return nil;
    return self.mgMap[key];
}

- (nullable id)sysctlValueForName:(NSString *)name {
    if (!name || !self.sysctlMap) return nil;
    return self.sysctlMap[name];
}

- (nullable NSString *)stringForPath:(NSString *)dotPath {
    if (!dotPath || !self.root) return nil;
    NSArray *parts = [dotPath componentsSeparatedByString:@"."];
    id cur = self.root;
    for (NSString *p in parts) {
        if (![cur isKindOfClass:[NSDictionary class]]) return nil;
        cur = cur[p];
    }
    if ([cur isKindOfClass:[NSString class]]) return cur;
    if ([cur isKindOfClass:[NSNumber class]]) return [cur stringValue];
    return nil;
}

@end
