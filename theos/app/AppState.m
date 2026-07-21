#import "AppState.h"
#import "Catalog.h"
#import "ProfileBuilder.h"
#import <CFNetwork/CFNetwork.h>

NSNotificationName const AppStateDidChangeNotification = @"AppStateDidChangeNotification";

static NSString *const kPoolDevices = @"ipf.pool.deviceIds";
static NSString *const kPoolIOS = @"ipf.pool.iosList";
static NSString *const kPoolWipeApps = @"ipf.pool.wipeBundleIds";
static NSString *const kPoolSpoofApps = @"ipf.pool.spoofBundleIds";

@implementation AppState

+ (instancetype)shared {
    static AppState *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[AppState alloc] init];
        s.selectedDeviceIds = [NSMutableArray array];
        s.selectedIOSList = [NSMutableArray array];
        s.selectedWipeBundleIds = [NSMutableArray array];
        s.selectedSpoofBundleIds = [NSMutableArray array];
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
    NSArray *w = [NSUserDefaults.standardUserDefaults arrayForKey:kPoolWipeApps];
    NSArray *sp = [NSUserDefaults.standardUserDefaults arrayForKey:kPoolSpoofApps];
    if ([d isKindOfClass:[NSArray class]] && d.count)
        self.selectedDeviceIds = [d mutableCopy];
    if ([i isKindOfClass:[NSArray class]] && i.count)
        self.selectedIOSList = [i mutableCopy];
    if ([w isKindOfClass:[NSArray class]] && w.count)
        self.selectedWipeBundleIds = [w mutableCopy];
    if ([sp isKindOfClass:[NSArray class]] && sp.count)
        self.selectedSpoofBundleIds = [sp mutableCopy];
}

- (void)savePools {
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedDeviceIds copy] forKey:kPoolDevices];
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedIOSList copy] forKey:kPoolIOS];
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedWipeBundleIds copy] forKey:kPoolWipeApps];
    [NSUserDefaults.standardUserDefaults setObject:[self.selectedSpoofBundleIds copy] forKey:kPoolSpoofApps];
    // PC app đọc pool từ đây (không chọn máy/iOS trên PC)
    @try {
        NSString *dir = @"/var/mobile/Library/iPFaker";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *pools = @{
            @"devices": [self.selectedDeviceIds copy] ?: @[],
            @"ios": [self.selectedIOSList copy] ?: @[],
            @"wipeApps": [self.selectedWipeBundleIds copy] ?: @[],
            @"spoofApps": [self.selectedSpoofBundleIds copy] ?: @[],
            @"updated": @([[NSDate date] timeIntervalSince1970]),
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:pools options:NSJSONWritingPrettyPrinted error:nil];
        if (json) [json writeToFile:[dir stringByAppendingPathComponent:@"pools.json"] atomically:YES];
    } @catch (__unused NSException *ex) {}
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
        self.statusText = @"Chưa có cấu hình — chọn máy + iOS rồi «Đặt lại + Lưu dữ liệu»";
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
    // Default wipe apps: Maps + Weather + Safari (Bản đồ, Thời tiết, Safari)
    if (self.selectedWipeBundleIds.count == 0) {
        [self.selectedWipeBundleIds addObjectsFromArray:@[
            @"com.apple.Maps",
            @"com.apple.weather",
            @"com.apple.mobilesafari",
        ]];
    } else {
        // Migrate classic Maps+Weather default → also include Safari (once)
        NSArray *classic = @[ @"com.apple.Maps", @"com.apple.weather" ];
        BOOL isClassicDefault =
            self.selectedWipeBundleIds.count == 2
            && [self.selectedWipeBundleIds containsObject:classic[0]]
            && [self.selectedWipeBundleIds containsObject:classic[1]]
            && ![self.selectedWipeBundleIds containsObject:@"com.apple.mobilesafari"];
        if (isClassicDefault) {
            [self.selectedWipeBundleIds addObject:@"com.apple.mobilesafari"];
            [self savePools];
        }
    }
    // Multi-app spoof default: Zalo only (lab wall). Settings never injected.
    if (self.selectedSpoofBundleIds.count == 0) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    } else {
        [self.selectedSpoofBundleIds removeObject:@"com.apple.Preferences"];
        BOOL hasZalo = NO;
        for (NSString *b in self.selectedSpoofBundleIds) {
            if ([b.lowercaseString containsString:@"zalo"] || [b.lowercaseString containsString:@"zing"]) {
                hasZalo = YES; break;
            }
        }
        if (!hasZalo) {
            [self.selectedSpoofBundleIds insertObject:@"vn.com.vng.zingalo" atIndex:0];
            [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
        }
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

- (void)selectAllDevices {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *d in Catalog.shared.devices) {
        NSString *did = d[@"id"];
        if (did.length) [ids addObject:did];
    }
    if (ids.count == 0) return;
    self.selectedDeviceIds = ids;
    if (!self.selectedDeviceId.length || ![self.selectedDeviceIds containsObject:self.selectedDeviceId])
        self.selectedDeviceId = self.selectedDeviceIds.firstObject;
    // Prune/refresh iOS pool against new device set
    NSArray *compat = [self compatibleIOSForSelectedDevices];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *v in self.selectedIOSList) {
        if ([compat containsObject:v]) [kept addObject:v];
    }
    self.selectedIOSList = kept;
    if (self.selectedIOSList.count == 0 && compat.count)
        [self.selectedIOSList addObject:compat.lastObject];
    if (![self.selectedIOSList containsObject:self.selectedIOS])
        self.selectedIOS = self.selectedIOSList.firstObject;
    [self savePools];
    [self postDidChange];
}

