// Env surfaces moved from Extra(MG) → CT for Dopamine AMFI MG size budget.
// Sensors: handler wrap + data-object getters (no CMAcceleration stret return hooks on the manager).
// Metal: name/description/registryID string surfaces synced to spoof profile.
#import "IPFHooksEnv.h"
#import "IPFConfig.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <stdint.h>
#import <string.h>

typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);
static MSHookMessageEx_t pMSHookMessageExEnv = NULL;

// CoreMotion vector (3 doubles) — used only as local value type when calling through orig IMP
typedef struct { double x, y, z; } IPFVec3;
typedef struct { double x, y, z; } IPFRotation; // same layout as CMRotationRate
typedef struct { double x, y, z; double accuracy; } IPFMag; // CMMagneticField-ish

static void IPFEnvTrace(NSString *s) {
    @try {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;
        NSString *path = [home stringByAppendingPathComponent:@"Documents/ipfaker_extra.log"];
        NSString *row = [NSString stringWithFormat:@"%0.3f [Env] %@\n", CFAbsoluteTimeGetCurrent(), s];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) {
            [row writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [h seekToEndOfFile];
            [h writeData:[row dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (__unused NSException *ex) {}
}

#pragma mark - Locale / TZ / Date

static NSArray *(*orig_preferredLanguages)(id, SEL);
static NSArray *stub_preferredLanguages(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES])
        return orig_preferredLanguages ? orig_preferredLanguages(self, _cmd) : nil;
    NSString *lang = [[IPFConfig shared] stringForKey:@"PreferredLanguage"]
        ?: [[IPFConfig shared] stringForKey:@"LocaleIdentifier"]
        ?: [[IPFConfig shared] stringForKey:@"AppleLocale"];
    if (!lang.length) lang = @"vi-VN";
    lang = [lang stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return @[ lang ];
}

static NSLocale *(*orig_currentLocale)(id, SEL);
static NSLocale *stub_currentLocale(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES])
        return orig_currentLocale ? orig_currentLocale(self, _cmd) : [NSLocale currentLocale];
    NSString *ident = [[IPFConfig shared] stringForKey:@"LocaleIdentifier"]
        ?: [[IPFConfig shared] stringForKey:@"AppleLocale"]
        ?: @"vi_VN";
    ident = [ident stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSLocale *loc = [[NSLocale alloc] initWithLocaleIdentifier:ident];
    return loc ?: (orig_currentLocale ? orig_currentLocale(self, _cmd) : nil);
}

static NSTimeZone *(*orig_systemTZ)(id, SEL);
static NSTimeZone *(*orig_defaultTZ)(id, SEL);
static NSTimeZone *(*orig_localTZ)(id, SEL);

static NSTimeZone *IPFTimeZone(void) {
    NSString *name = [[IPFConfig shared] stringForKey:@"TimeZoneName"] ?: @"Asia/Ho_Chi_Minh";
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:name];
    if (!tz) tz = [NSTimeZone timeZoneWithName:@"Asia/Bangkok"];
    return tz ?: [NSTimeZone systemTimeZone];
}

static NSTimeZone *stub_systemTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_systemTZ ? orig_systemTZ(self, _cmd) : [NSTimeZone systemTimeZone];
    return IPFTimeZone();
}
static NSTimeZone *stub_defaultTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_defaultTZ ? orig_defaultTZ(self, _cmd) : [NSTimeZone defaultTimeZone];
    return IPFTimeZone();
}
static NSTimeZone *stub_localTZ(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocale" defaultYes:YES]
        && ![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO])
        return orig_localTZ ? orig_localTZ(self, _cmd) : [NSTimeZone localTimeZone];
    return IPFTimeZone();
}

static NSDate *(*orig_date)(id, SEL);
static NSDate *stub_date(id self, SEL _cmd) {
    NSDate *real = orig_date ? orig_date(self, _cmd) : [NSDate date];
    if (![[IPFConfig shared] flag:@"FakeDateTime" defaultYes:NO]) return real;
    double off = [[IPFConfig shared] doubleForKey:@"TimeOffsetSeconds" fallback:0];
    if (fabs(off) < 0.5) return real;
    return [real dateByAddingTimeInterval:off];
}

