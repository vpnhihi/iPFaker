#import "AppState.h"
#import "Catalog.h"
#import "ProfileBuilder.h"

NSNotificationName const AppStateDidChangeNotification = @"AppStateDidChangeNotification";

static NSString *const kPoolDevices = @"ipf.pool.deviceIds";
static NSString *const kPoolIOS = @"ipf.pool.iosList";

@implementation AppState

+ (instancetype)shared {
    static AppState *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[AppState alloc] init];
        s.selectedDeviceIds = [NSMutableArray array];
        s.selectedIOSList = [NSMutableArray array];
        [[Catalog shared] reload];
        [s loadPools];
        [s reloadFromDisk];
        [s ensureDefaults];
    });
    return s;
}

#pragma mark - Persistence

- (void)loadPools {
    NSArray *d = [NSUserDefaults.standardUserDefaults arrayForKey:kPoolDevices];
    NSArray *i = [NSUserDefaults.standardUserDefaults arrayForKey:kPoolIOS];
    if ([d isKindOfClass:[NSArray class]] && d.count)
        self.selectedDeviceIds = [d mutableCopy];
    if ([i isKindOfClass:[NSArray class]] && i.count)
        self.selectedIOSList = [i mutableCopy];
}

- (void)savePools {
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedDeviceIds copy] forKey:kPoolDevices];
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedIOSList copy] forKey:kPoolIOS];
}

#pragma mark - Disk / defaults

- (void)reloadFromDisk {
    NSDictionary *flat = [ProfileBuilder loadCurrentFlat];
    self.lastFlat = flat;
    if (flat[@"DeviceCatalogId"]) {
        NSString *did = [flat[@"DeviceCatalogId"] description];
        self.selectedDeviceId = did;
        if (did.length && ![self.selectedDeviceIds containsObject:did])
            [self.selectedDeviceIds addObject:did];
    }
    if (flat[@"ProductVersion"]) {
        NSString *ios = [flat[@"ProductVersion"] description];
        self.selectedIOS = ios;
        if (ios.length && ![self.selectedIOSList containsObject:ios])
            [self.selectedIOSList addObject:ios];
    }
    if (flat.count) {
        self.statusText = [NSString stringWithFormat:@"Disk: %@ · iOS %@",
                           flat[@"MarketingName"] ?: @"?",
                           flat[@"ProductVersion"] ?: @"?"];
    } else if (!self.statusText.length) {
        self.statusText = @"Chưa có config — chọn máy + iOS (multi) rồi Apply / Kill Zalo";
    }
}

- (void)ensureDefaults {
    // Prune invalid device ids
    NSMutableArray *okDev = [NSMutableArray array];
    for (NSString *did in self.selectedDeviceIds) {
        if ([Catalog.shared deviceWithId:did]) [okDev addObject:did];
    }
    self.selectedDeviceIds = okDev;

    if (self.selectedDeviceIds.count == 0) {
        NSString *def = @"iphone15-pro";
        if (![Catalog.shared deviceWithId:def] && Catalog.shared.devices.count)
            def = Catalog.shared.devices.firstObject[@"id"];
        if (def.length) [self.selectedDeviceIds addObject:def];
    }
    if (!self.selectedDeviceId.length || ![self.selectedDeviceIds containsObject:self.selectedDeviceId])
        self.selectedDeviceId = self.selectedDeviceIds.firstObject;

    // Prune iOS not in union of selected devices' matrix
    NSArray *compat = [self compatibleIOSForSelectedDevices];
    NSMutableArray *okIOS = [NSMutableArray array];
    for (NSString *v in self.selectedIOSList) {
        if ([compat containsObject:v]) [okIOS addObject:v];
    }
    self.selectedIOSList = okIOS;

    if (self.selectedIOSList.count == 0) {
        NSDictionary *dev = [self currentDevice];
        NSString *defIOS = dev[@"defaultIOS"] ?: compat.lastObject ?: @"18.5";
        if (![compat containsObject:defIOS] && compat.count)
            defIOS = compat.lastObject;
        if (defIOS.length) [self.selectedIOSList addObject:defIOS];
    }
    // Primary iOS must be compatible with primary device
    NSDictionary *dev = [self currentDevice];
    if (!self.selectedIOS.length
        || ![self.selectedIOSList containsObject:self.selectedIOS]
        || (dev && ![Catalog.shared device:dev supportsIOS:self.selectedIOS])) {
        NSArray *forDev = [self selectedIOSCompatibleWithDevice:dev ?: @{}];
        self.selectedIOS = forDev.lastObject
            ?: self.selectedIOSList.firstObject
            ?: dev[@"defaultIOS"]
            ?: @"18.5";
        if (self.selectedIOS.length && ![self.selectedIOSList containsObject:self.selectedIOS])
            [self.selectedIOSList addObject:self.selectedIOS];
    }
    [self savePools];
}

