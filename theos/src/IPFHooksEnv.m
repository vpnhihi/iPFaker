// Env surfaces moved from Extra(MG) → CT for Dopamine AMFI MG size budget.
#import "IPFHooksEnv.h"
#import "IPFConfig.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>

typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);
static MSHookMessageEx_t pMSHookMessageExEnv = NULL;

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

#pragma mark - Sensors availability

static id (*orig_accelerometerData)(id, SEL);
static id stub_accelerometerData(id self, SEL _cmd) {
    return orig_accelerometerData ? orig_accelerometerData(self, _cmd) : nil;
}

static BOOL (*orig_isAccelAvailable)(id, SEL);
static BOOL stub_isAccelAvailable(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeSensor" defaultYes:YES]) return YES;
    return orig_isAccelAvailable ? orig_isAccelAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isGyroAvailable)(id, SEL);
static BOOL stub_isGyroAvailable(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeSensor" defaultYes:YES]) return YES;
    return orig_isGyroAvailable ? orig_isGyroAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isDeviceMotionAvailable)(id, SEL);
static BOOL stub_isDeviceMotionAvailable(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeSensor" defaultYes:YES]) return YES;
    return orig_isDeviceMotionAvailable ? orig_isDeviceMotionAvailable(self, _cmd) : YES;
}
static BOOL (*orig_isMagnetometerAvailable)(id, SEL);
static BOOL stub_isMagnetometerAvailable(id self, SEL _cmd) {
    if ([[IPFConfig shared] flag:@"FakeSensor" defaultYes:YES]) return YES;
    return orig_isMagnetometerAvailable ? orig_isMagnetometerAvailable(self, _cmd) : YES;
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
        IPFEnvTrace(@"CMMotionManager hooks OK");
    }

    IPFEnvTrace(@"IPFInstallEnvHooks done");
}
