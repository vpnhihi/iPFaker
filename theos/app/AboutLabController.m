#import "AboutLabController.h"

@implementation AboutLabController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Giới thiệu lab";
    self.tableView.allowsSelection = NO;
}

- (NSArray<NSArray<NSArray<NSString *> *> *> *)rows {
    NSDictionary *d = self.device ?: @{};
    NSDictionary *disp = d[@"display"] ?: @{};
    NSDictionary *f = self.flat ?: @{};
    NSString *name = f[@"UserAssignedDeviceName"] ?: f[@"MarketingName"] ?: d[@"MarketingName"] ?: @"iPhone";
    NSString *modelName = f[@"MarketingName"] ?: d[@"MarketingName"] ?: @"—";
    NSString *modelNum = f[@"ModelNumber"] ?: d[@"ModelNumber"] ?: @"—";
    NSString *serial = f[@"SerialNumber"] ?: @"(apply để sinh serial)";
    NSString *ios = f[@"ProductVersion"] ?: self.iosVer ?: @"—";
    NSString *build = f[@"BuildVersion"] ?: self.iosMeta[@"BuildVersion"] ?: @"—";
    NSString *screen = [NSString stringWithFormat:@"%@×%@ @%@ · %@\" · %@ Hz",
                        disp[@"NativeWidth"] ?: f[@"main-screen-width"] ?: @"?",
                        disp[@"NativeHeight"] ?: f[@"main-screen-height"] ?: @"?",
                        disp[@"ScreenScale"] ?: f[@"main-screen-scale"] ?: @"?",
                        disp[@"DiagonalInches"] ?: @"?",
                        disp[@"MaxRefreshHz"] ?: f[@"MaxRefreshHz"] ?: @"60"];
    NSString *ram = [NSString stringWithFormat:@"%@ MB", f[@"PhysicalMemoryMB"] ?: d[@"PhysicalMemoryMB"] ?: @"?"];
    NSString *chip = f[@"ChipName"] ?: d[@"chip"] ?: @"—";
    NSString *ptype = f[@"ProductType"] ?: d[@"ProductType"] ?: @"—";
    NSString *hw = f[@"HWModelStr"] ?: d[@"HWModelStr"] ?: @"—";
    NSString *bat = [NSString stringWithFormat:@"%@ mAh", d[@"batteryMah"] ?: @"—"];

    return @[
        @[
            @[ @"Tên", name ],
            @[ @"Tên model", modelName ],
            @[ @"Mã model", modelNum ],
            @[ @"Số sê-ri", serial ],
        ],
        @[
            @[ @"Phiên bản", [NSString stringWithFormat:@"iOS %@", ios] ],
            @[ @"Build", build ],
            @[ @"ProductType", ptype ],
            @[ @"Board", hw ],
        ],
        @[
            @[ @"Chip", chip ],
            @[ @"RAM", ram ],
            @[ @"Màn hình", screen ],
            @[ @"Pin (lab)", bat ],
        ],
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self rows].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self rows][section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Giống Cài đặt → Giới thiệu (lab)";
    if (section == 1) return @"Hệ điều hành & mã máy";
    return @"Phần cứng (catalog)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Đây là màn lab trong app iPFaker — không sửa trang Giới thiệu hệ thống (tránh crash Settings).";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"a";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    NSArray *row = [self rows][indexPath.section][indexPath.row];
    cell.textLabel.text = row[0];
    cell.detailTextLabel.text = row[1];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    return cell;
}

@end