- (NSDictionary *)currentDevice {
    return [[Catalog shared] deviceWithId:self.selectedDeviceId]
        ?: (self.selectedDeviceIds.count
            ? [Catalog.shared deviceWithId:self.selectedDeviceIds.firstObject]
            : Catalog.shared.devices.firstObject);
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

#pragma mark - Multi-select

- (BOOL)isDeviceSelected:(NSString *)deviceId {
    return deviceId.length && [self.selectedDeviceIds containsObject:deviceId];
}

- (BOOL)isIOSSelected:(NSString *)ios {
    return ios.length && [self.selectedIOSList containsObject:ios];
}

- (BOOL)toggleDeviceId:(NSString *)deviceId {
    if (!deviceId.length || ![Catalog.shared deviceWithId:deviceId]) return NO;
    if ([self.selectedDeviceIds containsObject:deviceId]) {
        // Keep at least one
        if (self.selectedDeviceIds.count <= 1) return YES;
        [self.selectedDeviceIds removeObject:deviceId];
        if ([self.selectedDeviceId isEqualToString:deviceId])
            self.selectedDeviceId = self.selectedDeviceIds.firstObject;
    } else {
        [self.selectedDeviceIds addObject:deviceId];
        self.selectedDeviceId = deviceId;
    }
    // Drop iOS versions no longer compatible with any remaining device
    NSArray *compat = [self compatibleIOSForSelectedDevices];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *v in self.selectedIOSList) {
        if ([compat containsObject:v]) [kept addObject:v];
    }
    self.selectedIOSList = kept;
    if (self.selectedIOSList.count == 0 && compat.count) {
        NSDictionary *dev = [self currentDevice];
        NSString *d = dev[@"defaultIOS"];
        if (d.length && [compat containsObject:d])
            [self.selectedIOSList addObject:d];
        else
            [self.selectedIOSList addObject:compat.lastObject];
    }
    if (![self.selectedIOSList containsObject:self.selectedIOS])
        self.selectedIOS = self.selectedIOSList.firstObject;
    [self savePools];
    [self postDidChange];
    return [self.selectedDeviceIds containsObject:deviceId];
}

- (BOOL)toggleIOS:(NSString *)ios {
    if (!ios.length) return NO;
    NSArray *compat = [self compatibleIOSForSelectedDevices];
    if (![compat containsObject:ios]) return NO; // not in matrix for selected devices

    if ([self.selectedIOSList containsObject:ios]) {
        if (self.selectedIOSList.count <= 1) return YES;
        [self.selectedIOSList removeObject:ios];
        if ([self.selectedIOS isEqualToString:ios])
            self.selectedIOS = self.selectedIOSList.firstObject;
    } else {
        [self.selectedIOSList addObject:ios];
        self.selectedIOS = ios;
    }
    [self savePools];
    [self postDidChange];
    return [self.selectedIOSList containsObject:ios];
}

- (NSArray<NSString *> *)compatibleIOSForSelectedDevices {
    // Union of supportedIOS for all selected devices, sorted numeric ascending
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *did in self.selectedDeviceIds) {
        NSDictionary *d = [Catalog.shared deviceWithId:did];
        if (!d) continue;
        for (NSString *v in [Catalog.shared supportedIOSForDevice:d]) {
            if (v.length) [set addObject:v];
        }
    }
    if (set.count == 0) {
        // fallback: primary device or all catalog
        NSDictionary *d = [self currentDevice];
        for (NSString *v in [Catalog.shared supportedIOSForDevice:d ?: @{}])
            if (v.length) [set addObject:v];
    }
    if (set.count == 0)
        return Catalog.shared.iosVersionsSorted ?: @[];
    return [[set allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];
}

