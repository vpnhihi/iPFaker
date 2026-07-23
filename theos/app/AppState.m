#import "AppState.h"
#import "Catalog.h"
#import "AppCatalog.h"
#import "ProfileBuilder.h"
#import <CFNetwork/CFNetwork.h>
#import <unistd.h>

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
    // User-facing list = third-party only (Zalo…). System Safari/Maps/Weather inject+wipe ngầm.
    [self.selectedSpoofBundleIds removeObject:@"com.apple.Preferences"];
    // Strip system from saved pools
    NSMutableArray *tp = [NSMutableArray array];
    for (NSString *b in self.selectedSpoofBundleIds) {
        if (b.length && ![AppState isSystemLabBundleId:b] && ![tp containsObject:b])
            [tp addObject:b];
    }
    [self.selectedSpoofBundleIds removeAllObjects];
    [self.selectedSpoofBundleIds addObjectsFromArray:tp];
    if (self.selectedSpoofBundleIds.count == 0) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    } else {
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
    [self syncLabAppPoolsFromSpoofMaster];
    // Dual-path config → NSUserDefaults proxy (keep UI + dylib wall in sync)
    [self loadProxyFromDualPathConfig];
    [self savePools];
}

+ (NSArray<NSString *> *)systemLabBackgroundBundleIds {
    // HIOS-style system surface (no Weather — CI strips it, crash risk / zero spoof value)
    return @[
        @"com.apple.mobilesafari",
        @"com.apple.WebKit.WebContent",
        @"com.apple.Maps",
    ];
}

+ (BOOL)isSystemLabBundleId:(NSString *)bundleId {
    if (!bundleId.length) return NO;
    if ([bundleId hasPrefix:@"com.apple."]) return YES;
    return NO;
}

- (void)syncLabAppPoolsFromSpoofMaster {
    // User list = third-party **đã cài** only (strip system + not installed)
    [[AppCatalog shared] reload];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *b in self.selectedSpoofBundleIds) {
        if (!b.length || [AppState isSystemLabBundleId:b]) continue;
        // Keep if installed; allow zalo ids even if LS lag (re-check)
        if (![[AppCatalog shared] isInstalledBundleId:b]) {
            // Prefer installed zalo if present
            continue;
        }
        if (![clean containsObject:b]) [clean addObject:b];
    }
    if (clean.count == 0) {
        // Default to installed Zalo if present
        for (NSString *z in @[ @"vn.com.vng.zingalo", @"com.zing.zalo" ]) {
            if ([[AppCatalog shared] isInstalledBundleId:z] && ![clean containsObject:z])
                [clean addObject:z];
        }
        // Else first installed third-party
        if (clean.count == 0) {
            for (AppCatalogItem *it in AppCatalog.shared.apps) {
                if (it.bundleId.length) { [clean addObject:it.bundleId]; break; }
            }
        }
    }
    [self.selectedSpoofBundleIds removeAllObjects];
    [self.selectedSpoofBundleIds addObjectsFromArray:clean];
    // Wipe pool = same as user lab apps (Method A: no system wipe)
    [self.selectedWipeBundleIds removeAllObjects];
    [self.selectedWipeBundleIds addObjectsFromArray:clean];
}

- (NSArray<NSString *> *)labAppTargets {
    [self ensureDefaults];
    [self syncLabAppPoolsFromSpoofMaster];
    return [self.selectedSpoofBundleIds copy] ?: @[];
}

- (NSArray<NSString *> *)filterSpoofTargets {
    // Inject: selected social apps + Safari/WebKit/Maps (HIOS surface)
    NSMutableArray *out = [[self labAppTargets] mutableCopy] ?: [NSMutableArray array];
    for (NSString *s in [AppState systemLabBackgroundBundleIds]) {
        if (![out containsObject:s]) [out addObject:s];
    }
    // Settings About only if user explicitly enabled (default OFF — not product focus)
    if ([self toggleForKey:@"SpoofSettingsAbout" defaultOn:NO]) {
        if (![out containsObject:@"com.apple.Preferences"])
            [out addObject:@"com.apple.Preferences"];
    }
    return out;
}

- (NSArray<NSString *> *)sessionWipeTargets {
    // Wipe: app lab đã chọn + system Safari/Maps/Weather (ngầm)
    NSMutableArray *out = [[self labAppTargets] mutableCopy] ?: [NSMutableArray array];
    for (NSString *s in [AppState systemLabBackgroundBundleIds]) {
        if (s.length && ![out containsObject:s]) [out addObject:s];
    }
    return out;
}

- (NSArray<NSString *> *)sessionWipeRelaunchTargets {
    return [self sessionWipeTargets];
}

+ (NSArray<NSString *> *)labCoreSpoofBundleIds {
    // Product default = HIOS multi-app deep set (+ system inject ngầm via filterSpoofTargets)
    return @[
        @"vn.com.vng.zingalo",
        @"com.zing.zalo",
        @"com.facebook.Facebook",
        @"com.facebook.Messenger",
        @"com.burbn.instagram",
        @"ph.telegra.Telegraph",
        @"com.viber",
    ];
}

- (void)applyLabCoreSpoofPreset {
    // All installed social targets (HIOS-style), not Zalo-only
    [self applyLabSocialSpoofPreset];
}

- (void)applyLabStockSpoofPreset {
    [self applyLabSocialSpoofPreset];
}

- (void)applyLabSocialSpoofPreset {
    // Only social apps **đã cài** trên máy
    [[AppCatalog shared] reload];
    [self.selectedSpoofBundleIds removeAllObjects];
    for (NSArray *row in [AppCatalog labSocialSpoofApps]) {
        NSString *bid = row.firstObject;
        if (!bid.length || [AppState isSystemLabBundleId:bid]) continue;
        if (![[AppCatalog shared] isInstalledBundleId:bid]) continue;
        if (![self.selectedSpoofBundleIds containsObject:bid])
            [self.selectedSpoofBundleIds addObject:bid];
    }
    // Always keep Zalo ids if any zalo installed (both bundle variants)
    for (NSString *z in @[ @"vn.com.vng.zingalo", @"com.zing.zalo" ]) {
        if ([[AppCatalog shared] isInstalledBundleId:z]
            && ![self.selectedSpoofBundleIds containsObject:z])
            [self.selectedSpoofBundleIds insertObject:z atIndex:0];
    }
    [self syncLabAppPoolsFromSpoofMaster];
    [self savePools];
    [self postDidChange];
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
    // Unified with spoof list
    return bundleId.length && [self.selectedSpoofBundleIds containsObject:bundleId];
}