#pragma mark - Location

static id (*orig_location)(id, SEL);
static id stub_location(id self, SEL _cmd) {
    if (![[IPFConfig shared] flag:@"FakeLocation" defaultYes:NO])
        return orig_location ? orig_location(self, _cmd) : nil;
    @try {
        Class CLLoc = objc_getClass("CLLocation");
        if (!CLLoc) return orig_location ? orig_location(self, _cmd) : nil;
        double lat = [[IPFConfig shared] doubleForKey:@"Latitude" fallback:10.8231];
        double lon = [[IPFConfig shared] doubleForKey:@"Longitude" fallback:106.6297];
        double acc = [[IPFConfig shared] doubleForKey:@"LocationAccuracy" fallback:10.0];
        SEL simple = NSSelectorFromString(@"initWithLatitude:longitude:");
        id loc = nil;
        if ([CLLoc instancesRespondToSelector:simple]) {
            id obj = [CLLoc alloc];
            loc = ((id (*)(id, SEL, double, double))objc_msgSend)(obj, simple, lat, lon);
        }
        if (loc) {
            IPFEnvTrace([NSString stringWithFormat:@"CLLocation FAKE lat=%.6f lon=%.6f acc=%.1f", lat, lon, acc]);
            return loc;
        }
    } @catch (__unused NSException *ex) {}
    return orig_location ? orig_location(self, _cmd) : nil;
}

static void (*orig_startUpdating)(id, SEL);
static void stub_startUpdating(id self, SEL _cmd) {
    if (orig_startUpdating) orig_startUpdating(self, _cmd);
    if (![[IPFConfig shared] flag:@"FakeLocation" defaultYes:NO]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            id del = nil;
            if ([self respondsToSelector:@selector(delegate)])
                del = [self performSelector:@selector(delegate)];
            id loc = stub_location(self, @selector(location));
            if (del && loc) {
                SEL s = NSSelectorFromString(@"locationManager:didUpdateLocations:");
                if ([del respondsToSelector:s]) {
                    NSMethodSignature *sig = [del methodSignatureForSelector:s];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setSelector:s];
                    [inv setTarget:del];
                    id mgr = self;
                    NSArray *arr = @[ loc ];
                    [inv setArgument:&mgr atIndex:2];
                    [inv setArgument:&arr atIndex:3];
                    [inv invoke];
                }
            }
        } @catch (__unused NSException *ex) {}
    });
}

#pragma mark - Sensor seed (profile-synced virtual IMU fingerprint)

static uint32_t IPFSensorHash(void) {
    IPFConfig *cfg = [IPFConfig shared];
    NSString *seed = [cfg stringForKey:@"SerialNumber"]
        ?: [cfg stringForKey:@"UniqueDeviceID"]
        ?: [cfg stringForKey:@"ProductType"]
        ?: @"iPhone";
    uint32_t h = 2166136261u;
    const char *s = seed.UTF8String ?: "x";
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h;
}

/// Bias + gentle synthetic motion so samples are NOT raw host; same profile → same base offset
static void IPFSensorSeedBias(double *bx, double *by, double *bz) {
    uint32_t h = IPFSensorHash();
    if (bx) *bx = ((int)(h & 0xFF) - 128) / 6400.0;
    if (by) *by = ((int)((h >> 8) & 0xFF) - 128) / 6400.0;
    if (bz) *bz = ((int)((h >> 16) & 0xFF) - 128) / 12800.0;
}

static void IPFApplyVecBias(IPFVec3 *v, double scale) {
    if (!v) return;
    double bx, by, bz;
    IPFSensorSeedBias(&bx, &by, &bz);
    // Micro motion from time so not perfectly static (still deterministic-ish per seed phase)
    double t = CFAbsoluteTimeGetCurrent();
    uint32_t h = IPFSensorHash();
    double phase = (h & 0xFFFF) / 65535.0 * 6.28318;
    double wobble = 0.002 * scale;
    v->x += bx * scale + sin(t * 1.7 + phase) * wobble;
    v->y += by * scale + cos(t * 1.3 + phase) * wobble;
    v->z += bz * scale + sin(t * 0.9 + phase * 0.5) * wobble * 0.5;
}