- (NSArray<NSString *> *)selectedIOSCompatibleWithDevice:(NSDictionary *)device {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *v in self.selectedIOSList) {
        if ([Catalog.shared device:device supportsIOS:v])
            [out addObject:v];
    }
    // Sort newest last for convenience
    [out sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];
    return out;
}

- (NSString *)devicePoolSummary {
    NSUInteger n = self.selectedDeviceIds.count;
    if (n == 0) return @"Chưa chọn đời máy";
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *did in self.selectedDeviceIds) {
        NSDictionary *d = [Catalog.shared deviceWithId:did];
        [names addObject:d[@"MarketingName"] ?: did];
        if (names.count >= 3) break;
    }
    NSString *head = [names componentsJoinedByString:@", "];
    if (n > names.count)
        return [NSString stringWithFormat:@"%lu máy: %@…", (unsigned long)n, head];
    if (n == 1) {
        NSDictionary *d = [Catalog.shared deviceWithId:self.selectedDeviceIds.firstObject];
        return [NSString stringWithFormat:@"%@ · %@",
                d[@"MarketingName"] ?: @"?", d[@"ProductType"] ?: @"?"];
    }
    return [NSString stringWithFormat:@"%lu máy: %@", (unsigned long)n, head];
}

- (NSString *)iosPoolSummary {
    NSUInteger n = self.selectedIOSList.count;
    if (n == 0) return @"Chưa chọn iOS";
    // Show newest-first snippet
    NSArray *sorted = [self.selectedIOSList sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a options:NSNumericSearch];
    }];
    NSMutableArray *bits = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN((NSUInteger)4, sorted.count); i++)
        [bits addObject:sorted[i]];
    NSString *head = [bits componentsJoinedByString:@", "];
    if (n > bits.count)
        return [NSString stringWithFormat:@"%lu bản: %@…", (unsigned long)n, head];
    return [NSString stringWithFormat:@"%lu bản: iOS %@", (unsigned long)n, head];
}

#pragma mark - Apply / random pool

/// Pick random device from pool + random iOS from pool that matrix allows for that device.
- (BOOL)pickRandomPairDevice:(NSDictionary **)outDev ios:(NSString **)outIOS error:(NSString **)err {
    [self ensureDefaults];
    if (self.selectedDeviceIds.count == 0) {
        if (err) *err = @"Chưa chọn đời máy nào";
        return NO;
    }

    // Build list of valid (deviceId, ios) pairs from pools + matrix
    NSMutableArray<NSDictionary *> *pairs = [NSMutableArray array];
    for (NSString *did in self.selectedDeviceIds) {
        NSDictionary *dev = [Catalog.shared deviceWithId:did];
        if (!dev) continue;
        NSArray *iosOpts = [self selectedIOSCompatibleWithDevice:dev];
        if (iosOpts.count == 0) {
            // Pool iOS empty for this device — use full matrix for device as fallback
            iosOpts = [Catalog.shared supportedIOSForDevice:dev];
        }
        for (NSString *v in iosOpts) {
            if (!Catalog.shared.iosReleases[v]) continue;
            [pairs addObject:@{ @"device": dev, @"ios": v }];
        }
    }
    if (pairs.count == 0) {
        if (err) *err = @"Không có cặp máy+iOS hợp lệ trong matrix. Chọn lại đời máy / iOS.";
        return NO;
    }
    NSDictionary *pick = pairs[arc4random_uniform((uint32_t)pairs.count)];
    if (outDev) *outDev = pick[@"device"];
    if (outIOS) *outIOS = pick[@"ios"];
    return YES;
}

