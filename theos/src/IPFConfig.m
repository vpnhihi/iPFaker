// IPFConfig.m — load order mirrors lab reference-stack:
//   1) /var/jb/etc/ipfaker/config.plist  (flat keys, dictionaryWithContentsOfFile)
//   2) active_profile.json fallback

#import "IPFConfig.h"

static NSArray<NSString *> *IPFPlistCandidates(void) {
    // Zalo sandbox: /var/jb/etc is readable; /var/mobile/Library/iPFaker often is NOT.
    // Prefer jb first, then mobile (app UI), then legacy.
    return @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
        @"/var/mobile/Library/Preferences/com.ipfaker.config.plist",
    ];
}

static NSArray<NSString *> *IPFJSONCandidates(void) {
    return @[
        @"/var/jb/etc/ipfaker/active_profile.json",
        @"/var/mobile/Library/iPFaker/active_profile.json",
        @"/var/mobile/Library/iPFaker/device_profile.json",
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
@property (nonatomic, strong, readwrite, nullable) NSDictionary *flat; // lab flat flat map
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

- (void)applyFlatPlist:(NSDictionary *)flatIn path:(NSString *)path {
    // Mutable so we can inject Hostname derived from device name (keep flat consistent)
    NSMutableDictionary *flat = [flatIn isKindOfClass:[NSDictionary class]]
        ? [flatIn mutableCopy] : [NSMutableDictionary dictionary];
    self.flat = flat;
    self.root = flat;
    self.profilePath = path;
    // Build mgMap / sysctl from flat lab keys
    NSMutableDictionary *mg = [NSMutableDictionary dictionary];
    NSMutableDictionary *sys = [NSMutableDictionary dictionary];
    NSArray *mgKeys = @[
        @"ProductType", @"HWModelStr", @"HardwareModel", @"DeviceName", @"UserAssignedDeviceName",
        @"MarketingName", @"SerialNumber", @"UniqueDeviceID", @"UniqueChipID",
        @"ProductVersion", @"BuildVersion", @"ProductBuildVersion",
        @"ModelNumber", @"PartNumber", @"RegionInfo", @"RegionCode", @"RegulatoryModelNumber",
        @"ModelNumberAxxxx", @"PartNumberRegion",
        @"CPUArchitecture", @"HardwarePlatform", @"DeviceClass",
        @"InternationalMobileEquipmentIdentity", @"InternationalMobileEquipmentIdentity2",
        @"MobileEquipmentIdentifier", @"EID",
        @"WifiAddress", @"BluetoothAddress", @"EthernetMacAddress",
        @"BSSID", @"SSID", @"VolumeUUID",
        @"IOPlatformSerialNumber", @"MLBSerialNumber",
        @"Hostname",
        @"main-screen-width", @"main-screen-height", @"main-screen-scale", @"main-screen-pitch",
        @"DeviceColor", @"DeviceEnclosureColor", @"BasebandVersion",
    ];
    for (NSString *k in mgKeys) {
        id v = flat[k];
        if (v) mg[k] = v;
    }
    // Aliases lab uses
    if (flat[@"ProductType"]) {
        sys[@"hw.machine"] = flat[@"ProductType"];
        mg[@"ProductType"] = flat[@"ProductType"];
    }
    if (flat[@"HWModelStr"] ?: flat[@"HardwareModel"]) {
        id hw = flat[@"HWModelStr"] ?: flat[@"HardwareModel"];
        sys[@"hw.model"] = hw;
        mg[@"HWModelStr"] = hw;
    }
    if (flat[@"SerialNumber"]) {
        mg[@"SerialNumber"] = flat[@"SerialNumber"];
        sys[@"hw.serialnumber"] = flat[@"SerialNumber"];
    }
    if (flat[@"UniqueDeviceID"]) mg[@"UniqueDeviceID"] = flat[@"UniqueDeviceID"];
    if (flat[@"ProductVersion"]) {
        mg[@"ProductVersion"] = flat[@"ProductVersion"];
        sys[@"kern.osproductversion"] = flat[@"ProductVersion"];
    }
    if (flat[@"BuildVersion"] ?: flat[@"ProductBuildVersion"]) {
        id b = flat[@"BuildVersion"] ?: flat[@"ProductBuildVersion"];
        mg[@"BuildVersion"] = b;
        sys[@"kern.osversion"] = b;
    }
    // Darwin kernel release/version must track spoof iOS (NOT leave host kernel 21.5.0 when spoof 15.4)
    // Mapping: iOS N.M → Darwin (N+6).M.0  (e.g. 15.4 → 21.4.0, 16.5 → 22.5.0)
    {
        NSString *iosVer = [flat[@"ProductVersion"] description];
        NSString *rel = flat[@"kern.osrelease"] ?: flat[@"DarwinRelease"];
        if (![rel isKindOfClass:[NSString class]] || !rel.length) {
            NSInteger maj = 21, min = 0, pat = 0;
            if (iosVer.length) {
                NSArray *parts = [iosVer componentsSeparatedByString:@"."];
                if (parts.count >= 1) maj = [parts[0] integerValue] + 6;
                if (parts.count >= 2) min = [parts[1] integerValue];
                if (parts.count >= 3) pat = [parts[2] integerValue];
                if (maj < 19) maj = 19;
            }
            rel = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)maj, (long)min, (long)pat];
        }
        sys[@"kern.osrelease"] = rel;
        NSString *kv = flat[@"kern.version"] ?: flat[@"DarwinVersion"];
        if (![kv isKindOfClass:[NSString class]] || !kv.length) {
            NSString *board = flat[@"HWModelStr"] ?: flat[@"HardwareModel"] ?: @"T8020";
            // Compact utsname.version-style string (apps often only parse leading Darwin Kernel Version X.Y.Z)
            kv = [NSString stringWithFormat:
                  @"Darwin Kernel Version %@: root:xnu-spoof/RELEASE_ARM64_%@",
                  rel, board];
        }
        sys[@"kern.version"] = kv;
        // Mirror flat for UI/debug
        if (!flat[@"kern.osrelease"]) ((NSMutableDictionary *)flat)[@"kern.osrelease"] = rel;
        if (!flat[@"kern.version"]) ((NSMutableDictionary *)flat)[@"kern.version"] = kv;
    }
    if (flat[@"DeviceName"] ?: flat[@"UserAssignedDeviceName"] ?: flat[@"Hostname"]) {
        id n = flat[@"UserAssignedDeviceName"] ?: flat[@"DeviceName"] ?: @"iPhone";
        mg[@"UserAssignedDeviceName"] = n;
        mg[@"DeviceName"] = flat[@"DeviceName"] ?: @"iPhone";
        // Hostname must stay in sync with gethostname / uname.nodename / NSProcessInfo
        // (DNS-label safe: A–Z a–z 0–9 hyphen only, ≤63)
        NSString *hn = flat[@"Hostname"];
        if (![hn isKindOfClass:[NSString class]] || hn.length == 0) {
            NSString *raw = [n description] ?: @"iPhone";
            NSMutableString *safe = [NSMutableString string];
            for (NSUInteger i = 0; i < raw.length && safe.length < 63; i++) {
                unichar c = [raw characterAtIndex:i];
                if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9') || c == '-') {
                    [safe appendFormat:@"%C", c];
                } else if ((c == ' ' || c == '_' || c == '.') && safe.length
                           && [safe characterAtIndex:safe.length - 1] != '-') {
                    [safe appendString:@"-"];
                }
            }
            while (safe.length && [safe characterAtIndex:0] == '-')
                [safe deleteCharactersInRange:NSMakeRange(0, 1)];
            while (safe.length && [safe characterAtIndex:safe.length - 1] == '-')
                [safe deleteCharactersInRange:NSMakeRange(safe.length - 1, 1)];
            hn = safe.length ? [safe copy] : @"iPhone";
        }
        mg[@"Hostname"] = hn;
        sys[@"kern.hostname"] = hn;
        flat[@"Hostname"] = hn; // Extra gethostname / NSProcessInfo read same key
    }
    // Marketing name for Zalo UI (critical — Zalo shows "iPhone XS Max" from real type)
    if (flat[@"MarketingName"]) mg[@"MarketingName"] = flat[@"MarketingName"];

    // RAM / CPU (sysctl integer keys)
    id mem = flat[@"hw.memsize"] ?: flat[@"PhysicalMemoryBytes"];
    if (mem) {
        if ([mem isKindOfClass:[NSString class]]) {
            sys[@"hw.memsize"] = @([(NSString *)mem longLongValue]);
        } else {
            sys[@"hw.memsize"] = mem;
        }
    } else if (flat[@"PhysicalMemoryMB"]) {
        long long mb = [flat[@"PhysicalMemoryMB"] longLongValue];
        sys[@"hw.memsize"] = @(mb * 1024LL * 1024LL);
    }
    for (NSString *ck in @[ @"hw.ncpu", @"hw.physicalcpu", @"hw.logicalcpu" ]) {
        if (flat[ck]) sys[ck] = flat[ck];
    }
    if (flat[@"kern.boottime"] ?: flat[@"BootTimeUnix"]) {
        id bt = flat[@"kern.boottime"] ?: flat[@"BootTimeUnix"];
        sys[@"kern.boottime"] = bt;
    }
    // Extra MG colors / baseband / disk / locale / location (Extra hooks also read stringForKey)
    for (NSString *ek in @[
        @"DeviceColor", @"DeviceEnclosureColor", @"BasebandVersion",
        @"TotalDiskCapacity", @"FreeDiskSpace", @"UserAgent", @"HTTPUserAgent",
        @"MaxRefreshHz", @"EID", @"PartNumber", @"ModelNumberAxxxx",
        @"IDFA", @"IDFV", @"identifierForVendor", @"advertisingIdentifier",
        // BCP 47 / ISO 639-1 / ISO 3166-1 / IANA tz
        @"AppleLocale", @"AppleLanguages", @"LanguageCode", @"CountryCode",
        @"LocaleIdentifier", @"PreferredLanguage", @"TimeZoneName",
        @"CalendarIdentifier", @"CurrencyCode",
        // WGS84
        @"Latitude", @"Longitude", @"LocationAccuracy", @"Altitude",
        @"BootTimeUnix", @"TimeOffsetSeconds",
        @"WebRTCLocalIP", @"SSID", @"BSSID",
    ]) {
        if (flat[ek]) mg[ek] = flat[ek];
    }

    self.mgMap = [mg copy];
    self.sysctlMap = [sys copy];
    // storage + webview + jb for Extra hooks / JSON root
    if (flat[@"TotalDiskCapacity"] || flat[@"FreeDiskSpace"]) {
        self.storage = @{
            @"TotalDiskCapacity": flat[@"TotalDiskCapacity"] ?: @0,
            @"FreeDiskSpace": flat[@"FreeDiskSpace"] ?: @0,
        };
    }
    if (flat[@"UserAgent"] ?: flat[@"HTTPUserAgent"]) {
        self.webview = @{
            @"UserAgent": flat[@"UserAgent"] ?: @"",
            @"HTTPUserAgent": flat[@"HTTPUserAgent"] ?: flat[@"UserAgent"] ?: @"",
        };
    }
    if (!self.jailbreakHide) {
        self.jailbreakHide = @{
            @"paths": @[
                @"/Applications/Cydia.app",
                @"/Applications/Sileo.app",
                @"/Library/MobileSubstrate",
                @"/usr/lib/TweakInject",
                @"/var/jb",
                @"/usr/lib/frida",
                @"FridaGadget",
            ],
        };
    }

    self.model = @{
        @"ProductType": flat[@"ProductType"] ?: @"",
        @"HWModelStr": flat[@"HWModelStr"] ?: flat[@"HardwareModel"] ?: @"",
        @"UserAssignedDeviceName": flat[@"UserAssignedDeviceName"] ?: flat[@"DeviceName"] ?: @"",
        @"MarketingName": flat[@"MarketingName"] ?: @"",
        @"hw.machine": flat[@"ProductType"] ?: @"",
    };
    self.os = @{
        @"ProductVersion": flat[@"ProductVersion"] ?: @"",
        @"BuildVersion": flat[@"BuildVersion"] ?: flat[@"ProductBuildVersion"] ?: @"",
        @"Hostname": flat[@"UserAssignedDeviceName"] ?: @"iPhone",
    };
    self.uidevice = @{
        @"name": flat[@"UserAssignedDeviceName"] ?: flat[@"DeviceName"] ?: @"iPhone",
        @"model": @"iPhone",
        @"localizedModel": @"iPhone",
        @"systemName": @"iOS",
        @"systemVersion": flat[@"ProductVersion"] ?: @"",
        @"identifierForVendor": flat[@"IDFV"] ?: flat[@"identifierForVendor"] ?: @"",
    };
    self.identity = @{
        @"SerialNumber": flat[@"SerialNumber"] ?: @"",
        @"UDID": flat[@"UniqueDeviceID"] ?: @"",
        @"IDFA": flat[@"IDFA"] ?: @"",
        @"IDFV": flat[@"IDFV"] ?: @"",
    };
    // Carrier (CommCenter + CTCarrier) — always fill radio for FakeNetwork spoof
    NSString *cname = flat[@"CarrierName"] ?: flat[@"carrierName"] ?: @"Viettel";
    NSString *mcc = flat[@"MobileCountryCode"] ?: flat[@"carrierMCC"] ?: @"452";
    NSString *mnc = flat[@"MobileNetworkCode"] ?: flat[@"carrierMNC"] ?: @"04";
    NSString *iso = flat[@"ISOCountryCode"] ?: flat[@"carrierISO"] ?: @"vn";
    iso = iso.lowercaseString;
    NSString *radio = flat[@"CurrentRadioAccessTechnology"]
        ?: flat[@"RadioAccessTechnology"]
        ?: flat[@"carrierRadioAccess"]
        ?: @"CTRadioAccessTechnologyNR";
    // Apple CTRadioAccessTechnology* full constant if short form
    if (radio.length && ![radio hasPrefix:@"CTRadioAccessTechnology"])
        radio = [@"CTRadioAccessTechnology" stringByAppendingString:radio];
    self.telephony = @{
        @"CarrierName": cname,
        @"MobileCountryCode": mcc,
        @"MobileNetworkCode": mnc,
        @"ISOCountryCode": iso,
        @"RadioAccessTechnology": radio,
        @"CurrentRadioAccessTechnology": radio,
        @"AllowsVOIP": flat[@"AllowsVOIP"] ?: @YES,
    };
    // Mirror back into flat so dual-path config always has canonical keys
    if ([flat isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *mf = (NSMutableDictionary *)flat;
        mf[@"CarrierName"] = cname;
        mf[@"MobileCountryCode"] = mcc;
        mf[@"MobileNetworkCode"] = mnc;
        mf[@"ISOCountryCode"] = iso;
        mf[@"carrierName"] = cname;
        mf[@"carrierMCC"] = mcc;
        mf[@"carrierMNC"] = mnc;
        mf[@"carrierISO"] = iso;
        mf[@"carrierRadioAccess"] = radio;
        mf[@"RadioAccessTechnology"] = radio;
        mf[@"CurrentRadioAccessTechnology"] = radio;
    }
    self.enabled = YES;
    if (flat[@"Enabled"] != nil) self.enabled = [flat[@"Enabled"] boolValue];
    self.loaded = YES;
}