- (BOOL)toggleWipeBundleId:(NSString *)bundleId {
    // Unified lab list: wipe toggle = spoof toggle (identity + session)
    if (!bundleId.length) return NO;
    if ([bundleId isEqualToString:@"com.apple.Preferences"]) return NO;
    BOOL on = [self toggleSpoofBundleId:bundleId];
    [self syncLabAppPoolsFromSpoofMaster];
    [self savePools];
    [self postDidChange];
    return on;
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
    [self syncLabAppPoolsFromSpoofMaster];
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
        if ([AppState isSystemLabBundleId:bid]) continue;
        if ([bid isEqualToString:@"com.apple.Preferences"]) continue;
        if (![self.selectedSpoofBundleIds containsObject:bid])
            [self.selectedSpoofBundleIds addObject:bid];
    }
    if (self.selectedSpoofBundleIds.count == 0) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    }
    [self syncLabAppPoolsFromSpoofMaster];
    [self savePools];
    [self postDidChange];
}

- (void)deselectAllSpoofAppsKeepingZalo:(BOOL)keepZalo {
    [self.selectedSpoofBundleIds removeAllObjects];
    if (keepZalo) {
        [self.selectedSpoofBundleIds addObject:@"vn.com.vng.zingalo"];
        [self.selectedSpoofBundleIds addObject:@"com.zing.zalo"];
    }
    [self syncLabAppPoolsFromSpoofMaster];
    [self savePools];
    [self postDidChange];
}

- (NSString *)spoofAppsSummary {
    NSUInteger n = self.selectedSpoofBundleIds.count;
    if (n == 0) return @"Chưa chọn app lab";
    if (n <= 3) return [self.selectedSpoofBundleIds componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"%lu app lab (spoof + wipe session)", (unsigned long)n];
}

