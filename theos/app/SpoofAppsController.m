#import "SpoofAppsController.h"
#import "AppCatalog.h"
#import "AppState.h"
#import "AppTheme.h"
#import "ProfileBuilder.h"
#import "ProgressOverlay.h"

@interface SpoofAppsController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<AppCatalogItem *> *items;
@property (nonatomic, strong) NSArray<AppCatalogItem *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation SpoofAppsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Multi-app spoof";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = self.view.backgroundColor;

    [[AppCatalog shared] reloadSpoofCatalog];
    self.items = AppCatalog.shared.spoofApps;
    self.filtered = self.items;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search apps";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(applyFilters)];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 176)];
    UIButton *all = [UIButton buttonWithType:UIButtonTypeSystem];
    [all setTitle:@"Select All" forState:UIControlStateNormal];
    all.titleLabel.font = AppTheme.sectionFont;
    all.translatesAutoresizingMaskIntoConstraints = NO;
    [all addTarget:self action:@selector(selectAllTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *none = [UIButton buttonWithType:UIButtonTypeSystem];
    [none setTitle:@"Deselect All" forState:UIControlStateNormal];
    none.titleLabel.font = AppTheme.sectionFont;
    none.translatesAutoresizingMaskIntoConstraints = NO;
    [none addTarget:self action:@selector(deselectAllTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *core = [UIButton buttonWithType:UIButtonTypeSystem];
    [core setTitle:@"Lab core" forState:UIControlStateNormal];
    core.titleLabel.font = AppTheme.sectionFont;
    core.translatesAutoresizingMaskIntoConstraints = NO;
    [core addTarget:self action:@selector(labCoreTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *stock = [UIButton buttonWithType:UIButtonTypeSystem];
    [stock setTitle:@"Lab stock" forState:UIControlStateNormal];
    stock.titleLabel.font = AppTheme.sectionFont;
    stock.translatesAutoresizingMaskIntoConstraints = NO;
    [stock addTarget:self action:@selector(labStockTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *social = [UIButton buttonWithType:UIButtonTypeSystem];
    [social setTitle:@"Lab social (FB/IG/TT…)" forState:UIControlStateNormal];
    social.titleLabel.font = AppTheme.sectionFont;
    social.translatesAutoresizingMaskIntoConstraints = NO;
    [social addTarget:self action:@selector(labSocialTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"1 list lab: spoof identity + wipe session (đồng bộ tab Xóa). "
                @"Lab-core / social preset. CT+WebKit helper auto. Không inject Settings.";
    hint.font = AppTheme.captionFont;
    hint.textColor = AppTheme.textSecondary;
    hint.numberOfLines = 3;
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:all];
    [header addSubview:none];
    [header addSubview:core];
    [header addSubview:stock];
    [header addSubview:social];
    [header addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [all.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [all.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [none.centerYAnchor constraintEqualToAnchor:all.centerYAnchor],
        [none.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [core.topAnchor constraintEqualToAnchor:all.bottomAnchor constant:8],
        [core.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [stock.centerYAnchor constraintEqualToAnchor:core.centerYAnchor],
        [stock.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [social.topAnchor constraintEqualToAnchor:core.bottomAnchor constant:6],
        [social.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [hint.topAnchor constraintEqualToAnchor:social.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)labCoreTapped {
    [AppState.shared applyLabCoreSpoofPreset];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)labStockTapped {
    [AppState.shared applyLabStockSpoofPreset];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)labSocialTapped {
    [AppState.shared applyLabSocialSpoofPreset];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)selectAllTapped {
    [AppState.shared selectAllSpoofAppsFromCatalog:self.items];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)deselectAllTapped {
    // Keep Zalo always selected for lab wall
    [AppState.shared deselectAllSpoofAppsKeepingZalo:YES];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)applyFilters {
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Áp dụng Multi-app spoof…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = [AppState.shared applySpoofAppFiltersProgress:^(NSString *s) {
            [ov appendStep:s];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ov finishWithTitle:@"Xong" detail:msg];
            [ov dismissAfter:1.6 completion:^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Multi-app spoof"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }];
            if (self.onChange) self.onChange();
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Đã chọn %lu / %lu app · Apply để ghi filter inject",
            (unsigned long)AppState.shared.selectedSpoofBundleIds.count,
            (unsigned long)self.items.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"spoofapp";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    AppCatalogItem *it = self.filtered[indexPath.row];
    BOOL on = [AppState.shared isSpoofAppSelected:it.bundleId];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.textLabel.textColor = AppTheme.textPrimary;
    cell.detailTextLabel.textColor = AppTheme.textSecondary;
    cell.textLabel.text = it.name;
    cell.detailTextLabel.text = it.bundleId;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppCatalogItem *it = self.filtered[indexPath.row];
    // Block Settings — historical crash with inject
    if ([it.bundleId isEqualToString:@"com.apple.Preferences"]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Không inject Settings"
                                                                   message:@"Settings (Preferences) đã từng crash khi inject — lab wall giữ ngoài scope."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [AppState.shared toggleSpoofBundleId:it.bundleId];
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
