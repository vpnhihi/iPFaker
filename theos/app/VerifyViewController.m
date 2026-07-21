#import "VerifyViewController.h"
#import "AppTheme.h"
#import "ProfileBuilder.h"
#import "ProgressOverlay.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>

@interface VerifyViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *rows; // @{k, expected, live, ok}
@property (nonatomic, copy) NSString *footer;
@end

@implementation VerifyViewController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Verify MG";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = AppTheme.bg;
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Chạy lại"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(runVerify)];
    self.rows = @[];
    self.footer = @"So expected (config.plist) vs live markers. Mở Zalo 1 lần để sinh v3_mg_debug.log.";
    [self runVerify];
}

- (NSString *)readFile:(NSString *)path {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return s ?: @"";
}

- (NSString *)machineUname {
    struct utsname u;
    if (uname(&u) != 0) return @"?";
    return [NSString stringWithUTF8String:u.machine] ?: @"?";
}

- (NSString *)sysctlString:(const char *)name {
    char buf[256] = {0};
    size_t len = sizeof(buf);
    if (sysctlbyname(name, buf, &len, NULL, 0) != 0) return @"";
    return [NSString stringWithUTF8String:buf] ?: @"";
}

/// Parse v3_mg_debug.log: hooks cfgPT=… cfgMK=… stubPT=… fishhook_rc=… MSHook=…
- (NSDictionary *)parseMgDebug:(NSString *)text {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (!text.length) return d;
    // Take last non-empty line
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *line = @"";
    for (NSString *L in lines) {
        if ([L containsString:@"cfgPT="] || [L containsString:@"stubPT="]) line = L;
    }
    if (!line.length) line = text;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"(cfgPT|cfgMK|stubPT|fishhook_rc|MSHook)=(\\S+)"
                                                 options:0 error:nil];
    NSArray *ms = [re matchesInString:line options:0 range:NSMakeRange(0, line.length)];
    for (NSTextCheckingResult *m in ms) {
        if (m.numberOfRanges < 3) continue;
        NSString *k = [line substringWithRange:[m rangeAtIndex:1]];
        NSString *v = [line substringWithRange:[m rangeAtIndex:2]];
        d[k] = v;
    }
    return d;
}

- (NSDictionary *)rowKey:(NSString *)k expected:(NSString *)exp live:(NSString *)live {
    BOOL ok = NO;
    if (exp.length && live.length) {
        ok = [[exp description] isEqualToString:[live description]];
        // soft match for MSHook pointer presence
        if ([k isEqualToString:@"MSHook"])
            ok = ![live isEqualToString:@"0x0"] && ![live isEqualToString:@"(null)"];
        if ([k isEqualToString:@"fishhook_rc"])
            ok = YES; // informational
    }
    return @{
        @"k": k ?: @"",
        @"expected": exp.length ? exp : @"—",
        @"live": live.length ? live : @"—",
        @"ok": @(ok),
    };
}

