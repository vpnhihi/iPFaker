#import "IPFLicenseManager.h"
#import "IPFCrypto.h"
#import <UIKit/UIKit.h>

static NSString *const kUDDeviceId = @"ipf.lic.deviceId";
static NSString *const kUDKey = @"ipf.lic.key";
static NSString *const kUDActive = @"ipf.lic.session";
static NSString *const kUDActivation = @"ipf.lic.activation";
static NSString *const kUDTotalDays = @"ipf.lic.totalDays";
static NSString *const kUDPausedDays = @"ipf.lic.pausedDays";
static NSString *const kUDPauseStarted = @"ipf.lic.pauseStarted";
static NSString *const kUDFrozenRemain = @"ipf.lic.frozenRemain";

@implementation IPFLicenseManager

+ (instancetype)shared {
    static IPFLicenseManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[IPFLicenseManager alloc] init]; });
    return s;
}

#pragma mark - Device ID

- (NSString *)deviceId {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *cached = [ud stringForKey:kUDDeviceId];
    if (cached.length >= 8) return cached;

    // Prefer persisted file (survives app reinstall somewhat if path kept)
    NSString *path = @"/var/mobile/Library/iPFaker/device_id.txt";
    NSString *fromFile = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    fromFile = [fromFile stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (fromFile.length >= 8) {
        [ud setObject:fromFile forKey:kUDDeviceId];
        return fromFile;
    }

    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: [[NSUUID UUID] UUIDString];
    NSString *raw = [[vendor stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
    if (raw.length > 12) raw = [raw substringToIndex:12];
    NSString *did = [NSString stringWithFormat:@"IPF-%@", raw];

    [ud setObject:did forKey:kUDDeviceId];
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/iPFaker"
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [did writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return did;
}

#pragma mark - Session

- (BOOL)isSessionActive {
    if (![NSUserDefaults.standardUserDefaults boolForKey:kUDActive]) return NO;
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kUDKey];
    if (!key.length) return NO;
    if ([self daysRemaining] <= 0) return NO;
    return YES;
}

- (NSString *)statusSummary {
    if (![self isSessionActive]) {
        return self.lastMessage.length ? self.lastMessage : @"Chưa kích hoạt key";
    }
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kUDKey] ?: @"—";
    return [NSString stringWithFormat:@"Key: %@ · Còn %ld ngày · ID: %@",
            key, (long)[self daysRemaining], [self deviceId]];
}

- (NSInteger)daysRemaining {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSInteger frozen = [ud integerForKey:kUDFrozenRemain];
    if (frozen > 0 && ![ud boolForKey:kUDActive]) {
        // paused / logged out with freeze
        return frozen;
    }
    NSTimeInterval act = [ud doubleForKey:kUDActivation];
    NSInteger total = [ud integerForKey:kUDTotalDays];
    if (act <= 0 || total <= 0) return 0;
    NSTimeInterval paused = [ud doubleForKey:kUDPausedDays];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval used = (now - act) - paused;
    if (used < 0) used = 0;
    NSInteger usedDays = (NSInteger)floor(used / 86400.0);
    NSInteger left = total - usedDays;
    return left > 0 ? left : 0;
}

#pragma mark - CSV / Sheet

- (void)fetchSheetRows:(void (^)(NSArray<NSArray<NSString *> *> * _Nullable rows, NSError * _Nullable err))done {
    NSString *urlStr = [IPFCrypto sheetCSVURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (done) done(nil, [NSError errorWithDomain:@"ipf.lic" code:1 userInfo:@{NSLocalizedDescriptionKey: @"URL Sheet không hợp lệ"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 25;
    [req setValue:@"iPFaker/2.7" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error || data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done) done(nil, error ?: [NSError errorWithDomain:@"ipf.lic" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Không đọc được Sheet (cần chia sẻ: Anyone with the link can view)"}]);
            });
            return;
        }
        NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!csv) csv = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSArray *rows = [self parseCSV:csv ?: @""];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (done) done(rows, nil);
        });
    }];
    [task resume];
}

- (NSArray<NSArray<NSString *> *> *)parseCSV:(NSString *)csv {
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *lines = [csv componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (!line.length) continue;
        // simple CSV split (handles quoted commas lightly)
        NSMutableArray *cols = [NSMutableArray array];
        NSMutableString *cur = [NSMutableString string];
        BOOL inQ = NO;
        for (NSUInteger i = 0; i < line.length; i++) {
            unichar c = [line characterAtIndex:i];
            if (c == '"') { inQ = !inQ; continue; }
            if (c == ',' && !inQ) {
                [cols addObject:[cur copy]];
                [cur setString:@""];
            } else {
                [cur appendFormat:@"%C", c];
            }
        }
        [cols addObject:[cur copy]];
        // pad to 6
        while (cols.count < 6) [cols addObject:@""];
        [rows addObject:cols];
    }
    return rows;
}

