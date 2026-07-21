#import "ProfileBuilder.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <time.h>
#import <stdlib.h>

@implementation ProfileBuilder

// Apple-like synthetic identity (match scripts/select_device_profile.py):
// Serial: no I/O/0/1; pre-2021=12, modern~10; IDFA/IDFV UUID v4; UDID 40 hex; IMEI 8-digit TAC+Luhn

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

    // Wi‑Fi SSID/BSSID — BSSID must equal WifiAddress (CNCopyCurrentNetworkInfo sync)
    NSArray *ssids = @[ @"Viettel-WiFi", @"Viettel", @"VNPT-Fiber", @"FPT-Telecom", @"MyWiFi" ];
    NSString *ssid = ssids[arc4random_uniform((u_int32_t)ssids.count)];
    NSString *bssid = wifi;
    NSString *volumeUUID = [self uuidUpper];

    return @{
        @"Enabled": @YES,
        @"ProductType": device[@"ProductType"] ?: @"iPhone16,1",
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
    // Remove root-owned stale file if we cannot overwrite (best-effort)
    if ([fm fileExistsAtPath:path] && ![fm isWritableFileAtPath:path]) {
        [fm removeItemAtPath:path error:nil];
    }
    BOOL ok = [flat writeToURL:[NSURL fileURLWithPath:path] error:err];
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

/// True if metadata plist text contains any of the bundle markers.
+ (BOOL)metadataAtPath:(NSString *)metaPath matchesAny:(NSArray<NSString *> *)needles {
    NSData *data = [NSData dataWithContentsOfFile:metaPath];
    if (!data.length) return NO;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) {
        // binary plist
        id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        s = [obj description];
    }
    if (!s.length) return NO;
    NSString *low = s.lowercaseString;
    for (NSString *n in needles) {
        if (n.length && [low rangeOfString:n.lowercaseString].location != NSNotFound)
            return YES;
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
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:base error:nil] ?: @[]) {
        NSString *root = [base stringByAppendingPathComponent:uuid];
        NSString *meta = [root stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        if ([self metadataAtPath:meta matchesAny:needles])
            [out addObject:root];
    }
    return out;
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
        step([NSString stringWithFormat:@"Đóng tiến trình: %@", bid]);
        [self killAppBundleId:bid executable:nil];
    }
    usleep(350000);
    [log addObject:@"① Đã đóng tiến trình"];

    BOOL wipingZalo = NO;
    for (NSString *b in bundles) {
        if ([b.lowercaseString containsString:@"zalo"] || [b.lowercaseString containsString:@"zing"]) {
            wipingZalo = YES; break;
        }
    }
    if (wipingZalo && !skipScript) {
        step(@"Chạy script xóa sâu (libexec)…");
        NSArray *scripts = @[
            @"/var/jb/usr/libexec/ipfaker-wipe-zalo",
            @"/var/jb/etc/ipfaker/wipe_zalo.sh",
            @"/var/mobile/Library/iPFaker/wipe_zalo.sh",
        ];
        BOOL scriptRan = NO;
        for (NSString *sp in scripts) {
            if (![fm fileExistsAtPath:sp]) continue;
            [fm setAttributes:@{ NSFilePosixPermissions: @0755 } ofItemAtPath:sp error:nil];
            int rc = [self runShellScript:sp args:@[]];
            if (rc >= 0) {
                NSString *m = [NSString stringWithFormat:@"② Script xóa sâu (mã %d)", rc];
                [log addObject:m]; step(m);
                scriptRan = YES;
                break;
            }
        }
        if (!scriptRan) {
            [log addObject:@"② Script: bỏ qua — xóa trực tiếp"];
            step(@"Script không chạy — xóa trực tiếp");
        }
    } else if (skipScript) {
        step(@"Bỏ script xóa sâu (chế độ giữ đăng nhập)");
    }

    step(@"Quét / xóa thư mục dữ liệu app…");
    NSUInteger dataWiped = 0;
    for (NSString *root in [self containerPathsUnder:@"/var/mobile/Containers/Data/Application" matchingNeedles:needles]) {
        step([NSString stringWithFormat:@"Xóa dữ liệu %@", root.lastPathComponent]);
        dataWiped += [self wipeContainerRoot:root fm:fm];
    }
    if (dataWiped == 0) {
        [log addObject:@"③ Dữ liệu: không tìm thấy / đã trống"];
        step(@"Thư mục dữ liệu: trống hoặc không khớp");
    } else {
        [log addObject:[NSString stringWithFormat:@"③ Dữ liệu mục~%lu", (unsigned long)dataWiped]];
    }

    step(@"Quét / xóa nhóm chia sẻ app…");
    NSUInteger groupWiped = 0;
    for (NSString *root in [self containerPathsUnder:@"/var/mobile/Containers/Shared/AppGroup" matchingNeedles:needles]) {
        step([NSString stringWithFormat:@"Xóa nhóm chia sẻ %@", [root.lastPathComponent substringToIndex:MIN((NSUInteger)8, root.lastPathComponent.length)]]);
        groupWiped += [self wipeContainerRoot:root fm:fm];
    }
    [log addObject:groupWiped ? [NSString stringWithFormat:@"④ Nhóm chia sẻ ~%lu", (unsigned long)groupWiped] : @"④ Nhóm chia sẻ: trống"];

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

    if (wipingZalo && !skipKeychain) {
        step(@"Xóa keychain (cố gắng hết sức)…");
        // same as before
        NSString *sqlite = nil;
        for (NSString *c in @[ @"/var/jb/usr/bin/sqlite3", @"/usr/bin/sqlite3" ]) {
            if ([fm isExecutableFileAtPath:c]) { sqlite = c; break; }
        }
        NSString *kcDB = nil;
        for (NSString *p in @[ @"/var/Keychains/keychain-2.db", @"/private/var/Keychains/keychain-2.db" ]) {
            if ([fm isReadableFileAtPath:p]) { kcDB = p; break; }
        }
        if (sqlite && kcDB) {
            for (NSString *pat in @[ @"zalo", @"Zalo", @"zing.zalo", @"vng.zalo" ]) {
                NSString *sql = [NSString stringWithFormat:
                    @"DELETE FROM genp WHERE svce LIKE '%%%@%%' OR acct LIKE '%%%@%%' OR agrp LIKE '%%%@%%';",
                    pat, pat, pat];
                pid_t pid = 0;
                const char *argv[] = { sqlite.UTF8String, kcDB.UTF8String, sql.UTF8String, NULL };
                if (posix_spawn(&pid, sqlite.UTF8String, NULL, NULL, (char *const *)argv, NULL) == 0 && pid > 0) {
                    int st = 0; waitpid(pid, &st, 0);
                }
            }
            [log addObject:@"⑥ Keychain đã dọn"];
            step(@"Keychain: đã dọn");
        } else {
            step(@"Keychain: bỏ qua");
        }
    } else if (skipKeychain) {
        step(@"Giữ keychain (để phiên đăng nhập)");
        [log addObject:@"⑥ Keychain: giữ nguyên"];
    }

    step(@"Đóng lại các tiến trình…");
    for (NSString *bid in bundles) [self killAppBundleId:bid executable:nil];

    step(@"Hoàn tất xóa dữ liệu");
    return [NSString stringWithFormat:
            @"Đã xóa dữ liệu %lu app:\n%@",
            (unsigned long)bundles.count,
            [log componentsJoinedByString:@"\n"]];
}

+ (NSString *)wipeZaloFull {
    return [self wipeApps:@[ @"vn.com.vng.zingalo", @"com.zing.zalo" ] progress:nil];
}

+ (NSString *)wipeZaloLab {
    return [self wipeZaloFull];
}

@end