- (void)selectAllIOS {
    NSArray *compat = [self compatibleIOSForSelectedDevices];
    if (compat.count == 0) return;
    self.selectedIOSList = [compat mutableCopy];
    if (!self.selectedIOS.length || ![self.selectedIOSList containsObject:self.selectedIOS])
        self.selectedIOS = self.selectedIOSList.lastObject;
    [self savePools];
    [self postDidChange];
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

#pragma mark - Wipe app multi-select

- (BOOL)isWipeAppSelected:(NSString *)bundleId {
    return bundleId.length && [self.selectedWipeBundleIds containsObject:bundleId];
}

- (BOOL)toggleWipeBundleId:(NSString *)bundleId {
    if (!bundleId.length) return NO;
    if ([self.selectedWipeBundleIds containsObject:bundleId]) {
        // Allow empty wipe pool? Keep at least 0 is OK for wipe tab
        [self.selectedWipeBundleIds removeObject:bundleId];
    } else {
        [self.selectedWipeBundleIds addObject:bundleId];
    }
    [self savePools];
    [self postDidChange];
    return [self.selectedWipeBundleIds containsObject:bundleId];
}

#pragma mark - Multi-app spoof

- (BOOL)isSpoofAppSelected:(NSString *)bundleId {
    return bundleId.length && [self.selectedSpoofBundleIds containsObject:bundleId];
}

- (BOOL)toggleSpoofBundleId:(NSString *)bundleId {
    if (!bundleId.length) return NO;
    if ([bundleId isEqualToString:@"com.apple.Preferences"]) return NO;
    if ([self.selectedSpoofBundleIds containsObject:bundleId]) {
        // Never leave empty — keep at least one Zalo id
        BOOL isZalo = [bundleId.lowercaseString containsString:@"zalo"]
            || [bundleId.lowercaseString containsString:@"zing"];
        if (isZalo) {
            NSUInteger zaloCount = 0;
            for (NSString *b in self.selectedSpoofBundleIds) {
                if ([b.lowercaseString containsString:@"zalo"] || [b.lowercaseString containsString:@"zing"])
                    zaloCount++;
            }
            if (zaloCount <= 1 && self.selectedSpoofBundleIds.count <= 2)
                return YES; // refuse deselect last zalo when only zalo selected
        }
        [self.selectedSpoofBundleIds removeObject:bundleId];
        if (self.selectedSpoofBundleIds.count == 0) {
            [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
            [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
        }
    } else {
        [self.selectedSpoofBundleIds addObject:bundleId];
    }
    [self savePools];
    [self postDidChange];
    return [self.selectedSpoofBundleIds containsObject:bundleId];
}

- (void)selectAllSpoofAppsFromCatalog:(NSArray *)items {
    [self.selectedSpoofBundleIds removeAllObjects];
    for (id it in items) {
        NSString *bid = nil;
        if ([it respondsToSelector:@selector(bundleId)])
            bid = [it valueForKey:@"bundleId"];
        else if ([it isKindOfClass:[NSString class]])
            bid = (NSString *)it;
        if (!bid.length) continue;
        if ([bid isEqualToString:@"com.apple.Preferences"]) continue;
        if (![self.selectedSpoofBundleIds containsObject:bid])
            [self.selectedSpoofBundleIds addObject:bid];
    }
    if (self.selectedSpoofBundleIds.count == 0) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    }
    [self savePools];
    [self postDidChange];
}

- (void)deselectAllSpoofAppsKeepingZalo:(BOOL)keepZalo {
    [self.selectedSpoofBundleIds removeAllObjects];
    if (keepZalo) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    }
    [self savePools];
    [self postDidChange];
}

- (NSString *)spoofAppsSummary {
    NSUInteger n = self.selectedSpoofBundleIds.count;
    if (n == 0) return @"Chưa chọn app spoof";
    if (n <= 3) return [self.selectedSpoofBundleIds componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"%lu app spoof (Zalo + …)", (unsigned long)n];
}

- (NSString *)applySpoofAppFiltersProgress:(void (^)(NSString *))progress {
    [self ensureDefaults];
    if (progress) progress(@"Ghi danh sách Multi-app spoof…");
    NSString *msg = [ProfileBuilder applySpoofFiltersForBundles:self.selectedSpoofBundleIds
                                                       progress:progress];
    self.statusText = msg;
    [self postDidChange];
    return msg;
}

- (NSString *)wipeAppsSummary {
    NSUInteger n = self.selectedWipeBundleIds.count;
    if (n == 0) return @"Chưa chọn ứng dụng (chạm để chọn)";
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *bid in self.selectedWipeBundleIds) {
        if ([bid isEqualToString:@"com.apple.Maps"]) [names addObject:@"Bản đồ"];
        else if ([bid isEqualToString:@"com.apple.weather"]) [names addObject:@"Thời tiết"];
        else if ([bid isEqualToString:@"com.apple.mobilesafari"]) [names addObject:@"Safari"];
        else [names addObject:bid.pathExtension.length ? bid.pathExtension : bid];
        if (names.count >= 4) break;
    }
    NSString *head = [names componentsJoinedByString:@", "];
    if (n > names.count)
        return [NSString stringWithFormat:@"%lu ứng dụng: %@…", (unsigned long)n, head];
    return [NSString stringWithFormat:@"%lu ứng dụng: %@", (unsigned long)n, head];
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
    if (!dev) return @"Danh mục máy trống";
    NSDictionary *meta = Catalog.shared.iosReleases[ios];
    if (!meta) return [NSString stringWithFormat:@"Không có iOS %@ trong catalog", ios];

    // Strict matrix guard
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
        if (!sup.count) return @"Máy này không có iOS trong matrix";
        ios = sup.lastObject;
        meta = Catalog.shared.iosReleases[ios];
        if (!meta) return @"Bảng iOS tương thích lỗi";
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
    // Keep Multi-app spoof filters + proxy/AppAttest in sync with wall
    NSString *filt = [ProfileBuilder applySpoofFiltersForBundles:self.selectedSpoofBundleIds progress:nil];
    NSMutableDictionary *m2 = [flat mutableCopy];
    [m2 addEntriesFromDictionary:[self proxyAppAttestFlatKeys]];
    flat = m2;
    (void)[ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    self.lastFlat = flat;
    self.statusText = [NSString stringWithFormat:@"%@ · %@ / iOS %@\n%@",
                       result ?: @"OK",
                       dev[@"MarketingName"] ?: dev[@"id"],
                       ios,
                       filt ?: @""];
    [self postDidChange];
    return self.statusText;
}

- (NSString *)applyReseedOnly:(BOOL)reseedOnly {
    (void)reseedOnly;
    // Apply primary pair (or fix matrix) — full new identity
    NSDictionary *dev = [self currentDevice];
    if (!dev) return @"Danh mục máy trống — thiếu device_catalog.json";
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
        return err ?: @"Chọn ngẫu nhiên thất bại";
    NSString *msg = [self applyWithDevice:dev ios:ios];
    return [NSString stringWithFormat:@"Ngẫu nhiên: %@ + iOS %@\n%@",
            dev[@"MarketingName"] ?: dev[@"id"], ios, msg];
}

- (NSArray<NSString *> *)targetsForDataOps {
    NSMutableArray *wipeBids = [self.selectedWipeBundleIds mutableCopy] ?: [NSMutableArray array];
    for (NSString *b in @[ @"vn.com.vng.zingalo", @"com.zing.zalo" ]) {
        if (![wipeBids containsObject:b]) [wipeBids addObject:b];
    }
    if (wipeBids.count == 0) {
        [wipeBids addObject:@"vn.com.vng.zingalo"];
    }
    return wipeBids;
}

- (NSString *)killZaloAndRandomizeFromPool {
    return [self killZaloAndRandomizeFromPoolProgress:nil];
}

- (NSString *)killZaloAndRandomizeFromPoolProgress:(void (^)(NSString *))progress {
    if (progress) progress(@"Đang chọn ngẫu nhiên máy + iOS…");
    NSString *applyMsg = [self applyRandomFromPool];
    NSArray *wipeBids = [self targetsForDataOps];
    if (progress) progress([NSString stringWithFormat:@"Đang xóa %lu app (không giữ đăng nhập)…", (unsigned long)wipeBids.count]);
    NSString *wipeMsg = [ProfileBuilder wipeApps:wipeBids progress:progress];
    self.statusText = [NSString stringWithFormat:
                       @"%@\n\n%@\n\n→ Mở lại app = dữ liệu sạch + hồ sơ máy mới.",
                       applyMsg, wipeMsg];
    [self postDidChange];
    return self.statusText;
}

- (NSString *)saveDataThenResetProgress:(void (^)(NSString *))progress {
    /**
     Luồng «Đặt lại + Lưu dữ liệu»:
     1) Lưu 100% thông số máy hiện tại + full data app đã chọn (kèm phiên đăng nhập)
     2) Random máy/iOS mới + ghi config
     3) Xóa data app (bỏ keychain wipe để không mất token nếu nằm ngoài file)
     4) Khôi phục data app → giữ đăng nhập, spoof máy mới
     */
    NSArray *apps = [self targetsForDataOps];
    NSMutableArray *log = [NSMutableArray array];

    if (progress) progress(@"① Lưu thông số thiết bị + data app (giữ đăng nhập)…");
    NSString *ts = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *backupRoot = [[ProfileBuilder defaultBackupBase] stringByAppendingPathComponent:ts];
    NSString *bak = [ProfileBuilder backupApps:apps backupRoot:backupRoot progress:progress];
    if ([bak hasPrefix:@"ERR"]) {
        self.statusText = bak;
        return bak;
    }
    [log addObject:[NSString stringWithFormat:@"Đã lưu backup: %@", bak]];

    if (progress) progress(@"② Đặt lại hồ sơ máy (ngẫu nhiên trong pool)…");
    NSString *applyMsg = [self applyRandomFromPool];
    [log addObject:applyMsg];

    if (progress) progress(@"③ Xóa data app (chuẩn bị khôi phục)…");
    NSString *wipeMsg = [ProfileBuilder wipeApps:apps
                                        progress:progress
                                         options:@{ @"skipKeychain": @YES, @"skipScript": @YES }];
    [log addObject:wipeMsg];

    if (progress) progress(@"④ Khôi phục data app — giữ phiên đăng nhập…");
    NSString *restMsg = [ProfileBuilder restoreApps:apps fromBackupRoot:bak progress:progress];
    [log addObject:restMsg];

    // Kill so next open loads new MG config + restored session files
    if (progress) progress(@"⑤ Đóng app để nạp spoof + session…");
    for (NSString *bid in apps)
        [ProfileBuilder killAppBundleId:bid executable:nil];

    self.statusText = [NSString stringWithFormat:
                       @"Đặt lại + Lưu dữ liệu xong:\n\n%@\n\n"
                       @"→ Đã lưu 100%% thông số máy + data app.\n"
                       @"→ Máy spoof mới + phiên đăng nhập được khôi phục.\n"
                       @"→ Backup: %@",
                       [log componentsJoinedByString:@"\n---\n"], bak];
    [self postDidChange];
    return self.statusText;
}

- (void)killZalo {
    (void)[self killZaloAndRandomizeFromPool];
}

- (NSString *)wipeZaloLab {
    return [self wipeSelectedAppsProgress:nil];
}

- (NSString *)wipeSelectedAppsProgress:(void (^)(NSString *))progress {
    [self ensureDefaults];
    NSArray *bids = [self.selectedWipeBundleIds copy];
    if (bids.count == 0) {
        NSString *m = @"Chưa chọn app nào để xóa dữ liệu.";
        self.statusText = m;
        return m;
    }
    if (progress) progress([NSString stringWithFormat:@"Đang xóa %lu app đã chọn…", (unsigned long)bids.count]);
    NSString *m = [ProfileBuilder wipeApps:bids progress:progress];
    self.statusText = m;
    [self postDidChange];
    return m;
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

#pragma mark - Proxy / AppAttest

static NSString *const kPxEnable = @"ipf.proxy.enabled";
static NSString *const kPxHost = @"ipf.proxy.host";
static NSString *const kPxPort = @"ipf.proxy.port";
static NSString *const kPxType = @"ipf.proxy.type";
static NSString *const kPxUser = @"ipf.proxy.user";
static NSString *const kPxPass = @"ipf.proxy.pass";
static NSString *const kAADisable = @"ipf.appattest.disable";

- (BOOL)proxyEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:kPxEnable];
}
- (void)setProxyEnabled:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kPxEnable];
}
- (NSString *)proxyHost {
    return [NSUserDefaults.standardUserDefaults stringForKey:kPxHost] ?: @"";
}
- (void)setProxyHost:(NSString *)host {
    [NSUserDefaults.standardUserDefaults setObject:host ?: @"" forKey:kPxHost];
}
- (NSInteger)proxyPort {
    return [NSUserDefaults.standardUserDefaults integerForKey:kPxPort];
}
- (void)setProxyPort:(NSInteger)port {
    [NSUserDefaults.standardUserDefaults setInteger:port forKey:kPxPort];
}
- (NSString *)proxyType {
    NSString *t = [NSUserDefaults.standardUserDefaults stringForKey:kPxType];
    return t.length ? t : @"HTTP";
}
- (void)setProxyType:(NSString *)type {
    [NSUserDefaults.standardUserDefaults setObject:type ?: @"HTTP" forKey:kPxType];
}
- (NSString *)proxyUsername {
    return [NSUserDefaults.standardUserDefaults stringForKey:kPxUser] ?: @"";
}
- (void)setProxyUsername:(NSString *)user {
    [NSUserDefaults.standardUserDefaults setObject:user ?: @"" forKey:kPxUser];
}
- (NSString *)proxyPassword {
    return [NSUserDefaults.standardUserDefaults stringForKey:kPxPass] ?: @"";
}
- (void)setProxyPassword:(NSString *)pass {
    [NSUserDefaults.standardUserDefaults setObject:pass ?: @"" forKey:kPxPass];
}
- (BOOL)disableAppAttest {
    return [NSUserDefaults.standardUserDefaults boolForKey:kAADisable];
}
- (void)setDisableAppAttest:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kAADisable];
}
- (void)saveProxyAppAttest {
    [NSUserDefaults.standardUserDefaults synchronize];
    // Mirror JSON for PC tools
    @try {
        NSString *dir = @"/var/mobile/Library/iPFaker";
        NSDictionary *d = @{
            @"EnableProxy": @([self proxyEnabled]),
            @"ProxyHost": [self proxyHost] ?: @"",
            @"ProxyPort": @([self proxyPort]),
            @"ProxyType": [self proxyType] ?: @"HTTP",
            @"ProxyUsername": [self proxyUsername] ?: @"",
            @"ProxyPassword": [self proxyPassword] ?: @"",
            @"DisableAppAttest": @([self disableAppAttest]),
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
        if (json) [json writeToFile:[dir stringByAppendingPathComponent:@"proxy_appattest.json"] atomically:YES];
    } @catch (__unused NSException *ex) {}
}

- (NSDictionary *)proxyAppAttestFlatKeys {
    return @{
        @"EnableProxy": @([self proxyEnabled]),
        @"ProxyHost": [self proxyHost] ?: @"",
        @"ProxyPort": @([self proxyPort]),
        @"ProxyType": [self proxyType] ?: @"HTTP",
        @"ProxyUsername": [self proxyUsername] ?: @"",
        @"ProxyPassword": [self proxyPassword] ?: @"",
        @"DisableAppAttest": @([self disableAppAttest]),
        @"FakeProxy": @([self proxyEnabled]),
    };
}

- (NSString *)applyProxyAppAttestToConfigProgress:(void (^)(NSString *))progress {
    [self saveProxyAppAttest];
    if (progress) progress(@"Gộp Proxy / AppAttest vào config.plist…");
    NSString *msg = [ProfileBuilder mergeKeysIntoConfig:[self proxyAppAttestFlatKeys] progress:progress];
    self.statusText = msg;
    [self postDidChange];
    return msg;
}

- (NSString *)testProxyConnection {
    NSString *host = [self proxyHost];
    NSInteger port = [self proxyPort];
    if (!host.length || port <= 0 || port > 65535)
        return @"ERR: Host/Port không hợp lệ";

    BOOL socks = [[self proxyType].uppercaseString containsString:@"SOCKS"];
    NSMutableDictionary *proxy = [NSMutableDictionary dictionary];
    if (socks) {
        proxy[(NSString *)kCFStreamPropertySOCKSProxyHost] = host;
        proxy[(NSString *)kCFStreamPropertySOCKSProxyPort] = @(port);
        if ([self proxyUsername].length) {
            proxy[(NSString *)kCFStreamPropertySOCKSUser] = [self proxyUsername];
            proxy[(NSString *)kCFStreamPropertySOCKSPassword] = [self proxyPassword] ?: @"";
        }
    } else {
        proxy[(NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxy[(NSString *)kCFNetworkProxiesHTTPProxy] = host;
        proxy[(NSString *)kCFNetworkProxiesHTTPPort] = @(port);
        proxy[(NSString *)kCFNetworkProxiesHTTPSEnable] = @YES;
        proxy[(NSString *)kCFNetworkProxiesHTTPSProxy] = host;
        proxy[(NSString *)kCFNetworkProxiesHTTPSPort] = @(port);
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.connectionProxyDictionary = proxy;
    cfg.timeoutIntervalForRequest = 12;
    cfg.timeoutIntervalForResource = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *result = @"ERR: timeout";
    // Public IP check through proxy (lab)
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org?format=text"];
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            result = [NSString stringWithFormat:@"FAIL: %@", err.localizedDescription];
        } else {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            NSString *body = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            result = [NSString stringWithFormat:@"OK HTTP %ld · IP qua proxy: %@",
                      (long)http.statusCode, body.length ? body : @"(empty)"];
        }
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_SEC));
    [session invalidateAndCancel];
    return result;
}

- (void)postDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:AppStateDidChangeNotification object:self];
}

@end