static BOOL IPFFakeSensorOn(void) {
    return [[IPFConfig shared] flag:@"FakeSensor" defaultYes:YES];
}

#pragma mark - CM*Data getters (apply bias to real samples — virtual IMU fingerprint)

// Use IMP function pointers with IPFVec3 return — ElleKit handles register/stret layout.
static IPFVec3 (*orig_accel_acc)(id, SEL);
static IPFVec3 stub_accel_acc(id self, SEL _cmd) {
    IPFVec3 v = {0, 0, 0};
    if (orig_accel_acc) v = orig_accel_acc(self, _cmd);
    if (IPFFakeSensorOn()) IPFApplyVecBias(&v, 1.0);
    return v;
}

static IPFRotation (*orig_gyro_rate)(id, SEL);
static IPFRotation stub_gyro_rate(id self, SEL _cmd) {
    IPFRotation v = {0, 0, 0};
    if (orig_gyro_rate) v = orig_gyro_rate(self, _cmd);
    if (IPFFakeSensorOn()) {
        IPFVec3 t = { v.x, v.y, v.z };
        IPFApplyVecBias(&t, 0.15); // gyro smaller bias
        v.x = t.x; v.y = t.y; v.z = t.z;
    }
    return v;
}

static IPFVec3 (*orig_dm_gravity)(id, SEL);
static IPFVec3 stub_dm_gravity(id self, SEL _cmd) {
    IPFVec3 v = {0, 0, -1};
    if (orig_dm_gravity) v = orig_dm_gravity(self, _cmd);
    if (IPFFakeSensorOn()) IPFApplyVecBias(&v, 0.05);
    return v;
}

static IPFVec3 (*orig_dm_userAcc)(id, SEL);
static IPFVec3 stub_dm_userAcc(id self, SEL _cmd) {
    IPFVec3 v = {0, 0, 0};
    if (orig_dm_userAcc) v = orig_dm_userAcc(self, _cmd);
    if (IPFFakeSensorOn()) IPFApplyVecBias(&v, 0.8);
    return v;
}

static IPFRotation (*orig_dm_rot)(id, SEL);
static IPFRotation stub_dm_rot(id self, SEL _cmd) {
    IPFRotation v = {0, 0, 0};
    if (orig_dm_rot) v = orig_dm_rot(self, _cmd);
    if (IPFFakeSensorOn()) {
        IPFVec3 t = { v.x, v.y, v.z };
        IPFApplyVecBias(&t, 0.12);
        v.x = t.x; v.y = t.y; v.z = t.z;
    }
    return v;
}

#pragma mark - CMMotionManager handler wraps

static void (*orig_startAccelH)(id, SEL, id, id);
static void stub_startAccelH(id self, SEL _cmd, id queue, id handler) {
    if (!IPFFakeSensorOn() || !handler) {
        if (orig_startAccelH) orig_startAccelH(self, _cmd, queue, handler);
        return;
    }
    // Wrap: getters on CMAccelerometerData already bias; keep path alive + log once
    void (^h)(id, id) = handler;
    void (^wrap)(id, id) = ^(id data, id err) {
        // Data object getters are hooked — pass through
        if (h) h(data, err);
    };
    if (orig_startAccelH) orig_startAccelH(self, _cmd, queue, wrap);
    else if (h) { /* no-op */ }
    static int once = 0;
    if (!once) { once = 1; IPFEnvTrace(@"accel handler wrap ON (profile-seeded IMU)"); }
}