- (NSString *)applySpoofAppFiltersProgress:(void (^)(NSString *))progress {
    [self ensureDefaults];
    if (progress) progress(@"Ghi filter inject (app lab + system ngầm)…");
    NSString *msg = [ProfileBuilder applySpoofFiltersForBundles:[self filterSpoofTargets]
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

/// Best iOS for device (soft-host 2.10.7):
/// 1) Prefer highest catalog iOS that device supports AND ≤ host
/// 2) Else catalog-native: lowest supported (may be > host, e.g. 17 Pro Max → 26.x)
/// NEVER invent host iOS if not on device matrix.
- (NSString *)bestHostAlignedIOSForDevice:(NSDictionary *)dev {
    if (!dev) return nil;
    NSString *host = [ProfileBuilder hostSystemVersion] ?: @"15.0";
    NSArray *iosOpts = [self selectedIOSCompatibleWithDevice:dev];
    if (iosOpts.count == 0)
        iosOpts = [Catalog.shared supportedIOSForDevice:dev];
    NSString *bestLeHost = nil;
    NSString *lowestAny = nil;
    for (NSString *v in iosOpts) {
        if (!Catalog.shared.iosReleases[v]) continue;
        if (![Catalog.shared device:dev supportsIOS:v]) continue;
        if (!lowestAny || [ProfileBuilder compareVersion:v toVersion:lowestAny] == NSOrderedAscending)
            lowestAny = v;
        if ([ProfileBuilder compareVersion:v toVersion:host] == NSOrderedDescending)
            continue; // > host — keep for fallback only
        if (!bestLeHost || [ProfileBuilder compareVersion:v toVersion:bestLeHost] == NSOrderedDescending)
            bestLeHost = v;
    }
    if (bestLeHost) {
        // Prefer host string when it is on matrix
        if ([Catalog.shared device:dev supportsIOS:host] && Catalog.shared.iosReleases[host]
            && [ProfileBuilder compareVersion:host toVersion:bestLeHost] != NSOrderedAscending)
            return host;
        return bestLeHost;
    }
    // Soft: allow catalog-native iOS > host (weighted pick still prefers near-host models)
    return lowestAny;
}

/// Pick random pair — Full catalog OK; weighted toward host-realism (iOS≤host, model gen near host).
- (BOOL)pickRandomPairDevice:(NSDictionary **)outDev ios:(NSString **)outIOS error:(NSString **)err {
    [self ensureDefaults];
    if (self.selectedDeviceIds.count == 0) {
        if (err) *err = @"Chưa chọn đời máy nào";
        return NO;
    }

    NSMutableArray<NSDictionary *> *pairs = [NSMutableArray array];
    NSMutableArray<NSNumber *> *weights = [NSMutableArray array];
    NSInteger totalW = 0;
    for (NSString *did in self.selectedDeviceIds) {
        NSDictionary *dev = [Catalog.shared deviceWithId:did];
        if (!dev) continue;
        NSString *ios = [self bestHostAlignedIOSForDevice:dev];
        if (!ios.length || !Catalog.shared.iosReleases[ios]) continue;
        // One canonical pair per device (best iOS) — still Full model coverage
        NSInteger score = [ProfileBuilder labRealismScoreForProductType:dev[@"ProductType"] ios:ios];
        // Weight: score^2 so near-host dominates but far models still possible
        NSInteger w = score * score;
        if (w < 1) w = 1;
        [pairs addObject:@{ @"device": dev, @"ios": ios, @"score": @(score) }];
        [weights addObject:@(w)];
        totalW += w;
    }
    if (pairs.count == 0) {
        if (err) *err = @"Không có cặp máy+iOS hợp lệ trong pool (thiếu matrix / catalog).";
        return NO;
    }
    NSDictionary *pick = nil;
    if (totalW > 0) {
        NSInteger r = (NSInteger)arc4random_uniform((uint32_t)totalW);
        NSInteger acc = 0;
        for (NSUInteger i = 0; i < pairs.count; i++) {
            acc += weights[i].integerValue;
            if (r < acc) { pick = pairs[i]; break; }
        }
    }
    if (!pick) pick = pairs[arc4random_uniform((uint32_t)pairs.count)];
    if (outDev) *outDev = pick[@"device"];
    if (outIOS) *outIOS = pick[@"ios"];
    return YES;
}

- (NSString *)applyWithDevice:(NSDictionary *)dev ios:(NSString *)ios {
    if (!dev) return @"Danh mục máy trống";
    NSString *iosRequested = [ios copy];
    NSString *hostIOS = [ProfileBuilder hostSystemVersion] ?: @"?";
    // Soft-host: matrix first. Prefer ≤ host; else catalog-native (may be > host).
    // Never invent host iOS for phones that never shipped it (17 Pro Max ≠ 15.5).
    NSString *aligned = [self bestHostAlignedIOSForDevice:dev];
    if (!aligned.length) {
        return [NSString stringWithFormat:
                @"❌ %@ không có iOS nào trong matrix catalog.",
                dev[@"MarketingName"] ?: dev[@"id"]];
    }
    // Requested iOS if on matrix; else aligned (soft — may be > host)
    if (ios.length && [Catalog.shared device:dev supportsIOS:ios]
        && Catalog.shared.iosReleases[ios]) {
        // Prefer requested when user/pool chose it; still valid on matrix
        // Soft: if requested ≤ host and aligned ≤ host, pick higher (nearer host)
        if ([ProfileBuilder compareVersion:ios toVersion:hostIOS] != NSOrderedDescending
            && [ProfileBuilder compareVersion:aligned toVersion:hostIOS] != NSOrderedDescending) {
            if ([ProfileBuilder compareVersion:ios toVersion:aligned] == NSOrderedAscending)
                ios = aligned; // bump toward host when both ≤ host
        }
        // else keep requested (including > host catalog-native)
    } else {
        ios = aligned;
    }
    NSDictionary *meta = Catalog.shared.iosReleases[ios];
    if (!meta) {
        ios = aligned;
        meta = Catalog.shared.iosReleases[ios];
    }
    if (!meta) return [NSString stringWithFormat:@"Không có iOS %@ trong catalog", ios ?: @"?"];

    // Matrix guard — never use unsupported version
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        ios = aligned;
        meta = Catalog.shared.iosReleases[ios];
        if (!meta || ![Catalog.shared device:dev supportsIOS:ios]) {
            return [NSString stringWithFormat:
                    @"❌ Không có iOS hợp lệ cho %@",
                    dev[@"MarketingName"] ?: dev[@"id"]];
        }
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
    // HIOS-style deep identity wall (apps), not Settings UI vanity
    setFlag(@"FakeDevice", YES);
    setFlag(@"FakeHardware", YES);
    setFlag(@"FakeAds", YES);
    // Screen OFF — host pixels; spoofing screen dims crashes Zalo UIFont/IsCompact on A10
    setFlag(@"FakeScreen", NO);
    setFlag(@"FakeRealScreen", NO);
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
    setFlag(@"DisableAppAttest", YES);
    setFlag(@"HideJailbreak", YES);
    setFlag(@"FakeWifi", YES);
    setFlag(@"FakeProxy", [self proxyEnabled]);
    // Force deep path (legacy lean flags OFF)
    mflat[@"SkipExtraForZalo"] = @NO;
    mflat[@"DeepSpoofSocial"] = @YES;
    mflat[@"InjectWebKit"] = @YES;
    mflat[@"KeychainSpoof"] = @YES;
    mflat[@"WipeResidueHIOS"] = @YES;
    // Settings About is optional noise — default OFF
    mflat[@"SpoofSettingsAbout"] = @([self toggleForKey:@"SpoofSettingsAbout" defaultOn:NO]);
    mflat[@"SelectedDevicePool"] = [self.selectedDeviceIds copy];
    mflat[@"SelectedIOSPool"] = [self.selectedIOSList copy];
    flat = mflat;

    NSString *result = [ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    // Keep Multi-app spoof filters + proxy/AppAttest in sync with wall
    NSString *filt = [ProfileBuilder applySpoofFiltersForBundles:[self filterSpoofTargets] progress:nil];
    NSMutableDictionary *m2 = [flat mutableCopy];
    [m2 addEntriesFromDictionary:[self proxyAppAttestFlatKeys]];
    // Ensure Darwin keys present (schema-safe)
    NSDictionary *dk = [ProfileBuilder darwinKernelKeysForIOS:ios board:dev[@"HWModelStr"]];
    [m2 addEntriesFromDictionary:dk];
    if (flat[@"BuildVersion"]) m2[@"kern.osversion"] = flat[@"BuildVersion"];
    flat = m2;
    (void)[ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    self.lastFlat = flat;
    NSString *warn = [ProfileBuilder labMismatchWarningForSpoofIOS:ios
                                                       productType:dev[@"ProductType"]];
    NSInteger realism = [ProfileBuilder labRealismScoreForProductType:dev[@"ProductType"] ios:ios];
    NSString *clampNote = @"";
    if (iosRequested.length && ![iosRequested isEqualToString:ios])
        clampNote = [NSString stringWithFormat:@"\n✓ iOS thật nhất: %@ → %@ (≤ host)", iosRequested, ios];
    self.statusText = [NSString stringWithFormat:
                       @"DEEP · %@ / iOS %@ · điểm %ld/100%@\n%@%@%@",
                       dev[@"MarketingName"] ?: dev[@"id"],
                       ios,
                       (long)realism,
                       clampNote,
                       filt ?: @"",
                       warn.length ? @"\n" : @"",
                       warn ?: @""];
    [self postDidChange];
    return self.statusText;
}

- (NSString *)applyReseedOnly:(BOOL)reseedOnly {
    (void)reseedOnly;
    // Apply primary pair — host-aligned matrix only (no fake iOS on wrong silicon gen)
    NSDictionary *dev = [self currentDevice];
    if (!dev) return @"Danh mục máy trống — thiếu device_catalog.json";
    NSString *ios = [self bestHostAlignedIOSForDevice:dev];
    if (!ios.length) {
        // Prefer random valid pair from pool over inventing host iOS on 17 Pro Max etc.
        return [self applyRandomFromPool];
    }
    // If user-selected iOS still valid ≤ host, prefer it when higher/closer
    NSString *sel = self.selectedIOS;
    if (sel.length && [Catalog.shared device:dev supportsIOS:sel]
        && Catalog.shared.iosReleases[sel]
        && [ProfileBuilder compareVersion:sel toVersion:[ProfileBuilder hostSystemVersion]] != NSOrderedDescending) {
        ios = sel;
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
    // Unified lab list (spoof = wipe). Method A session ops use sessionWipeRelaunchTargets.
    return [self labAppTargets];
}

- (BOOL)applyProxyPasteLine:(NSString *)line error:(NSString **)errOut {
    NSString *raw = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!raw.length) {
        if (errOut) *errOut = @"Dòng proxy trống";
        return NO;
    }
    // host:port:user:pass  |  host:port  |  host:port:user:
    NSArray *parts = [raw componentsSeparatedByString:@":"];
    if (parts.count < 2) {
        if (errOut) *errOut = @"Định dạng: host:port:user:pass";
        return NO;
    }
    NSString *host = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSInteger port = [parts[1] integerValue];
    if (!host.length || port <= 0 || port > 65535) {
        if (errOut) *errOut = @"Host/Port không hợp lệ";
        return NO;
    }
    NSString *user = parts.count > 2 ? parts[2] : @"";
    // password may contain ':' — rejoin remainder
    NSString *pass = @"";
    if (parts.count > 3) {
        NSArray *rest = [parts subarrayWithRange:NSMakeRange(3, parts.count - 3)];
        pass = [rest componentsJoinedByString:@":"];
    }
    [self setProxyHost:host];
    [self setProxyPort:port];
    [self setProxyUsername:user ?: @""];
    [self setProxyPassword:pass ?: @""];
    if (![self proxyType].length) [self setProxyType:@"HTTP"];
    [self saveProxyAppAttest];
    return YES;
}

- (void)loadProxyFromDualPathConfig {
    @try {
        NSArray *paths = @[
            @"/var/jb/etc/ipfaker/config.plist",
            @"/var/mobile/Library/iPFaker/config.plist",
        ];
        NSDictionary *d = nil;
        for (NSString *p in paths) {
            d = [NSDictionary dictionaryWithContentsOfFile:p];
            if (d.count) break;
        }
        if (!d.count) return;
        if (d[@"ProxyHost"]) [self setProxyHost:[d[@"ProxyHost"] description]];
        if (d[@"ProxyPort"]) [self setProxyPort:[d[@"ProxyPort"] integerValue]];
        if (d[@"ProxyUsername"]) [self setProxyUsername:[d[@"ProxyUsername"] description]];
        if (d[@"ProxyPassword"]) [self setProxyPassword:[d[@"ProxyPassword"] description]];
        if (d[@"ProxyType"]) [self setProxyType:[d[@"ProxyType"] description]];
        if (d[@"EnableProxy"] != nil || d[@"FakeProxy"] != nil) {
            BOOL on = [d[@"EnableProxy"] boolValue] || [d[@"FakeProxy"] boolValue];
            [self setProxyEnabled:on];
        }
        if (d[@"DisableAppAttest"] != nil)
            [self setDisableAppAttest:[d[@"DisableAppAttest"] boolValue]];
        if (d[@"SyncGeoFromProxy"] != nil)
            [self setSyncGeoFromProxyEnabled:[d[@"SyncGeoFromProxy"] boolValue]];
        [self saveProxyAppAttest];
    } @catch (__unused NSException *ex) {}
}

- (NSString *)killZaloAndRandomizeFromPool {
    return [self killZaloAndRandomizeFromPoolProgress:nil];
}

- (NSString *)vuotZaloOneTapProgress:(void (^)(NSString *))progress {
    // Unified wall entry (UI no longer shows separate «Vượt…» button)
    return [self killZaloAndRandomizeFromPoolProgress:progress];
}

- (NSString *)killZaloAndRandomizeFromPoolProgress:(void (^)(NSString *))progress {
    /**
     «Đặt lại dữ liệu app» — Method A nhanh:
     1) Filter inject (app đã chọn + system identity ngầm)
     2) Flags ON → random spoof (apply đã gộp proxy/flags)
     3) Wipe app lab đã chọn + system Safari/Maps/Weather
     4) Kill — không relaunch, **không geo** (dùng nút Đồng bộ Location)
     */
    NSMutableArray *log = [NSMutableArray array];
    [self ensureDefaults];
    [self loadProxyFromDualPathConfig];
    [self syncLabAppPoolsFromSpoofMaster];

    if (progress) progress(@"① Filter inject…");
    if (self.selectedSpoofBundleIds.count == 0)
        [self applyLabCoreSpoofPreset];
    @try {
        NSString *filt = [self applySpoofAppFiltersProgress:progress];
        [log addObject:filt ?: @"filter"];
    } @catch (NSException *ex) {
        [log addObject:[NSString stringWithFormat:@"filter EX: %@", ex.reason ?: @"?"]];
    }

    if (progress) progress(@"② Spoof máy + iOS + flags…");
    NSArray *flagsOn = @[
        @"FakeDevice", @"FakeHardware", @"FakeAds", @"FakeScreen", @"FakeRealScreen",
        @"FakeBrowser", @"FakeNetwork", @"FakeWifi", @"FakeSysctl", @"FakeSysOSVersion",
        @"HideJailbreak", @"FakeLocale", @"FakeLocation", @"FakeSensor",
        @"FakeWebRTC", @"DisableAppAttest", @"Enabled",
    ];
    for (NSString *k in flagsOn)
        [self setToggle:YES forKey:k];
    [self setToggle:NO forKey:@"DisableWebRTC"];
    [self savePools];
    [self saveProxyAppAttest];
    BOOL hasProxy = [self proxyEnabled] && [self proxyHost].length > 0;

    NSString *applyMsg = nil;
    @try {
        // applyWithDevice already writes flags + proxy keys dual-path + Darwin kernel
        applyMsg = [self applyRandomFromPool];
    } @catch (NSException *ex) {
        applyMsg = [NSString stringWithFormat:@"apply EX: %@", ex.reason ?: @"?"];
    }
    [log addObject:applyMsg ?: @"apply"];
    // Surface host vs spoof mismatch (iOS/model) — do not force proxy (Shadowrocket OK)
    {
        NSDictionary *flatNow = [ProfileBuilder loadCurrentFlat] ?: @{};
        NSString *warn = [ProfileBuilder labMismatchWarningForSpoofIOS:flatNow[@"ProductVersion"]
                                                           productType:flatNow[@"ProductType"]];
        if (warn.length) {
            [log addObject:warn];
            if (progress) progress(@"⚠ Lệch host/spoof — xem log");
        }
        NSString *kr = flatNow[@"kern.osrelease"];
        NSString *kv = flatNow[@"kern.version"];
        if (kr.length)
            [log addObject:[NSString stringWithFormat:@"Kernel spoof: Darwin %@ · host %@ · %@",
                            kr, [ProfileBuilder hostSystemVersion],
                            kv.length > 60 ? [[kv substringToIndex:60] stringByAppendingString:@"…"] : (kv ?: @"")]];
    }

    // Light re-merge proxy keys only (geo = nút Location; proxy VPN app = user tự lo)
    if (progress) progress(@"③ Khóa proxy dual-path (không bắt buộc ON)…");
    NSMutableDictionary *mit = [[self proxyAppAttestFlatKeys] mutableCopy] ?: [NSMutableDictionary dictionary];
    mit[@"WebRTCLocalIP"] = @"10.0.0.2";
    mit[@"FakeWebRTC"] = @YES;
    mit[@"DisableAppAttest"] = @YES;
    // Re-assert Darwin keys after merge
    {
        NSDictionary *flatNow = [ProfileBuilder loadCurrentFlat] ?: self.lastFlat ?: @{};
        NSDictionary *dk = [ProfileBuilder darwinKernelKeysForIOS:flatNow[@"ProductVersion"] ?: @"15.0"
                                                            board:flatNow[@"HWModelStr"]];
        [mit addEntriesFromDictionary:dk];
        if (flatNow[@"BuildVersion"]) mit[@"kern.osversion"] = flatNow[@"BuildVersion"];
    }
    NSString *m2 = [ProfileBuilder mergeKeysIntoConfig:mit progress:progress];
    [log addObject:m2 ?: @"proxy"];
    if (!hasProxy)
        [log addObject:@"Proxy iPFaker OFF — OK nếu dùng Shadowrocket/VPN app khác."];
    else
        [log addObject:@"Geo: bấm «Đồng bộ Location» nếu cần Map/Thời tiết."];

    // Wipe lab apps + system Safari/Maps/Weather
    NSArray *wipeBids = [self sessionWipeTargets];
    NSUInteger nUser = [self labAppTargets].count;
    NSUInteger nSys = wipeBids.count > nUser ? wipeBids.count - nUser : 0;
    if (progress)
        progress([NSString stringWithFormat:@"④ Xóa session %lu app lab + %lu system…",
                  (unsigned long)nUser, (unsigned long)nSys]);
    NSString *wipeMsg = @"wipe skip";
    @try {
        wipeMsg = [ProfileBuilder wipeApps:wipeBids progress:progress];
    } @catch (NSException *ex) {
        wipeMsg = [NSString stringWithFormat:@"wipe EX: %@", ex.reason ?: @"?"];
    }
    [log addObject:wipeMsg ?: @"wipe"];

    if (progress) progress(@"⑤ Đóng app…");
    for (NSString *bid in wipeBids)
        [ProfileBuilder killAppBundleId:bid executable:nil];
    usleep(80 * 1000);
    [log addObject:@"Đã đóng — mở tay khi cần"];

    @try {
        NSDictionary *flat = [ProfileBuilder loadCurrentFlat] ?: @{};
        NSDictionary *snap = @{
            @"schema": @"ipfaker.reset_app_data/6",
            @"ts": @((NSInteger)[[NSDate date] timeIntervalSince1970]),
            @"ProductType": flat[@"ProductType"] ?: @"",
            @"MarketingName": flat[@"MarketingName"] ?: @"",
            @"ProductVersion": flat[@"ProductVersion"] ?: @"",
            @"SerialNumber": flat[@"SerialNumber"] ?: @"",
            @"proxyConfigured": @(hasProxy),
            @"sessionApps": wipeBids ?: @[],
            @"filterApps": [self filterSpoofTargets] ?: @[],
            @"userApps": [self labAppTargets] ?: @[],
            @"systemWipe": [AppState systemLabBackgroundBundleIds] ?: @[],
            @"noGeoOnReset": @YES,
            @"noRelaunch": @YES,
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:snap options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:@"/var/mobile/Library/iPFaker/last_reset_app.json" atomically:YES];
        [json writeToFile:@"/var/jb/etc/ipfaker/last_reset_app.json" atomically:YES];
    } @catch (__unused NSException *ex) {}

    self.statusText = [NSString stringWithFormat:
                       @"Đặt lại dữ liệu app xong:\n\n%@\n\n"
                       @"→ Wipe %lu app lab + system (Safari/Maps/Weather)\n"
                       @"→ Không geo / không tự mở app\n"
                       @"→ Proxy: %@\n",
                       [log componentsJoinedByString:@"\n---\n"],
                       (unsigned long)nUser,
                       hasProxy ? ([NSString stringWithFormat:@"%@:%ld", [self proxyHost], (long)[self proxyPort]])
                                : @"CHƯA bật"];
    [self postDidChange];
    return self.statusText;
}

- (NSString *)saveDataThenResetProgress:(void (^)(NSString *))progress {
    /**
     «Đặt lại + Lưu dữ liệu» — Method A + giữ session:
     filter full list · backup/soft-wipe/relaunch session apps only · geo timeout ngắn
     */
    [self ensureDefaults];
    [self loadProxyFromDualPathConfig];
    [self syncLabAppPoolsFromSpoofMaster];
    // Soft-reset only user third-party (giữ session); system still get identity via filter
    NSArray *apps = [self labAppTargets];
    NSMutableArray *log = [NSMutableArray array];

    if (progress) progress(@"① Filter + cờ mitigation…");
    if (self.selectedSpoofBundleIds.count == 0)
        [self applyLabCoreSpoofPreset];
    NSString *filt = [self applySpoofAppFiltersProgress:progress];
    [log addObject:filt ?: @"filter"];

    NSArray *flagsOn = @[
        @"FakeDevice", @"FakeHardware", @"FakeAds", @"FakeScreen", @"FakeRealScreen",
        @"FakeBrowser", @"FakeNetwork", @"FakeWifi", @"FakeSysctl", @"FakeSysOSVersion",
        @"HideJailbreak", @"FakeLocale", @"FakeLocation", @"FakeSensor",
        @"FakeWebRTC", @"DisableAppAttest", @"Enabled",
    ];
    for (NSString *k in flagsOn)
        [self setToggle:YES forKey:k];
    [self setToggle:NO forKey:@"DisableWebRTC"];
    [self savePools];
    [self saveProxyAppAttest];
    BOOL hasProxy = [self proxyEnabled] && [self proxyHost].length > 0;
    if (!hasProxy)
        [log addObject:@"⚠ Chưa bật proxy — dán trên trang chủ."];

    if (progress) progress(@"② Lưu session app…");
    NSString *ts = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *backupRoot = [[ProfileBuilder defaultBackupBase] stringByAppendingPathComponent:ts];
    NSString *bak = [ProfileBuilder backupApps:apps backupRoot:backupRoot progress:progress];
    if ([bak hasPrefix:@"ERR"]) {
        self.statusText = bak;
        return bak;
    }
    [log addObject:[NSString stringWithFormat:@"Backup: %@", bak]];

    if (progress) progress(@"③ Spoof ngẫu nhiên…");
    NSString *applyMsg = [self applyRandomFromPool];
    [log addObject:applyMsg ?: @"apply"];

    if (progress) progress(@"④ Khóa flag + proxy…");
    NSMutableDictionary *mit = [NSMutableDictionary dictionary];
    for (NSString *k in flagsOn) mit[k] = @YES;
    mit[@"DisableWebRTC"] = @NO;
    mit[@"WebRTCLocalIP"] = @"10.0.0.2";
    mit[@"FakeWebRTC"] = @YES;
    [mit addEntriesFromDictionary:[self proxyAppAttestFlatKeys]];
    NSString *m2 = [ProfileBuilder mergeKeysIntoConfig:mit progress:progress];
    [log addObject:m2 ?: @"merge"];

    // Method A: no geo on save-reset either (use «Đồng bộ Location»)

    if (progress) progress(@"⑤ Soft wipe + restore session…");
    NSString *wipeMsg = [ProfileBuilder wipeApps:apps
                                        progress:progress
                                         options:@{ @"skipKeychain": @YES, @"skipScript": @YES }];
    [log addObject:wipeMsg];
    NSString *restMsg = [ProfileBuilder restoreApps:apps fromBackupRoot:bak progress:progress];
    [log addObject:restMsg];

    if (progress) progress(@"⑥ Đóng app…");
    for (NSString *bid in apps)
        [ProfileBuilder killAppBundleId:bid executable:nil];
    usleep(80 * 1000);
    [log addObject:@"Đã đóng — mở tay khi cần"];

    @try {
        NSDictionary *flat = [ProfileBuilder loadCurrentFlat] ?: @{};
        NSDictionary *snap = @{
            @"schema": @"ipfaker.one_tap_save/4",
            @"ts": @((NSInteger)[[NSDate date] timeIntervalSince1970]),
            @"ProductType": flat[@"ProductType"] ?: @"",
            @"MarketingName": flat[@"MarketingName"] ?: @"",
            @"ProductVersion": flat[@"ProductVersion"] ?: @"",
            @"SerialNumber": flat[@"SerialNumber"] ?: @"",
            @"Latitude": flat[@"Latitude"] ?: @0,
            @"Longitude": flat[@"Longitude"] ?: @0,
            @"ProxyGeoCity": flat[@"ProxyGeoCity"] ?: @"",
            @"proxyConfigured": @(hasProxy),
            @"sessionApps": apps ?: @[],
            @"backup": bak ?: @"",
            @"noRelaunch": @YES,
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:snap options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:@"/var/mobile/Library/iPFaker/last_one_tap.json" atomically:YES];
        [json writeToFile:@"/var/jb/etc/ipfaker/last_one_tap.json" atomically:YES];
    } @catch (__unused NSException *ex) {}

    self.statusText = [NSString stringWithFormat:
                       @"Đặt lại + Lưu xong:\n\n%@\n\n"
                       @"→ Giữ đăng nhập · %lu app · không tự mở lại\n"
                       @"→ Proxy: %@\n→ Backup: %@",
                       [log componentsJoinedByString:@"\n---\n"],
                       (unsigned long)apps.count,
                       hasProxy ? ([NSString stringWithFormat:@"%@:%ld", [self proxyHost], (long)[self proxyPort]])
                                : @"CHƯA bật",
                       bak];
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
static NSString *const kPxSyncGeo = @"ipf.proxy.syncGeo";

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
- (BOOL)syncGeoFromProxyEnabled {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if ([ud objectForKey:kPxSyncGeo] == nil) return YES; // default ON
    return [ud boolForKey:kPxSyncGeo];
}
- (void)setSyncGeoFromProxyEnabled:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kPxSyncGeo];
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
            @"SyncGeoFromProxy": @([self syncGeoFromProxyEnabled]),
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
        @"SyncGeoFromProxy": @([self syncGeoFromProxyEnabled]),
    };
}

/// Build CFNetwork proxy dictionary for NSURLSession (shared by test + geo).
- (NSDictionary *)proxySessionDictionary {
    NSString *host = [self proxyHost];
    NSInteger port = [self proxyPort];
    if (!host.length || port <= 0 || port > 65535) return nil;
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
        // HTTPS* CF constants are macOS-only in SDK — use string keys (same as iPFakerAA ServerLite)
        proxy[(NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxy[(NSString *)kCFNetworkProxiesHTTPProxy] = host;
        proxy[(NSString *)kCFNetworkProxiesHTTPPort] = @(port);
        proxy[@"HTTPSEnable"] = @YES;
        proxy[@"HTTPSProxy"] = host;
        proxy[@"HTTPSPort"] = @(port);
    }
    return proxy;
}

/// Locale BCP-47 / Apple locale from ISO country (lab heuristic).
+ (NSDictionary *)localeBundleForCountryCode:(NSString *)cc {
    NSString *c = (cc ?: @"").uppercaseString;
    NSDictionary *map = @{
        @"VN": @{ @"bcp": @"vi-VN", @"apple": @"vi_VN", @"lang": @"vi", @"cur": @"VND" },
        @"US": @{ @"bcp": @"en-US", @"apple": @"en_US", @"lang": @"en", @"cur": @"USD" },
        @"GB": @{ @"bcp": @"en-GB", @"apple": @"en_GB", @"lang": @"en", @"cur": @"GBP" },
        @"JP": @{ @"bcp": @"ja-JP", @"apple": @"ja_JP", @"lang": @"ja", @"cur": @"JPY" },
        @"KR": @{ @"bcp": @"ko-KR", @"apple": @"ko_KR", @"lang": @"ko", @"cur": @"KRW" },
        @"CN": @{ @"bcp": @"zh-CN", @"apple": @"zh_CN", @"lang": @"zh", @"cur": @"CNY" },
        @"TW": @{ @"bcp": @"zh-TW", @"apple": @"zh_TW", @"lang": @"zh", @"cur": @"TWD" },
        @"TH": @{ @"bcp": @"th-TH", @"apple": @"th_TH", @"lang": @"th", @"cur": @"THB" },
        @"SG": @{ @"bcp": @"en-SG", @"apple": @"en_SG", @"lang": @"en", @"cur": @"SGD" },
        @"DE": @{ @"bcp": @"de-DE", @"apple": @"de_DE", @"lang": @"de", @"cur": @"EUR" },
        @"FR": @{ @"bcp": @"fr-FR", @"apple": @"fr_FR", @"lang": @"fr", @"cur": @"EUR" },
        @"AU": @{ @"bcp": @"en-AU", @"apple": @"en_AU", @"lang": @"en", @"cur": @"AUD" },
        @"IN": @{ @"bcp": @"en-IN", @"apple": @"en_IN", @"lang": @"en", @"cur": @"INR" },
        @"ID": @{ @"bcp": @"id-ID", @"apple": @"id_ID", @"lang": @"id", @"cur": @"IDR" },
        @"MY": @{ @"bcp": @"ms-MY", @"apple": @"ms_MY", @"lang": @"ms", @"cur": @"MYR" },
        @"PH": @{ @"bcp": @"en-PH", @"apple": @"en_PH", @"lang": @"en", @"cur": @"PHP" },
        @"RU": @{ @"bcp": @"ru-RU", @"apple": @"ru_RU", @"lang": @"ru", @"cur": @"RUB" },
    };
    return map[c] ?: @{ @"bcp": @"en-US", @"apple": @"en_US", @"lang": @"en", @"cur": @"USD" };
}

- (NSData *)httpGET:(NSString *)urlString throughProxy:(BOOL)useProxy error:(NSError **)errOut {
    return [self httpGET:urlString throughProxy:useProxy timeout:6.0 error:errOut];
}

- (NSData *)httpGET:(NSString *)urlString throughProxy:(BOOL)useProxy timeout:(NSTimeInterval)timeout error:(NSError **)errOut {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;
    if (timeout < 2.0) timeout = 2.0;
    if (timeout > 20.0) timeout = 20.0;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = timeout;
    cfg.timeoutIntervalForResource = timeout + 1.0;
    if (useProxy) {
        NSDictionary *px = [self proxySessionDictionary];
        if (px) cfg.connectionProxyDictionary = px;
    }
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *outData = nil;
    __block NSError *outErr = nil;
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        outData = data;
        outErr = err;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 1.5) * NSEC_PER_SEC)));
    [session invalidateAndCancel];
    if (errOut) *errOut = outErr;
    return outData;
}

