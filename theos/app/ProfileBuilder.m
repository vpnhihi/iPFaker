#import "ProfileBuilder.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <time.h>
#import <stdlib.h>
#import <sys/sysctl.h>
#import <string.h>

@implementation ProfileBuilder

#pragma mark - Host / Darwin kernel helpers

+ (NSString *)hostSystemVersion {
    NSDictionary *sv = [NSDictionary dictionaryWithContentsOfFile:
                        @"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *v = sv[@"ProductVersion"];
    if (v.length) return v;
    return UIDevice.currentDevice.systemVersion ?: @"0";
}

+ (NSString *)hostProductType {
    char buf[64] = {0};
    size_t len = sizeof(buf);
    if (sysctlbyname("hw.machine", buf, &len, NULL, 0) == 0 && buf[0])
        return [NSString stringWithUTF8String:buf];
    return @"";
}

+ (NSComparisonResult)compareVersion:(NSString *)a toVersion:(NSString *)b {
    NSArray *pa = [[a description] componentsSeparatedByString:@"."];
    NSArray *pb = [[b description] componentsSeparatedByString:@"."];
    NSUInteger n = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger va = i < pa.count ? [pa[i] integerValue] : 0;
        NSInteger vb = i < pb.count ? [pb[i] integerValue] : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

/// Map iOS → Darwin release + a realistic utsname.version line (board from HWModelStr).
/// Apple-style Metal GPU name from catalog chip string (A17 Pro → Apple A17 Pro GPU).
+ (NSString *)metalDeviceNameFromChip:(NSString *)chip {
    if (![chip isKindOfClass:[NSString class]] || !chip.length) return @"Apple GPU";
    NSString *c = [chip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([c rangeOfString:@"GPU" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        if ([c hasPrefix:@"Apple "]) return c;
        return [@"Apple " stringByAppendingString:c];
    }
    c = [c stringByReplacingOccurrencesOfString:@" Bionic" withString:@""];
    c = [c stringByReplacingOccurrencesOfString:@"bionic" withString:@""];
    if ([c hasPrefix:@"Apple "]) return [c stringByAppendingString:@" GPU"];
    return [NSString stringWithFormat:@"Apple %@ GPU", c];
}

/// Synthetic Metal registryID (uint64 string) — deterministic from serial, not host GPU die.
+ (NSString *)metalRegistryIDForSerial:(NSString *)serial {
    NSString *seed = serial.length ? serial : @"iPhone";
    uint32_t h = 2166136261u;
    const char *s = seed.UTF8String ?: "x";
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    uint64_t reg = 0x0000000100000000ULL | ((uint64_t)h << 8) | 0xA1ULL;
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)reg];
}

+ (NSDictionary *)darwinKernelKeysForIOS:(NSString *)iosVer board:(NSString *)board {
    NSString *iv = iosVer.length ? iosVer : @"15.0";
    int maj = 15, min = 0, pat = 0;
    sscanf(iv.UTF8String ?: "15.0", "%d.%d.%d", &maj, &min, &pat);
    // Apple: Darwin major ≈ iOS major + 6
    int dMaj = maj + 6;
    int dMin = min;
    int dPat = 0;
    // Known fine-tunes (common public Darwin minors for iOS 15.x family)
    if (maj == 15) {
        if (min <= 0) { dMin = 0; dPat = 0; }
        else if (min == 1) { dMin = 1; }
        else if (min == 2) { dMin = 2; }
        else if (min == 3) { dMin = 3; }
        else if (min == 4) { dMin = 4; }
        else if (min == 5) { dMin = 5; }
        else if (min >= 6) { dMin = 6; } // 15.6–15.8 often ship 21.6.x line
    } else if (maj == 16) {
        dMin = MIN(min, 6);
    } else if (maj == 17) {
        dMin = MIN(min, 6);
    } else if (maj >= 18) {
        dMin = MIN(min, 5);
    }
    NSString *rel = [NSString stringWithFormat:@"%d.%d.%d", dMaj, dMin, dPat];
    // Board → RELEASE_ARM64_* suffix (common AP board codes)
    NSString *b = board.length ? board : @"T8020";
    NSString *arm = @"T8020";
    NSDictionary *boardMap = @{
        @"D20AP": @"T8015", @"D21AP": @"T8015", @"D22AP": @"T8015", // 8 / 8+ / X
        @"D321AP": @"T8020", @"D331AP": @"T8020", @"D331pAP": @"T8020", // XR / XS / XS Max
        @"N841AP": @"T8020", @"D421AP": @"T8030", @"D431AP": @"T8030",
        @"D52gAP": @"T8101", @"D53gAP": @"T8101", @"D53pAP": @"T8101",
        @"D63AP": @"T8110", @"D64AP": @"T8110",
        @"D73AP": @"T8120", @"D74AP": @"T8120",
    };
    if (boardMap[b]) arm = boardMap[b];
    else if ([b hasPrefix:@"D20"] || [b hasPrefix:@"D21"] || [b hasPrefix:@"D22"]) arm = @"T8015";
    else if ([b hasPrefix:@"D33"] || [b hasPrefix:@"N84"] || [b hasPrefix:@"D32"]) arm = @"T8020";
    // Stamp strings approximate public Darwin release notes (lab identity, not byte-identical xnu)
    NSString *stamp = @"Fri Mar 18 00:48:17 PDT 2022";
    if (dMaj == 21 && dMin >= 5) stamp = @"Thu Apr 21 21:50:10 PDT 2022";
    if (dMaj == 21 && dMin >= 6) stamp = @"Sun Jun  5 20:10:15 PDT 2022";
    if (dMaj == 22) stamp = @"Sun Aug 14 20:00:00 PDT 2022";
    if (dMaj == 23) stamp = @"Wed Sep  6 21:00:00 PDT 2023";
    if (dMaj >= 24) stamp = @"Mon Mar  4 20:00:00 PST 2024";
    // Public-style xnu tags (identity strings for uname/sysctl — NOT byte-identical kernel binary)
    NSString *xnu = @"8020.101.4~15";
    if (dMaj == 21 && dMin == 0) xnu = @"8020.40.9~2";
    if (dMaj == 21 && dMin >= 1) xnu = @"8020.60.14~1";
    if (dMaj == 21 && dMin >= 2) xnu = @"8020.80.33~1";
    if (dMaj == 21 && dMin >= 3) xnu = @"8020.100.5~1";
    if (dMaj == 21 && dMin >= 4) xnu = @"8020.101.4~15";
    if (dMaj == 21 && dMin >= 5) xnu = @"8020.122.1~1";
    if (dMaj == 21 && dMin >= 6) xnu = @"8020.140.41~1";
    if (dMaj == 22) xnu = @"8209.41.16~2";
    if (dMaj == 23) xnu = @"10002.1.13~1";
    if (dMaj >= 24) xnu = @"11215.1.10~2";
    // Expand board → SoC map (keep in sync with catalog HWModelStr)
    NSDictionary *boardMap2 = @{
        @"D79AP": @"T8122", @"D80AP": @"T8122", // 15 / 15 Pro-class samples
        @"D83AP": @"T8130", @"D84AP": @"T8130",
    };
    if (boardMap2[b]) arm = boardMap2[b];
    else if ([b hasPrefix:@"D7"] || [b hasPrefix:@"D8"]) {
        if ([b hasPrefix:@"D83"] || [b hasPrefix:@"D84"]) arm = @"T8130";
        else if ([b hasPrefix:@"D79"] || [b hasPrefix:@"D80"]) arm = @"T8122";
    }
    NSString *ver = [NSString stringWithFormat:
                     @"Darwin Kernel Version %@: %@: root:xnu-%@/RELEASE_ARM64_%@",
                     rel, stamp, xnu, arm];
    return @{
        @"kern.osrelease": rel,
        @"kern.version": ver,
        @"kern.ostype": @"Darwin",
        @"kern.osproductversion": iv,
        @"kern.osversion": @"", // filled by caller with BuildVersion if known
        @"uname.sysname": @"Darwin",
    };
}

+ (NSInteger)ipfMajorFromVersion:(NSString *)v {
    if (!v.length) return 0;
    return [[v componentsSeparatedByString:@"."].firstObject integerValue];
}

/// Lab rule: spoof iOS never > host; never major-gap ≥ 2 below host (forces host iOS).
+ (NSString *)clampSpoofIOSToHost:(NSString *)spoofIOS {
    NSString *host = [self hostSystemVersion];
    if (!spoofIOS.length) return host.length ? host : @"15.0";
    if (!host.length) return spoofIOS;
    if ([self compareVersion:spoofIOS toVersion:host] == NSOrderedDescending)
        return host;
    NSInteger sm = [self ipfMajorFromVersion:spoofIOS];
    NSInteger hm = [self ipfMajorFromVersion:host];
    if (hm > 0 && sm > 0 && (hm - sm) >= 2)
        return host; // e.g. spoof 12.x on host 15.x → clamp 15.x (WebKit/UA sync)
    return spoofIOS;
}

+ (NSString *)radioAccessTechnologyForDevice:(NSDictionary *)device {
    NSInteger year = [device[@"year"] integerValue];
    NSString *pt = [device[@"ProductType"] description] ?: @"";
    int gen = 0;
    sscanf(pt.UTF8String ?: "", "iPhone%d", &gen);
    // 5G: iPhone 12+ (ProductType iPhone13,* …) or year ≥ 2020
    if (year >= 2020 || gen >= 13)
        return @"CTRadioAccessTechnologyNR";
    // LTE era iPhone 6s–11 class
    if (year >= 2016 || gen >= 8)
        return @"CTRadioAccessTechnologyLTE";
    return @"CTRadioAccessTechnologyWCDMA";
}

+ (NSString *)labHonestClaimFooter {
    return @"Lab «Thật nhất»: Full model OK · iOS ≤ host & gần host · radio/màn/UA/Darwin sync.\n"
           @"KHÔNG claim: server risk VNG · silicon SE/GPU die · App Attest token thật.";
}

+ (NSInteger)productTypeGeneration:(NSString *)productType {
    if (!productType.length) return 0;
    int gen = 0;
    // iPhone11,6 / iPhone8,1 → 11 / 8
    if (sscanf(productType.UTF8String ?: "", "iPhone%d", &gen) == 1) return gen;
    return 0;
}

+ (NSInteger)labRealismScoreForProductType:(NSString *)productType ios:(NSString *)ios {
    // Higher = safer on this host (API/OS/silicon class closer). Full catalog still allowed.
    NSString *hostIOS = [self hostSystemVersion] ?: @"15.0";
    NSString *hostPT = [self hostProductType] ?: @"";
    NSInteger score = 100;
    NSString *useIOS = ios.length ? [self clampSpoofIOSToHost:ios] : hostIOS;
    NSInteger hm = [self ipfMajorFromVersion:hostIOS];
    NSInteger sm = [self ipfMajorFromVersion:useIOS];
    if (hm > 0 && sm > 0) {
        score -= labs(hm - sm) * 18; // major iOS gap hurts WebKit story
        // minor: prefer closer to host string
        if ([self compareVersion:useIOS toVersion:hostIOS] == NSOrderedAscending)
            score -= 3;
    }
    NSInteger hg = [self productTypeGeneration:hostPT];
    NSInteger sg = [self productTypeGeneration:productType];
    if (hg > 0 && sg > 0) {
        NSInteger gap = labs(hg - sg);
        // Soft: model far from host still OK but lower weight (Full catalog)
        score -= (NSInteger)MIN(gap * 8, 48);
        // Spoof much newer than host silicon = riskier than slightly older
        if (sg > hg) score -= (sg - hg) * 4;
    } else if (productType.length && hostPT.length && ![productType isEqualToString:hostPT]) {
        score -= 15;
    }
    if (score < 1) score = 1;
    if (score > 100) score = 100;
    return score;
}

+ (NSString *)labMismatchWarningForSpoofIOS:(NSString *)spoofIOS productType:(NSString *)productType {
    NSMutableArray *w = [NSMutableArray array];
    NSString *hostIOS = [self hostSystemVersion];
    NSString *hostPT = [self hostProductType];
    NSString *aligned = spoofIOS.length ? [self clampSpoofIOSToHost:spoofIOS] : spoofIOS;
    if (spoofIOS.length && aligned.length && ![aligned isEqualToString:spoofIOS]) {
        [w addObject:[NSString stringWithFormat:
                      @"✓ Đã kẹp iOS %@ → %@ (khớp host, chống lệch WebKit/UA)",
                      spoofIOS, aligned]];
    }
    if (aligned.length && hostIOS.length) {
        NSComparisonResult c = [self compareVersion:aligned toVersion:hostIOS];
        if (c == NSOrderedDescending) {
            [w addObject:[NSString stringWithFormat:
                          @"⚠ Spoof iOS %@ > host iOS %@", aligned, hostIOS]];
        } else if (c == NSOrderedAscending) {
            NSInteger sm = [self ipfMajorFromVersion:aligned];
            NSInteger hm = [self ipfMajorFromVersion:hostIOS];
            if (hm - sm >= 1) {
                [w addObject:[NSString stringWithFormat:
                              @"⚠ Spoof iOS %@ < host %@ — đã cố đồng bộ major",
                              aligned, hostIOS]];
            }
        }
    }
    if (productType.length && hostPT.length && ![productType isEqualToString:hostPT]) {
        [w addObject:[NSString stringWithFormat:
                      @"⚠ Spoof model %@ ≠ host %@ — silicon IMU/GPU die vẫn host",
                      productType, hostPT]];
        int spoofGen = 0, hostGen = 0;
        sscanf(productType.UTF8String ?: "", "iPhone%d", &spoofGen);
        sscanf(hostPT.UTF8String ?: "", "iPhone%d", &hostGen);
        if (spoofGen > 0 && hostGen > 0) {
            int gap = abs(spoofGen - hostGen);
            if (gap >= 3) {
                [w addObject:[NSString stringWithFormat:
                              @"⚠ Gen gap iPhone%d vs host iPhone%d — Full model OK nhưng silicon lệch",
                              spoofGen, hostGen]];
            }
        }
    }
    [w addObject:[self labHonestClaimFooter]];
    return [w componentsJoinedByString:@"\n"];
}

// Apple-like synthetic identity (match scripts/select_device_profile.py):
// Serial: no I/O/0/1; pre-2021=12, modern~10; IDFA/IDFV UUID v4; UDID 40 hex; IMEI 8-digit TAC+Luhn

#pragma mark - Schema lock (Apply không ghi key lạ)

+ (NSSet<NSString *> *)knownConfigKeySet {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Keep in sync with select_device_profile.py KNOWN_CONFIG_KEYS + IPFConfig mgKeys + Extra/proxy/geo
        s = [NSSet setWithArray:@[
            // Identity / MG
            @"ProductType", @"HWModelStr", @"HardwareModel", @"DeviceName", @"UserAssignedDeviceName",
            @"MarketingName", @"SerialNumber", @"UniqueDeviceID", @"UniqueChipID",
            @"ProductVersion", @"BuildVersion", @"ProductBuildVersion",
            @"ModelNumber", @"PartNumber", @"RegionInfo", @"RegionCode", @"RegulatoryModelNumber",
            @"ModelNumberAxxxx", @"PartNumberRegion",
            @"CPUArchitecture", @"HardwarePlatform", @"DeviceClass", @"ChipName",
            @"MetalDeviceName", @"GPUName", @"MetalRegistryID", @"DeviceSupportsMetal",
            @"DeviceCatalogId", @"DeviceYear", @"BatteryMah",
            @"InternationalMobileEquipmentIdentity", @"InternationalMobileEquipmentIdentity2",
            @"MobileEquipmentIdentifier", @"EID",
            @"WifiAddress", @"BluetoothAddress", @"EthernetMacAddress",
            @"BSSID", @"SSID", @"VolumeUUID",
            @"IOPlatformSerialNumber", @"MLBSerialNumber",
            @"Hostname", @"kern.hostname",
            @"DeviceColor", @"DeviceEnclosureColor", @"BasebandVersion",
            @"IDFA", @"IDFV", @"identifierForVendor", @"advertisingIdentifier",
            @"serial-number", @"Serial",
            // Screen
            @"main-screen-width", @"main-screen-height", @"main-screen-scale", @"main-screen-pitch",
            @"LogicalScreenWidth", @"LogicalScreenHeight", @"ScreenDiagonalInches", @"MaxRefreshHz",
            // Memory / CPU / disk
            @"PhysicalMemoryMB", @"PhysicalMemoryBytes", @"hw.memsize",
            @"hw.ncpu", @"hw.physicalcpu", @"hw.logicalcpu",
            @"DiskCapacityGB", @"TotalDiskCapacity", @"FreeDiskSpace",
            // Boot / time / Darwin kernel
            @"BootTimeUnix", @"kern.boottime", @"TimeOffsetSeconds", @"TimeZoneName",
            @"kern.osrelease", @"kern.version", @"kern.osversion", @"kern.osproductversion",
            @"kern.ostype", @"uname.sysname",
            @"BatteryLevel", @"BatteryState", @"ThermalState",
            // Locale
            @"PreferredLanguage", @"LocaleIdentifier", @"AppleLocale", @"AppleLanguages",
            @"LanguageCode", @"CountryCode", @"CurrencyCode", @"CalendarIdentifier",
            @"ISOCountryCode",
            // Location
            @"Latitude", @"Longitude", @"LocationAccuracy", @"Altitude",
            // Network / UA / WebRTC
            @"UserAgent", @"HTTPUserAgent", @"WebRTCLocalIP",
            // Telephony
            @"carrierName", @"carrierMCC", @"carrierMNC", @"carrierISO", @"carrierRadioAccess",
            @"CarrierName", @"MobileCountryCode", @"MobileNetworkCode",
            @"CurrentRadioAccessTechnology", @"RadioAccessTechnology", @"AllowsVOIP",
            // Flags (Fake*)
            @"Enabled", @"FakeDevice", @"FakeHardware", @"FakeAds", @"FakeScreen", @"FakeRealScreen",
            @"FakeBrowser", @"FakeNetwork", @"FakeWifi", @"FakeSysctl", @"FakeSysOSVersion",
            @"HideJailbreak", @"FakeLocale", @"FakeDateTime", @"FakeLocation", @"FakeSensor",
            @"SpoofSettingsAbout",
            @"FakeWebRTC", @"DisableWebRTC", @"FakeProxy", @"DisableAppAttest",
            // Proxy / AppAttest / geo meta
            @"EnableProxy", @"ProxyHost", @"ProxyPort", @"ProxyType",
            @"ProxyUsername", @"ProxyPassword",
            @"WebRTCLocalIP",
            @"SyncGeoFromProxy", @"ProxyEgressIP", @"ProxyGeoCity", @"ProxyGeoCountry",
            @"ProxyGeoISP", @"ProxyGeoRegion", @"GeoSyncedAtUnix",
            @"ProxyGeoBox", @"ProxyGeoCenterLat", @"ProxyGeoCenterLon", @"GeoRandomInCity",
            // Nested blobs allowed as-is
            @"jailbreakHide", @"jailbreak_hide",
        ]];
    });
    return s;
}