static void (*orig_startGyroH)(id, SEL, id, id);
static void stub_startGyroH(id self, SEL _cmd, id queue, id handler) {
    if (!IPFFakeSensorOn() || !handler) {
        if (orig_startGyroH) orig_startGyroH(self, _cmd, queue, handler);
        return;
    }
    void (^h)(id, id) = handler;
    void (^wrap)(id, id) = ^(id data, id err) { if (h) h(data, err); };
    if (orig_startGyroH) orig_startGyroH(self, _cmd, queue, wrap);
    static int once = 0;
    if (!once) { once = 1; IPFEnvTrace(@"gyro handler wrap ON"); }
}

static void (*orig_startMotionH)(id, SEL, id, id);
static void stub_startMotionH(id self, SEL _cmd, id queue, id handler) {
    if (!IPFFakeSensorOn() || !handler) {
        if (orig_startMotionH) orig_startMotionH(self, _cmd, queue, handler);
        return;
    }
    void (^h)(id, id) = handler;
    void (^wrap)(id, id) = ^(id data, id err) { if (h) h(data, err); };
    if (orig_startMotionH) orig_startMotionH(self, _cmd, queue, wrap);
    static int once = 0;
    if (!once) { once = 1; IPFEnvTrace(@"deviceMotion handler wrap ON"); }
}

// Reference-frame variants (common risk SDK path)
static void (*orig_startMotionRefH)(id, SEL, int, id, id);
static void stub_startMotionRefH(id self, SEL _cmd, int ref, id queue, id handler) {
    if (!IPFFakeSensorOn() || !handler) {
        if (orig_startMotionRefH) orig_startMotionRefH(self, _cmd, ref, queue, handler);
        return;
    }
    void (^h)(id, id) = handler;
    void (^wrap)(id, id) = ^(id data, id err) { if (h) h(data, err); };
    if (orig_startMotionRefH) orig_startMotionRefH(self, _cmd, ref, queue, wrap);
}

static id (*orig_accelerometerData)(id, SEL);
static id stub_accelerometerData(id self, SEL _cmd) {
    // Object path; acceleration getter applies bias
    return orig_accelerometerData ? orig_accelerometerData(self, _cmd) : nil;
}

static BOOL (*orig_isAccelAvailable)(id, SEL);
static BOOL stub_isAccelAvailable(id self, SEL _cmd) {
    if (IPFFakeSensorOn()) return YES;
    return orig_isAccelAvailable ? orig_isAccelAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isGyroAvailable)(id, SEL);
static BOOL stub_isGyroAvailable(id self, SEL _cmd) {
    if (IPFFakeSensorOn()) return YES;
    return orig_isGyroAvailable ? orig_isGyroAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isDeviceMotionAvailable)(id, SEL);
static BOOL stub_isDeviceMotionAvailable(id self, SEL _cmd) {
    if (IPFFakeSensorOn()) return YES;
    return orig_isDeviceMotionAvailable ? orig_isDeviceMotionAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isMagnetometerAvailable)(id, SEL);
static BOOL stub_isMagnetometerAvailable(id self, SEL _cmd) {
    if (IPFFakeSensorOn()) return YES;
    return orig_isMagnetometerAvailable ? orig_isMagnetometerAvailable(self, _cmd) : YES;
}

#pragma mark - Metal / GPU string + registryID surfaces

static BOOL IPFFakeGPUOn(void) {
    // Tie to FakeHardware/FakeDevice — GPU name must match spoof chip catalog
    return [[IPFConfig shared] flag:@"FakeHardware" defaultYes:YES]
        || [[IPFConfig shared] flag:@"FakeDevice" defaultYes:YES];
}

static NSString *IPFMetalName(void) {
    IPFConfig *cfg = [IPFConfig shared];
    NSString *n = [cfg stringForKey:@"MetalDeviceName"]
        ?: [cfg stringForKey:@"GPUName"]
        ?: [cfg stringForKey:@"ChipName"];
    if (!n.length) return nil;
    if ([n rangeOfString:@"GPU"].location != NSNotFound) return n;
    if ([n hasPrefix:@"Apple "]) return [n stringByAppendingString:@" GPU"];
    // "A17 Pro" / "A12 Bionic" → Apple style
    NSString *c = [n stringByReplacingOccurrencesOfString:@" Bionic" withString:@""];
    return [NSString stringWithFormat:@"Apple %@ GPU", c];
}

