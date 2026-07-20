#import "IOSListController.h"
#import "Catalog.h"
#import "AppState.h"
#import "AppTheme.h"

@interface IOSListController ()
@property (nonatomic, strong) NSArray<NSString *> *versions; // newest first
@end

@implementation IOSListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn iOS";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = self.view.backgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Chọn tất cả"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(selectAllTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Xong"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(doneTapped)];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
    hint.text = @"  Chỉ iOS matrix của đời máy đã chọn · Chạm = chọn/bỏ · «Chọn tất cả»";
    hint.font = AppTheme.captionFont;
    hint.textColor = AppTheme.textSecondary;
    hint.numberOfLines = 2;
    self.tableView.tableHeaderView = hint;

    [self reloadVersions];
}

- (void)selectAllTapped {
    [AppState.shared selectAllIOS];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadVersions];
    [self.tableView reloadData];
}

- (void)reloadVersions {
    // Compatible union for multi-selected devices, newest first
    NSArray *asc = [AppState.shared compatibleIOSForSelectedDevices];
    self.versions = [[asc reverseObjectEnumerator] allObjects];
}

- (void)doneTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.versions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSUInteger nDev = AppState.shared.selectedDeviceIds.count;
    NSUInteger nSel = AppState.shared.selectedIOSList.count;
    NSUInteger nShow = self.versions.count;
    return [NSString stringWithFormat:
            @"%lu đời máy · %lu iOS trong matrix · đã chọn %lu bản.\n"
            @"«Đặt lại dữ liệu app» sẽ chọn ngẫu nhiên cặp (máy + iOS) hợp lệ trong tập chọn.",
            (unsigned long)nDev, (unsigned long)nShow, (unsigned long)nSel];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"i";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    NSString *ver = self.versions[indexPath.row];
    NSDictionary *meta = Catalog.shared.iosReleases[ver];
    BOOL lab = [meta[@"lab"] boolValue];
    BOOL on = [AppState.shared isIOSSelected:ver];

    // Which selected devices support this iOS?
    NSMutableArray *who = [NSMutableArray array];
    for (NSString *did in AppState.shared.selectedDeviceIds) {
        NSDictionary *d = [Catalog.shared deviceWithId:did];
        if (d && [Catalog.shared device:d supportsIOS:ver]) {
            [who addObject:d[@"MarketingName"] ?: did];
            if (who.count >= 3) break;
        }
    }
    NSString *whoStr = who.count ? [who componentsJoinedByString:@", "] : @"—";

    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.textLabel.text = [NSString stringWithFormat:@"iOS %@%@", ver, lab ? @"  [lab]" : @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Build %@ · OK: %@",
                                 meta[@"BuildVersion"] ?: @"?", whoStr];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *ver = self.versions[indexPath.row];
    [AppState.shared toggleIOS:ver];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    if (self.onChange) self.onChange();
}

@end
