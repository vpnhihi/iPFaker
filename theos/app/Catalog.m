#import "Catalog.h"

@interface Catalog ()
@property (nonatomic, strong) NSArray<NSDictionary *> *devices;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *iosReleases;
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
            return YES;
        }
    }
    self.devices = @[];
    self.iosReleases = @{};
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

@end
