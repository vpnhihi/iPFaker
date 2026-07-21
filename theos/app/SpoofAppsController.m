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
    self.title = @"App lab";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = self.view.backgroundColor;

    [[AppCatalog shared] reloadSpoofCatalog];
    // Only third-party (installed / social) — hide system apps
    NSMutableArray *tp = [NSMutableArray array];
    for (AppCatalogItem *it in AppCatalog.shared.spoofApps) {
        if (!it.bundleId.length) continue;
        if ([AppState isSystemLabBundleId:it.bundleId]) continue;
        if (it.systemApp && [it.bundleId hasPrefix:@"com.apple."]) continue;
        [tp addObject:it];
    }
    // Also merge live third-party from wipe scan
    [[AppCatalog shared] reload];
    for (AppCatalogItem *it in AppCatalog.shared.apps) {
        if (!it.bundleId.length || it.systemApp) continue;
        if ([AppState isSystemLabBundleId:it.bundleId]) continue;
        BOOL exists = NO;
        for (AppCatalogItem *x in tp) {
            if ([x.bundleId isEqualToString:it.bundleId]) { exists = YES; break; }
        }
        if (!exists) [tp addObject:it];
    }
    self.items = [tp sortedArrayUsingComparator:^NSComparisonResult(AppCatalogItem *a, AppCatalogItem *b) {
        BOOL az = [a.bundleId.lowercaseString containsString:@"zalo"];
        BOOL bz = [b.bundleId.lowercaseString containsString:@"zalo"];
        if (az != bz) return az ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    self.filtered = self.items;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Tìm app";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(applyFilters)];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 56)];
    UIButton *all = [UIButton buttonWithType:UIButtonTypeSystem];
    [all setTitle:@"Chọn tất cả" forState:UIControlStateNormal];
    all.titleLabel.font = AppTheme.sectionFont;
    all.translatesAutoresizingMaskIntoConstraints = NO;
    [all addTarget:self action:@selector(selectAllTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *none = [UIButton buttonWithType:UIButtonTypeSystem];
    [none setTitle:@"Bỏ chọn" forState:UIControlStateNormal];
    none.titleLabel.font = AppTheme.sectionFont;
    none.translatesAutoresizingMaskIntoConstraints = NO;
    [none addTarget:self action:@selector(deselectAllTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *social = [UIButton buttonWithType:UIButtonTypeSystem];
    [social setTitle:@"Social" forState:UIControlStateNormal];
    social.titleLabel.font = AppTheme.sectionFont;
    social.translatesAutoresizingMaskIntoConstraints = NO;
    [social addTarget:self action:@selector(labSocialTapped) forControlEvents:UIControlEventTouchUpInside];

    [header addSubview:all];
    [header addSubview:none];
    [header addSubview:social];
    [NSLayoutConstraint activateConstraints:@[
        [all.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [all.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [none.centerYAnchor constraintEqualToAnchor:all.centerYAnchor],
        [none.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [social.centerYAnchor constraintEqualToAnchor:all.centerYAnchor],
        [social.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    ]];
    self.tableView.tableHeaderView = header;
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
    [AppState.shared deselectAllSpoofAppsKeepingZalo:YES];
    [self.tableView reloadData];
    if (self.onChange) self.onChange();
}

- (void)applyFilters {
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Áp dụng filter…"];
    if (!ov) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = nil;
        @try {
            msg = [AppState.shared applySpoofAppFiltersProgress:^(NSString *s) {
                [ov appendStep:s];
            }];
        } @catch (NSException *ex) {
            msg = [NSString stringWithFormat:@"Lỗi: %@", ex.reason ?: @"?"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [ov finishWithTitle:@"Xong" detail:msg];
            [ov dismissAfter:1.0 completion:^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"App lab"
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
    return [NSString stringWithFormat:@"Đã chọn %lu app",
            (unsigned long)AppState.shared.selectedSpoofBundleIds.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"spoofapp";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    if (indexPath.row >= (NSInteger)self.filtered.count) return cell;
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
    if (indexPath.row >= (NSInteger)self.filtered.count) return;
    AppCatalogItem *it = self.filtered[indexPath.row];
    [AppState.shared toggleSpoofBundleId:it.bundleId];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    if (self.onChange) self.onChange();
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) {
        self.filtered = self.items;
    } else {
        NSMutableArray *f = [NSMutableArray array];
        for (AppCatalogItem *it in self.items) {
            if ([it.name.lowercaseString containsString:q] || [it.bundleId.lowercaseString containsString:q])
                [f addObject:it];
        }
        self.filtered = f;
    }
    [self.tableView reloadData];
}

@end