/// City bounding box (WGS84). Known VN metros + generic jitter around IP center.
/// Returns @{ minLat, maxLat, minLon, maxLon, label } — approx metro area for Maps/Weather.
+ (NSDictionary *)boundingBoxForCity:(NSString *)city
                              region:(NSString *)region
                         countryCode:(NSString *)cc
                           centerLat:(double)clat
                           centerLon:(double)clon {
    NSString *blob = [NSString stringWithFormat:@"%@ %@ %@",
                      city ?: @"", region ?: @"", cc ?: @""].lowercaseString;
    // Normalize Vietnamese / common aliases (ip-api may return Hanoi / Ha Noi / etc.)
    blob = [blob stringByReplacingOccurrencesOfString:@"à" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"á" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ạ" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ả" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ã" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ă" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"â" withString:@"a"];
    blob = [blob stringByReplacingOccurrencesOfString:@"è" withString:@"e"];
    blob = [blob stringByReplacingOccurrencesOfString:@"é" withString:@"e"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ê" withString:@"e"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ì" withString:@"i"];
    blob = [blob stringByReplacingOccurrencesOfString:@"í" withString:@"i"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ò" withString:@"o"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ó" withString:@"o"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ô" withString:@"o"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ơ" withString:@"o"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ù" withString:@"u"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ú" withString:@"u"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ư" withString:@"u"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ỳ" withString:@"y"];
    blob = [blob stringByReplacingOccurrencesOfString:@"ý" withString:@"y"];
    blob = [blob stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];

    typedef struct { const char *needle; double minLat, maxLat, minLon, maxLon; const char *label; } Box;
    // Approximate metro bounds (OpenStreetMap / common geo ranges — lab spoof only)
    static const Box kBoxes[] = {
        { "ha noi",      20.96, 21.12, 105.75, 105.92, "Ha Noi metro" },
        { "hanoi",       20.96, 21.12, 105.75, 105.92, "Ha Noi metro" },
        { "ho chi minh", 10.72, 10.89, 106.60, 106.85, "Ho Chi Minh metro" },
        { "thu duc",     10.72, 10.89, 106.60, 106.85, "Ho Chi Minh metro" },
        { "saigon",      10.72, 10.89, 106.60, 106.85, "Ho Chi Minh metro" },
        { "da nang",     15.98, 16.12, 108.15, 108.28, "Da Nang metro" },
        { "danang",      15.98, 16.12, 108.15, 108.28, "Da Nang metro" },
        { "hai phong",   20.80, 20.92, 106.63, 106.75, "Hai Phong metro" },
        { "haiphong",    20.80, 20.92, 106.63, 106.75, "Hai Phong metro" },
        { "can tho",     10.00, 10.08, 105.72, 105.82, "Can Tho metro" },
        { "cantho",      10.00, 10.08, 105.72, 105.82, "Can Tho metro" },
        { "bien hoa",    10.90, 11.00, 106.78, 106.90, "Bien Hoa" },
        { "nha trang",   12.20, 12.30, 109.15, 109.22, "Nha Trang" },
        { "hue",         16.43, 16.50, 107.55, 107.62, "Hue" },
        { "vung tau",    10.32, 10.40, 107.05, 107.12, "Vung Tau" },
        { NULL, 0, 0, 0, 0, NULL }
    };
    for (int i = 0; kBoxes[i].needle; i++) {
        if ([blob containsString:@(kBoxes[i].needle)]) {
            return @{
                @"minLat": @(kBoxes[i].minLat), @"maxLat": @(kBoxes[i].maxLat),
                @"minLon": @(kBoxes[i].minLon), @"maxLon": @(kBoxes[i].maxLon),
                @"label": @(kBoxes[i].label),
            };
        }
    }
    // Generic: ~±3–4 km around IP geocode center (≈0.035°)
    double d = 0.035;
    return @{
        @"minLat": @(clat - d), @"maxLat": @(clat + d),
        @"minLon": @(clon - d), @"maxLon": @(clon + d),
        @"label": city.length ? [NSString stringWithFormat:@"%@ area", city] : @"proxy area",
    };
}

