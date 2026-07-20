#import "SettingsViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "Catalog.h"

@interface SettingsViewController ()
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@end

@implementation SettingsViewController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = AppTheme.bg;
    self.tableView.separatorColor = AppTheme.separator;
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    // Shadow Tech–style toggles (mapped to lab spoof surface)
    self.sections = @[
        @[
            @{ @"t": @"Fake Device", @"k": @"FakeDevice", @"d": @YES },
            @{ @"t": @"Fake Hardware", @"k": @"FakeHardware", @"d": @YES },
            @{ @"t": @"Fake Ads (IDFA/IDFV)", @"k": @"FakeAds", @"d": @YES },
            @{ @"t": @"Fake Screen", @"k": @"FakeScreen", @"d": @YES },
            @{ @"t": @"Fake Real Screen", @"k": @"FakeRealScreen", @"d": @YES },
            @{ @"t": @"Fake Browser (UA)", @"k": @"FakeBrowser", @"d": @YES },
            @{ @"t": @"Fake Network / Carrier", @"k": @"FakeNetwork", @"d": @YES },
            @{ @"t": @"Fake Wifi Info", @"k": @"FakeWifi", @"d": @YES },
            @{ @"t": @"Fake Sysctl", @"k": @"FakeSysctl", @"d": @YES },
            @{ @"t": @"Fake Sys OSVersion", @"k": @"FakeSysOSVersion", @"d": @YES },
            @{ @"t": @"Hide Jailbreak", @"k": @"HideJailbreak", @"d": @YES },
        ],
        @[
            @{ @"t": @"Fake Locale (vi-VN + TZ)", @"k": @"FakeLocale", @"d": @YES },
            @{ @"t": @"Fake Date Time (boot + offset)", @"k": @"FakeDateTime", @"d": @NO },
            @{ @"t": @"Fake Location (WGS84)", @"k": @"FakeLocation", @"d": @YES },
            @{ @"t": @"Fake Sensor", @"k": @"FakeSensor", @"d": @YES },
            @{ @"t": @"Fake WebRTC (local IP)", @"k": @"FakeWebRTC", @"d": @YES },
            @{ @"t": @"Disable WebRTC", @"k": @"DisableWebRTC", @"d": @NO },
        ],
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < (NSInteger)self.sections.count)
        return self.sections[section].count;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Fake surface (Zalo spoof)";
    if (section == 1) return @"Tuỳ chọn nâng cao";
    return @"Thông tin";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Mỗi switch bật/tắt hook thật trong Zalo sau Apply. Format: UUID v4, IMEI Luhn, ITU E.212, ISO/BCP-47, IANA TZ, WGS84.";
    if (section == 1)
        return @"Locale vi-VN · TZ Asia/Ho_Chi_Minh · GPS HCMC · WebRTC IP RFC1918. Fake Date Time mặc định TẮT (tránh lệch giờ TLS).";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < (NSInteger)self.sections.count) {
        static NSString *cid = @"sw";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        NSDictionary *row = self.sections[indexPath.section][indexPath.row];
        cell.textLabel.text = row[@"t"];
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.textLabel.numberOfLines = 2;
        cell.backgroundColor = AppTheme.cardAlt;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UISwitch *sw = [[UISwitch alloc] init];
        sw.onTintColor = AppTheme.success;
        BOOL def = [row[@"d"] boolValue];
        sw.on = [AppState.shared toggleForKey:row[@"k"] defaultOn:def];
        sw.tag = indexPath.section * 100 + indexPath.row;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    static NSString *cid2 = @"info";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid2];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid2];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Catalog devices";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)Catalog.shared.devices.count];
    } else {
        cell.textLabel.text = @"iOS releases";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)Catalog.shared.iosReleases.count];
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    NSInteger section = sw.tag / 100;
    NSInteger row = sw.tag % 100;
    if (section < 0 || section >= (NSInteger)self.sections.count) return;
    if (row < 0 || row >= (NSInteger)self.sections[section].count) return;
    NSDictionary *item = self.sections[section][row];
    [AppState.shared setToggle:sw.on forKey:item[@"k"]];
}

@end
