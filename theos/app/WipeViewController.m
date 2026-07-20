#import "WipeViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "AppListController.h"
#import "AppCatalog.h"
#import "ProgressOverlay.h"
#import "ProfileBuilder.h"

@interface WipeViewController ()
@property (nonatomic, strong) UILabel *appsDetailLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation WipeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.title = @"Wipe App";
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshUI)
                                                 name:AppStateDidChangeNotification
                                               object:nil];
    [[AppCatalog shared] reload];
    [AppState.shared ensureDefaults];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"Wipe App Data";
    header.font = AppTheme.titleFont;
    header.textColor = AppTheme.textPrimary;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UILabel *note = [[UILabel alloc] init];
    note.text = @"Chọn app tải ngoài (multi ✓) · Mặc định Bản đồ + Thời tiết · Có overlay tiến trình.";
    note.font = AppTheme.captionFont;
    note.textColor = AppTheme.textSecondary;
    note.numberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:note];

    UIView *card = [AppTheme roundedCardIn:self.view];
    UIControl *appsRow = [self makeRowTitle:@"Chọn app để wipe (nhiều)"
                                detailOut:&_appsDetailLabel
                                   action:@selector(pickApps)];
    [card addSubview:appsRow];

    UIButton *wipeSel = [AppTheme primaryButtonWithTitle:@"Wipe data app đã chọn"
                                                  target:self
                                                  action:@selector(wipeSelectedTapped)];
    wipeSel.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.1 alpha:1.0];

    UIButton *resetData = [AppTheme primaryButtonWithTitle:@"Reset Data app"
                                                    target:self
                                                    action:@selector(resetDataTapped)];

    UIButton *saveData = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveData setTitle:@"Reset + Save Data (không wipe)" forState:UIControlStateNormal];
    [saveData setTitleColor:AppTheme.accent forState:UIControlStateNormal];
    saveData.titleLabel.font = AppTheme.bodyFont;
    saveData.translatesAutoresizingMaskIntoConstraints = NO;
    [saveData addTarget:self action:@selector(saveDataTapped) forControlEvents:UIControlEventTouchUpInside];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = AppTheme.captionFont;
    self.hintLabel.textColor = AppTheme.textSecondary;
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:wipeSel];
    [self.view addSubview:resetData];
    [self.view addSubview:saveData];
    [self.view addSubview:self.hintLabel];

    CGFloat pad = 16;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [note.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],
        [note.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [card.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:16],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [appsRow.topAnchor constraintEqualToAnchor:card.topAnchor],
        [appsRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [appsRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [appsRow.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [wipeSel.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:18],
        [wipeSel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [wipeSel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [wipeSel.heightAnchor constraintEqualToConstant:52],

        [resetData.topAnchor constraintEqualToAnchor:wipeSel.bottomAnchor constant:10],
        [resetData.leadingAnchor constraintEqualToAnchor:wipeSel.leadingAnchor],
        [resetData.trailingAnchor constraintEqualToAnchor:wipeSel.trailingAnchor],
        [resetData.heightAnchor constraintEqualToConstant:52],

        [saveData.topAnchor constraintEqualToAnchor:resetData.bottomAnchor constant:12],
        [saveData.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.hintLabel.topAnchor constraintEqualToAnchor:saveData.bottomAnchor constant:16],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
    ]];

    [self refreshUI];
}

- (UIControl *)makeRowTitle:(NSString *)title
                  detailOut:(UILabel * __strong *)detailOut
                     action:(SEL)action {
    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UILabel *titleLab = [[UILabel alloc] init];
    titleLab.text = title;
    titleLab.font = AppTheme.sectionFont;
    titleLab.textColor = AppTheme.textPrimary;
    titleLab.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *detail = [[UILabel alloc] init];
    detail.font = AppTheme.captionFont;
    detail.textColor = AppTheme.textSecondary;
    detail.numberOfLines = 3;
    detail.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *chev = [[UILabel alloc] init];
    chev.text = @"›";
    chev.font = [UIFont systemFontOfSize:28 weight:UIFontWeightUltraLight];
    chev.textColor = AppTheme.textSecondary;
    chev.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:titleLab];
    [row addSubview:detail];
    [row addSubview:chev];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:84],
        [titleLab.topAnchor constraintEqualToAnchor:row.topAnchor constant:14],
        [titleLab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [detail.topAnchor constraintEqualToAnchor:titleLab.bottomAnchor constant:6],
        [detail.leadingAnchor constraintEqualToAnchor:titleLab.leadingAnchor],
        [detail.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-8],
        [detail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-14],
        [chev.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chev.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
    ]];
    if (detailOut) *detailOut = detail;
    return row;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshUI];
}

- (void)refreshUI {
    self.appsDetailLabel.text = [NSString stringWithFormat:@"%@\nDanh sách: %lu app (ngoài + Bản đồ/Thời tiết)",
                                 [AppState.shared wipeAppsSummary],
                                 (unsigned long)AppCatalog.shared.apps.count];
    self.hintLabel.text = [NSString stringWithFormat:
        @"• Wipe data app đã chọn: xóa container/prefs pool.\n"
        @"• Reset Data app: random profile + wipe data.\n"
        @"• Reset + Save Data: random + ghi config (không wipe).\n"
        @"%@\n%@",
        [AppState.shared wipeAppsSummary],
        AppState.shared.statusText ?: @""];
}

- (void)pickApps {
    AppListController *vc = [[AppListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    vc.onChange = ^{ [weakSelf refreshUI]; };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)runWithProgressTitle:(NSString *)title work:(NSString * (^)(void (^step)(NSString *)))work {
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:title];
    self.view.userInteractionEnabled = NO;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *result = work(^(NSString *step) {
            [ov appendStep:step];
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            [ov finishWithTitle:@"Hoàn tất" detail:result];
            [self refreshUI];
            [ov dismissAfter:1.8 completion:^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                           message:result
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }];
        });
    });
}

- (void)wipeSelectedTapped {
    if (AppState.shared.selectedWipeBundleIds.count == 0) {
        [self alert:@"Wipe" msg:@"Chưa chọn app. Chạm «Chọn app để wipe» và tích ✓."];
        return;
    }
    [self runWithProgressTitle:@"Đang wipe data app…" work:^NSString *(void (^step)(NSString *)) {
        return [AppState.shared wipeSelectedAppsProgress:step];
    }];
}

- (void)resetDataTapped {
    [self runWithProgressTitle:@"Reset Data app…" work:^NSString *(void (^step)(NSString *)) {
        return [AppState.shared killZaloAndRandomizeFromPoolProgress:step];
    }];
}

- (void)saveDataTapped {
    [self runWithProgressTitle:@"Reset + Save Data…" work:^NSString *(void (^step)(NSString *)) {
        step(@"Random máy + iOS trong pool…");
        NSString *msg = [AppState.shared applyRandomFromPool];
        step(@"Đã ghi config");
        return msg;
    }];
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t
                                                               message:m
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