+ (NSDictionary *)schemaLockedFlat:(NSDictionary *)flat dropped:(NSUInteger *)droppedOut {
    if (![flat isKindOfClass:[NSDictionary class]] || !flat.count) {
        if (droppedOut) *droppedOut = 0;
        return @{};
    }
    NSSet *known = [self knownConfigKeySet];
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:flat.count];
    __block NSUInteger drop = 0;
    [flat enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *k = [key description];
        if (!k.length) { drop++; return; }
        // Allow Fake* / Enable* toggles dynamically
        if ([known containsObject:k]
            || [k hasPrefix:@"Fake"]
            || [k hasPrefix:@"Enable"]
            || [k hasPrefix:@"Disable"]
            || [k hasPrefix:@"Hide"]
            || [k hasPrefix:@"Proxy"]
            || [k hasPrefix:@"carrier"]
            || [k hasPrefix:@"hw."]
            || [k hasPrefix:@"kern."]) {
            out[k] = obj;
        } else {
            drop++;
        }
    }];
    if (droppedOut) *droppedOut = drop;
    return [out copy];
}

+ (NSString *)randomSerialForYear:(NSInteger)year {
    static NSString *alpha = @"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I,O,0,1
    static NSArray *plants = @[ @"C", @"F", @"D", @"G", @"H", @"M", @"P", @"R", @"S", @"W",
                                 @"CK", @"F7", @"DN", @"F2", @"G6", @"FK", @"YM", @"C3" ];
    NSString *plant = plants[arc4random_uniform((u_int32_t)plants.count)];
    int len;
    if (year > 0 && year < 2021) {
        len = 12;
    } else {
        // Cluster at 10 (modern randomised style)
        u_int32_t r = arc4random_uniform(100);
        len = (r < 70) ? 10 : (r < 85 ? 11 : 12);
    }
    NSMutableString *s = [NSMutableString stringWithString:plant];
    while ((int)s.length < len) {
        u_int32_t ri = arc4random_uniform((u_int32_t)alpha.length);
        [s appendFormat:@"%C", [alpha characterAtIndex:ri]];
    }
    if (s.length > (NSUInteger)len) [s deleteCharactersInRange:NSMakeRange(len, s.length - len)];
    if (s.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[s characterAtIndex:0]]) {
        [s replaceCharactersInRange:NSMakeRange(0, 1) withString:@"C"];
    }
    return s;
}

+ (NSDictionary *)randomPartNumberFromDevice:(NSDictionary *)device {
    // Part Number: MU783KH/A style — Settings "Số máy" default
    static NSString *alpha = @"ABCDEFGHJKLMNPQRSTUVWXYZ0123456789";
    static NSArray *regions = @[ @"LL", @"J", @"CH", @"KH", @"ZA", @"ZP", @"B", @"D", @"F", @"T", @"X", @"Y", @"C", @"HN", @"PP", @"TH", @"TU", @"RU" ];
    static NSArray *pfx = @[ @"M", @"N", @"F", @"P" ];
    NSString *prefix = pfx[arc4random_uniform((u_int32_t)pfx.count)];
    NSMutableString *body = [NSMutableString string];
    int blen = (arc4random_uniform(4) == 0) ? 5 : 4;
    for (int i = 0; i < blen; i++)
        [body appendFormat:@"%C", [alpha characterAtIndex:arc4random_uniform((u_int32_t)alpha.length)]];
    NSString *region = regions[arc4random_uniform((u_int32_t)regions.count)];
    NSString *part = [NSString stringWithFormat:@"%@%@%@/A", prefix, body, region];
    return @{ @"part": part, @"region": region };
}

+ (NSString *)randomAxxxxFromDevice:(NSDictionary *)device {
    // Axxxx — Settings after tap; random from modelNumbers when available
    NSArray *nums = device[@"modelNumbers"];
    if ([nums isKindOfClass:[NSArray class]] && nums.count) {
        NSMutableArray *ax = [NSMutableArray array];
        for (id n in nums) {
            NSString *s = [n description].uppercaseString;
            if (s.length == 5 && [s hasPrefix:@"A"]) [ax addObject:s];
        }
        if (ax.count) return ax[arc4random_uniform((u_int32_t)ax.count)];
    }
    NSString *reg = device[@"RegulatoryModelNumber"] ?: device[@"ModelNumber"] ?: @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"A\\d{4}" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:reg.uppercaseString ?: @"" options:0 range:NSMakeRange(0, reg.length)];
    if (m) return [reg.uppercaseString substringWithRange:m.range];
    return @"A0000";
}

+ (NSString *)randomEID {
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 32; i++) [s appendFormat:@"%u", arc4random_uniform(10)];
    return s;
}

+ (NSString *)randomMAC {
    // Prefer public Apple OUI + random NIC (looks more factory-like than pure random)
    static NSArray *ouis = @[
        @"F0:18:98", @"A4:83:E7", @"3C:22:FB", @"DC:A9:04", @"AC:DE:48",
        @"F4:5C:89", @"28:CF:E9", @"D0:03:4B", @"BC:52:B7", @"6C:96:CF",
    ];
    if (arc4random_uniform(100) < 85) {
        NSString *oui = ouis[arc4random_uniform((u_int32_t)ouis.count)];
        return [NSString stringWithFormat:@"%@:%02X:%02X:%02X",
                oui, arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)];
    }
    u_int32_t b0 = (arc4random_uniform(256) | 0x02) & 0xFE;
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
            b0, arc4random_uniform(256), arc4random_uniform(256),
            arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)];
}

+ (NSString *)luhnCheckDigitFor14:(NSString *)digits14 {
    NSInteger total = 0;
    for (NSUInteger i = 0; i < digits14.length && i < 14; i++) {
        NSInteger n = [digits14 characterAtIndex:i] - '0';
        if (i % 2 == 1) {
            n *= 2;
            if (n > 9) n -= 9;
        }
        total += n;
    }
    return [NSString stringWithFormat:@"%ld", (long)((10 - (total % 10)) % 10)];
}

+ (NSString *)randomIMEI {
    // 15-digit IMEI: 8-digit TAC (Apple-range style) + 6 SNR + Luhn
    static NSArray *tacs = @[
        @"35328510", @"35325809", @"35672011", @"35299109", @"35334709",
        @"35445107", @"35569508", @"35397710", @"35925406", @"35407115",
    ];
    NSString *tac = tacs[arc4random_uniform((u_int32_t)tacs.count)];
    NSMutableString *body = [NSMutableString stringWithString:tac];
    for (int i = 0; i < 6; i++)
        [body appendFormat:@"%u", arc4random_uniform(10)];
    return [body stringByAppendingString:[self luhnCheckDigitFor14:body]];
}