- (void)applyJSONRoot:(NSDictionary *)root path:(NSString *)path {
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
    // Ensure MarketingName present for Zalo device list
    if (self.mgMap && !self.mgMap[@"MarketingName"]) {
        NSMutableDictionary *m = [self.mgMap mutableCopy];
        // Prefer model/flat MarketingName for ANY catalog device — never force one SKU
        NSString *mkt = self.model[@"MarketingName"]
            ?: self.model[@"ProductName"]
            ?: self.flat[@"MarketingName"]
            ?: @"iPhone";
        m[@"MarketingName"] = mkt;
        self.mgMap = m;
    }
    NSDictionary *apply = root[@"apply"];
    self.enabled = YES;
    if ([apply isKindOfClass:[NSDictionary class]] && apply[@"enabled"] != nil)
        self.enabled = [apply[@"enabled"] boolValue];
    self.loaded = YES;
}

- (BOOL)reload {
    self.loaded = NO;
    self.enabled = NO;
    self.root = nil;
    self.flat = nil;
    self.profilePath = nil;
    self.mgMap = nil;
    self.sysctlMap = nil;

    // Pick NEWER readable plist among candidates (avoids split-brain mobile vs jb).
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bestPath = nil;
    NSDictionary *bestPlist = nil;
    NSDate *bestDate = [NSDate distantPast];
    for (NSString *path in IPFPlistCandidates()) {
        if (![fm isReadableFileAtPath:path]) continue;
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![plist isKindOfClass:[NSDictionary class]] || plist.count == 0) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        NSDate *mod = attrs[NSFileModificationDate] ?: [NSDate distantPast];
        // Prefer jb when mtimes equal (Zalo can always read jb)
        BOOL prefer = [mod compare:bestDate] == NSOrderedDescending
            || ([mod isEqualToDate:bestDate] && [path containsString:@"/var/jb/"]);
        if (!bestPlist || prefer) {
            bestPlist = plist;
            bestPath = path;
            bestDate = mod;
        }
    }
    if (bestPlist) {
        [self applyFlatPlist:bestPlist path:bestPath];
        NSLog(@"[iPFaker] config %@ PT=%@ MK=%@ mtime=%@",
              bestPath, bestPlist[@"ProductType"], bestPlist[@"MarketingName"], bestDate);
        return YES;
    }

    // JSON fallback (same newest logic)
    bestPath = nil;
    NSDictionary *bestJSON = nil;
    bestDate = [NSDate distantPast];
    for (NSString *path in IPFJSONCandidates()) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        NSDate *mod = attrs[NSFileModificationDate] ?: [NSDate distantPast];
        if (!bestJSON || [mod compare:bestDate] == NSOrderedDescending) {
            bestJSON = obj;
            bestPath = path;
            bestDate = mod;
        }
    }
    if (bestJSON) {
        [self applyJSONRoot:bestJSON path:bestPath];
        NSLog(@"[iPFaker] JSON config: %@ mg=%lu", bestPath, (unsigned long)self.mgMap.count);
        return YES;
    }

    NSLog(@"[iPFaker] config NOT found — need /var/jb/etc/ipfaker/config.plist");
    return NO;
}

