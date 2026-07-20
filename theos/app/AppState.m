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
    // Merge ALL Settings toggles so dylibs gate each surface for real
    NSMutableDictionary *mflat = [flat mutableCopy];
    void (^setFlag)(NSString *, BOOL) = ^(NSString *k, BOOL def) {
        mflat[k] = @([self toggleForKey:k defaultOn:def]);
    };
    setFlag(@"FakeDevice", YES);
    setFlag(@"FakeHardware", YES);
    setFlag(@"FakeAds", YES);
    setFlag(@"FakeScreen", YES);
    setFlag(@"FakeRealScreen", YES); // nativeBounds — real pixel spoof
    setFlag(@"FakeBrowser", YES);
    setFlag(@"FakeNetwork", YES);
    setFlag(@"FakeWifi", YES);
    setFlag(@"FakeSysctl", YES);
    setFlag(@"FakeSysOSVersion", YES);
    setFlag(@"HideJailbreak", YES);
    setFlag(@"FakeLocale", YES);
    setFlag(@"FakeDateTime", NO);   // clock offset off by default (TLS safety)
    setFlag(@"FakeLocation", YES);  // now real WGS84 when on
    setFlag(@"FakeSensor", YES);
    setFlag(@"FakeWebRTC", YES);    // rewrite ICE host IP → RFC1918
    setFlag(@"DisableWebRTC", NO);
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