static uint64_t IPFMetalRegistryID(void) {
    IPFConfig *cfg = [IPFConfig shared];
    NSString *s = [cfg stringForKey:@"MetalRegistryID"];
    if (s.length) {
        unsigned long long v = strtoull(s.UTF8String, NULL, 0);
        if (v) return (uint64_t)v;
    }
    id num = [cfg mgValueForKey:@"MetalRegistryID"];
    if ([num isKindOfClass:[NSNumber class]])
        return (uint64_t)[(NSNumber *)num unsignedLongLongValue];
    // Deterministic synthetic IOKit-style id from spoof serial (not host GPU die id)
    uint32_t h = IPFSensorHash();
    return 0x0000000100000000ULL | ((uint64_t)h << 8) | 0xA1ULL;
}

static NSString *(*orig_mtl_name)(id, SEL);
static NSString *stub_mtl_name(id self, SEL _cmd) {
    if (IPFFakeGPUOn()) {
        NSString *n = IPFMetalName();
        if (n.length) return n;
    }
    return orig_mtl_name ? orig_mtl_name(self, _cmd) : nil;
}

static NSString *(*orig_mtl_desc)(id, SEL);
static NSString *stub_mtl_desc(id self, SEL _cmd) {
    if (IPFFakeGPUOn()) {
        NSString *n = IPFMetalName();
        if (n.length) return n;
    }
    return orig_mtl_desc ? orig_mtl_desc(self, _cmd) : nil;
}

static uint64_t (*orig_mtl_regid)(id, SEL);
static uint64_t stub_mtl_regid(id self, SEL _cmd) {
    if (IPFFakeGPUOn())
        return IPFMetalRegistryID();
    return orig_mtl_regid ? orig_mtl_regid(self, _cmd) : 0;
}

#pragma mark - Install

