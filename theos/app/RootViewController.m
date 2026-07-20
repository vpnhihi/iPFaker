#import "RootViewController.h"
#import "Catalog.h"
#import "ProfileBuilder.h"
#import "DeviceListController.h"
#import "IOSListController.h"
#import "AboutLabController.h"
#import "AppState.h"

@interface RootViewController ()
@property (nonatomic, copy) NSString *selectedDeviceId;
@property (nonatomic, copy) NSString *selectedIOS;
@property (nonatomic, strong) NSDictionary *lastFlat;
@property (nonatomic, copy) NSString *statusText;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iPFaker";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // Quick Apply button
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(quickApply)];

    [[Catalog shared] reload];
    [self restoreSelectionFromDisk];
    if (!self.selectedDeviceId.length) {
        self.selectedDeviceId = @"iphone15-pro";
        self.selectedIOS = @"18.5";
    }
    NSUInteger nDev = Catalog.shared.devices.count;
    NSUInteger nIOS = Catalog.shared.iosReleases.count;
    self.statusText = [NSString stringWithFormat:
        @"Lab · %lu máy · %lu iOS · không inject Settings",
        (unsigned long)nDev, (unsigned long)nIOS];
}

- (void)quickApply {
    [self applyProfileReseedOnly:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)restoreSelectionFromDisk {
    NSDictionary *flat = [ProfileBuilder loadCurrentFlat];
    self.lastFlat = flat;
    if (flat[@"DeviceCatalogId"]) self.selectedDeviceId = [flat[@"DeviceCatalogId"] description];
    if (flat[@"ProductVersion"]) self.selectedIOS = [flat[@"ProductVersion"] description];
}

- (NSDictionary *)currentDevice {
    return [[Catalog shared] deviceWithId:self.selectedDeviceId]
        ?: (Catalog.shared.devices.firstObject);
}

- (NSDictionary *)currentIOSMeta {
    NSString *ios = self.selectedIOS ?: @"18.5";
    NSDictionary *m = Catalog.shared.iosReleases[ios];
    if (m) return m;
    // fallback default of device
    NSDictionary *dev = [self currentDevice];
    ios = dev[@"defaultIOS"] ?: @"18.5";
    self.selectedIOS = ios;
    return Catalog.shared.iosReleases[ios] ?: @{ @"ProductVersion": ios, @"BuildVersion": @"?" };
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // device, ios, about lab
    if (section == 1) return 3; // apply, reseed, kill zalo
    if (section == 2) return 1; // wipe note
    return 1; // status
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Hồ sơ lab";
        case 1: return @"Thao tác";
        case 2: return @"Wipe";
        default: return @"Trạng thái";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Chọn model + iOS → Reset + Save Data (không đụng Cài đặt hệ thống).";
    if (section == 1)
        return @"Apply ghi config.plist vào /var/mobile/Library/iPFaker và /var/jb/etc/ipfaker.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"c";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    NSDictionary *dev = [self currentDevice];
    NSDictionary *iosMeta = [self currentIOSMeta];
    NSDictionary *disp = dev[@"display"] ?: @{};

    if (indexPath.section == 0) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.row == 0) {
            cell.textLabel.text = dev[@"MarketingName"] ?: @"Chọn máy";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · RAM %@ MB · %@",
                                         dev[@"ProductType"] ?: @"?",
                                         dev[@"chip"] ?: @"?",
                                         dev[@"PhysicalMemoryMB"] ?: @"?",
                                         dev[@"id"] ?: @""];
        } else if (indexPath.row == 1) {
            BOOL lab = [iosMeta[@"lab"] boolValue];
            cell.textLabel.text = [NSString stringWithFormat:@"iOS %@", self.selectedIOS ?: @"?"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Build %@%@",
                                         iosMeta[@"BuildVersion"] ?: @"?",
                                         lab ? @" · lab" : @""];
        } else {
            cell.textLabel.text = @"Giới thiệu lab";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@x%@ @%@ · pin %@ mAh",
                                         dev[@"MarketingName"] ?: @"",
                                         disp[@"NativeWidth"] ?: @"",
                                         disp[@"NativeHeight"] ?: @"",
                                         disp[@"ScreenScale"] ?: @"",
                                         dev[@"batteryMah"] ?: @"—"];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Apply profile";
            cell.detailTextLabel.text = @"Ghi config + serial/IDFA/IDFV mới";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Reseed identity";
            cell.detailTextLabel.text = @"Giữ model/iOS, random serial & UUID";
        } else {
            cell.textLabel.text = @"Reset Data app";
            cell.detailTextLabel.text = @"Random profile + wipe data app";
            cell.textLabel.textColor = [UIColor systemOrangeColor];
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Wipe data app";
        cell.detailTextLabel.text = @"Xóa sạch data app đã chọn";
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = self.statusText ?: @"—";
        cell.detailTextLabel.text = self.lastFlat
            ? [NSString stringWithFormat:@"Disk: %@ / iOS %@",
               self.lastFlat[@"MarketingName"] ?: @"?",
               self.lastFlat[@"ProductVersion"] ?: @"?"]
            : @"Chưa có config trên disk";
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            DeviceListController *vc = [[DeviceListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            __weak typeof(self) weakSelf = self;
            vc.onChange = ^{
                weakSelf.selectedDeviceId = AppState.shared.selectedDeviceId;
                weakSelf.selectedIOS = AppState.shared.selectedIOS;
                [weakSelf.tableView reloadData];
            };
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 1) {
            IOSListController *vc = [[IOSListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            __weak typeof(self) weakSelf = self;
            vc.onChange = ^{
                weakSelf.selectedDeviceId = AppState.shared.selectedDeviceId;
                weakSelf.selectedIOS = AppState.shared.selectedIOS;
                [weakSelf.tableView reloadData];
            };
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            AboutLabController *vc = [[AboutLabController alloc] init];
            vc.device = [self currentDevice];
            vc.iosVer = self.selectedIOS;
            vc.iosMeta = [self currentIOSMeta];
            vc.flat = self.lastFlat;
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0 || indexPath.row == 1) {
            [self applyProfileReseedOnly:(indexPath.row == 1)];
        } else {
            [ProfileBuilder killZalo];
            self.statusText = @"Đã kill Zalo. Mở lại Zalo để load spoof.";
            [self.tableView reloadData];
            [self toast:self.statusText];
        }
        return;
    }

    if (indexPath.section == 2) {
        NSString *m = [ProfileBuilder wipeZaloLab];
        self.statusText = m;
        [self.tableView reloadData];
        [self toast:m];
    }
}

- (void)applyProfileReseedOnly:(BOOL)reseedOnly {
    NSDictionary *dev = [self currentDevice];
    if (!dev) {
        [self toast:@"Catalog trống — thiếu device_catalog.json"];
        return;
    }
    NSString *ios = self.selectedIOS ?: dev[@"defaultIOS"] ?: @"18.5";
    // Enforce support matrix
    if (![Catalog.shared device:dev supportsIOS:ios]) {
        NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
        if (sup.count) {
            ios = sup.lastObject;
            self.selectedIOS = ios;
            [self toast:[NSString stringWithFormat:@"iOS không hợp lệ → dùng %@", ios]];
        } else {
            [self toast:@"Máy này không có iOS trong matrix"];
            return;
        }
    }
    NSDictionary *meta = Catalog.shared.iosReleases[ios];
    if (!meta) {
        ios = dev[@"defaultIOS"] ?: @"18.5";
        meta = Catalog.shared.iosReleases[ios];
        self.selectedIOS = ios;
    }
    if (!meta) {
        [self toast:@"Không tìm thấy iOS trong catalog"];
        return;
    }

    NSDictionary *flat = [ProfileBuilder flatProfileForDevice:dev ios:ios iosMeta:meta deviceName:nil];
    NSString *result = [ProfileBuilder applyFlatProfile:flat deviceId:dev[@"id"] ios:ios];
    self.lastFlat = flat;
    self.statusText = result ?: @"OK";
    [self.tableView reloadData];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Apply"
                                                               message:result
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Kill Zalo" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
        [ProfileBuilder killZalo];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end