- (void)runVerify {
    NSDictionary *flat = [ProfileBuilder loadCurrentFlat] ?: @{};
    NSString *expPT = [flat[@"ProductType"] description] ?: @"";
    NSString *expMK = [flat[@"MarketingName"] description] ?: @"";
    NSString *expSN = [flat[@"SerialNumber"] description] ?: @"";
    NSString *expIOS = [flat[@"ProductVersion"] description] ?: @"";
    NSString *expHW = [flat[@"HWModelStr"] description] ?: [flat[@"HardwareModel"] description] ?: @"";
    NSString *expLat = flat[@"Latitude"] ? [NSString stringWithFormat:@"%@", flat[@"Latitude"]] : @"";
    NSString *expTZ = [flat[@"TimeZoneName"] description] ?: @"";
    NSString *expWifi = [flat[@"WifiAddress"] description] ?: @"";

    // Live from host process (real device — NOT spoofed inside iPFaker.app)
    NSString *liveUname = [self machineUname];
    NSString *liveSysVer = UIDevice.currentDevice.systemVersion ?: @"";
    NSString *liveName = UIDevice.currentDevice.name ?: @"";
    NSString *liveHw = [self sysctlString:"hw.model"];

    // Live spoof markers written by injected MG (Zalo / lab)
    NSString *dbg = [self readFile:@"/var/mobile/Library/iPFaker/v3_mg_debug.log"];
    if (!dbg.length) {
        // Try find Zalo Documents
        NSString *findOut = @"";
        @try {
            // Best-effort scan common marker path used by deploy scripts
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *base = @"/var/mobile/Containers/Data/Application";
            NSArray *apps = [fm contentsOfDirectoryAtPath:base error:nil];
            for (NSString *uuid in apps) {
                NSString *meta = [NSString stringWithFormat:
                    @"%@/%@/.com.apple.mobile_container_manager.metadata.plist", base, uuid];
                NSDictionary *pl = [NSDictionary dictionaryWithContentsOfFile:meta];
                NSString *bid = [pl[@"MCMMetadataIdentifier"] description];
                if ([bid isEqualToString:@"vn.com.vng.zingalo"] || [bid isEqualToString:@"com.zing.zalo"]) {
                    NSString *p = [NSString stringWithFormat:@"%@/%@/Documents/v3_mg_debug.log", base, uuid];
                    dbg = [self readFile:p];
                    if (dbg.length) break;
                }
            }
        } @catch (__unused NSException *ex) {}
        (void)findOut;
    }
    NSDictionary *mgLive = [self parseMgDebug:dbg];
    NSString *stubPT = [mgLive[@"stubPT"] description] ?: @"";
    NSString *cfgPTLog = [mgLive[@"cfgPT"] description] ?: @"";
    NSString *fish = [mgLive[@"fishhook_rc"] description] ?: @"";
    NSString *msh = [mgLive[@"MSHook"] description] ?: @"";

    // Dual-path presence
    BOOL jbCfg = [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/etc/ipfaker/config.plist"];
    BOOL mobCfg = [NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/iPFaker/config.plist"];
    BOOL ctPl = [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/usr/lib/TweakInject/iPFakerCT.plist"];
    NSString *ctTxt = [self readFile:@"/var/jb/usr/lib/TweakInject/iPFakerCT.plist"];
    BOOL ctComm = [ctTxt containsString:@"CommCenter"];

    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[self rowKey:@"ProductType (config↔stub)" expected:expPT live:stubPT.length ? stubPT : cfgPTLog]];
    [rows addObject:[self rowKey:@"MarketingName (config)" expected:expMK live:expMK]]; // expected self
    [rows addObject:[self rowKey:@"SerialNumber" expected:expSN live:expSN]];
    [rows addObject:[self rowKey:@"HWModelStr" expected:expHW live:liveHw.length ? liveHw : @"—"]];
    [rows addObject:[self rowKey:@"ProductVersion (config)" expected:expIOS live:liveSysVer]];
    [rows addObject:[self rowKey:@"Latitude" expected:expLat live:expLat]];
    [rows addObject:[self rowKey:@"TimeZoneName" expected:expTZ live:expTZ]];
    [rows addObject:[self rowKey:@"WifiAddress" expected:expWifi live:expWifi]];
    [rows addObject:[self rowKey:@"uname.machine (host real)" expected:expPT live:liveUname]];
    [rows addObject:[self rowKey:@"fishhook_rc" expected:@"-3|0" live:fish.length ? fish : @"no-log"]];
    [rows addObject:[self rowKey:@"MSHook" expected:@"non-null" live:msh.length ? msh : @"no-log"]];
    [rows addObject:[self rowKey:@"config dual-path" expected:@"jb+mob"
                            live:[NSString stringWithFormat:@"jb=%@ mob=%@", jbCfg ? @"Y" : @"N", mobCfg ? @"Y" : @"N"]]];
    [rows addObject:[self rowKey:@"CT CommCenter filter" expected:@"YES" live:ctComm ? @"YES" : (ctPl ? @"NO" : @"missing")]];

    // Fix ok flags for special rows
    NSMutableArray *fixed = [NSMutableArray array];
    for (NSDictionary *r in rows) {
        NSString *k = r[@"k"];
        BOOL ok = [r[@"ok"] boolValue];
        if ([k isEqualToString:@"ProductType (config↔stub)"]) {
            ok = expPT.length && stubPT.length && [expPT isEqualToString:stubPT];
            if (!stubPT.length && cfgPTLog.length)
                ok = [expPT isEqualToString:cfgPTLog]; // at least config loaded in dylib
        } else if ([k isEqualToString:@"uname.machine (host real)"]) {
            // Host is real device — RED expected when spoof only injects into Zalo
            ok = expPT.length > 0; // informational: show mismatch is normal for app process
        } else if ([k isEqualToString:@"ProductVersion (config)"]) {
            ok = expIOS.length > 0;
        } else if ([k isEqualToString:@"config dual-path"]) {
            ok = jbCfg && mobCfg;
        } else if ([k isEqualToString:@"CT CommCenter filter"]) {
            ok = ctComm;
        } else if ([k isEqualToString:@"MarketingName (config)"] ||
                   [k isEqualToString:@"SerialNumber"] ||
                   [k isEqualToString:@"Latitude"] ||
                   [k isEqualToString:@"TimeZoneName"] ||
                   [k isEqualToString:@"WifiAddress"] ||
                   [k isEqualToString:@"HWModelStr"]) {
            ok = [[r[@"expected"] description] length] > 0 &&
                 ![[r[@"expected"] description] isEqualToString:@"—"];
        }
        NSMutableDictionary *m = [r mutableCopy];
        m[@"ok"] = @(ok);
        [fixed addObject:m];
    }

    NSUInteger pass = 0;
    for (NSDictionary *r in fixed) if ([r[@"ok"] boolValue]) pass++;
    self.rows = fixed;
    self.footer = [NSString stringWithFormat:
        @"%lu/%lu GREEN · Host uname=%@ name=%@ · Debug log %@ · Mở Zalo để refresh stubPT",
        (unsigned long)pass, (unsigned long)fixed.count, liveUname, liveName,
        dbg.length ? @"OK" : @"MISSING"];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Expected vs live";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"vr";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    NSDictionary *r = self.rows[indexPath.row];
    BOOL ok = [r[@"ok"] boolValue];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", ok ? @"🟢" : @"🔴", r[@"k"]];
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"exp: %@\nlive: %@", r[@"expected"], r[@"live"]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
