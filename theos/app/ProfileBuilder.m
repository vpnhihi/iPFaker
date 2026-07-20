#import "ProfileBuilder.h"
#import <UIKit/UIKit.h>

@implementation ProfileBuilder

+ (NSString *)randomSerial {
    static NSString *alpha = @"ABCDEFGHJKLMNPQRSTUVWXYZ0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:12];
    for (int i = 0; i < 12; i++) {
        u_int32_t r = arc4random_uniform((u_int32_t)alpha.length);
        [s appendFormat:@"%C", [alpha characterAtIndex:r]];
    }
    return s;
}

+ (NSString *)randomMAC {
    return [NSString stringWithFormat:@"F0:18:98:%02X:%02X:%02X",
            arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)];
}

+ (NSString *)randomIMEI {
    NSMutableString *s = [NSMutableString stringWithString:@"35"];
    for (int i = 0; i < 13; i++)
        [s appendFormat:@"%u", arc4random_uniform(10)];
    return [s substringToIndex:15];
}

+ (NSString *)uuidUpper {
    return [[[NSUUID UUID] UUIDString] uppercaseString];
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
    NSString *udid = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]
                      stringByAppendingString:[[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:8]];
    NSString *serial = [self randomSerial];
    NSString *imei = [self randomIMEI];
    NSString *imei2 = [[imei substringToIndex:14] stringByAppendingFormat:@"%d", (int)(([imei characterAtIndex:14] - '0') + 1) % 10];
    NSString *devName = name.length ? name : [NSString stringWithFormat:@"iPhone Lab %@", device[@"id"] ?: @"dev"];

    NSInteger w = [disp[@"NativeWidth"] integerValue] ?: 1170;
    NSInteger h = [disp[@"NativeHeight"] integerValue] ?: 2532;
    NSInteger scale = [disp[@"ScreenScale"] integerValue] ?: 3;
    NSInteger pitch = [disp[@"Pitch"] integerValue] ?: 460;
    NSInteger cores = [device[@"cpuCores"] integerValue] ?: 6;

    return @{
        @"Enabled": @YES,
        @"ProductType": device[@"ProductType"] ?: @"iPhone16,1",
        @"MarketingName": device[@"MarketingName"] ?: @"iPhone",
        @"DeviceName": @"iPhone",
        @"UserAssignedDeviceName": devName,
        @"HWModelStr": device[@"HWModelStr"] ?: @"",
        @"HardwareModel": device[@"HWModelStr"] ?: @"",
        @"ModelNumber": device[@"ModelNumber"] ?: @"",
        @"RegionInfo": @"VN/A",
        @"RegionCode": @"VN",
        @"RegulatoryModelNumber": device[@"RegulatoryModelNumber"] ?: @"",
        @"HardwarePlatform": device[@"HardwarePlatform"] ?: @"",
        @"CPUArchitecture": device[@"CPUArchitecture"] ?: @"arm64e",
        @"DeviceClass": @"iPhone",
        @"SerialNumber": serial,
        @"UniqueDeviceID": udid,
        @"UniqueChipID": [NSString stringWithFormat:@"%016llX", ((uint64_t)arc4random() << 32) | arc4random()],
        @"ProductVersion": iosMeta[@"ProductVersion"] ?: iosVer,
        @"BuildVersion": iosMeta[@"BuildVersion"] ?: @"",
        @"ProductBuildVersion": iosMeta[@"BuildVersion"] ?: @"",
        @"IDFA": idfa,
        @"IDFV": idfv,
        @"identifierForVendor": idfv,
        @"InternationalMobileEquipmentIdentity": imei,
        @"InternationalMobileEquipmentIdentity2": imei2,
        @"MobileEquipmentIdentifier": [imei substringToIndex:MIN((NSUInteger)14, imei.length)],
        @"WifiAddress": wifi,
        @"BluetoothAddress": bt,
        @"EthernetMacAddress": wifi,
        @"carrierName": @"Viettel",
        @"carrierMCC": @"452",
        @"carrierMNC": @"04",
        @"carrierISO": @"vn",
        @"carrierRadioAccess": @"CTRadioAccessTechnologyNR",
        @"CarrierName": @"Viettel",
        @"MobileCountryCode": @"452",
        @"MobileNetworkCode": @"04",
        @"ISOCountryCode": @"vn",
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
    // Best-effort; works on JB when sandbox allows
    system("killall -9 Zalo 2>/dev/null");
    system("killall -9 vn.com.vng.zingalo 2>/dev/null");
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