+ (NSString *)uuidUpper {
    // IDFA / IDFV — RFC 4122 UUID v4, uppercase with hyphens (NSUUID)
    return [[[NSUUID UUID] UUIDString] uppercaseString];
}

+ (NSString *)randomUDID {
    // UniqueDeviceID — 40 hex via SHA-1 of random (legacy UDID length)
    uint8_t rnd[32];
    arc4random_buf(rnd, sizeof(rnd));
    // Simple FNV-ish expand to 40 hex without CommonCrypto dependency:
    // two UUID digests concatenated (same length as SHA-1 hex)
    NSString *a = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *b = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *c = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    // Mix rnd into first chars for entropy beyond pure UUID concat
    NSMutableString *out = [NSMutableString stringWithCapacity:40];
    NSString *src = [[a stringByAppendingString:b] stringByAppendingString:c];
    for (int i = 0; i < 40; i++) {
        unichar ch = [src characterAtIndex:i % src.length];
        unsigned v = (unsigned)ch ^ rnd[i % 32];
        [out appendFormat:@"%X", v & 0xF];
    }
    return out;
}

+ (NSString *)randomECIDHex {
    uint64_t hi = ((uint64_t)arc4random() << 32) | arc4random();
    if (hi < 0x1000000000ULL) hi |= 0xA000000000ULL;
    return [NSString stringWithFormat:@"%016llX", hi];
}

+ (NSString *)randomECIDecimalFromHex:(NSString *)hex {
    // Parse hex as 64-bit for ECID decimal twin
    unsigned long long v = strtoull(hex.UTF8String, NULL, 16);
    return [NSString stringWithFormat:@"%llu", v];
}

+ (NSDictionary *)flatProfileForDevice:(NSDictionary *)device
                                   ios:(NSString *)iosVer
                               iosMeta:(NSDictionary *)iosMeta
                            deviceName:(NSString *)name {
    NSDictionary *disp = device[@"display"] ?: @{};
    NSInteger ramMB = [device[@"PhysicalMemoryMB"] integerValue] ?: 4096;
    long long ramBytes = (long long)ramMB * 1024LL * 1024LL;
    NSString *wifi = [self randomMAC];
    NSArray *wp = [wifi componentsSeparatedByString:@":"];
    NSMutableArray *btp = [wp mutableCopy];
    if (btp.count == 6) {
        unsigned v = 0;
        [[NSScanner scannerWithString:btp[5]] scanHexInt:&v];
        btp[5] = [NSString stringWithFormat:@"%02X", (v ^ 1) & 0xFF];
    }
    NSString *bt = [btp componentsJoinedByString:@":"];
    NSString *idfv = [self uuidUpper];
    NSString *idfa = [self uuidUpper];
    while ([idfa isEqualToString:idfv]) idfa = [self uuidUpper];
    NSString *udid = [self randomUDID];
    NSString *ecidHex = [self randomECIDHex];
    NSString *ecidDec = [self randomECIDecimalFromHex:ecidHex];
    NSInteger year = [device[@"year"] integerValue];
    NSString *serial = [self randomSerialForYear:year];
    NSDictionary *partInfo = [self randomPartNumberFromDevice:device];
    NSString *partNumber = partInfo[@"part"]; // Settings default MU783KH/A
    NSString *axxxx = [self randomAxxxxFromDevice:device]; // tap → Axxxx
    NSString *imei = [self randomIMEI];
    NSString *imei2 = [self randomIMEI];
    while ([imei2 isEqualToString:imei]) imei2 = [self randomIMEI];
    NSString *meid = [imei substringToIndex:MIN((NSUInteger)14, imei.length)];
    NSString *eid = [self randomEID];
    NSString *devName = name.length ? name : [NSString stringWithFormat:@"iPhone Lab %@", device[@"id"] ?: @"dev"];
    // Hostname ≡ gethostname / uname.nodename / NSProcessInfo (DNS-label safe)
    NSMutableString *hostBuf = [NSMutableString string];
    for (NSUInteger i = 0; i < devName.length && hostBuf.length < 63; i++) {
        unichar c = [devName characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
            [hostBuf appendFormat:@"%C", c];
        else if ((c == ' ' || c == '_' || c == '.') && hostBuf.length
                 && [hostBuf characterAtIndex:hostBuf.length - 1] != '-')
            [hostBuf appendString:@"-"];
    }
    while (hostBuf.length && [hostBuf characterAtIndex:0] == '-')
        [hostBuf deleteCharactersInRange:NSMakeRange(0, 1)];
    while (hostBuf.length && [hostBuf characterAtIndex:hostBuf.length - 1] == '-')
        [hostBuf deleteCharactersInRange:NSMakeRange(hostBuf.length - 1, 1)];
    NSString *hostName = hostBuf.length ? [hostBuf copy] : @"iPhone";
    NSString *regLetters = partInfo[@"region"] ?: @"ZA";
    NSString *regionCode = @{ @"LL":@"US", @"J":@"JP", @"CH":@"CN", @"KH":@"KR", @"ZA":@"SG", @"ZP":@"HK",
                              @"B":@"GB", @"D":@"DE", @"F":@"FR", @"T":@"IT", @"X":@"AU", @"C":@"CA" }[regLetters] ?: @"VN";

    // Display — 100% from catalog row (any device), never hardcode one model
    NSInteger w = [disp[@"NativeWidth"] integerValue];
    NSInteger h = [disp[@"NativeHeight"] integerValue];
    NSInteger scale = [disp[@"ScreenScale"] integerValue];
    if (scale < 1) scale = 2;
    if (w < 1) w = [disp[@"LogicalWidth"] integerValue] * scale;
    if (h < 1) h = [disp[@"LogicalHeight"] integerValue] * scale;
    NSInteger logicalW = [disp[@"LogicalWidth"] integerValue];
    NSInteger logicalH = [disp[@"LogicalHeight"] integerValue];
    if (logicalW < 1 && scale > 0) logicalW = w / scale;
    if (logicalH < 1 && scale > 0) logicalH = h / scale;
    NSInteger pitch = [disp[@"Pitch"] integerValue] ?: 460;
    NSInteger maxHz = [disp[@"MaxRefreshHz"] integerValue];
    if (maxHz < 1) maxHz = 60;
    NSInteger cores = [device[@"cpuCores"] integerValue] ?: 6;

    // Storage tier from catalog storageOptionsGB (or storageGB); free 35–55%
    NSInteger storageGB = 0;
    id opts = device[@"storageOptionsGB"];
    if ([opts isKindOfClass:[NSArray class]] && [(NSArray *)opts count] > 0) {
        NSArray *arr = (NSArray *)opts;
        storageGB = [arr[arc4random_uniform((u_int32_t)arr.count)] integerValue];
    }
    if (storageGB <= 0) storageGB = [device[@"storageGB"] integerValue];
    if (storageGB <= 0) storageGB = 128;
    long long totalDisk = (long long)storageGB * 1000LL * 1000LL * 1000LL; // decimal GB
    long long freeDisk = (long long)(totalDisk * (0.35 + (arc4random_uniform(200) / 1000.0)));

    // Boot time: now − [3d … 21d] (kern.boottime timeval.tv_sec, Unix epoch)
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    long long bootAgo = 3LL * 86400 + (long long)arc4random_uniform(18 * 86400);
    long long bootUnix = now - bootAgo;

    // Locale — BCP 47 / Unicode CLDR (preferredLanguages: vi-VN)
    // AppleLocale / NSLocale: underscore vi_VN
    // Language ISO 639-1, region ISO 3166-1 alpha-2, currency ISO 4217, TZ IANA
    NSString *localeBCP = @"vi-VN";
    NSString *localeApple = @"vi_VN";
    NSString *langISO = @"vi";
    NSString *countryISO = @"VN";
    NSString *currency = @"VND";
    NSString *tzIANA = @"Asia/Ho_Chi_Minh"; // IANA TZDB; VN UTC+7 no DST
    NSString *calendar = @"gregorian";

    // WGS84 (EPSG:4326) — HCMC approx city center
    double lat = 10.8231;
    double lon = 106.6297;
    double locAcc = 8.0 + (arc4random_uniform(70) / 10.0); // 8–15 m
    double alt = 5.0 + (arc4random_uniform(30));

    // Safari/WebKit UA (Apple documented form for Mobile Safari)
    // https://developer.apple.com — CFNetwork / WebKit UA pattern
    NSString *pv = iosMeta[@"ProductVersion"] ?: iosVer ?: @"18.0";
    NSArray *parts = [pv componentsSeparatedByString:@"."];
    NSString *maj = parts.count > 0 ? parts[0] : @"18";
    NSString *min = parts.count > 1 ? parts[1] : @"0";
    NSString *uaOS = [NSString stringWithFormat:@"%@_%@", maj, min];
    NSString *ua = [NSString stringWithFormat:
        @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
        @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%@.%@ "
        @"Mobile/15E148 Safari/604.1",
        uaOS, maj, min];

    // WebRTC: RFC1918 private IPv4 (not a public IP leak)
    NSString *webrtcIP = [NSString stringWithFormat:@"10.%u.%u.%u",
                          1 + arc4random_uniform(254),
                          arc4random_uniform(256),
                          2 + arc4random_uniform(250)];

    // Battery level seed (sync UIDevice.batteryLevel hook)
    uint32_t batH = 2166136261u;
    const char *batS = serial.UTF8String ?: "x";
    for (const unsigned char *p = (const unsigned char *)batS; *p; p++) {
        batH ^= *p;
        batH *= 16777619u;
    }
    double batLvl = 0.35 + ((batH & 0xFF) / 255.0) * 0.57;

    // Wi‑Fi SSID/BSSID — BSSID must equal WifiAddress (CNCopyCurrentNetworkInfo sync)
    NSArray *ssids = @[ @"Viettel-WiFi", @"Viettel", @"VNPT-Fiber", @"FPT-Telecom", @"MyWiFi" ];
    NSString *ssid = ssids[arc4random_uniform((u_int32_t)ssids.count)];
    NSString *bssid = wifi;
    NSString *volumeUUID = [self uuidUpper];

    NSMutableDictionary *m = [@{
        @"Enabled": @YES,
        @"FakeDevice": @YES,
        @"FakeScreen": @YES,
        @"FakeRealScreen": @YES,
        @"FakeHardware": @YES,
        @"FakeAds": @YES,
        @"FakeWifi": @YES,
        @"FakeNetwork": @YES,
        @"FakeSysctl": @YES,
        @"FakeSysOSVersion": @YES,
        @"HideJailbreak": @YES,
        @"FakeBrowser": @YES,
        @"FakeLocale": @YES,
        @"FakeLocation": @YES,
        @"FakeSensor": @YES,
        @"FakeWebRTC": @YES,
        @"DisableWebRTC": @NO,
        // Class A — always from selected catalog device (any model, not one fixed SKU)
        @"ProductType": device[@"ProductType"] ?: @"",
        @"MarketingName": device[@"MarketingName"] ?: @"iPhone",
        @"DeviceName": @"iPhone",
        @"UserAssignedDeviceName": devName,
        @"Hostname": hostName,
        @"kern.hostname": hostName,
        @"HWModelStr": device[@"HWModelStr"] ?: @"",
        @"HardwareModel": device[@"HWModelStr"] ?: @"",
        // BOTH: Settings default Part Number + Axxxx after tap
        @"ModelNumber": partNumber,
        @"PartNumber": partNumber,
        @"RegulatoryModelNumber": axxxx,
        @"ModelNumberAxxxx": axxxx,
        @"PartNumberRegion": regLetters,
        @"RegionInfo": [NSString stringWithFormat:@"%@/A", regionCode],
        @"RegionCode": regionCode,
        @"HardwarePlatform": device[@"HardwarePlatform"] ?: @"",
        @"CPUArchitecture": device[@"CPUArchitecture"] ?: @"arm64e",
        @"DeviceClass": @"iPhone",
        @"SerialNumber": serial,
        @"UniqueDeviceID": udid,
        @"UniqueChipID": ecidHex,
        @"ECID": ecidDec,
        @"ChipID": ecidDec,
        @"serial-number": serial,
        @"unique-device-id": udid,
        @"DeviceUniqueIdentifier": udid,
        @"AdvertisingIdentifier": idfa,
        // also set plain keys used by MG maps (see below IDFA/IDFV)
        @"ProductVersion": iosMeta[@"ProductVersion"] ?: iosVer,
        @"BuildVersion": iosMeta[@"BuildVersion"] ?: @"",
        @"ProductBuildVersion": iosMeta[@"BuildVersion"] ?: @"",
        // Darwin (iOS N.M → (N+6).M.0) filled after dict build — see below
        // UUID v4 uppercase (Apple IDFA / IDFV)
        @"IDFA": idfa,
        @"IDFV": idfv,
        @"identifierForVendor": idfv,
        @"advertisingIdentifier": idfa,
        // IMEI Luhn 15-digit / MEID / EID 32-digit
        @"InternationalMobileEquipmentIdentity": imei,
        @"InternationalMobileEquipmentIdentity2": imei2,
        @"MobileEquipmentIdentifier": meid,
        @"EID": eid,
        // IEEE 802 EUI-48 MAC
        @"WifiAddress": wifi,
        @"BluetoothAddress": bt,
        @"EthernetMacAddress": wifi,
        @"BSSID": bssid,
        @"SSID": ssid,
        @"VolumeUUID": volumeUUID,
        @"IOPlatformSerialNumber": serial,
        @"MLBSerialNumber": serial,
        // ITU-T E.212 MCC/MNC — Viettel 452/04; ISO 3166-1 alpha-2
        @"carrierName": @"Viettel",
        @"carrierMCC": @"452",
        @"carrierMNC": @"04",
        @"carrierISO": @"vn",
        @"carrierRadioAccess": [self radioAccessTechnologyForDevice:device],
        @"CarrierName": @"Viettel",
        @"MobileCountryCode": @"452",
        @"MobileNetworkCode": @"04",
        @"ISOCountryCode": @"vn",
        @"RadioAccessTechnology": [self radioAccessTechnologyForDevice:device],
        @"CurrentRadioAccessTechnology": [self radioAccessTechnologyForDevice:device],
        @"AllowsVOIP": @YES,
        // Display (catalog native + logical + scale) — UIScreen / WK JS / MG same source
        @"main-screen-width": @(w),
        @"main-screen-height": @(h),
        @"main-screen-scale": @(scale),
        @"main-screen-pitch": @(pitch),
        @"LogicalScreenWidth": @(logicalW),
        @"LogicalScreenHeight": @(logicalH),
        @"ScreenDiagonalInches": [NSString stringWithFormat:@"%@", disp[@"DiagonalInches"] ?: @""],
        @"PhysicalMemoryMB": @(ramMB),
        @"PhysicalMemoryBytes": @(ramBytes),
        @"hw.memsize": @(ramBytes),
        @"hw.ncpu": @(cores),
        @"hw.physicalcpu": @(cores),
        @"hw.logicalcpu": @(cores),
        @"ChipName": device[@"chip"] ?: @"",
        // GPU/Metal identity (name + synthetic registryID synced to serial — not host die)
        @"MetalDeviceName": [self metalDeviceNameFromChip:device[@"chip"]],
        @"GPUName": [self metalDeviceNameFromChip:device[@"chip"]],
        @"MetalRegistryID": [self metalRegistryIDForSerial:serial],
        @"DeviceSupportsMetal": @YES,
        @"DeviceCatalogId": device[@"id"] ?: @"",
        @"MaxRefreshHz": @(maxHz),
        @"DeviceYear": device[@"year"] ?: @0,
        @"BatteryMah": device[@"batteryMah"] ?: @0,
        @"BatteryLevel": @(batLvl),
        @"BatteryState": @1,
        @"ThermalState": @0,
        // Disk bytes (tier from catalog storageOptionsGB)
        @"DiskCapacityGB": @(storageGB),
        @"TotalDiskCapacity": @(totalDisk),
        @"FreeDiskSpace": @(freeDisk),
        // Locale / TZ (BCP-47, ISO, IANA)
        @"PreferredLanguage": localeBCP,
        @"LocaleIdentifier": localeApple,
        @"AppleLocale": localeApple,
        @"AppleLanguages": @[ localeBCP ],
        @"LanguageCode": langISO,
        @"CountryCode": countryISO,
        @"CurrencyCode": currency,
        @"TimeZoneName": tzIANA,
        @"CalendarIdentifier": calendar,
        // Location WGS84
        @"Latitude": @(lat),
        @"Longitude": @(lon),
        @"LocationAccuracy": @(locAcc),
        @"Altitude": @(alt),
        // Boot / time
        @"BootTimeUnix": @(bootUnix),
        @"kern.boottime": @(bootUnix),
        @"TimeOffsetSeconds": @0,
        // Browser UA + WebRTC private IP (lab: avoid leaking public IP via ICE)
        @"UserAgent": ua,
        @"HTTPUserAgent": ua,
        @"WebRTCLocalIP": webrtcIP.length ? webrtcIP : @"10.0.0.2",
        // FakeWebRTC / DisableWebRTC / FakeSensor / HideJailbreak / FakeWifi set above once
        @"DisableAppAttest": @YES,
    } mutableCopy];
    // Darwin kernel map (realistic release + version stamp; not host uname)
    NSString *iv = iosMeta[@"ProductVersion"] ?: iosVer ?: @"15.0";
    NSDictionary *dk = [self darwinKernelKeysForIOS:iv board:device[@"HWModelStr"]];
    if (dk[@"kern.osrelease"]) m[@"kern.osrelease"] = dk[@"kern.osrelease"];
    if (dk[@"kern.version"]) m[@"kern.version"] = dk[@"kern.version"];
    if (dk[@"kern.ostype"]) m[@"kern.ostype"] = dk[@"kern.ostype"];
    if (dk[@"uname.sysname"]) m[@"uname.sysname"] = dk[@"uname.sysname"];
    if (m[@"BuildVersion"]) m[@"kern.osversion"] = m[@"BuildVersion"];
    if (iv.length) m[@"kern.osproductversion"] = iv;
    return m;
}

+ (BOOL)ensureDir:(NSString *)dir error:(NSError **)err {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
        // Best-effort: make mobile-writable (needed for /var/jb/etc/ipfaker after root-owned install)
        [fm setAttributes:@{ NSFilePosixPermissions: @0775 } ofItemAtPath:dir error:nil];
        return YES;
    }
    NSDictionary *attrs = @{
        NSFilePosixPermissions: @0775,
        NSFileOwnerAccountName: @"mobile",
    };
    return [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:attrs error:err];
}