- (NSString *)applyWithDevice:(NSDictionary *)dev ios:(NSString *)ios {
    if (!dev) return @"Catalog trống";
    NSDictionary *meta = Catalog.shared.iosReleases[ios];
    if (!meta) return [NSString stringWithFormat:@"Không có iOS %@ trong catalog", ios];

    // Strict matrix guard
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
        if (!sup.count) return @"Máy này không có iOS trong matrix";
        ios = sup.lastObject;
        meta = Catalog.shared.iosReleases[ios];
        if (!meta) return @"iOS matrix lỗi";
    }

    self.selectedDeviceId = dev[@"id"];
    self.selectedIOS = ios;
    if (self.selectedDeviceId.length && ![self.selectedDeviceIds containsObject:self.selectedDeviceId])
        [self.selectedDeviceIds addObject:self.selectedDeviceId];
    if (ios.length && ![self.selectedIOSList containsObject:ios])
        [self.selectedIOSList addObject:ios];
    [self savePools];

    // Full identity from ProfileBuilder — hardware/catalog synced to device template
    NSDictionary *flat = [ProfileBuilder flatProfileForDevice:dev ios:ios iosMeta:meta deviceName:nil];
    NSMutableDictionary *mflat = [flat mutableCopy];
    void (^setFlag)(NSString *, BOOL) = ^(NSString *k, BOOL def) {
        mflat[k] = @([self toggleForKey:k defaultOn:def]);
    };
    setFlag(@"FakeDevice", YES);
    setFlag(@"FakeHardware", YES);
    setFlag(@"FakeAds", YES);
    setFlag(@"FakeScreen", YES);
    setFlag(@"FakeRealScreen", YES);
    setFlag(@"FakeBrowser", YES);
    setFlag(@"FakeNetwork", YES);
    setFlag(@"FakeWifi", YES);
    setFlag(@"FakeSysctl", YES);
    setFlag(@"FakeSysOSVersion", YES);
    setFlag(@"HideJailbreak", YES);
    setFlag(@"FakeLocale", YES);
    setFlag(@"FakeDateTime", NO);
    setFlag(@"FakeLocation", YES);
    setFlag(@"FakeSensor", YES);
    setFlag(@"FakeWebRTC", YES);
    setFlag(@"DisableWebRTC", NO);
    // Pool metadata for lab debug
    mflat[@"SelectedDevicePool"] = [self.selectedDeviceIds copy];
    mflat[@"SelectedIOSPool"] = [self.selectedIOSList copy];
    flat = mflat;

    NSString *result = [ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    self.lastFlat = flat;
    self.statusText = [NSString stringWithFormat:@"%@ · %@ / iOS %@",
                       result ?: @"OK",
                       dev[@"MarketingName"] ?: dev[@"id"],
                       ios];
    [self postDidChange];
    return self.statusText;
}

- (NSString *)applyReseedOnly:(BOOL)reseedOnly {
    (void)reseedOnly;
    // Apply primary pair (or fix matrix) — full new identity
    NSDictionary *dev = [self currentDevice];
    if (!dev) return @"Catalog trống — thiếu device_catalog.json";
    NSString *ios = self.selectedIOS ?: dev[@"defaultIOS"] ?: @"18.5";
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        NSArray *forDev = [self selectedIOSCompatibleWithDevice:dev];
        if (forDev.count) ios = forDev.lastObject;
        else {
            NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
            if (!sup.count) return @"Máy này không có iOS trong matrix";
            ios = sup.lastObject;
        }
    }
    return [self applyWithDevice:dev ios:ios];
}

- (NSString *)applyRandomFromPool {
    NSDictionary *dev = nil;
    NSString *ios = nil;
    NSString *err = nil;
    if (![self pickRandomPairDevice:&dev ios:&ios error:&err])
        return err ?: @"Random pool thất bại";
    NSString *msg = [self applyWithDevice:dev ios:ios];
    return [NSString stringWithFormat:@"Random: %@ + iOS %@\n%@",
            dev[@"MarketingName"] ?: dev[@"id"], ios, msg];
}

- (NSString *)killZaloAndRandomizeFromPool {
    // 1) Random full profile FIRST (spoof ready before next open)
    NSString *applyMsg = [self applyRandomFromPool];
    // 2) Full 100% wipe Zalo data (account gone) + kill
    NSString *wipeMsg = [ProfileBuilder wipeZaloFull];
    self.statusText = [NSString stringWithFormat:
                       @"%@\n\n%@\n\n→ Mở Zalo = máy mới + form login trống.",
                       applyMsg, wipeMsg];
    [self postDidChange];
    return self.statusText;
}

- (void)killZalo {
    // Kill button = random identity from pool + wipe 100% Zalo data
    (void)[self killZaloAndRandomizeFromPool];
}

- (NSString *)wipeZaloLab {
    // Wipe tab: full wipe only (keep current spoof profile)
    NSString *m = [ProfileBuilder wipeZaloFull];
    self.statusText = m ?: @"Wipe done";
    [self postDidChange];
    return self.statusText;
}

#pragma mark - Toggles

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