- (IPFLicenseStatus)parseStatus:(NSString *)raw {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return IPFLicenseStatusUnknown;
    // Prefer exact Vietnamese labels from Sheet dropdown
    if ([s caseInsensitiveCompare:@"Chạy"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Chay"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Run"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Active"] == NSOrderedSame)
        return IPFLicenseStatusActive;
    if ([s caseInsensitiveCompare:@"Dừng"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Dung"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Stop"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Pause"] == NSOrderedSame)
        return IPFLicenseStatusPaused;
    if ([s caseInsensitiveCompare:@"Out"] == NSOrderedSame ||
        [s caseInsensitiveCompare:@"Logout"] == NSOrderedSame)
        return IPFLicenseStatusOut;
    NSString *low = s.lowercaseString;
    if ([low containsString:@"chạy"] || [low containsString:@"chay"]) return IPFLicenseStatusActive;
    if ([low containsString:@"dừng"] || [low containsString:@"dung"]) return IPFLicenseStatusPaused;
    if ([low containsString:@"out"]) return IPFLicenseStatusOut;
    return IPFLicenseStatusUnknown;
}

- (NSDictionary *)findRowForKey:(NSString *)key inRows:(NSArray *)rows {
    NSString *want = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!want.length) return nil;
    BOOL header = YES;
    for (NSArray *cols in rows) {
        if (header) { header = NO; continue; } // skip STT header
        if (cols.count < 5) continue;
        NSString *b = [cols[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([b caseInsensitiveCompare:want] == NSOrderedSame) {
            return @{
                @"key": b,
                @"days": cols[2] ?: @"0",
                @"device": [cols[3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"",
                @"status": cols[4] ?: @"",
            };
        }
    }
    return nil;
}

#pragma mark - Activate / revalidate

- (void)activateWithKey:(NSString *)key completion:(void (^)(BOOL, NSString *))completion {
    NSString *k = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!k.length) {
        if (completion) completion(NO, @"Nhập key (cột B trên Sheet).");
        return;
    }
    NSString *did = [self deviceId];
    __weak typeof(self) weakSelf = self;
    [self fetchSheetRows:^(NSArray *rows, NSError *err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (err) {
            self.lastMessage = err.localizedDescription;
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        NSDictionary *row = [self findRowForKey:k inRows:rows];
        if (!row) {
            self.lastMessage = @"Không tìm thấy key trên Sheet (cột B).";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        IPFLicenseStatus st = [self parseStatus:row[@"status"]];
        if (st == IPFLicenseStatusPaused) {
            [self applyPausedRemote];
            self.lastMessage = @"Key đang Dừng — không dùng được. Đổi Sheet → Chạy rồi kích lại.";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        if (st == IPFLicenseStatusOut) {
            [self clearAll];
            self.lastMessage = @"Key Out — đã đăng xuất / vô hiệu.";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        if (st != IPFLicenseStatusActive && st != IPFLicenseStatusUnknown) {
            self.lastMessage = @"Tình trạng key không hợp lệ (cần: Chạy).";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        // Unknown with empty status → treat as active for first setup
        NSString *bound = row[@"device"] ?: @"";
        if (!bound.length) {
            self.lastMessage = [NSString stringWithFormat:
                                @"Chưa gán ID máy trên Sheet.\n\n1) Copy ID máy:\n%@\n2) Dán vào cột D cùng dòng key\n3) Cột E = Chạy\n4) Bấm Kích hoạt lại",
                                did];
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        if ([bound caseInsensitiveCompare:did] != NSOrderedSame) {
            self.lastMessage = [NSString stringWithFormat:
                                @"Key đã gắn máy khác.\nSheet: %@\nMáy này: %@", bound, did];
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        NSInteger days = [row[@"days"] integerValue];
        if (days <= 0) days = 1;
        [self commitActiveKey:k totalDays:days];
        self.lastMessage = [NSString stringWithFormat:@"Kích hoạt OK · còn %ld ngày", (long)[self daysRemaining]];
        if (completion) completion(YES, self.lastMessage);
    }];
}

- (void)revalidateWithCompletion:(void (^)(BOOL, NSString *))completion {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kUDKey];
    if (!key.length) {
        if (completion) completion(NO, @"Chưa có key");
        return;
    }
    NSString *did = [self deviceId];
    __weak typeof(self) weakSelf = self;
    [self fetchSheetRows:^(NSArray *rows, NSError *err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (err) {
            // offline grace: keep session if still days left
            if ([self daysRemaining] > 0 && [NSUserDefaults.standardUserDefaults boolForKey:kUDActive]) {
                self.lastMessage = @"Offline — dùng cache local";
                if (completion) completion(YES, self.lastMessage);
            } else {
                self.lastMessage = err.localizedDescription;
                if (completion) completion(NO, self.lastMessage);
            }
            return;
        }
        NSDictionary *row = [self findRowForKey:key inRows:rows];
        if (!row) {
            [self clearAll];
            self.lastMessage = @"Key không còn trên Sheet";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        IPFLicenseStatus st = [self parseStatus:row[@"status"]];
        NSString *bound = row[@"device"] ?: @"";
        if (bound.length && [bound caseInsensitiveCompare:did] != NSOrderedSame) {
            [self clearAll];
            self.lastMessage = @"Key đã chuyển máy khác";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        if (st == IPFLicenseStatusPaused) {
            [self applyPausedRemote];
            self.lastMessage = @"Sheet: Dừng — đã đẩy key khỏi máy (không tính ngày khi dừng).";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        if (st == IPFLicenseStatusOut) {
            [self clearAll];
            self.lastMessage = @"Sheet: Out — đăng xuất key";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        // Active — update total days if sheet changed upward only carefully
        NSInteger sheetDays = [row[@"days"] integerValue];
        if (sheetDays > 0) {
            NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
            // if never activated, set now
            if ([ud doubleForKey:kUDActivation] <= 0) {
                [self commitActiveKey:key totalDays:sheetDays];
            } else {
                [ud setInteger:sheetDays forKey:kUDTotalDays];
                [ud setBool:YES forKey:kUDActive];
                // clear freeze
                [ud setInteger:0 forKey:kUDFrozenRemain];
                NSTimeInterval ps = [ud doubleForKey:kUDPauseStarted];
                if (ps > 0) {
                    NSTimeInterval add = [[NSDate date] timeIntervalSince1970] - ps;
                    [ud setDouble:[ud doubleForKey:kUDPausedDays] + add forKey:kUDPausedDays];
                    [ud setDouble:0 forKey:kUDPauseStarted];
                }
            }
        }
        if ([self daysRemaining] <= 0) {
            [self logout];
            self.lastMessage = @"Hết hạn sử dụng";
            if (completion) completion(NO, self.lastMessage);
            return;
        }
        self.lastMessage = [self statusSummary];
        if (completion) completion(YES, self.lastMessage);
    }];
}

- (void)commitActiveKey:(NSString *)key totalDays:(NSInteger)days {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setObject:key forKey:kUDKey];
    [ud setBool:YES forKey:kUDActive];
    if ([ud doubleForKey:kUDActivation] <= 0) {
        // resume from freeze?
        NSInteger frozen = [ud integerForKey:kUDFrozenRemain];
        if (frozen > 0) {
            // reconstruct activation so remaining ≈ frozen
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            NSTimeInterval act = now - ((days - frozen) * 86400.0);
            [ud setDouble:act forKey:kUDActivation];
            [ud setInteger:0 forKey:kUDFrozenRemain];
            [ud setDouble:0 forKey:kUDPausedDays];
            [ud setDouble:0 forKey:kUDPauseStarted];
        } else {
            [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kUDActivation];
            [ud setDouble:0 forKey:kUDPausedDays];
            [ud setDouble:0 forKey:kUDPauseStarted];
        }
    }
    [ud setInteger:days forKey:kUDTotalDays];
    [ud synchronize];
    [self persistLicenseFile];
}

- (void)applyPausedRemote {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSInteger left = [self daysRemaining];
    if (left > 0) [ud setInteger:left forKey:kUDFrozenRemain];
    if ([ud doubleForKey:kUDPauseStarted] <= 0)
        [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kUDPauseStarted];
    [ud setBool:NO forKey:kUDActive];
    [ud synchronize];
    [self persistLicenseFile];
}

- (void)logout {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSInteger left = [self daysRemaining];
    if (left > 0) [ud setInteger:left forKey:kUDFrozenRemain];
    [ud setBool:NO forKey:kUDActive];
    // keep key + activation for re-login same device
    [ud synchronize];
    [self persistLicenseFile];
    self.lastMessage = @"Đã đăng xuất key trên máy";
}

- (void)clearAll {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud removeObjectForKey:kUDKey];
    [ud setBool:NO forKey:kUDActive];
    [ud setDouble:0 forKey:kUDActivation];
    [ud setInteger:0 forKey:kUDTotalDays];
    [ud setDouble:0 forKey:kUDPausedDays];
    [ud setDouble:0 forKey:kUDPauseStarted];
    [ud setInteger:0 forKey:kUDFrozenRemain];
    [ud synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:[IPFCrypto licenseFilePath] error:nil];
}

- (void)persistLicenseFile {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSDictionary *d = @{
        @"key": [ud stringForKey:kUDKey] ?: @"",
        @"deviceId": [self deviceId],
        @"active": @([ud boolForKey:kUDActive]),
        @"activation": @([ud doubleForKey:kUDActivation]),
        @"totalDays": @([ud integerForKey:kUDTotalDays]),
        @"daysRemaining": @([self daysRemaining]),
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/iPFaker"
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [json writeToFile:[IPFCrypto licenseFilePath] atomically:YES];
}

@end
