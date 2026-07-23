#import "SettingsViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "Catalog.h"
#import "ProxyAppAttestController.h"
#import "VerifyViewController.h"

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
            @{ @"t": @"Giả lập màn hình (HIOS UIScreen)", @"k": @"FakeScreen", @"d": @YES },
            @{ @"t": @"Giả lập màn hình gốc (pixel)", @"k": @"FakeRealScreen", @"d": @YES },
            @{ @"t": @"Giả lập trình duyệt (UA)", @"k": @"FakeBrowser", @"d": @YES },
            @{ @"t": @"Giả lập mạng / nhà mạng", @"k": @"FakeNetwork", @"d": @YES },
            @{ @"t": @"Giả lập Wi‑Fi", @"k": @"FakeWifi", @"d": @YES },
            @{ @"t": @"Giả lập sysctl", @"k": @"FakeSysctl", @"d": @YES },
            @{ @"t": @"Giả lập phiên bản hệ thống", @"k": @"FakeSysOSVersion", @"d": @YES },
            @{ @"t": @"Ẩn jailbreak", @"k": @"HideJailbreak", @"d": @YES },
            @{ @"t": @"Spoof Cài đặt → Giới thiệu (mặc định BẬT)", @"k": @"SpoofSettingsAbout", @"d": @YES },
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
    return self.sections.count + 3; // toggles + tools + info
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < (NSInteger)self.sections.count)
        return self.sections[section].count;
    if (section == (NSInteger)self.sections.count)
        return 2; // Proxy / AppAttest + Verify MG
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Lớp giả lập (lab)";
    if (section == 1) return @"Tuỳ chọn nâng cao";
    if (section == (NSInteger)self.sections.count) return @"Công cụ lab";
    return @"Thông tin";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Bật «Hiện spoof trong Cài đặt → Giới thiệu» để xem model/serial/iOS ảo tại Cài đặt chung → Giới thiệu (dylib iPFakerAbout nhỏ, MG only — full MG bị AMFI chặn trên Preferences). Không xóa data Settings khi Đặt lại. Sau Đặt lại: killall Preferences rồi mở lại Cài đặt.";
    if (section == 1)
        return @"Ngôn ngữ · múi giờ · GPS · WebRTC. Giả lập ngày giờ mặc định TẮT (tránh lệch giờ TLS).";
    if (section == (NSInteger)self.sections.count)
        return @"Proxy nhanh: trang chủ (ô dán + bật/tắt). Tại đây: Type / Test / AppAttest / geo chi tiết.";
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

    if (indexPath.section == (NSInteger)self.sections.count) {
        static NSString *cidp = @"tools";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cidp];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cidp];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.detailTextLabel.textColor = AppTheme.textSecondary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Proxy / AppAttest / Geo (chi tiết)";
            NSString *host = [AppState.shared proxyHost];
            BOOL en = [AppState.shared proxyEnabled];
            cell.detailTextLabel.text = en && host.length
                ? [NSString stringWithFormat:@"ON · %@:%ld · %@", host, (long)[AppState.shared proxyPort], [AppState.shared proxyType]]
                : @"Trang chủ: dán proxy · đây: Type/Test/AA/geo";
        } else {
            cell.textLabel.text = @"Verify expected vs live MG";
            cell.detailTextLabel.text = @"So config dual-path với stub MG / CT filter";
        }
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
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Số đời máy trong danh mục";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)Catalog.shared.devices.count];
    } else {
        cell.textLabel.text = @"Số bản iOS trong danh mục";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)Catalog.shared.iosReleases.count];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == (NSInteger)self.sections.count) {
        if (indexPath.row == 0) {
            ProxyAppAttestController *vc = [[ProxyAppAttestController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            VerifyViewController *vc = [[VerifyViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
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