+ (void)randomPointInBox:(NSDictionary *)box latOut:(double *)latOut lonOut:(double *)lonOut {
    double minLat = [box[@"minLat"] doubleValue];
    double maxLat = [box[@"maxLat"] doubleValue];
    double minLon = [box[@"minLon"] doubleValue];
    double maxLon = [box[@"maxLon"] doubleValue];
    if (maxLat < minLat) { double t = minLat; minLat = maxLat; maxLat = t; }
    if (maxLon < minLon) { double t = minLon; minLon = maxLon; maxLon = t; }
    double u1 = (double)arc4random_uniform(100000) / 100000.0;
    double u2 = (double)arc4random_uniform(100000) / 100000.0;
    if (latOut) *latOut = minLat + (maxLat - minLat) * u1;
    if (lonOut) *lonOut = minLon + (maxLon - minLon) * u2;
}

- (NSString *)syncTimeMapWeatherFromProxyProgress:(void (^)(NSString *))progress
                                      geoKeysOut:(NSDictionary **)keysOut {
    if (progress) progress(@"Lấy geo theo IP (qua proxy nếu bật)…");
    BOOL usePx = [self proxyEnabled] && [self proxySessionDictionary] != nil;
    // ip-api.com free JSON (HTTP) — fields: lat, lon, timezone, countryCode, city, query
    // Standard WGS84 + IANA TZ for FakeLocation / FakeLocale / Maps / Weather
    NSError *err = nil;
    NSData *data = [self httpGET:@"http://ip-api.com/json/?fields=status,message,country,countryCode,regionName,city,lat,lon,timezone,query,isp"
                    throughProxy:usePx error:&err];
    if (!data.length) {
        // Fallback without proxy
        data = [self httpGET:@"http://ip-api.com/json/?fields=status,message,country,countryCode,regionName,city,lat,lon,timezone,query,isp"
                throughProxy:NO error:&err];
    }
    if (!data.length) {
        NSString *m = [NSString stringWithFormat:@"Geo FAIL: %@", err.localizedDescription ?: @"no data"];
        if (keysOut) *keysOut = nil;
        return m;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        if (keysOut) *keysOut = nil;
        return @"Geo FAIL: JSON không hợp lệ";
    }
    NSDictionary *j = (NSDictionary *)obj;
    if (![[j[@"status"] description] isEqualToString:@"success"]) {
        if (keysOut) *keysOut = nil;
        return [NSString stringWithFormat:@"Geo FAIL: %@", j[@"message"] ?: @"status!=success"];
    }
    double centerLat = [j[@"lat"] doubleValue];
    double centerLon = [j[@"lon"] doubleValue];
    NSString *tz = [j[@"timezone"] description] ?: @"UTC";
    NSString *cc = [j[@"countryCode"] description] ?: @"US";
    NSString *city = [j[@"city"] description] ?: @"";
    NSString *region = [j[@"regionName"] description] ?: @"";
    NSString *country = [j[@"country"] description] ?: @"";
    NSString *ip = [j[@"query"] description] ?: @"";
    NSString *isp = [j[@"isp"] description] ?: @"";
    NSDictionary *loc = [AppState localeBundleForCountryCode:cc];

    // Random point inside city / metro box (Maps + Weather + spoof apps share dual-path)
    NSDictionary *box = [AppState boundingBoxForCity:city region:region countryCode:cc
                                           centerLat:centerLat centerLon:centerLon];
    double lat = centerLat, lon = centerLon;
    [AppState randomPointInBox:box latOut:&lat lonOut:&lon];
    double acc = 8.0 + (double)arc4random_uniform(180) / 10.0; // 8–26 m
    double alt = 5.0 + (double)arc4random_uniform(40);         // 5–45 m

    NSString *bcp = loc[@"bcp"] ?: @"en-US";
    NSString *appleLoc = loc[@"apple"] ?: @"en_US";
    NSString *boxLabel = box[@"label"] ?: @"area";
    NSDictionary *keys = @{
        // Location → Maps + Weather (CLLocation hooks, WGS84) — random in city
        @"FakeLocation": @YES,
        @"Latitude": @(lat),
        @"Longitude": @(lon),
        @"LocationAccuracy": @(acc),
        @"Altitude": @(alt),
        // Timezone → clock / FakeLocale (NSTimeZone IANA)
        @"FakeLocale": @YES,
        @"TimeZoneName": tz,
        @"CountryCode": cc,
        @"PreferredLanguage": bcp,
        @"LocaleIdentifier": appleLoc,
        @"AppleLocale": appleLoc,
        @"AppleLanguages": @[ bcp ],
        @"LanguageCode": loc[@"lang"] ?: @"en",
        @"CurrencyCode": loc[@"cur"] ?: @"USD",
        @"CalendarIdentifier": @"gregorian",
        // Meta for UI / lab / dual-path audit
        @"ProxyEgressIP": ip,
        @"ProxyGeoCity": city,
        @"ProxyGeoCountry": country,
        @"ProxyGeoISP": isp,
        @"ProxyGeoRegion": region,
        @"ProxyGeoBox": boxLabel,
        @"ProxyGeoCenterLat": @(centerLat),
        @"ProxyGeoCenterLon": @(centerLon),
        @"SyncGeoFromProxy": @YES,
        @"GeoRandomInCity": @YES,
        @"GeoSyncedAtUnix": @((NSInteger)[[NSDate date] timeIntervalSince1970]),
    };
    if (keysOut) *keysOut = keys;

    // Persist last geo summary (dual-path readable)
    @try {
        NSData *json = [NSJSONSerialization dataWithJSONObject:keys options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:@"/var/mobile/Library/iPFaker/proxy_geo.json" atomically:YES];
        [json writeToFile:@"/var/jb/etc/ipfaker/proxy_geo.json" atomically:YES];
    } @catch (__unused NSException *ex) {}

    NSString *summary = [NSString stringWithFormat:
        @"Đã đồng bộ theo proxy/IP (random trong thành phố):\n"
        @"• IP: %@\n"
        @"• Thành phố proxy: %@, %@ · vùng fake: %@\n"
        @"• Vị trí Map/Thời tiết (random): %.5f, %.5f (±acc %.0fm)\n"
        @"• Tâm IP-API: %.4f, %.4f\n"
        @"• Múi giờ: %@ · Ngôn ngữ: %@ · Quốc gia: %@\n"
        @"• ISP: %@",
        ip, city, country, boxLabel, lat, lon, acc, centerLat, centerLon,
        tz, loc[@"bcp"] ?: @"?", cc, isp];
    if (progress) progress(summary);
    return summary;
}

