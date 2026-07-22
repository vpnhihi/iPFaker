#import "AboutLabController.h"
#import "AppTheme.h"
#import "IPFLicenseManager.h"
#import "AppDelegate.h"
#import "ProfileBuilder.h"

@implementation AboutLabController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Giới thiệu lab";
    self.tableView.allowsSelection = YES;
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = AppTheme.bg;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh from dual-path disk SoT every time (Settings ↔ Lab stay in sync)
    NSDictionary *live = [ProfileBuilder loadCurrentFlat];
    if (live.count) {
        self.flat = live;
        [self.tableView reloadData];
    }
}

- (NSArray<NSArray<NSArray<NSString *> *> *> *)profileRows {
    NSDictionary *d = self.device ?: @{};
    NSDictionary *disp = d[@"display"] ?: @{};
    NSDictionary *f = self.flat ?: @{};
    NSString *name = f[@"UserAssignedDeviceName"] ?: f[@"MarketingName"] ?: d[@"MarketingName"] ?: @"iPhone";
    NSString *modelName = f[@"MarketingName"] ?: d[@"MarketingName"] ?: @"—";
    NSString *modelNum = f[@"ModelNumber"] ?: d[@"ModelNumber"] ?: @"—";
    NSString *partNum = f[@"PartNumber"] ?: d[@"PartNumber"] ?: @"—";
    NSString *serial = f[@"SerialNumber"] ?: @"—";
    NSString *idfa = f[@"IDFA"] ?: @"—";
    NSString *idfv = f[@"IDFV"] ?: f[@"identifierForVendor"] ?: @"—";
    NSString *ios = f[@"ProductVersion"] ?: self.iosVer ?: @"—";
    NSString *build = f[@"BuildVersion"] ?: self.iosMeta[@"BuildVersion"] ?: @"—";
    NSString *screen = [NSString stringWithFormat:@"%@×%@ @%@",
                        disp[@"NativeWidth"] ?: f[@"main-screen-width"] ?: @"?",
                        disp[@"NativeHeight"] ?: f[@"main-screen-height"] ?: @"?",
                        disp[@"ScreenScale"] ?: f[@"main-screen-scale"] ?: @"?"];
    NSString *ram = [NSString stringWithFormat:@"%@ MB", f[@"PhysicalMemoryMB"] ?: d[@"PhysicalMemoryMB"] ?: @"?"];
    NSString *chip = f[@"ChipName"] ?: d[@"chip"] ?: @"—";
    NSString *ptype = f[@"ProductType"] ?: d[@"ProductType"] ?: @"—";
    NSString *hw = f[@"HWModelStr"] ?: d[@"HWModelStr"] ?: @"—";
    NSString *reg = f[@"RegulatoryModelNumber"] ?: d[@"RegulatoryModelNumber"] ?: @"—";
    NSString *wifi = f[@"WifiAddress"] ?: @"—";
    NSString *bt = f[@"BluetoothAddress"] ?: @"—";
    NSString *eid = f[@"EID"] ?: @"—";
    NSString *seid = f[@"SEID"] ?: f[@"SecureElementID"] ?: @"—";
    NSString *bb = f[@"BasebandVersion"] ?: @"—";

    return @[
        @[
            @[ @"Tên", name ],
            @[ @"Tên model", modelName ],
            @[ @"Số máy (Part)", modelNum ],
            @[ @"Axxxx", reg ],
            @[ @"Số part", partNum ],
            @[ @"Số sê-ri", serial ],
        ],
        @[
            @[ @"IDFA", idfa ],
            @[ @"IDFV", idfv ],
        ],
        @[
            @[ @"Phiên bản", [NSString stringWithFormat:@"iOS %@", ios] ],
            @[ @"Bản dựng", build ],
            @[ @"Loại máy", ptype ],
            @[ @"Bo mạch", hw ],
        ],
        @[
            @[ @"Chip", chip ],
            @[ @"RAM", ram ],
            @[ @"Màn hình", screen ],
        ],
        // Network / eSIM / modem — same SoT as Settings → Giới thiệu
        @[
            @[ @"Địa chỉ Wi-Fi", wifi ],
            @[ @"Bluetooth", bt ],
            @[ @"EID", eid ],
            @[ @"SEID", seid ],
            @[ @"Vi c.trình modem", bb ],
        ],
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6; // account + 5 profile (incl. network/eSIM/modem)
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; // key, deviceId, contact, logout
    return [self profileRows][section - 1].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Key / Tài khoản";
    if (section == 5) return @"Mạng / eSIM / Modem (SoT)";
    if (section == 1) return @"Hồ sơ lab";
    if (section == 2) return @"IDFA / IDFV";
    if (section == 3) return @"Hệ điều hành & mã máy";
    return @"Phần cứng";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *cid = @"acc";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.detailTextLabel.textColor = AppTheme.textSecondary;
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        IPFLicenseManager *lic = IPFLicenseManager.shared;
        NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:@"ipf.lic.key"] ?: @"—";
        if (key.length > 24) key = [[key substringToIndex:20] stringByAppendingString:@"…"];
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Key kích hoạt";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · còn %ld ngày",
                                             key, (long)[lic daysRemaining]];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            case 1:
                cell.textLabel.text = @"Device ID";
                cell.detailTextLabel.text = [lic deviceId] ?: @"—";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 2:
                cell.textLabel.text = @"Liên hệ Admin";
                cell.detailTextLabel.text = @"Telegram @Bemm1102";
                cell.textLabel.textColor = AppTheme.accent;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            default:
                cell.textLabel.text = @"Đăng xuất";
                cell.detailTextLabel.text = @"Xóa phiên key trên máy này";
                cell.textLabel.textColor = [UIColor colorWithRed:0.95 green:0.35 blue:0.3 alpha:1];
                cell.accessoryType = UITableViewCellAccessoryNone;
                break;
        }
        return cell;
    }

    static NSString *cid = @"a";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    NSArray *row = [self profileRows][indexPath.section - 1][indexPath.row];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.text = row[0];
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.text = row[1];
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    if (indexPath.row == 1) {
        // Copy device id
        NSString *did = [IPFLicenseManager.shared deviceId] ?: @"";
        if (did.length) {
            UIPasteboard.generalPasteboard.string = did;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đã copy Device ID"
                                                                       message:did
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    } else if (indexPath.row == 2) {
        NSURL *url = [NSURL URLWithString:@"https://t.me/Bemm1102"];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else {
            UIPasteboard.generalPasteboard.string = @"@Bemm1102";
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Telegram"
                                                                       message:@"@Bemm1102 (đã copy)"
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    } else if (indexPath.row == 3) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đăng xuất key?"
                                                                    message:@"Xóa phiên trên máy này."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Đăng xuất" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [IPFLicenseManager.shared logout];
            AppDelegate *del = (AppDelegate *)UIApplication.sharedApplication.delegate;
            if ([del respondsToSelector:@selector(showLogin)]) {
                [del showLogin];
            }
        }]];
        [self presentViewController:ac animated:YES completion:nil];
    }
}

@end
