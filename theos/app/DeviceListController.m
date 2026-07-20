#import "DeviceListController.h"
#import "Catalog.h"
#import "AppState.h"
#import "AppTheme.h"

@interface DeviceListController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@end

@implementation DeviceListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn đời máy";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.allowsMultipleSelection = NO; // we manage ✓ manually
    self.items = Catalog.shared.devices;
    self.filtered = self.items;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"15 Pro, iphone16, A17…";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Xong"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(doneTapped)];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    hint.text = @"  Chạm để chọn · chạm lại để bỏ · ✓ = đã chọn (giữ ≥1 máy)";
    hint.font = AppTheme.captionFont;
    hint.textColor = AppTheme.textSecondary;
    hint.numberOfLines = 2;
    self.tableView.tableHeaderView = hint;
}

- (void)doneTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSUInteger n = AppState.shared.selectedDeviceIds.count;
    return [NSString stringWithFormat:@"Đã chọn %lu đời máy. iOS list chỉ còn bản matrix hợp lệ.",
            (unsigned long)n];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"d";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    NSDictionary *d = self.filtered[indexPath.row];
    NSDictionary *disp = d[@"display"] ?: @{};
    BOOL lab = [d[@"lab"] boolValue];
    NSString *did = d[@"id"] ?: @"";
    BOOL on = [AppState.shared isDeviceSelected:did];

    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", d[@"MarketingName"] ?: @"?", lab ? @" ★" : @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ MB · %@x%@ · iOS %@–%@",
                                 d[@"ProductType"] ?: @"",
                                 d[@"chip"] ?: @"",
                                 d[@"PhysicalMemoryMB"] ?: @"",
                                 disp[@"NativeWidth"] ?: @"",
                                 disp[@"NativeHeight"] ?: @"",
                                 d[@"minIOS"] ?: @"?",
                                 d[@"maxIOS"] ?: @"?"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppTheme.accent;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *d = self.filtered[indexPath.row];
    NSString *did = d[@"id"];
    if (!did.length) return;

    BOOL nowOn = [AppState.shared toggleDeviceId:did];
    // If user tried to deselect last item, still selected
    (void)nowOn;

    // Reload row for ✓ + footer count
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    // Footer
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];

    if (self.onChange) self.onChange();
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString ?: @"";
    if (q.length == 0) {
        self.filtered = self.items;
    } else {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in self.items) {
            NSString *blob = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                               d[@"id"], d[@"MarketingName"], d[@"ProductType"], d[@"chip"], d[@"HWModelStr"]] lowercaseString];
            if ([blob containsString:q]) [out addObject:d];
        }
        self.filtered = out;
    }
    [self.tableView reloadData];
}

@end