/// Proxy keys + random-in-city geo → dual-path (called from both Reset buttons).
- (NSString *)attachProxyGeoRandomInCityProgress:(void (^)(NSString *))progress {
    [self saveProxyAppAttest];
    [self setSyncGeoFromProxyEnabled:YES];
    NSMutableDictionary *keys = [[self proxyAppAttestFlatKeys] mutableCopy];
    NSDictionary *geo = nil;
    NSString *geoMsg = [self syncTimeMapWeatherFromProxyProgress:progress geoKeysOut:&geo];
    if (geo.count) {
        [keys addEntriesFromDictionary:geo];
        keys[@"FakeLocation"] = @YES;
        keys[@"FakeLocale"] = @YES;
        [self setToggle:YES forKey:@"FakeLocation"];
        [self setToggle:YES forKey:@"FakeLocale"];
    }
    NSString *merge = [ProfileBuilder mergeKeysIntoConfig:keys progress:progress];
    return [NSString stringWithFormat:@"%@\n%@", geoMsg ?: @"", merge ?: @""];
}

- (NSString *)syncLocationNowProgress:(void (^)(NSString *))progress {
    [self loadProxyFromDualPathConfig];
    if (![self proxyEnabled] || ![self proxyHost].length) {
        NSString *m = @"Bật proxy (host:port:user:pass) trước khi đồng bộ Location.";
        self.statusText = m;
        return m;
    }
    if (progress) progress(@"Đồng bộ Location / Map / Thời tiết…");
    NSString *msg = [self attachProxyGeoRandomInCityProgress:progress];
    self.statusText = msg;
    [self postDidChange];
    return msg;
}