+ (BOOL)writePlist:(NSDictionary *)flat toPath:(NSString *)path error:(NSError **)err {
    NSFileManager *fm = [NSFileManager defaultManager];
    // Schema lock — never write unknown keys into config.plist
    NSUInteger dropped = 0;
    NSDictionary *locked = [self schemaLockedFlat:flat dropped:&dropped];
    if (dropped > 0) {
        NSLog(@"[iPFaker] schema lock dropped %lu unknown key(s) before write %@",
              (unsigned long)dropped, path.lastPathComponent);
    }
    // Remove root-owned stale file if we cannot overwrite (best-effort)
    if ([fm fileExistsAtPath:path] && ![fm isWritableFileAtPath:path]) {
        [fm removeItemAtPath:path error:nil];
    }
    BOOL ok = [locked writeToURL:[NSURL fileURLWithPath:path] error:err];
    if (ok) {
        [fm setAttributes:@{ NSFilePosixPermissions: @0644 } ofItemAtPath:path error:nil];
    }
    return ok;
}

+ (NSString *)applyFlatProfile:(NSDictionary *)flat deviceId:(NSString *)deviceId ios:(NSString *)ios {
    NSError *err = nil;
    // CRITICAL: Zalo sandbox typically CANNOT read /var/mobile/Library/iPFaker —
    // only /var/jb/etc/ipfaker is visible to the injected dylib. Write jb FIRST.
    NSArray *dirs = @[
        @"/var/jb/etc/ipfaker",
        @"/var/mobile/Library/iPFaker",
    ];
    NSMutableArray *okPaths = [NSMutableArray array];
    NSMutableArray *failMsgs = [NSMutableArray array];

    // Schema lock + identity alias sync before any write
    NSUInteger dropped = 0;
    NSMutableDictionary *safeFlat = [[self schemaLockedFlat:flat dropped:&dropped] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    // Multi-source serial: IOKit / MLB / Serial always same value (lab identity sync)
    NSString *sn = [safeFlat[@"SerialNumber"] description];
    if (sn.length) {
        safeFlat[@"IOPlatformSerialNumber"] = sn;
        safeFlat[@"MLBSerialNumber"] = sn;
        safeFlat[@"serial-number"] = sn;
        safeFlat[@"Serial"] = sn;
    }
    // MAC path: BSSID / Ethernet ≡ WifiAddress
    NSString *wifi = [safeFlat[@"WifiAddress"] description];
    if (wifi.length) {
        safeFlat[@"EthernetMacAddress"] = wifi;
        if (![safeFlat[@"BSSID"] description].length) safeFlat[@"BSSID"] = wifi;
    }
    // Environment consistency pack — no field may drift from catalog identity
    {
        NSString *pv = [safeFlat[@"ProductVersion"] description] ?: ios ?: @"15.0";
        NSArray *parts = [pv componentsSeparatedByString:@"."];
        NSString *maj = parts.count ? parts[0] : @"15";
        NSString *min = parts.count > 1 ? parts[1] : @"0";
        NSString *osUnd = [pv stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        NSString *safariUA = [NSString stringWithFormat:
            @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
            @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%@.%@ "
            @"Mobile/15E148 Safari/604.1", osUnd, maj, min];
        safeFlat[@"HTTPUserAgent"] = safariUA;
        // Keep app UA if Zalo-style already set; else Safari
        NSString *ua = [safeFlat[@"UserAgent"] description];
        if (!ua.length || [ua.lowercaseString containsString:@"safari"])
            safeFlat[@"UserAgent"] = safariUA;
        NSString *chip = [safeFlat[@"ChipName"] description];
        if (chip.length) {
            safeFlat[@"MetalDeviceName"] = [self metalDeviceNameFromChip:chip];
            safeFlat[@"GPUName"] = safeFlat[@"MetalDeviceName"];
        }
        if (![[safeFlat[@"MetalRegistryID"] description] length] && sn.length)
            safeFlat[@"MetalRegistryID"] = [self metalRegistryIDForSerial:sn];
        if (!safeFlat[@"BatteryLevel"]) {
            uint32_t bh = 2166136261u;
            const char *bs = (sn ?: @"x").UTF8String;
            for (const unsigned char *p = (const unsigned char *)bs; *p; p++) { bh ^= *p; bh *= 16777619u; }
            safeFlat[@"BatteryLevel"] = @(0.35 + ((bh & 0xFF) / 255.0) * 0.57);
        }
        if (!safeFlat[@"BatteryState"]) safeFlat[@"BatteryState"] = @1;
        if (!safeFlat[@"ThermalState"]) safeFlat[@"ThermalState"] = @0;
        safeFlat[@"kern.ostype"] = @"Darwin";
        safeFlat[@"uname.sysname"] = @"Darwin";
        // Darwin map if missing
        if (![[safeFlat[@"kern.osrelease"] description] length]) {
            NSDictionary *dk = [self darwinKernelKeysForIOS:pv board:safeFlat[@"HWModelStr"]];
            [safeFlat addEntriesFromDictionary:dk];
        }
        if (safeFlat[@"BuildVersion"])
            safeFlat[@"kern.osversion"] = safeFlat[@"BuildVersion"];
        safeFlat[@"kern.osproductversion"] = pv;
        // Mitigation flags always on for lab wall
        for (NSString *fk in @[ @"FakeDevice", @"FakeHardware", @"FakeScreen", @"FakeBrowser",
                                 @"FakeSensor", @"FakeSysctl", @"FakeSysOSVersion", @"DisableAppAttest",
                                 @"FakeLocale", @"Enabled" ]) {
            if (!safeFlat[fk]) safeFlat[fk] = @YES;
        }
        safeFlat[@"DisableAppAttest"] = @YES;
        if (safeFlat[@"SpoofSettingsAbout"] == nil)
            safeFlat[@"SpoofSettingsAbout"] = @YES;
    }
    flat = [safeFlat copy];

    // active_profile schema mirrors select_device_profile.py (any device + iOS)
    NSDictionary *active = @{
        @"schema": @"ipfaker.active_profile/3",
        @"generated_from": @"iPFaker.app",
        @"device_id": deviceId ?: @"",
        @"ios": ios ?: @"",
        @"flat": flat ?: @{},
        @"model": @{
            @"ProductType": flat[@"ProductType"] ?: @"",
            @"MarketingName": flat[@"MarketingName"] ?: @"",
            @"HWModelStr": flat[@"HWModelStr"] ?: @"",
            @"HardwareModel": flat[@"HardwareModel"] ?: flat[@"HWModelStr"] ?: @"",
            @"ModelNumber": flat[@"ModelNumber"] ?: @"",
            @"PartNumber": flat[@"PartNumber"] ?: @"",
            @"RegulatoryModelNumber": flat[@"RegulatoryModelNumber"] ?: @"",
            @"HardwarePlatform": flat[@"HardwarePlatform"] ?: @"",
            @"CPUArchitecture": flat[@"CPUArchitecture"] ?: @"",
            @"PhysicalMemoryMB": flat[@"PhysicalMemoryMB"] ?: @0,
            @"ChipName": flat[@"ChipName"] ?: @"",
            @"DiskCapacityGB": flat[@"DiskCapacityGB"] ?: @0,
            @"UserAssignedDeviceName": flat[@"UserAssignedDeviceName"] ?: @"",
        },
        @"os": @{
            @"ProductVersion": flat[@"ProductVersion"] ?: @"",
            @"BuildVersion": flat[@"BuildVersion"] ?: @"",
        },
        @"display": @{
            @"NativeWidth": flat[@"main-screen-width"] ?: @0,
            @"NativeHeight": flat[@"main-screen-height"] ?: @0,
            @"ScreenScale": flat[@"main-screen-scale"] ?: @0,
            @"LogicalWidth": flat[@"LogicalScreenWidth"] ?: @0,
            @"LogicalHeight": flat[@"LogicalScreenHeight"] ?: @0,
            @"MaxRefreshHz": flat[@"MaxRefreshHz"] ?: @60,
            @"main-screen-pitch": flat[@"main-screen-pitch"] ?: @0,
            @"DiagonalInches": flat[@"ScreenDiagonalInches"] ?: @"",
        },
        @"storage": @{
            @"TotalDiskCapacity": flat[@"TotalDiskCapacity"] ?: @0,
            @"FreeDiskSpace": flat[@"FreeDiskSpace"] ?: @0,
            @"DiskCapacityGB": flat[@"DiskCapacityGB"] ?: @0,
        },
        @"webview": @{
            @"UserAgent": flat[@"UserAgent"] ?: @"",
            @"HTTPUserAgent": flat[@"HTTPUserAgent"] ?: @"",
        },
        @"hooks": @{
            @"mobilegestalt": @{
                @"ProductType": flat[@"ProductType"] ?: @"",
                @"MarketingName": flat[@"MarketingName"] ?: @"",
                @"HWModelStr": flat[@"HWModelStr"] ?: @"",
            },
            @"sysctl": @{
                @"hw.machine": flat[@"ProductType"] ?: @"",
                @"hw.model": flat[@"HWModelStr"] ?: @"",
                @"hw.memsize": flat[@"hw.memsize"] ?: @0,
                @"hw.ncpu": flat[@"hw.ncpu"] ?: @0,
                @"kern.osversion": flat[@"BuildVersion"] ?: @"",
                @"kern.osproductversion": flat[@"ProductVersion"] ?: @"",
                @"kern.osrelease": flat[@"kern.osrelease"] ?: @"",
                @"kern.version": flat[@"kern.version"] ?: @"",
            },
        },
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:active options:NSJSONWritingPrettyPrinted error:&err];

    BOOL jbOk = NO;
    for (NSString *dir in dirs) {
        if (![self ensureDir:dir error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"mkdir %@: %@", dir, err.localizedDescription ?: @"?"]];
            continue;
        }
        NSString *plistPath = [dir stringByAppendingPathComponent:@"config.plist"];
        NSString *jsonPath = [dir stringByAppendingPathComponent:@"active_profile.json"];
        if (![self writePlist:flat toPath:plistPath error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"plist %@: %@", plistPath, err.localizedDescription ?: @"permission?"]];
            continue;
        }
        if (json && ![json writeToFile:jsonPath options:NSDataWritingAtomic error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"json %@: %@", jsonPath, err.localizedDescription ?: @"?"]];
            // still count plist as ok
        }
        [okPaths addObject:dir];
        if ([dir containsString:@"/var/jb/"]) jbOk = YES;
    }

    if (okPaths.count == 0) {
        return [NSString stringWithFormat:
                @"Lưu thất bại (không ghi được cấu hình):\n%@\n"
                @"Sửa: cài lại gói (postinst chown mobile) hoặc SSH: "
                @"sudo chown -R mobile:mobile /var/jb/etc/ipfaker",
                [failMsgs componentsJoinedByString:@"\n"]];
    }

    NSString *mk = flat[@"MarketingName"] ?: @"?";
    NSString *pt = flat[@"ProductType"] ?: @"?";
    NSString *msg = [NSString stringWithFormat:
                     @"Đã áp dụng %@ (%@) iOS %@ → %@",
                     mk, pt, ios ?: @"?",
                     [okPaths componentsJoinedByString:@", "]];
    if (!jbOk) {
        msg = [msg stringByAppendingString:
               @"\n⚠ CHƯA ghi /var/jb/etc/ipfaker — app đích vẫn đọc cấu hình cũ. "
               @"Chạy: sudo chown -R mobile:mobile /var/jb/etc/ipfaker rồi lưu lại."];
    }
    if (failMsgs.count)
        msg = [msg stringByAppendingFormat:@"\n(partial) %@", [failMsgs componentsJoinedByString:@"; "]];
    return msg;
}

