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
    self.title = @"Cài đặt";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = AppTheme.bg;
    self.tableView.separatorColor = AppTheme.separator;
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    // Công tắc giả lập (map sang hook lab)
    self.sections = @[
        @[
            @{ @"t": @"Giả lập thiết bị", @"k": @"FakeDevice", @"d": @YES },
            @{ @"t": @"Giả lập phần cứng", @"k": @"FakeHardware", @"d": @YES },
            @{ @"t": @"Giả lập quảng cáo (IDFA/IDFV)", @"k": @"FakeAds", @"d": @YES },
            @{ @"t": @"Giả lập màn hình", @"k": @"FakeScreen", @"d": @YES },
            @{ @"t": @"Giả lập màn hình gốc (pixel)", @"k": @"FakeRealScreen", @"d": @YES },
            @{ @"t": @"Giả lập trình duyệt (UA)", @"k": @"FakeBrowser", @"d": @YES },
            @{ @"t": @"Giả lập mạng / nhà mạng", @"k": @"FakeNetwork", @"d": @YES },
            @{ @"t": @"Giả lập Wi‑Fi", @"k": @"FakeWifi", @"d": @YES },
            @{ @"t": @"Giả lập sysctl", @"k": @"FakeSysctl", @"d": @YES },
            @{ @"t": @"Giả lập phiên bản hệ thống", @"k": @"FakeSysOSVersion", @"d": @YES },
            @{ @"t": @"Ẩn jailbreak", @"k": @"HideJailbreak", @"d": @YES },
        ],
        @[
            @{ @"t": @"Giả lập ngôn ngữ / múi giờ", @"k": @"FakeLocale", @"d": @YES },
            @{ @"t": @"Giả lập ngày giờ (boot/offset)", @"k": @"FakeDateTime", @"d": @NO },
            @{ @"t": @"Giả lập vị trí (GPS)", @"k": @"FakeLocation", @"d": @YES },
            @{ @"t": @"Giả lập cảm biến", @"k": @"FakeSensor", @"d": @YES },
            @{ @"t": @"Giả lập WebRTC (IP nội bộ)", @"k": @"FakeWebRTC", @"d": @YES },
            @{ @"t": @"Tắt WebRTC", @"k": @"DisableWebRTC", @"d": @NO },
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
    if (section == 0) return @"Lớp giả lập (lab)";
    if (section == 1) return @"Tuỳ chọn nâng cao";
    return @"Thông tin";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Mỗi công tắc bật/tắt hook sau «Đặt lại + Lưu dữ liệu». Định dạng: UUID v4, IMEI Luhn, ITU E.212, ISO/BCP-47, múi giờ IANA.";
    if (section == 1)
        return @"Ngôn ngữ vi-VN · Múi giờ Asia/Ho_Chi_Minh · GPS TP.HCM · WebRTC IP nội bộ. Giả lập ngày giờ mặc định TẮT (tránh lệch giờ TLS).";
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
        cell.textLabel.text = @"Số đời máy trong danh mục";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)Catalog.shared.devices.count];
    } else {
        cell.textLabel.text = @"Số bản iOS trong danh mục";
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
