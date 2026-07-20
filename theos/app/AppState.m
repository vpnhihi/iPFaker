#import "AppState.h"
#import "Catalog.h"
#import "ProfileBuilder.h"

NSNotificationName const AppStateDidChangeNotification = @"AppStateDidChangeNotification";

@implementation AppState

+ (instancetype)shared {
    static AppState *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[AppState alloc] init];
        [[Catalog shared] reload];
        [s reloadFromDisk];
        [s ensureDefaults];
    });
    return s;
}

- (void)reloadFromDisk {
    NSDictionary *flat = [ProfileBuilder loadCurrentFlat];
    self.lastFlat = flat;
    if (flat[@"DeviceCatalogId"])
        self.selectedDeviceId = [flat[@"DeviceCatalogId"] description];
    if (flat[@"ProductVersion"])
        self.selectedIOS = [flat[@"ProductVersion"] description];
    if (flat.count) {
        self.statusText = [NSString stringWithFormat:@"Disk: %@ · iOS %@",
                           flat[@"MarketingName"] ?: @"?",
                           flat[@"ProductVersion"] ?: @"?"];
    } else {
        self.statusText = @"Chưa có config trên disk — chọn máy + iOS rồi Apply";
    }
}

- (void)ensureDefaults {
    if (!self.selectedDeviceId.length) {
        self.selectedDeviceId = @"iphone15-pro";
        if (![Catalog.shared deviceWithId:self.selectedDeviceId] && Catalog.shared.devices.count)
            self.selectedDeviceId = Catalog.shared.devices.firstObject[@"id"];
    }
    if (!self.selectedIOS.length) {
        NSDictionary *dev = [self currentDevice];
        self.selectedIOS = dev[@"defaultIOS"] ?: @"18.5";
    }
}

- (NSDictionary *)currentDevice {
    return [[Catalog shared] deviceWithId:self.selectedDeviceId]
        ?: Catalog.shared.devices.firstObject;
}

- (NSDictionary *)currentIOSMeta {
    NSString *ios = self.selectedIOS ?: @"18.5";
    NSDictionary *m = Catalog.shared.iosReleases[ios];
    if (m) return m;
    NSDictionary *dev = [self currentDevice];
    ios = dev[@"defaultIOS"] ?: @"18.5";
    self.selectedIOS = ios;
    return Catalog.shared.iosReleases[ios] ?: @{ @"ProductVersion": ios, @"BuildVersion": @"?" };
}

- (NSString *)applyReseedOnly:(BOOL)reseedOnly {
    NSDictionary *dev = [self currentDevice];
    if (!dev) return @"Catalog trống — thiếu device_catalog.json";

    NSString *ios = self.selectedIOS ?: dev[@"defaultIOS"] ?: @"18.5";
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
        if (sup.count) {
            ios = sup.lastObject;
            self.selectedIOS = ios;
        } else {
            return @"Máy này không có iOS trong matrix";
        }
    }
    NSDictionary *meta = Catalog.shared.iosReleases[ios];
    if (!meta) {
        ios = dev[@"defaultIOS"] ?: @"18.5";
        meta = Catalog.shared.iosReleases[ios];
        self.selectedIOS = ios;
    }
    if (!meta) return @"Không tìm thấy iOS trong catalog";

    // If reseedOnly and we already have flat for same model/ios, rebuild identity only
    // (flatProfile always regenerates serial/IDFA — same as full apply for lab)
    (void)reseedOnly;
    NSDictionary *flat = [ProfileBuilder flatProfileForDevice:dev ios:ios iosMeta:meta deviceName:nil];
    // Merge Settings toggles into flat so dylibs can respect Enabled flags later
    NSMutableDictionary *mflat = [flat mutableCopy];
    mflat[@"FakeDevice"] = @([self toggleForKey:@"FakeDevice" defaultOn:YES]);
    mflat[@"FakeHardware"] = @([self toggleForKey:@"FakeHardware" defaultOn:YES]);
    mflat[@"FakeAds"] = @([self toggleForKey:@"FakeAds" defaultOn:YES]);
    mflat[@"FakeScreen"] = @([self toggleForKey:@"FakeScreen" defaultOn:YES]);
    mflat[@"FakeBrowser"] = @([self toggleForKey:@"FakeBrowser" defaultOn:YES]);
    mflat[@"FakeNetwork"] = @([self toggleForKey:@"FakeNetwork" defaultOn:YES]);
    mflat[@"FakeSysctl"] = @([self toggleForKey:@"FakeSysctl" defaultOn:YES]);
    mflat[@"FakeSysOSVersion"] = @([self toggleForKey:@"FakeSysOSVersion" defaultOn:YES]);
    mflat[@"HideJailbreak"] = @([self toggleForKey:@"HideJailbreak" defaultOn:YES]);
    flat = mflat;

    NSString *result = [ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    self.lastFlat = flat;
    self.statusText = result ?: @"OK";
    [self postDidChange];
    return result ?: @"OK";
}

- (void)killZalo {
    [ProfileBuilder killZalo];
    self.statusText = @"Đã kill Zalo. Mở lại Zalo để load spoof.";
    [self postDidChange];
}

- (NSString *)wipeZaloLab {
    NSString *m = [ProfileBuilder wipeZaloLab];
    self.statusText = m ?: @"Wipe note";
    [self postDidChange];
    return self.statusText;
}

- (BOOL)toggleForKey:(NSString *)key defaultOn:(BOOL)on {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *k = [@"ipf.toggle." stringByAppendingString:key];
    if ([ud objectForKey:k] == nil) return on;
    return [ud boolForKey:k];
}

- (void)setToggle:(BOOL)on forKey:(NSString *)key {
    NSString *k = [@"ipf.toggle." stringByAppendingString:key];
    [NSUserDefaults.standardUserDefaults setBool:on forKey:k];
}

- (void)postDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:AppStateDidChangeNotification object:self];
}

@end