+ (NSDictionary *)loadCurrentFlat {
    // Same source-of-truth rule as IPFConfig: newest mtime wins; jb preferred on tie
    // so app UI matches what Zalo dylib actually loads.
    NSArray *paths = @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bestPath = nil;
    NSDictionary *best = nil;
    NSDate *bestDate = [NSDate distantPast];
    for (NSString *p in paths) {
        if (![fm isReadableFileAtPath:p]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:p error:nil];
        NSDate *mod = attrs[NSFileModificationDate] ?: [NSDate distantPast];
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (!d.count) continue;
        BOOL newer = [mod compare:bestDate] == NSOrderedDescending;
        BOOL sameTimePreferJb = [mod isEqualToDate:bestDate] && [p containsString:@"/var/jb/"];
        if (!best || newer || sameTimePreferJb) {
            best = d;
            bestPath = p;
            bestDate = mod;
        }
    }
    (void)bestPath;
    return best;
}

+ (void)killProcessesNamed:(NSArray<NSString *> *)names {
    NSArray<NSString *> *bins = @[
        @"/var/jb/usr/bin/killall",
        @"/usr/bin/killall",
        @"/var/jb/bin/killall",
    ];
    for (NSString *bin in bins) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:bin]) continue;
        for (NSString *name in names) {
            if (!name.length) continue;
            pid_t pid = 0;
            const char *argv[] = { bin.UTF8String, "-9", name.UTF8String, NULL };
            posix_spawn(&pid, bin.UTF8String, NULL, NULL, (char *const *)argv, NULL);
            if (pid > 0) {
                int st = 0;
                waitpid(pid, &st, 0);
            }
        }
        break;
    }
}

+ (void)killZalo {
    [self killProcessesNamed:@[
        @"Zalo", @"zalo", @"vn.com.vng.zingalo",
        @"ZaloShare", @"NotificationService",
        @"NotificationServiceExtension",
    ]];
}

+ (void)killAppBundleId:(NSString *)bundleId executable:(NSString *)exe {
    NSMutableArray *names = [NSMutableArray array];
    if (exe.length) [names addObject:exe];
    // Common Apple short names
    NSDictionary *map = @{
        @"com.apple.Maps": @"Maps",
        @"com.apple.weather": @"Weather",
        @"com.apple.mobilesafari": @"MobileSafari",
        @"com.apple.mobilecal": @"MobileCal",
        @"com.apple.MobileSMS": @"MobileSMS",
        @"com.apple.mobilemail": @"MobileMail",
        @"com.apple.Preferences": @"Preferences",
        @"com.apple.AppStore": @"AppStore",
        @"com.apple.camera": @"Camera",
        @"com.apple.mobileslideshow": @"MobileSlideShow",
        @"com.apple.Music": @"Music",
        @"vn.com.vng.zingalo": @"Zalo",
        @"com.zing.zalo": @"Zalo",
    };
    NSString *known = map[bundleId];
    if (known.length) [names addObject:known];
    // Last path component of bundle often equals process
    NSString *last = bundleId.pathExtension.length ? bundleId.pathExtension : bundleId.lastPathComponent;
    if (last.length) [names addObject:last];
    if ([bundleId containsString:@"zalo"] || [bundleId containsString:@"zing"]) {
        [names addObjectsFromArray:@[ @"Zalo", @"zalo", @"ZaloShare" ]];
    }
    [self killProcessesNamed:names];
}

+ (BOOL)openBundleIdViaUIOpen:(NSString *)bundleId {
    if (!bundleId.length) return NO;
    NSArray *bins = @[
        @"/var/jb/usr/bin/uiopen",
        @"/usr/bin/uiopen",
        @"/var/jb/bin/uiopen",
    ];
    for (NSString *bin in bins) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:bin]) continue;
        pid_t pid = 0;
        const char *argv[] = {
            bin.UTF8String, "--bundleid", bundleId.UTF8String, NULL
        };
        if (posix_spawn(&pid, bin.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
            int st = 0;
            waitpid(pid, &st, 0);
            return WIFEXITED(st) && WEXITSTATUS(st) == 0;
        }
    }
    return NO;
}

+ (BOOL)openBundleIdViaWorkspace:(NSString *)bundleId {
    if (!bundleId.length) return NO;
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsClass) return NO;
        id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
        if (!ws) return NO;
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (![ws respondsToSelector:openSel]) return NO;
        // BOOL return on modern iOS — ignore result type safely
        ((void (*)(id, SEL, id))objc_msgSend)(ws, openSel, bundleId);
        return YES;
    } @catch (__unused NSException *ex) {
        return NO;
    }
}

+ (NSString *)relaunchAppsWithBundleIds:(NSArray<NSString *> *)bundleIds {
    if (!bundleIds.count) return @"Relaunch: không có bundle";
    // Dedupe, prefer Zalo first for lab wall
    NSMutableArray *ordered = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *prefer in @[ @"vn.com.vng.zingalo", @"com.zing.zalo" ]) {
        if ([bundleIds containsObject:prefer] && ![seen containsObject:prefer]) {
            [ordered addObject:prefer];
            [seen addObject:prefer];
        }
    }
    for (NSString *bid in bundleIds) {
        if (!bid.length || [seen containsObject:bid]) continue;
        // Avoid reopening Settings / SpringBoard helpers
        if ([bid isEqualToString:@"com.apple.Preferences"]) continue;
        [ordered addObject:bid];
        [seen addObject:bid];
    }
    // Cap relaunch to primary targets (Zalo + max 2 more) — avoid mass launch
    if (ordered.count > 3)
        ordered = [[ordered subarrayWithRange:NSMakeRange(0, 3)] mutableCopy];

    NSMutableArray *ok = [NSMutableArray array];
    NSMutableArray *fail = [NSMutableArray array];
    for (NSString *bid in ordered) {
        BOOL opened = [self openBundleIdViaUIOpen:bid];
        if (!opened) opened = [self openBundleIdViaWorkspace:bid];
        if (opened) [ok addObject:bid];
        else [fail addObject:bid];
        // Brief gap so SpringBoard can schedule next open (Method A: shorter)
        usleep(160 * 1000);
    }
    NSMutableString *msg = [NSMutableString stringWithFormat:
                            @"Relaunch %lu app: OK=%lu",
                            (unsigned long)ordered.count, (unsigned long)ok.count];
    if (ok.count)
        [msg appendFormat:@" [%@]", [ok componentsJoinedByString:@", "]];
    if (fail.count)
        [msg appendFormat:@" · fail=%@", [fail componentsJoinedByString:@", "]];
    return msg;
}

/// Run external shell script (wipe helper). Returns exit code, -1 if not found.
+ (int)runShellScript:(NSString *)scriptPath args:(NSArray<NSString *> *)args {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:scriptPath]
        && ![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        return -1;
    }
    NSString *sh = nil;
    for (NSString *c in @[ @"/var/jb/bin/sh", @"/var/jb/usr/bin/sh", @"/bin/sh", @"/var/jb/usr/bin/bash" ]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) { sh = c; break; }
    }
    if (!sh) sh = @"/bin/sh";

    NSMutableArray<NSString *> *argvStr = [NSMutableArray arrayWithObjects:sh, scriptPath, nil];
    if (args.count) [argvStr addObjectsFromArray:args];

    // Build C argv
    char **argv = calloc(argvStr.count + 1, sizeof(char *));
    if (!argv) return -1;
    for (NSUInteger i = 0; i < argvStr.count; i++)
        argv[i] = (char *)[argvStr[i] UTF8String];
    argv[argvStr.count] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, sh.UTF8String, NULL, NULL, argv, NULL);
    free(argv);
    if (rc != 0 || pid <= 0) return -1;
    int st = 0;
    waitpid(pid, &st, 0);
    if (WIFEXITED(st)) return WEXITSTATUS(st);
    return -1;
}