- (nullable id)mgValueForKey:(NSString *)key {
    if (!key) return nil;
    id v = self.mgMap[key];
    if (v) return v;
    if (self.flat[key]) return self.flat[key];

    // MobileGestalt aliases Zalo/system actually query (hyphen / camel / lower)
    static NSDictionary *aliases;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        aliases = @{
            // Settings → General → About (Giới thiệu) + Zalo
            @"marketing-name": @"MarketingName",
            @"Marketing-Name": @"MarketingName",
            @"MarketingProductName": @"MarketingName",
            @"product-type": @"ProductType",
            @"Product-Type": @"ProductType",
            @"hw.model": @"HWModelStr",
            @"HWModel": @"HWModelStr",
            @"hardware-model": @"HWModelStr",
            @"DeviceName": @"DeviceName",
            @"device-name": @"UserAssignedDeviceName",
            @"user-assigned-device-name": @"UserAssignedDeviceName",
            @"UserAssignedDeviceName": @"UserAssignedDeviceName",
            @"SerialNumber": @"SerialNumber",
            @"serial-number": @"SerialNumber",
            @"Serial": @"SerialNumber",
            @"UniqueDeviceID": @"UniqueDeviceID",
            @"unique-device-id": @"UniqueDeviceID",
            @"DeviceUniqueIdentifier": @"UniqueDeviceID",
            @"UDID": @"UniqueDeviceID",
            @"UniqueChipID": @"UniqueChipID",
            @"ECID": @"UniqueChipID",
            @"ChipID": @"UniqueChipID",
            @"IDFA": @"IDFA",
            @"AdvertisingIdentifier": @"IDFA",
            @"advertisingIdentifier": @"IDFA",
            @"IDFV": @"IDFV",
            @"identifierForVendor": @"IDFV",
            @"ProductVersion": @"ProductVersion",
            @"product-version": @"ProductVersion",
            @"BuildVersion": @"BuildVersion",
            @"build-version": @"BuildVersion",
            @"ProductBuildVersion": @"ProductBuildVersion",
            @"ModelNumber": @"ModelNumber",
            @"model-number": @"ModelNumber",
            @"RegulatoryModelNumber": @"RegulatoryModelNumber",
            @"regulatory-model-number": @"RegulatoryModelNumber",
            @"RegionInfo": @"RegionInfo",
            @"region-info": @"RegionInfo",
            @"InternationalMobileEquipmentIdentity": @"InternationalMobileEquipmentIdentity",
            @"MobileEquipmentIdentifier": @"MobileEquipmentIdentifier",
            @"EID": @"EID",
            @"WifiAddress": @"WifiAddress",
            @"BluetoothAddress": @"BluetoothAddress",
        };
    });
    NSString *canon = aliases[key];
    if (canon) {
        v = self.mgMap[canon] ?: self.flat[canon];
        if (v) return v;
    }
    // case-insensitive scan of mgMap (rare keys)
    for (NSString *k in self.mgMap) {
        if ([k caseInsensitiveCompare:key] == NSOrderedSame) return self.mgMap[k];
    }
    return nil;
}

- (nullable id)sysctlValueForName:(NSString *)name {
    if (!name) return nil;
    id v = self.sysctlMap[name];
    if (v) return v;
    return nil;
}

- (nullable NSString *)stringForKey:(NSString *)key {
    id v = [self mgValueForKey:key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    if (self.flat[key]) {
        id f = self.flat[key];
        if ([f isKindOfClass:[NSString class]]) return f;
        if ([f isKindOfClass:[NSNumber class]]) return [f stringValue];
    }
    return nil;
}

- (BOOL)flag:(NSString *)key defaultYes:(BOOL)defaultYes {
    if (!key.length) return defaultYes;
    id v = self.flat[key] ?: self.root[key];
    if (v == nil) return defaultYes;
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"0"] || [s isEqualToString:@"false"] || [s isEqualToString:@"no"])
            return NO;
        if ([s isEqualToString:@"1"] || [s isEqualToString:@"true"] || [s isEqualToString:@"yes"])
            return YES;
    }
    return defaultYes;
}

- (double)doubleForKey:(NSString *)key fallback:(double)fb {
    id v = self.flat[key] ?: self.root[key] ?: [self mgValueForKey:key];
    if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    return fb;
}

@end