void IPFInstallEnvHooks(void) {
    if (!pMSHookMessageExEnv) {
        void *h = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
        if (!h) h = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_NOW);
        if (h) pMSHookMessageExEnv = (MSHookMessageEx_t)dlsym(h, "MSHookMessageEx");
        if (!pMSHookMessageExEnv)
            pMSHookMessageExEnv = (MSHookMessageEx_t)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    }
    if (!pMSHookMessageExEnv) {
        IPFEnvTrace(@"IPFInstallEnvHooks skip");
        return;
    }
    IPFEnvTrace(@"IPFInstallEnvHooks begin");

    Class nsl = object_getClass(objc_getClass("NSLocale"));
    if (nsl) {
        if (class_getClassMethod(objc_getClass("NSLocale"), @selector(preferredLanguages)))
            pMSHookMessageExEnv(nsl, @selector(preferredLanguages), (IMP)stub_preferredLanguages, (IMP *)&orig_preferredLanguages);
        if (class_getClassMethod(objc_getClass("NSLocale"), @selector(currentLocale)))
            pMSHookMessageExEnv(nsl, @selector(currentLocale), (IMP)stub_currentLocale, (IMP *)&orig_currentLocale);
        if (class_getClassMethod(objc_getClass("NSLocale"), @selector(autoupdatingCurrentLocale)))
            pMSHookMessageExEnv(nsl, @selector(autoupdatingCurrentLocale), (IMP)stub_currentLocale, (IMP *)&orig_currentLocale);
        IPFEnvTrace(@"NSLocale hooks OK");
    }
    Class ntz = object_getClass(objc_getClass("NSTimeZone"));
    if (ntz) {
        if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(systemTimeZone)))
            pMSHookMessageExEnv(ntz, @selector(systemTimeZone), (IMP)stub_systemTZ, (IMP *)&orig_systemTZ);
        if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(defaultTimeZone)))
            pMSHookMessageExEnv(ntz, @selector(defaultTimeZone), (IMP)stub_defaultTZ, (IMP *)&orig_defaultTZ);
        if (class_getClassMethod(objc_getClass("NSTimeZone"), @selector(localTimeZone)))
            pMSHookMessageExEnv(ntz, @selector(localTimeZone), (IMP)stub_localTZ, (IMP *)&orig_localTZ);
        IPFEnvTrace(@"NSTimeZone hooks OK");
    }
    Class nd = object_getClass(objc_getClass("NSDate"));
    if (nd && class_getClassMethod(objc_getClass("NSDate"), @selector(date))) {
        pMSHookMessageExEnv(nd, @selector(date), (IMP)stub_date, (IMP *)&orig_date);
        IPFEnvTrace(@"NSDate.date hook OK");
    }

    Class clm = objc_getClass("CLLocationManager");
    if (clm) {
        if (class_getInstanceMethod(clm, @selector(location)))
            pMSHookMessageExEnv(clm, @selector(location), (IMP)stub_location, (IMP *)&orig_location);
        if (class_getInstanceMethod(clm, @selector(startUpdatingLocation)))
            pMSHookMessageExEnv(clm, @selector(startUpdatingLocation), (IMP)stub_startUpdating, (IMP *)&orig_startUpdating);
        IPFEnvTrace(@"CLLocationManager hooks OK");
    }

    // --- IMU ---
    Class cmm = objc_getClass("CMMotionManager");
    if (cmm) {
        if (class_getInstanceMethod(cmm, @selector(isAccelerometerAvailable)))
            pMSHookMessageExEnv(cmm, @selector(isAccelerometerAvailable), (IMP)stub_isAccelAvailable, (IMP *)&orig_isAccelAvailable);
        if (class_getInstanceMethod(cmm, @selector(isGyroAvailable)))
            pMSHookMessageExEnv(cmm, @selector(isGyroAvailable), (IMP)stub_isGyroAvailable, (IMP *)&orig_isGyroAvailable);
        if (class_getInstanceMethod(cmm, @selector(isDeviceMotionAvailable)))
            pMSHookMessageExEnv(cmm, @selector(isDeviceMotionAvailable), (IMP)stub_isDeviceMotionAvailable, (IMP *)&orig_isDeviceMotionAvailable);
        if (class_getInstanceMethod(cmm, @selector(isMagnetometerAvailable)))
            pMSHookMessageExEnv(cmm, @selector(isMagnetometerAvailable), (IMP)stub_isMagnetometerAvailable, (IMP *)&orig_isMagnetometerAvailable);
        if (class_getInstanceMethod(cmm, @selector(accelerometerData)))
            pMSHookMessageExEnv(cmm, @selector(accelerometerData), (IMP)stub_accelerometerData, (IMP *)&orig_accelerometerData);

        SEL sa = NSSelectorFromString(@"startAccelerometerUpdatesToQueue:withHandler:");
        SEL sg = NSSelectorFromString(@"startGyroUpdatesToQueue:withHandler:");
        SEL sm = NSSelectorFromString(@"startDeviceMotionUpdatesToQueue:withHandler:");
        SEL smr = NSSelectorFromString(@"startDeviceMotionUpdatesUsingReferenceFrame:toQueue:withHandler:");
        if (class_getInstanceMethod(cmm, sa))
            pMSHookMessageExEnv(cmm, sa, (IMP)stub_startAccelH, (IMP *)&orig_startAccelH);
        if (class_getInstanceMethod(cmm, sg))
            pMSHookMessageExEnv(cmm, sg, (IMP)stub_startGyroH, (IMP *)&orig_startGyroH);
        if (class_getInstanceMethod(cmm, sm))
            pMSHookMessageExEnv(cmm, sm, (IMP)stub_startMotionH, (IMP *)&orig_startMotionH);
        if (class_getInstanceMethod(cmm, smr))
            pMSHookMessageExEnv(cmm, smr, (IMP)stub_startMotionRefH, (IMP *)&orig_startMotionRefH);
        IPFEnvTrace(@"CMMotionManager + handler wrap OK");
    }

    Class cad = objc_getClass("CMAccelerometerData");
    if (cad && class_getInstanceMethod(cad, @selector(acceleration))) {
        pMSHookMessageExEnv(cad, @selector(acceleration), (IMP)stub_accel_acc, (IMP *)&orig_accel_acc);
        IPFEnvTrace(@"CMAccelerometerData.acceleration bias OK");
    }
    Class cgd = objc_getClass("CMGyroData");
    if (cgd && class_getInstanceMethod(cgd, @selector(rotationRate))) {
        pMSHookMessageExEnv(cgd, @selector(rotationRate), (IMP)stub_gyro_rate, (IMP *)&orig_gyro_rate);
        IPFEnvTrace(@"CMGyroData.rotationRate bias OK");
    }
    Class cdm = objc_getClass("CMDeviceMotion");
    if (cdm) {
        if (class_getInstanceMethod(cdm, @selector(gravity)))
            pMSHookMessageExEnv(cdm, @selector(gravity), (IMP)stub_dm_gravity, (IMP *)&orig_dm_gravity);
        if (class_getInstanceMethod(cdm, @selector(userAcceleration)))
            pMSHookMessageExEnv(cdm, @selector(userAcceleration), (IMP)stub_dm_userAcc, (IMP *)&orig_dm_userAcc);
        if (class_getInstanceMethod(cdm, @selector(rotationRate)))
            pMSHookMessageExEnv(cdm, @selector(rotationRate), (IMP)stub_dm_rot, (IMP *)&orig_dm_rot);
        IPFEnvTrace(@"CMDeviceMotion bias OK");
    }

    // --- Metal GPU name / registryID (runtime, no Metal.framework hard link) ---
    // Hook common concrete device class names used across iOS versions
    const char *mtlClasses[] = {
        "MTLDebugDevice", "MTLToolsDevice", "AGXG14FamilyDevice", "AGXG13XFamilyDevice",
        "AGXG13GFamilyDevice", "AGXG12FamilyDevice", "AGXDevice", "MTLIGAccelDevice",
        NULL
    };
    int mtlHooked = 0;
    for (int i = 0; mtlClasses[i]; i++) {
        Class mc = objc_getClass(mtlClasses[i]);
        if (!mc) continue;
        if (class_getInstanceMethod(mc, @selector(name))) {
            pMSHookMessageExEnv(mc, @selector(name), (IMP)stub_mtl_name, (IMP *)&orig_mtl_name);
            mtlHooked++;
        }
        if (class_getInstanceMethod(mc, @selector(description))) {
            pMSHookMessageExEnv(mc, @selector(description), (IMP)stub_mtl_desc, (IMP *)&orig_mtl_desc);
        }
        SEL rid = @selector(registryID);
        if (class_getInstanceMethod(mc, rid)) {
            pMSHookMessageExEnv(mc, rid, (IMP)stub_mtl_regid, (IMP *)&orig_mtl_regid);
        }
    }
    // Fallback: any class conforming via MTLCreateSystemDefaultDevice runtime class
    void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
    if (metal) {
        id (*MTLCreate)(void) = (id (*)(void))dlsym(metal, "MTLCreateSystemDefaultDevice");
        if (MTLCreate) {
            @try {
                id dev = MTLCreate();
                if (dev) {
                    Class mc = object_getClass(dev);
                    if (mc && class_getInstanceMethod(mc, @selector(name))) {
                        pMSHookMessageExEnv(mc, @selector(name), (IMP)stub_mtl_name, (IMP *)&orig_mtl_name);
                        mtlHooked++;
                    }
                    if (mc && class_getInstanceMethod(mc, @selector(registryID))) {
                        pMSHookMessageExEnv(mc, @selector(registryID), (IMP)stub_mtl_regid, (IMP *)&orig_mtl_regid);
                    }
                    IPFEnvTrace([NSString stringWithFormat:@"Metal live class %@ hooked", NSStringFromClass(mc)]);
                }
            } @catch (__unused NSException *ex) {}
        }
    }
    IPFEnvTrace([NSString stringWithFormat:@"Metal hooks classes~%d name=%@", mtlHooked, IPFMetalName() ?: @"—"]);

    IPFEnvTrace(@"IPFInstallEnvHooks done");
}
