#import "ProfileBuilder.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>

@implementation ProfileBuilder

// Apple identity formats (match scripts/select_device_profile.py):
// SerialNumber: 12-char, no I/O/0/1; ModelNumber: MPN/A; IDFA/IDFV: UUID v4 upper; IMEI: Luhn

+ (NSString *)randomSerialForYear:(NSInteger)year {
    // <2021: 12 chars; >=2021: 10-14 random. No I/O.
    static NSString *alpha = @"ABCDEFGHJKLMNPQRSTUVWXYZ0123456789";
    static NSString *plants = @"CDFGHJKLMNPQRSTUVWXYZ";
    int len = (year > 0 && year < 2021) ? 12 : (10 + (int)arc4random_uniform(5));
    unichar plant = [plants characterAtIndex:arc4random_uniform((u_int32_t)plants.length)];
    NSMutableString *s = [NSMutableString stringWithFormat:@"%C", plant];
    for (int i = 1; i < len; i++) {
        u_int32_t r = arc4random_uniform((u_int32_t)alpha.length);
        [s appendFormat:@"%C", [alpha characterAtIndex:r]];
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
    // Locally administered unicast MAC
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
    // 15-digit IMEI with valid Luhn check digit
    NSMutableString *body = [NSMutableString stringWithString:@"35"];
    for (int i = 0; i < 12; i++)
        [body appendFormat:@"%u", arc4random_uniform(10)];
    return [body stringByAppendingString:[self luhnCheckDigitFor14:body]];
}

+ (NSString *)uuidUpper {
    // IDFA / IDFV — RFC 4122 UUID v4, uppercase with hyphens (NSUUID style)
    return [[[NSUUID UUID] UUIDString] uppercaseString];
}

+ (NSString *)randomUDID {
    // UniqueDeviceID — 40 hex (legacy Apple UDID length)
    NSString *a = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *b = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return [[a stringByAppendingString:[b substringToIndex:8]] uppercaseString];
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
    NSString *udid = [self randomUDID];
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
    NSString *regLetters = partInfo[@"region"] ?: @"ZA";
    NSString *regionCode = @{ @"LL":@"US", @"J":@"JP", @"CH":@"CN", @"KH":@"KR", @"ZA":@"SG", @"ZP":@"HK",
                              @"B":@"GB", @"D":@"DE", @"F":@"FR", @"T":@"IT", @"X":@"AU", @"C":@"CA" }[regLetters] ?: @"VN";

    NSInteger w = [disp[@"NativeWidth"] integerValue] ?: 1170;
    NSInteger h = [disp[@"NativeHeight"] integerValue] ?: 2532;
    NSInteger scale = [disp[@"ScreenScale"] integerValue] ?: 3;
    NSInteger pitch = [disp[@"Pitch"] integerValue] ?: 460;
    NSInteger cores = [device[@"cpuCores"] integerValue] ?: 6;

    // Storage (bytes) — catalog storageGB or typical tier; free ≈ 35–55% used
    NSInteger storageGB = [device[@"storageGB"] integerValue];
    if (storageGB <= 0) storageGB = 128;
    long long totalDisk = (long long)storageGB * 1000LL * 1000LL * 1000LL; // decimal GB (iOS reports 1000-base)
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

    // Wi‑Fi SSID/BSSID display (BSSID = MAC-like EUI-48)
    NSString *ssid = @"Viettel-WiFi";
    NSString *bssid = wifi;

    return @{
        @"Enabled": @YES,
        @"ProductType": device[@"ProductType"] ?: @"iPhone16,1",
        @"MarketingName": device[@"MarketingName"] ?: @"iPhone",
        @"DeviceName": @"iPhone",
        @"UserAssignedDeviceName": devName,
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
        @"UniqueChipID": [NSString stringWithFormat:@"%016llX", ((uint64_t)arc4random() << 32) | arc4random()],
        @"ProductVersion": iosMeta[@"ProductVersion"] ?: iosVer,
        @"BuildVersion": iosMeta[@"BuildVersion"] ?: @"",
        @"ProductBuildVersion": iosMeta[@"BuildVersion"] ?: @"",
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
        @"SSID": ssid,
        @"BSSID": bssid,
        // ITU-T E.212 MCC/MNC — Viettel 452/04; ISO 3166-1 alpha-2
        @"carrierName": @"Viettel",
        @"carrierMCC": @"452",
        @"carrierMNC": @"04",
        @"carrierISO": @"vn",
        @"carrierRadioAccess": @"CTRadioAccessTechnologyNR",
        @"CarrierName": @"Viettel",
        @"MobileCountryCode": @"452",
        @"MobileNetworkCode": @"04",
        @"ISOCountryCode": @"vn",
        @"AllowsVOIP": @YES,
        // Display (native pixels + scale)
        @"main-screen-width": @(w),
        @"main-screen-height": @(h),
        @"main-screen-scale": @(scale),
        @"main-screen-pitch": @(pitch),
        @"PhysicalMemoryMB": @(ramMB),
        @"PhysicalMemoryBytes": @(ramBytes),
        @"hw.memsize": @(ramBytes),
        @"hw.ncpu": @(cores),
        @"hw.physicalcpu": @(cores),
        @"hw.logicalcpu": @(cores),
        @"ChipName": device[@"chip"] ?: @"",
        @"DeviceCatalogId": device[@"id"] ?: @"",
        @"MaxRefreshHz": disp[@"MaxRefreshHz"] ?: @60,
        @"DeviceYear": device[@"year"] ?: @0,
        @"BatteryMah": device[@"batteryMah"] ?: @0,
        // Disk bytes
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
        // Browser UA + WebRTC private IP
        @"UserAgent": ua,
        @"HTTPUserAgent": ua,
        @"WebRTCLocalIP": webrtcIP,
    };
}

+ (BOOL)ensureDir:(NSString *)dir error:(NSError **)err {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) return YES;
    return [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:err];
}

