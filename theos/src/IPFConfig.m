// IPFConfig.m — load order mirrors HIOS ChangeInfoIos:
//   1) /var/jb/etc/ipfaker/config.plist  (flat keys, dictionaryWithContentsOfFile)
//   2) active_profile.json fallback

#import "IPFConfig.h"

static NSArray<NSString *> *IPFPlistCandidates(void) {
    // Prefer paths readable from app sandbox (mobile Library first)
    return @[
        @"/var/mobile/Library/iPFaker/config.plist",
        @"/var/mobile/Library/Preferences/com.ipfaker.config.plist",
        @"/var/jb/etc/ipfaker/config.plist",
        @"/var/jb/etc/changeinfoios/config.plist",
    ];
}

static NSArray<NSString *> *IPFJSONCandidates(void) {
    return @[
        @"/var/mobile/Library/iPFaker/active_profile.json",
        @"/var/jb/etc/ipfaker/active_profile.json",
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
@property (nonatomic, strong, readwrite, nullable) NSDictionary *flat; // HIOS-style flat map
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

- (void)applyFlatPlist:(NSDictionary *)flat path:(NSString *)path {
    self.flat = flat;
    self.root = flat;
    self.profilePath = path;
    // Build mgMap / sysctl from flat HIOS keys
    NSMutableDictionary *mg = [NSMutableDictionary dictionary];
    NSMutableDictionary *sys = [NSMutableDictionary dictionary];
    NSArray *mgKeys = @[
        @"ProductType", @"HWModelStr", @"HardwareModel", @"DeviceName", @"UserAssignedDeviceName",
        @"MarketingName", @"SerialNumber", @"UniqueDeviceID", @"UniqueChipID",
        @"ProductVersion", @"BuildVersion", @"ProductBuildVersion",
        @"ModelNumber", @"RegionInfo", @"RegionCode", @"RegulatoryModelNumber",
        @"CPUArchitecture", @"HardwarePlatform", @"DeviceClass",
        @"InternationalMobileEquipmentIdentity", @"InternationalMobileEquipmentIdentity2",
        @"MobileEquipmentIdentifier", @"WifiAddress", @"BluetoothAddress", @"EthernetMacAddress",
        @"main-screen-width", @"main-screen-height", @"main-screen-scale", @"main-screen-pitch",
        @"DeviceColor", @"DeviceEnclosureColor", @"BasebandVersion",
    ];
    for (NSString *k in mgKeys) {
        id v = flat[k];
        if (v) mg[k] = v;
    }
    // Aliases HIOS uses
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
    if (flat[@"DeviceName"] ?: flat[@"UserAssignedDeviceName"]) {
        id n = flat[@"UserAssignedDeviceName"] ?: flat[@"DeviceName"];
        mg[@"UserAssignedDeviceName"] = n;
        mg[@"DeviceName"] = flat[@"DeviceName"] ?: @"iPhone";
        sys[@"kern.hostname"] = n;
    }
    // Marketing name for Zalo UI (critical — Zalo shows "iPhone XS Max" from real type)
    if (flat[@"MarketingName"]) mg[@"MarketingName"] = flat[@"MarketingName"];

    self.mgMap = [mg copy];
    self.sysctlMap = [sys copy];

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
    self.telephony = @{
        @"CarrierName": flat[@"carrierName"] ?: flat[@"CarrierName"] ?: @"",
        @"MobileCountryCode": flat[@"carrierMCC"] ?: flat[@"MobileCountryCode"] ?: @"",
        @"MobileNetworkCode": flat[@"carrierMNC"] ?: flat[@"MobileNetworkCode"] ?: @"",
        @"ISOCountryCode": flat[@"carrierISO"] ?: flat[@"ISOCountryCode"] ?: @"",
        @"RadioAccessTechnology": flat[@"carrierRadioAccess"] ?: flat[@"RadioAccessTechnology"] ?: @"",
        @"CurrentRadioAccessTechnology": flat[@"carrierRadioAccess"] ?: flat[@"CurrentRadioAccessTechnology"] ?: @"",
        @"AllowsVOIP": flat[@"AllowsVOIP"] ?: @YES,
    };
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
        NSString *mkt = self.model[@"MarketingName"] ?: self.model[@"ProductName"] ?: @"iPhone 15 Pro";
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

    // 1) HIOS-style config.plist first
    for (NSString *path in IPFPlistCandidates()) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![plist isKindOfClass:[NSDictionary class]] || plist.count == 0) continue;
        [self applyFlatPlist:plist path:path];
        NSLog(@"[iPFaker] HIOS-style plist config: %@ keys=%lu ProductType=%@",
              path, (unsigned long)plist.count, plist[@"ProductType"]);
        return YES;
    }

    // 2) JSON fallback
    for (NSString *path in IPFJSONCandidates()) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        [self applyJSONRoot:obj path:path];
        NSLog(@"[iPFaker] JSON config: %@ mg=%lu", path, (unsigned long)self.mgMap.count);
        return YES;
    }

    NSLog(@"[iPFaker] config NOT found (need /var/jb/etc/ipfaker/config.plist like HIOS)");
    return NO;
}

- (nullable id)mgValueForKey:(NSString *)key {
    if (!key) return nil;
    id v = self.mgMap[key];
    if (v) return v;
    // flat fallback
    return self.flat[key];
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

@end