/// True if metadata matches bundle markers (binary MCM plists: MCMMetadataIdentifier).
+ (BOOL)metadataAtPath:(NSString *)metaPath matchesAny:(NSArray<NSString *> *)needles {
    NSData *data = [NSData dataWithContentsOfFile:metaPath];
    if (!data.length) return NO;
    id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    NSMutableArray<NSString *> *hay = [NSMutableArray array];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)obj;
        for (NSString *k in @[ @"MCMMetadataIdentifier", @"Identifier", @"CFBundleIdentifier",
                               @"com.apple.MobileContainerManager.ContentClass" ]) {
            id v = d[k];
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length])
                [hay addObject:[(NSString *)v lowercaseString]];
        }
        // Nested dicts / description fallback
        [hay addObject:[[d description] lowercaseString]];
    } else {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s.length) [hay addObject:s.lowercaseString];
        else if (obj) [hay addObject:[[obj description] lowercaseString]];
    }
    if (!hay.count) return NO;
    for (NSString *n in needles) {
        if (!n.length) continue;
        NSString *nl = n.lowercaseString;
        for (NSString *h in hay) {
            if ([h rangeOfString:nl].location != NSNotFound) return YES;
        }
    }
    return NO;
}

/// Wipe everything inside container root except Apple metadata shells.
+ (NSUInteger)wipeContainerRoot:(NSString *)root fm:(NSFileManager *)fm {
    if (!root.length || ![fm fileExistsAtPath:root]) return 0;
    NSUInteger n = 0;
    NSError *err = nil;
    NSArray *kids = [fm contentsOfDirectoryAtPath:root error:&err];
    for (NSString *name in kids) {
        if ([name isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]
            || [name isEqualToString:@"iTunesMetadata.plist"]
            || [name isEqualToString:@".com.apple.mobile_container_manager.metadata.plist.bak"]) {
            continue;
        }
        NSString *p = [root stringByAppendingPathComponent:name];
        if ([fm removeItemAtPath:p error:&err]) n++;
        else {
            // force contents if remove failed
            NSArray *deep = [fm contentsOfDirectoryAtPath:p error:nil];
            for (NSString *c in deep) {
                if ([fm removeItemAtPath:[p stringByAppendingPathComponent:c] error:nil]) n++;
            }
            [fm removeItemAtPath:p error:nil];
            n++;
        }
    }
    // Recreate empty sandbox dirs so first-launch works
    for (NSString *sub in @[ @"Documents", @"Library", @"tmp", @"Library/Caches", @"Library/Preferences" ]) {
        NSString *p = [root stringByAppendingPathComponent:sub];
        [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return n;
}

+ (NSArray<NSString *> *)needlesForBundles:(NSArray<NSString *> *)bundles {
    NSMutableArray *needles = [NSMutableArray array];
    for (NSString *bid in bundles) {
        if (!bid.length) continue;
        [needles addObject:bid];
        NSArray *parts = [bid componentsSeparatedByString:@"."];
        if (parts.count) [needles addObject:parts.lastObject];
    }
    return needles;
}

+ (NSArray<NSString *> *)containerPathsUnder:(NSString *)base matchingNeedles:(NSArray *)needles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *out = [NSMutableArray array];
    if (![fm fileExistsAtPath:base]) return out;
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:base error:nil] ?: @[]) {
        NSString *root = [base stringByAppendingPathComponent:uuid];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        NSString *meta = [root stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        if ([self metadataAtPath:meta matchesAny:needles])
            [out addObject:root];
    }
    return out;
}

/// Write targets file for root wipe script (one bid per line).
+ (BOOL)writeWipeTargets:(NSArray<NSString *> *)bundles {
    NSString *path = @"/var/mobile/Library/iPFaker/wipe_targets.txt";
    NSMutableString *body = [NSMutableString stringWithString:@"# iPFaker wipe targets\n"];
    for (NSString *b in bundles) {
        if (b.length) [body appendFormat:@"%@\n", b];
    }
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/iPFaker"
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
}

/// Run multi-app wipe script as root when possible (Dopamine sudo).
+ (int)runTrustedWipeScriptForBundles:(NSArray<NSString *> *)bundles {
    [self writeWipeTargets:bundles];
    NSArray *scripts = @[
        @"/var/jb/usr/libexec/ipfaker-wipe-apps",
        @"/var/jb/etc/ipfaker/wipe_apps.sh",
        @"/var/mobile/Library/iPFaker/wipe_apps.sh",
        @"/var/jb/usr/libexec/ipfaker-wipe-zalo", // legacy Zalo-only fallback
        @"/var/jb/etc/ipfaker/wipe_zalo.sh",
        @"/var/mobile/Library/iPFaker/wipe_zalo.sh",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"--targets-file"];
    [args addObject:@"/var/mobile/Library/iPFaker/wipe_targets.txt"];
    for (NSString *b in bundles) {
        if (!b.length) continue;
        [args addObject:@"--bundle"];
        [args addObject:b];
    }

    for (NSString *sp in scripts) {
        if (![fm fileExistsAtPath:sp]) continue;
        [fm setAttributes:@{ NSFilePosixPermissions: @0755 } ofItemAtPath:sp error:nil];
        // Prefer passwordless sudo (mobile often has sudo on Dopamine lab)
        for (NSString *sudoBin in @[ @"/var/jb/usr/bin/sudo", @"/usr/bin/sudo" ]) {
            if (![fm isExecutableFileAtPath:sudoBin]) continue;
            NSMutableArray *sargv = [NSMutableArray arrayWithObjects:sudoBin, @"-n", @"sh", sp, nil];
            [sargv addObjectsFromArray:args];
            char **argv = calloc(sargv.count + 1, sizeof(char *));
            if (!argv) continue;
            for (NSUInteger i = 0; i < sargv.count; i++)
                argv[i] = (char *)[sargv[i] UTF8String];
            pid_t pid = 0;
            int rc = posix_spawn(&pid, sudoBin.UTF8String, NULL, NULL, argv, NULL);
            free(argv);
            if (rc == 0 && pid > 0) {
                int st = 0;
                waitpid(pid, &st, 0);
                if (WIFEXITED(st)) {
                    int code = WEXITSTATUS(st);
                    // 0 ok, 5 residual (still success-ish), 4 not found
                    if (code == 0 || code == 5) return code;
                }
            }
        }
        // Direct sh (if app has enough rights)
        int direct = [self runShellScript:sp args:args];
        if (direct == 0 || direct == 5) return direct;
    }
    return -1;
}