- (NSString *)applyProxyAppAttestToConfigProgress:(void (^)(NSString *))progress {
    [self saveProxyAppAttest];
    if (progress) progress(@"Gộp Proxy / AppAttest vào config.plist…");
    NSMutableDictionary *keys = [[self proxyAppAttestFlatKeys] mutableCopy];
    NSString *geoMsg = @"";
    // Sync geo when toggle ON: through proxy if enabled, else direct egress IP.
    if ([self syncGeoFromProxyEnabled]) {
        if (progress) progress(@"Đồng bộ thời gian / map / thời tiết theo proxy…");
        NSDictionary *geo = nil;
        geoMsg = [self syncTimeMapWeatherFromProxyProgress:progress geoKeysOut:&geo];
        if (geo.count) [keys addEntriesFromDictionary:geo];
    }
    // Always enable location/locale flags when geo present
    if (keys[@"Latitude"]) {
        keys[@"FakeLocation"] = @YES;
        keys[@"FakeLocale"] = @YES;
        [self setToggle:YES forKey:@"FakeLocation"];
        [self setToggle:YES forKey:@"FakeLocale"];
    }
    NSString *msg = [ProfileBuilder mergeKeysIntoConfig:keys progress:progress];
    NSString *full = geoMsg.length
        ? [NSString stringWithFormat:@"%@\n\n%@", geoMsg, msg]
        : msg;
    self.statusText = full;
    [self postDidChange];
    return full;
}