+ (BOOL)writePlist:(NSDictionary *)flat toPath:(NSString *)path error:(NSError **)err {
    return [flat writeToURL:[NSURL fileURLWithPath:path] error:err];
}

+ (NSString *)applyFlatProfile:(NSDictionary *)flat deviceId:(NSString *)deviceId ios:(NSString *)ios {
    NSError *err = nil;
    NSArray *dirs = @[
        @"/var/mobile/Library/iPFaker",
        @"/var/jb/etc/ipfaker",
    ];
    NSMutableArray *okPaths = [NSMutableArray array];
    NSMutableArray *failMsgs = [NSMutableArray array];

    NSDictionary *active = @{
        @"schema": @"ipfaker.active_profile/2",
        @"generated_from": @"iPFaker.app",
        @"device_id": deviceId ?: @"",
        @"ios": ios ?: @"",
        @"flat": flat ?: @{},
        @"model": @{
            @"ProductType": flat[@"ProductType"] ?: @"",
            @"MarketingName": flat[@"MarketingName"] ?: @"",
            @"HWModelStr": flat[@"HWModelStr"] ?: @"",
            @"PhysicalMemoryMB": flat[@"PhysicalMemoryMB"] ?: @0,
            @"ChipName": flat[@"ChipName"] ?: @"",
        },
        @"os": @{
            @"ProductVersion": flat[@"ProductVersion"] ?: @"",
            @"BuildVersion": flat[@"BuildVersion"] ?: @"",
        },
        @"display": @{
            @"NativeWidth": flat[@"main-screen-width"] ?: @0,
            @"NativeHeight": flat[@"main-screen-height"] ?: @0,
            @"ScreenScale": flat[@"main-screen-scale"] ?: @0,
        },
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:active options:NSJSONWritingPrettyPrinted error:&err];

    for (NSString *dir in dirs) {
        if (![self ensureDir:dir error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"mkdir %@: %@", dir, err.localizedDescription]];
            continue;
        }
        NSString *plistPath = [dir stringByAppendingPathComponent:@"config.plist"];
        NSString *jsonPath = [dir stringByAppendingPathComponent:@"active_profile.json"];
        if (![self writePlist:flat toPath:plistPath error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"plist %@: %@", plistPath, err.localizedDescription]];
            continue;
        }
        if (json && ![json writeToFile:jsonPath options:NSDataWritingAtomic error:&err]) {
            [failMsgs addObject:[NSString stringWithFormat:@"json %@: %@", jsonPath, err.localizedDescription]];
            continue;
        }
        [okPaths addObject:dir];
    }

    if (okPaths.count == 0) {
        return [NSString stringWithFormat:@"Apply failed:\n%@", [failMsgs componentsJoinedByString:@"\n"]];
    }
    NSString *msg = [NSString stringWithFormat:@"Applied → %@", [okPaths componentsJoinedByString:@", "]];
    if (failMsgs.count)
        msg = [msg stringByAppendingFormat:@"\n(partial) %@", [failMsgs componentsJoinedByString:@"; "]];
    return msg; // success message (nil means success in header — we return message always; controller treats as OK if starts with Applied)
}

+ (NSDictionary *)loadCurrentFlat {
    NSArray *paths = @[
        @"/var/mobile/Library/iPFaker/config.plist",
        @"/var/jb/etc/ipfaker/config.plist",
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count) return d;
    }
    return nil;
}

+ (void)killZalo {
    // system() is unavailable on iOS SDK — use posix_spawn(killall)
    NSArray<NSString *> *bins = @[
        @"/var/jb/usr/bin/killall",
        @"/usr/bin/killall",
        @"/var/jb/bin/killall",
    ];
    NSArray<NSString *> *names = @[ @"Zalo", @"vn.com.vng.zingalo" ];
    for (NSString *bin in bins) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:bin]) continue;
        for (NSString *name in names) {
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

+ (NSString *)wipeZaloLab {
    [self killZalo];
    // Soft wipe of common prefs only — full wipe stays on PC scripts
    NSArray *hints = @[
        @"/var/mobile/Containers/Data/Application",
    ];
    // Don't rm -rf from app (too dangerous). Instruct user.
    return @"Đã kill Zalo. Wipe container đầy đủ: chạy trên PC scripts/wipe_and_ready.py (an toàn hơn).";
}

@end
