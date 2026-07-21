#import "Catalog.h"

@interface Catalog ()
@property (nonatomic, strong) NSArray<NSDictionary *> *devices;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *iosReleases;
@property (nonatomic, strong) NSDictionary *deviceToIOS; // ios_device_compat.device_to_ios
@end

@implementation Catalog

+ (instancetype)shared {
    static Catalog *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[Catalog alloc] init];
        [s reload];
    });
    return s;
}

- (void)loadCompatMatrix {
    NSArray *paths = @[
        [[NSBundle mainBundle] pathForResource:@"ios_device_compat" ofType:@"json"] ?: @"",
        @"/var/mobile/Library/iPFaker/ios_device_compat.json",
        @"/var/jb/etc/ipfaker/ios_device_compat.json",
    ];
    for (NSString *p in paths) {
        if (p.length == 0) continue;
        NSData *data = [NSData dataWithContentsOfFile:p];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *map = obj[@"device_to_ios"];
        if ([map isKindOfClass:[NSDictionary class]]) {
            self.deviceToIOS = map;
            return;
        }
    }
    self.deviceToIOS = @{};
}

- (BOOL)reload {
    NSArray *paths = @[
        [[NSBundle mainBundle] pathForResource:@"device_catalog" ofType:@"json"] ?: @"",
        @"/var/mobile/Library/iPFaker/device_catalog.json",
        @"/var/jb/etc/ipfaker/device_catalog.json",
    ];
    for (NSString *p in paths) {
        if (p.length == 0) continue;
        NSData *data = [NSData dataWithContentsOfFile:p];
        if (!data) continue;
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *root = obj;
        NSArray *devs = root[@"devices"];
        NSDictionary *ios = root[@"ios_releases"];
        if ([devs isKindOfClass:[NSArray class]] && [ios isKindOfClass:[NSDictionary class]]) {
            self.devices = devs;
            self.iosReleases = ios;
            [self loadCompatMatrix];
            return YES;
        }
    }
    self.devices = @[];
    self.iosReleases = @{};
    self.deviceToIOS = @{};
    return NO;
}

- (NSArray<NSString *> *)iosVersionsSorted {
    return [[self.iosReleases allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];
}

- (NSDictionary *)deviceWithId:(NSString *)deviceId {
    for (NSDictionary *d in self.devices) {
        if ([d[@"id"] isEqualToString:deviceId]) return d;
    }
    return nil;
}

- (NSArray<NSString *> *)supportedIOSForDevice:(NSDictionary *)device {
    // Prefer embedded supportedIOS (full wall); fallback compatInherit / id map
    id arr = device[@"supportedIOS"];
    if ([arr isKindOfClass:[NSArray class]] && [arr count] > 0)
        return arr;
    NSString *did = device[@"id"] ?: @"";
    NSString *inherit = device[@"compatInherit"] ?: did;
    if (!self.deviceToIOS.count) [self loadCompatMatrix];
    id fromMap = self.deviceToIOS[inherit] ?: self.deviceToIOS[did];
    if ([fromMap isKindOfClass:[NSArray class]])
        return fromMap;
    return @[];
}

- (BOOL)device:(NSDictionary *)device supportsIOS:(NSString *)ios {
    if (!ios.length) return NO;
    return [[self supportedIOSForDevice:device] containsObject:ios];
}

@end