+ (BOOL)copyTreeFrom:(NSString *)src to:(NSString *)dst fm:(NSFileManager *)fm {
    [fm removeItemAtPath:dst error:nil];
    NSString *parent = [dst stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    return [fm copyItemAtPath:src toPath:dst error:nil];
}

/// Copy container children except Apple metadata shells.
+ (NSUInteger)copyContainerContentsFrom:(NSString *)src to:(NSString *)dst fm:(NSFileManager *)fm {
    [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger n = 0;
    for (NSString *name in [fm contentsOfDirectoryAtPath:src error:nil] ?: @[]) {
        if ([name isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]
            || [name isEqualToString:@"iTunesMetadata.plist"]) continue;
        NSString *s = [src stringByAppendingPathComponent:name];
        NSString *d = [dst stringByAppendingPathComponent:name];
        [fm removeItemAtPath:d error:nil];
        if ([fm copyItemAtPath:s toPath:d error:nil]) n++;
    }
    return n;
}

+ (NSString *)defaultBackupBase {
    return @"/var/mobile/Library/iPFaker/backups";
}

+ (BOOL)backupCurrentDeviceProfileTo:(NSString *)backupRoot error:(NSString **)errOut {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *devDir = [backupRoot stringByAppendingPathComponent:@"device"];
    [fm createDirectoryAtPath:devDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *srcs = @[
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/mobile/Library/iPFaker/config.plist",
        @"/var/jb/etc/ipfaker/active_profile.json",
        @"/var/mobile/Library/iPFaker/active_profile.json",
    ];
    BOOL any = NO;
    for (NSString *s in srcs) {
        if (![fm fileExistsAtPath:s]) continue;
        NSString *name = s.lastPathComponent;
        // Prefer jb config if both exist — write once per name, jb first in list
        NSString *dst = [devDir stringByAppendingPathComponent:name];
        if ([name isEqualToString:@"config.plist"] && [fm fileExistsAtPath:dst] && [s containsString:@"/var/mobile/"])
            continue; // already have jb
        if ([name isEqualToString:@"active_profile.json"] && [fm fileExistsAtPath:dst] && [s containsString:@"/var/mobile/"])
            continue;
        [fm removeItemAtPath:dst error:nil];
        if ([fm copyItemAtPath:s toPath:dst error:nil]) any = YES;
    }
    // Manifest of saved device keys
    NSDictionary *flat = [self loadCurrentFlat] ?: @{};
    NSDictionary *manifest = @{
        @"savedAt": @([[NSDate date] timeIntervalSince1970]),
        @"MarketingName": flat[@"MarketingName"] ?: @"",
        @"ProductType": flat[@"ProductType"] ?: @"",
        @"ProductVersion": flat[@"ProductVersion"] ?: @"",
        @"SerialNumber": flat[@"SerialNumber"] ?: @"",
        @"IDFA": flat[@"IDFA"] ?: @"",
        @"IDFV": flat[@"IDFV"] ?: @"",
        @"DeviceCatalogId": flat[@"DeviceCatalogId"] ?: @"",
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[devDir stringByAppendingPathComponent:@"manifest.json"] atomically:YES];
    if (!any && errOut) *errOut = @"Không tìm thấy config.plist để lưu";
    return any || json != nil;
}

+ (NSString *)backupApps:(NSArray<NSString *> *)bundleIds
              backupRoot:(NSString *)backupRoot
                progress:(IPFWipeProgress)progress {
    void (^step)(NSString *) = ^(NSString *s) { if (progress) progress(s); };
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *bundles = bundleIds.count ? bundleIds : @[];
    if (!backupRoot.length) {
        NSString *ts = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
        backupRoot = [[self defaultBackupBase] stringByAppendingPathComponent:ts];
    }
    [fm createDirectoryAtPath:backupRoot withIntermediateDirectories:YES attributes:nil error:nil];
    // also update "latest" symlink-like folder
    NSString *latest = [[self defaultBackupBase] stringByAppendingPathComponent:@"latest"];
    [fm removeItemAtPath:latest error:nil];
    [fm createDirectoryAtPath:latest withIntermediateDirectories:YES attributes:nil error:nil];

    step(@"Đóng app trước khi sao lưu…");
    for (NSString *bid in bundles) [self killAppBundleId:bid executable:nil];
    usleep(300000);

    NSString *err = nil;
    step(@"Lưu 100% thông số thiết bị…");
    [self backupCurrentDeviceProfileTo:backupRoot error:&err];
    [self backupCurrentDeviceProfileTo:latest error:nil];

    NSArray *needles = [self needlesForBundles:bundles];
    NSUInteger nData = 0, nGroup = 0;
    NSString *appsDir = [backupRoot stringByAppendingPathComponent:@"apps"];
    [fm createDirectoryAtPath:appsDir withIntermediateDirectories:YES attributes:nil error:nil];

    for (NSString *bid in bundles) {
        step([NSString stringWithFormat:@"Sao lưu data: %@", bid]);
        NSString *bidDir = [appsDir stringByAppendingPathComponent:bid];
        NSString *dataBak = [bidDir stringByAppendingPathComponent:@"data"];
        NSString *groupBak = [bidDir stringByAppendingPathComponent:@"groups"];
        [fm createDirectoryAtPath:dataBak withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:groupBak withIntermediateDirectories:YES attributes:nil error:nil];

        NSArray *datas = [self containerPathsUnder:@"/var/mobile/Containers/Data/Application"
                                  matchingNeedles:@[ bid, bid.pathExtension ?: @"" ]];
        // also match needles list for this bid only
        NSMutableArray *bidNeedles = [NSMutableArray arrayWithObject:bid];
        if (bid.pathExtension.length) [bidNeedles addObject:bid.pathExtension];
        datas = [self containerPathsUnder:@"/var/mobile/Containers/Data/Application" matchingNeedles:bidNeedles];
        int i = 0;
        for (NSString *root in datas) {
            NSString *dst = [dataBak stringByAppendingPathComponent:[NSString stringWithFormat:@"c%d", i++]];
            nData += [self copyContainerContentsFrom:root to:dst fm:fm];
        }
        NSArray *groups = [self containerPathsUnder:@"/var/mobile/Containers/Shared/AppGroup" matchingNeedles:needles];
        // Filter groups that mention this bid
        int g = 0;
        for (NSString *root in groups) {
            NSString *meta = [root stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            if (![self metadataAtPath:meta matchesAny:bidNeedles] && bundles.count > 1) {
                // still allow zalo group match via needles if single token
                if (![self metadataAtPath:meta matchesAny:needles]) continue;
            }
            NSString *dst = [groupBak stringByAppendingPathComponent:[NSString stringWithFormat:@"g%d", g++]];
            nGroup += [self copyContainerContentsFrom:root to:dst fm:fm];
        }
        // Shared prefs crumbs
        NSString *crumbs = [bidDir stringByAppendingPathComponent:@"crumbs"];
        [fm createDirectoryAtPath:crumbs withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *p in @[
            [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", bid],
            [NSString stringWithFormat:@"/var/mobile/Library/Cookies/%@.binarycookies", bid],
        ]) {
            if ([fm fileExistsAtPath:p]) {
                [fm copyItemAtPath:p toPath:[crumbs stringByAppendingPathComponent:p.lastPathComponent] error:nil];
            }
        }
    }

    // Mirror to latest
    [fm removeItemAtPath:[latest stringByAppendingPathComponent:@"apps"] error:nil];
    [self copyTreeFrom:appsDir to:[latest stringByAppendingPathComponent:@"apps"] fm:fm];

    NSString *msg = [NSString stringWithFormat:
                     @"Đã lưu backup:\n%@\nData~%lu · Groups~%lu · App: %lu",
                     backupRoot, (unsigned long)nData, (unsigned long)nGroup, (unsigned long)bundles.count];
    step(msg);
    // Write marker path for restore
    [[backupRoot dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[[self defaultBackupBase] stringByAppendingPathComponent:@"LAST_BACKUP_PATH.txt"]
         atomically:YES];
    return backupRoot;
}

+ (NSString *)restoreApps:(NSArray<NSString *> *)bundleIds
           fromBackupRoot:(NSString *)backupRoot
                 progress:(IPFWipeProgress)progress {
    void (^step)(NSString *) = ^(NSString *s) { if (progress) progress(s); };
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!backupRoot.length || ![fm fileExistsAtPath:backupRoot])
        return @"ERR: không có thư mục backup";

    step(@"Đóng app trước khi khôi phục…");
    for (NSString *bid in bundleIds) [self killAppBundleId:bid executable:nil];
    usleep(250000);

    NSUInteger restored = 0;
    for (NSString *bid in bundleIds) {
        step([NSString stringWithFormat:@"Khôi phục data (giữ đăng nhập): %@", bid]);
        NSString *bidDir = [[backupRoot stringByAppendingPathComponent:@"apps"] stringByAppendingPathComponent:bid];
        if (![fm fileExistsAtPath:bidDir]) {
            step([NSString stringWithFormat:@"Không có backup cho %@", bid]);
            continue;
        }
        NSMutableArray *bidNeedles = [NSMutableArray arrayWithObject:bid];
        if (bid.pathExtension.length) [bidNeedles addObject:bid.pathExtension];

        // Restore data containers — map backup c0,c1… onto live containers for bid
        NSArray *liveData = [self containerPathsUnder:@"/var/mobile/Containers/Data/Application" matchingNeedles:bidNeedles];
        NSString *dataBak = [bidDir stringByAppendingPathComponent:@"data"];
        NSArray *bakSlots = [[fm contentsOfDirectoryAtPath:dataBak error:nil] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
        for (NSUInteger i = 0; i < liveData.count; i++) {
            NSString *live = liveData[i];
            // Clear then copy
            [self wipeContainerRoot:live fm:fm];
            if (i < bakSlots.count) {
                NSString *slot = [dataBak stringByAppendingPathComponent:bakSlots[i]];
                restored += [self copyContainerContentsFrom:slot to:live fm:fm];
            }
        }
        // If no live container yet but we have backup — cannot create UUID container easily; log
        if (liveData.count == 0 && bakSlots.count > 0)
            step([NSString stringWithFormat:@"%@: chưa có container sống — mở app 1 lần rồi khôi phục lại", bid]);

        // Groups
        NSString *groupBak = [bidDir stringByAppendingPathComponent:@"groups"];
        NSArray *bakG = [[fm contentsOfDirectoryAtPath:groupBak error:nil] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
        NSArray *liveG = [self containerPathsUnder:@"/var/mobile/Containers/Shared/AppGroup" matchingNeedles:bidNeedles];
        if (liveG.count == 0)
            liveG = [self containerPathsUnder:@"/var/mobile/Containers/Shared/AppGroup" matchingNeedles:[self needlesForBundles:bundleIds]];
        for (NSUInteger i = 0; i < liveG.count && i < bakG.count; i++) {
            [self wipeContainerRoot:liveG[i] fm:fm];
            restored += [self copyContainerContentsFrom:[groupBak stringByAppendingPathComponent:bakG[i]] to:liveG[i] fm:fm];
        }

        // Crumbs
        NSString *crumbs = [bidDir stringByAppendingPathComponent:@"crumbs"];
        for (NSString *name in [fm contentsOfDirectoryAtPath:crumbs error:nil] ?: @[]) {
            NSString *src = [crumbs stringByAppendingPathComponent:name];
            NSString *dst = nil;
            if ([name hasSuffix:@".plist"])
                dst = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@", name];
            else if ([name hasSuffix:@".binarycookies"])
                dst = [NSString stringWithFormat:@"/var/mobile/Library/Cookies/%@", name];
            if (dst) {
                [[dst stringByDeletingLastPathComponent] length];
                [fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:dst error:nil];
                if ([fm copyItemAtPath:src toPath:dst error:nil]) restored++;
            }
        }
    }

    step(@"Đóng app sau khôi phục…");
    for (NSString *bid in bundleIds) [self killAppBundleId:bid executable:nil];

    return [NSString stringWithFormat:@"Đã khôi phục data app (giữ phiên đăng nhập). Mục~%lu", (unsigned long)restored];
}

+ (NSString *)wipeApps:(NSArray<NSString *> *)bundleIds progress:(IPFWipeProgress)progress {
    return [self wipeApps:bundleIds progress:progress options:nil];
}

+ (NSString *)wipeApps:(NSArray<NSString *> *)bundleIds
              progress:(IPFWipeProgress)progress
               options:(NSDictionary *)options {
    void (^step)(NSString *) = ^(NSString *s) {
        if (progress) progress(s);
    };
    BOOL skipKeychain = [options[@"skipKeychain"] boolValue];
    BOOL skipScript = [options[@"skipScript"] boolValue];

    NSMutableArray *log = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *bundles = bundleIds.count ? bundleIds : @[ @"vn.com.vng.zingalo" ];
    NSArray *needles = [self needlesForBundles:bundles];

    step([NSString stringWithFormat:@"Bắt đầu xóa dữ liệu %lu app…", (unsigned long)bundles.count]);
    [log addObject:[NSString stringWithFormat:@"Mục tiêu: %@", [bundles componentsJoinedByString:@", "]]];

    for (NSString *bid in bundles) {
        step([NSString stringWithFormat:@"Đóng: %@", bid.pathExtension.length ? bid : bid]);
        [self killAppBundleId:bid executable:nil];
    }
    usleep(60 * 1000); // kill is enough; keep short for Method A
    [log addObject:@"① Đã đóng tiến trình"];

    BOOL wipingZalo = NO;
    for (NSString *b in bundles) {
        if ([b.lowercaseString containsString:@"zalo"] || [b.lowercaseString containsString:@"zing"]) {
            wipingZalo = YES; break;
        }
    }

    // One-tap trusted path: root multi-app script (all selected bundles)
    BOOL scriptTrusted = NO;
    if (!skipScript) {
        step(@"Script xóa root…");
        int rc = [self runTrustedWipeScriptForBundles:bundles];
        if (rc == 0 || rc == 5) {
            scriptTrusted = YES;
            NSString *m = [NSString stringWithFormat:@"② Script tin cậy OK (mã %d)", rc];
            [log addObject:m];
            step(m);
        } else {
            [log addObject:[NSString stringWithFormat:@"② Script root: mã %d — xóa trực tiếp", rc]];
            step(@"Xóa trực tiếp…");
        }
    } else {
        [log addObject:@"② Script: bỏ qua"];
    }

    // FAST PATH: if root script succeeded, skip full FileManager container walk (was 2x wipe → very slow).
    // Only light residual prefs/cookies below.
    NSUInteger dataWiped = 0;
    NSUInteger groupWiped = 0;
    if (!scriptTrusted) {
        step(@"Quét / xóa thư mục dữ liệu app…");
        for (NSString *root in [self containerPathsUnder:@"/var/mobile/Containers/Data/Application" matchingNeedles:needles]) {
            dataWiped += [self wipeContainerRoot:root fm:fm];
        }
        for (NSString *base in @[
                 @"/var/mobile/Containers/Data/PluginKitPlugin",
                 @"/private/var/mobile/Containers/Data/PluginKitPlugin" ]) {
            for (NSString *root in [self containerPathsUnder:base matchingNeedles:needles]) {
                dataWiped += [self wipeContainerRoot:root fm:fm];
            }
        }
        for (NSString *root in [self containerPathsUnder:@"/var/mobile/Containers/Shared/AppGroup" matchingNeedles:needles]) {
            groupWiped += [self wipeContainerRoot:root fm:fm];
        }
        [log addObject:[NSString stringWithFormat:@"③ Dữ liệu mục~%lu · nhóm~%lu",
                        (unsigned long)dataWiped, (unsigned long)groupWiped]];
    } else {
        // Residual only (fast)
        step(@"Dọn residual prefs/cache…");
        [log addObject:@"③ Containers: script đã xóa — residual nhẹ"];
    }

    step(@"Xóa tuỳ chọn / cookie / bộ nhớ đệm…");
    NSUInteger crumb = 0;
    for (NSString *bid in bundles) {
        for (NSString *p in @[
            [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", bid],
            [NSString stringWithFormat:@"/var/mobile/Library/Cookies/%@.binarycookies", bid],
            [NSString stringWithFormat:@"/var/mobile/Library/HTTPStorages/%@", bid],
            [NSString stringWithFormat:@"/var/mobile/Library/Caches/%@", bid],
        ]) {
            if ([fm fileExistsAtPath:p] && [fm removeItemAtPath:p error:nil]) crumb++;
        }
    }
    [log addObject:[NSString stringWithFormat:@"⑤ Tuỳ chọn/bộ nhớ đệm ~%lu", (unsigned long)crumb]];

    // Keychain: script tin cậy đã purge Zalo trong wipe_apps.sh — không lặp (đã đo rất chậm).
    if (scriptTrusted && wipingZalo && !skipKeychain) {
        [log addObject:@"⑥ Keychain Zalo: script đã dọn"];
        step(@"Keychain: script đã dọn");
    } else if (wipingZalo && !skipKeychain) {
        step(@"Xóa keychain Zalo (1 SQL)…");
        NSString *sqlite = nil;
        for (NSString *c in @[ @"/var/jb/usr/bin/sqlite3", @"/usr/bin/sqlite3" ]) {
            if ([fm isExecutableFileAtPath:c]) { sqlite = c; break; }
        }
        NSString *kcDB = nil;
        for (NSString *p in @[ @"/var/Keychains/keychain-2.db", @"/private/var/Keychains/keychain-2.db" ]) {
            if ([fm isReadableFileAtPath:p]) { kcDB = p; break; }
        }
        if (sqlite && kcDB) {
            // Match wipe_zalo_session.sh: team agrp + zalo patterns (genp/inet/keys)
            NSString *where =
                @"agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR "
                 "agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR "
                 "agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%' OR agrp LIKE '%zing.zalo%' OR "
                 "svce LIKE '%zalo%' OR acct LIKE '%zalo%' OR "
                 "svce LIKE '%zingalo%' OR acct LIKE '%zingalo%'";
            // genp (has svce); inet has no svce on modern keychain-2.db
            {
                NSString *sql = [NSString stringWithFormat:@"DELETE FROM genp WHERE %@;", where];
                pid_t pid = 0;
                const char *argv[] = { sqlite.UTF8String, kcDB.UTF8String, sql.UTF8String, NULL };
                if (posix_spawn(&pid, sqlite.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
                    int st = 0; waitpid(pid, &st, 0);
                }
            }
            {
                NSString *inetWhere =
                    @"agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR "
                     "agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%com.zing.zalo%' OR "
                     "agrp LIKE '%vng.zalo%' OR agrp LIKE '%zingalo%' OR "
                     "acct LIKE '%zalo%' OR srvr LIKE '%zalo%' OR srvr LIKE '%zalo.me%'";
                NSString *sql = [NSString stringWithFormat:@"DELETE FROM inet WHERE %@;", inetWhere];
                pid_t pid = 0;
                const char *argv[] = { sqlite.UTF8String, kcDB.UTF8String, sql.UTF8String, NULL };
                if (posix_spawn(&pid, sqlite.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
                    int st = 0; waitpid(pid, &st, 0);
                }
            }
            {
                NSString *sqlKeys =
                    @"DELETE FROM keys WHERE agrp LIKE '%group.keychain.vn.com.vng.zalo%' OR "
                     "agrp LIKE '%vn.com.vng.zingalo%' OR agrp LIKE '%zingalo%' OR "
                     "agrp LIKE '%vng.zalo%' OR labl LIKE '%zalo%';";
                pid_t pid = 0;
                const char *argv[] = { sqlite.UTF8String, kcDB.UTF8String, sqlKeys.UTF8String, NULL };
                if (posix_spawn(&pid, sqlite.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
                    int st = 0; waitpid(pid, &st, 0);
                }
            }
            {
                NSString *chk = @"PRAGMA wal_checkpoint(TRUNCATE);";
                pid_t pid = 0;
                const char *argv[] = { sqlite.UTF8String, kcDB.UTF8String, chk.UTF8String, NULL };
                if (posix_spawn(&pid, sqlite.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
                    int st = 0; waitpid(pid, &st, 0);
                }
            }
            [self killProcessesNamed:@[ @"securityd" ]];
            [log addObject:@"⑥ Keychain Zalo session (genp/inet/keys) đã dọn"];
            step(@"Keychain Zalo session: đã dọn");
        } else {
            step(@"Keychain: bỏ qua (cần sqlite3)");
            [log addObject:@"⑥ Keychain: bỏ qua — cài sqlite3 (apt)"];
        }
    } else if (skipKeychain) {
        step(@"Giữ keychain (để phiên đăng nhập)");
        [log addObject:@"⑥ Keychain: giữ nguyên"];
    }

    step(@"Đóng lại…");
    for (NSString *bid in bundles) [self killAppBundleId:bid executable:nil];

    // Skip full residual walk when script trusted (was very slow)
    if (!scriptTrusted) {
        NSUInteger residual = 0;
        for (NSString *root in [self containerPathsUnder:@"/var/mobile/Containers/Data/Application" matchingNeedles:needles]) {
            for (NSString *sub in @[ @"Documents", @"Library", @"tmp" ]) {
                NSString *p = [root stringByAppendingPathComponent:sub];
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:p];
                for (NSString *rel in en) {
                    NSString *full = [p stringByAppendingPathComponent:rel];
                    BOOL isDir = NO;
                    if ([fm fileExistsAtPath:full isDirectory:&isDir] && !isDir) residual++;
                    if (residual > 50) break; // cap scan
                }
                if (residual > 50) break;
            }
        }
        [log addObject:residual == 0 ? @"⑦ Kiểm tra: sạch" :
         [NSString stringWithFormat:@"⑦ Kiểm tra: còn ~%lu file", (unsigned long)residual]];
    } else {
        [log addObject:@"⑦ Kiểm tra: bỏ qua (script OK)"];
    }

    step(@"Hoàn tất");
    return [NSString stringWithFormat:
            @"Xóa 1 chạm %lu app:\n%@",
            (unsigned long)bundles.count,
            [log componentsJoinedByString:@"\n"]];
}

+ (NSString *)wipeZaloFull {
    return [self wipeApps:@[ @"vn.com.vng.zingalo", @"com.zing.zalo" ] progress:nil];
}

+ (NSString *)wipeZaloLab {
    return [self wipeZaloFull];
}

#pragma mark - Multi-app spoof filters

+ (NSData *)filterPlistDataForBundles:(NSArray<NSString *> *)bundles
                      includeCommCenter:(BOOL)comm {
    NSMutableArray *bids = [NSMutableArray array];
    for (NSString *b in bundles) {
        if (!b.length) continue;
        if ([b isEqualToString:@"com.apple.Preferences"]) continue;
        if (![bids containsObject:b]) [bids addObject:b];
    }
    if (bids.count == 0) {
        [bids addObject:@"vn.com.vng.zingalo"];
        [bids addObject:@"com.zing.zalo"];
    }
    NSMutableDictionary *filter = [@{
        @"Bundles": bids,
        @"Mode": @"Any",
    } mutableCopy];
    if (comm) {
        filter[@"Executables"] = @[ @"CommCenter", @"commcenter", @"CoreTelephonyHelper" ];
    }
    NSDictionary *root = @{ @"Filter": filter };
    return [NSPropertyListSerialization dataWithPropertyList:root
                                                      format:NSPropertyListXMLFormat_v1_0
                                                     options:0
                                                       error:nil];
}

+ (NSString *)mergeKeysIntoConfig:(NSDictionary *)keys progress:(IPFWipeProgress)progress {
    void (^step)(NSString *) = ^(NSString *s) { if (progress) progress(s); };
    if (!keys.count) return @"ERR: không có key";
    step(@"Đọc config hiện tại…");
    NSMutableDictionary *flat = [[self loadCurrentFlat] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Schema-lock incoming keys before merge (no foreign pollution)
    NSUInteger dropped = 0;
    NSDictionary *safeKeys = [self schemaLockedFlat:keys dropped:&dropped];
    if (dropped > 0)
        step([NSString stringWithFormat:@"Schema lock: bỏ %lu key lạ", (unsigned long)dropped]);
    [flat addEntriesFromDictionary:safeKeys];
    NSString *did = flat[@"DeviceCatalogId"] ?: @"";
    NSString *ios = flat[@"ProductVersion"] ?: @"";
    step(@"Ghi dual-path config.plist (schema lock)…");
    NSString *r = [self applyFlatProfile:flat deviceId:did ios:ios];
    return [NSString stringWithFormat:@"Config merge OK (schema lock)%@\n%@",
            dropped ? [NSString stringWithFormat:@" · drop %lu", (unsigned long)dropped] : @"",
            r ?: @"OK"];
}

+ (NSString *)applySpoofFiltersForBundles:(NSArray<NSString *> *)bundleIds
                                 progress:(IPFWipeProgress)progress {
    void (^step)(NSString *) = ^(NSString *s) { if (progress) progress(s); };
    NSMutableArray *bids = [bundleIds mutableCopy] ?: [NSMutableArray array];
    // Always keep Zalo for lab wall
    if (![bids containsObject:@"vn.com.vng.zingalo"])
        [bids insertObject:@"vn.com.vng.zingalo" atIndex:0];
    if (![bids containsObject:@"com.zing.zalo"])
        [bids addObject:@"com.zing.zalo"];
    [bids removeObject:@"com.apple.Preferences"];

    // Do NOT inject full MG/CT/JB into WebKit.WebContent/Networking/GPU by default.
    // Full stack on WebContent causes lag/white hybrid WebViews (Zalo zBox / in-app browser).
    // Safari main process still spoofed when listed; WKWebView in Zalo uses Zalo process hooks.
    for (NSString *wk in @[
             @"com.apple.WebKit.WebContent",
             @"com.apple.WebKit.Networking",
             @"com.apple.WebKit.GPU",
         ]) {
        [bids removeObject:wk];
    }

    step([NSString stringWithFormat:@"Chuẩn bị filter %lu app (CT + CommCenter, no WebKit helpers)…", (unsigned long)bids.count]);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *stage = @"/var/mobile/Library/iPFaker";
    [fm createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];

    // MG/JB = app bundles only; CT = same bundles + CommCenter/CoreTelephonyHelper (lab CT daemon)
    NSData *mgPl = [self filterPlistDataForBundles:bids includeCommCenter:NO];
    NSData *ctPl = [self filterPlistDataForBundles:bids includeCommCenter:YES];
    NSData *jbPl = mgPl;
    if (!mgPl.length || !ctPl.length) return @"ERR: không tạo được filter plist";
    // Hard guarantee: CT filter must include CommCenter executables
    NSString *ctStr = [[NSString alloc] initWithData:ctPl encoding:NSUTF8StringEncoding] ?: @"";
    if (![ctStr containsString:@"CommCenter"]) {
        return @"ERR: CT filter thiếu CommCenter — abort (lab CT daemon required)";
    }

    [mgPl writeToFile:[stage stringByAppendingPathComponent:@"iPFakerMG.plist"] atomically:YES];
    [ctPl writeToFile:[stage stringByAppendingPathComponent:@"iPFakerCT.plist"] atomically:YES];
    [jbPl writeToFile:[stage stringByAppendingPathComponent:@"iPFakerJB.plist"] atomically:YES];

    // Settings → Giới thiệu: tiny iPFakerAbout only (full MG is CODESIGN-killed in Preferences)
    NSData *aboutPl = [self filterPlistDataForBundles:@[ @"com.apple.Preferences" ] includeCommCenter:NO];
    if (aboutPl.length)
        [aboutPl writeToFile:[stage stringByAppendingPathComponent:@"iPFakerAbout.plist"] atomically:YES];

    // Manifest for PC / debug
    NSDictionary *manifest = @{
        @"schema": @"ipfaker.spoof_apps/1",
        @"bundles": bids,
        @"settingsAbout": @[ @"com.apple.Preferences" ],
        @"updated": @([[NSDate date] timeIntervalSince1970]),
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    if (json) [json writeToFile:[stage stringByAppendingPathComponent:@"spoof_apps.json"] atomically:YES];

    step(@"Cài filter vào TweakInject (root)…");
    NSString *script = [stage stringByAppendingPathComponent:@"install_spoof_filters.sh"];
    NSString *sh = @"#!/bin/sh\n"
        "set -e\n"
        "STAGE=/var/mobile/Library/iPFaker\n"
        "for INJ in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do\n"
        "  [ -d \"$INJ\" ] || continue\n"
        "  for n in iPFakerMG iPFakerCT iPFakerJB iPFakerAbout; do\n"
        "    if [ -f \"$STAGE/${n}.plist\" ]; then\n"
        "      cp -f \"$STAGE/${n}.plist\" \"$INJ/${n}.plist\"\n"
        "      chmod 644 \"$INJ/${n}.plist\"\n"
        "      chown root:wheel \"$INJ/${n}.plist\" 2>/dev/null || true\n"
        "    fi\n"
        "  done\n"
        "done\n"
        "cp -f \"$STAGE/spoof_apps.json\" /var/jb/etc/ipfaker/spoof_apps.json 2>/dev/null || true\n"
        "chown mobile:mobile /var/jb/etc/ipfaker/spoof_apps.json 2>/dev/null || true\n"
        "echo OK install_spoof_filters\n";
    [sh writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm setAttributes:@{ NSFilePosixPermissions: @0755 } ofItemAtPath:script error:nil];

    int rc = -1;
    for (NSString *sudoBin in @[ @"/var/jb/usr/bin/sudo", @"/usr/bin/sudo" ]) {
        if (![fm isExecutableFileAtPath:sudoBin]) continue;
        pid_t pid = 0;
        const char *argv[] = { sudoBin.UTF8String, "-n", "sh", script.UTF8String, NULL };
        if (posix_spawn(&pid, sudoBin.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
            int st = 0;
            waitpid(pid, &st, 0);
            if (WIFEXITED(st)) rc = WEXITSTATUS(st);
            if (rc == 0) break;
        }
    }
    if (rc != 0) {
        // Try direct write (if already root / writable)
        for (NSString *inj in @[
                 @"/var/jb/usr/lib/TweakInject",
                 @"/var/jb/Library/MobileSubstrate/DynamicLibraries" ]) {
            if (![fm fileExistsAtPath:inj]) continue;
            for (NSString *n in @[ @"iPFakerMG", @"iPFakerCT", @"iPFakerJB", @"iPFakerAbout" ]) {
                NSString *src = [stage stringByAppendingPathComponent:[n stringByAppendingString:@".plist"]];
                NSString *dst = [inj stringByAppendingPathComponent:[n stringByAppendingString:@".plist"]];
                if ([fm fileExistsAtPath:src])
                    [fm copyItemAtPath:src toPath:dst error:nil];
            }
        }
        rc = 0;
    }

    step(@"Đóng app spoof để lần mở sau inject…");
    for (NSString *bid in bids)
        [self killAppBundleId:bid executable:nil];
    // Refresh Settings so About dylib reloads
    [self killAppBundleId:@"com.apple.Preferences" executable:nil];

    NSString *preview = bids.count <= 6
        ? [bids componentsJoinedByString:@", "]
        : [NSString stringWithFormat:@"%@ … (+%lu)",
           [[bids subarrayWithRange:NSMakeRange(0, 4)] componentsJoinedByString:@", "],
           (unsigned long)(bids.count - 4)];
    return [NSString stringWithFormat:
            @"Multi-app spoof: %lu app · CT CommCenter=ON · Settings About=ON\n%@\n"
            @"Đã ghi filter MG/CT/JB/About · mở lại app = spoof active\n"
            @"rc=%d",
            (unsigned long)bids.count, preview, rc];
}

@end


