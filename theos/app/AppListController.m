#import "AppListController.h"
#import "AppCatalog.h"
#import "AppState.h"
#import "AppTheme.h"

@interface AppListController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<AppCatalogItem *> *items;
@property (nonatomic, strong) NSArray<AppCatalogItem *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation AppListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn ứng dụng";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = self.view.backgroundColor;

    [[AppCatalog shared] reload];
    self.items = AppCatalog.shared.apps;
    self.filtered = self.items;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Tên ứng dụng, mã gói…";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Xong"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(done)];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
    hint.text = @"  Chỉ app tải ngoài + Bản đồ/Thời tiết · Chạm = ✓ chọn/bỏ";
    hint.font = AppTheme.captionFont;
    hint.textColor = AppTheme.textSecondary;
    hint.numberOfLines = 2;
    self.tableView.tableHeaderView = hint;
}

- (void)done {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Đã chọn %lu ứng dụng · Tổng %lu trên máy",
            (unsigned long)AppState.shared.selectedWipeBundleIds.count,
            (unsigned long)self.items.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"app";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    AppCatalogItem *it = self.filtered[indexPath.row];
    BOOL on = [AppState.shared isWipeAppSelected:it.bundleId];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", it.name, it.systemApp ? @"  · hệ thống" : @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@",
                                 it.bundleId,
                                 it.version.length ? [NSString stringWithFormat:@" · phiên bản %@", it.version] : @""];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppCatalogItem *it = self.filtered[indexPath.row];
    [AppState.shared toggleWipeBundleId:it.bundleId];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    if (self.onChange) self.onChange();
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) {
        self.filtered = self.items;
    } else {
        NSMutableArray *out = [NSMutableArray array];
        for (AppCatalogItem *it in self.items) {
            NSString *blob = [[NSString stringWithFormat:@"%@ %@", it.name, it.bundleId] lowercaseString];
            if ([blob containsString:q]) [out addObject:it];
        }
        self.filtered = out;
    }
    [self.tableView reloadData];
}

@end
