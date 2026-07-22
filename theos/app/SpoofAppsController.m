#import "SpoofAppsController.h"
#import "AppCatalog.h"
#import "AppState.h"
#import "AppTheme.h"
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
    self.tableView.rowHeight = 58;

    [self reloadItems];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Tìm app đã cài";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(applyFilters)];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 52)];
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
    [self.tableView reloadData];
}

- (void)reloadItems {
    // Chỉ app third-party **đã cài** (LS) — kèm icon
    [[AppCatalog shared] reloadSpoofCatalog];
    self.items = AppCatalog.shared.spoofApps ?: @[];
    self.filtered = self.items;
    // Prune selection to installed only
    [AppState.shared syncLabAppPoolsFromSpoofMaster];
}

- (void)labSocialTapped {
    [AppState.shared applyLabSocialSpoofPreset];
    [self reloadItems];
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
    [AppState.shared syncLabAppPoolsFromSpoofMaster];
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
            [ov dismissAfter:0.9 completion:^{
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
    return [NSString stringWithFormat:@"%lu app đã cài · chọn %lu",
            (unsigned long)self.items.count,
            (unsigned long)AppState.shared.selectedSpoofBundleIds.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"spoofapp_icon";
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
    cell.detailTextLabel.text = it.version.length
        ? [NSString stringWithFormat:@"%@ · v%@", it.bundleId, it.version]
        : it.bundleId;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppTheme.accent;

    // Icon
    UIImage *icon = it.icon;
    if (icon) {
        cell.imageView.image = icon;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.layer.cornerRadius = 10;
        cell.imageView.clipsToBounds = YES;
        // Fixed size via layer
        CGFloat s = 40;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
        [icon drawInRect:CGRectMake(0, 0, s, s)];
        UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        cell.imageView.image = scaled ?: icon;
        cell.imageView.layer.cornerRadius = 9;
        cell.imageView.clipsToBounds = YES;
    } else {
        // Placeholder
        if (@available(iOS 13.0, *)) {
            cell.imageView.image = [UIImage systemImageNamed:@"app.fill"];
            cell.imageView.tintColor = AppTheme.textSecondary;
        } else {
            cell.imageView.image = nil;
        }
    }
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