- (NSString *)testProxyConnection {
    NSString *host = [self proxyHost];
    NSInteger port = [self proxyPort];
    if (!host.length || port <= 0 || port > 65535)
        return @"ERR: Host/Port không hợp lệ";

    NSDictionary *proxy = [self proxySessionDictionary];
    if (!proxy) return @"ERR: không tạo được proxy dict";

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.connectionProxyDictionary = proxy;
    cfg.timeoutIntervalForRequest = 12;
    cfg.timeoutIntervalForResource = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *result = @"ERR: timeout";
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

    // Auto geo sync after successful test
    if ([result hasPrefix:@"OK"] && [self syncGeoFromProxyEnabled]) {
        NSDictionary *geo = nil;
        NSString *geoMsg = [self syncTimeMapWeatherFromProxyProgress:nil geoKeysOut:&geo];
        if (geo.count) {
            NSMutableDictionary *keys = [[self proxyAppAttestFlatKeys] mutableCopy];
            [keys addEntriesFromDictionary:geo];
            keys[@"FakeLocation"] = @YES;
            keys[@"FakeLocale"] = @YES;
            [ProfileBuilder mergeKeysIntoConfig:keys progress:nil];
            result = [NSString stringWithFormat:@"%@\n\n%@", result, geoMsg];
        } else {
            result = [NSString stringWithFormat:@"%@\n\n%@", result, geoMsg];
        }
    }
    return result;
}

- (void)postDidChange {
    // Always main-thread: observers refresh UI (crash if posted from bg work queues).
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AppStateDidChangeNotification object:self];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:AppStateDidChangeNotification object:self];
        });
    }
}

@end
