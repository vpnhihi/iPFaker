#import "SelectDevicesViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "Catalog.h"
#import "DeviceListController.h"
#import "IOSListController.h"

@interface SelectDevicesViewController ()
@property (nonatomic, strong) UILabel *deviceDetailLabel;
@property (nonatomic, strong) UILabel *iosDetailLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *card;
@end

@implementation SelectDevicesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.title = @"Select Devices";
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshUI)
                                                 name:AppStateDidChangeNotification
                                               object:nil];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"Select Devices";
    header.font = AppTheme.titleFont;
    header.textColor = AppTheme.textPrimary;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"Multi-select · ✓ = đã chọn · Kill Zalo = random cặp máy+iOS hợp lệ";
    sub.font = AppTheme.captionFont;
    sub.textColor = AppTheme.textSecondary;
    sub.numberOfLines = 2;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    if (@available(iOS 13.0, *)) {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.spinner.color = AppTheme.textSecondary;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    self.card = [AppTheme roundedCardIn:self.view];

    UIControl *deviceRow = [self makeRowTitle:@"Chọn đời máy (nhiều)"
                                 detailOut:&_deviceDetailLabel
                                    action:@selector(pickDevice)];

    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = AppTheme.separator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    UIControl *iosRow = [self makeRowTitle:@"Chọn iOS (nhiều · theo matrix)"
                               detailOut:&_iosDetailLabel
                                  action:@selector(pickIOS)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[deviceRow, sep, iosRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:stack];
    [sep.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;

    UIButton *applyBtn = [AppTheme primaryButtonWithTitle:@"Apply (random trong pool)"
                                                   target:self
                                                   action:@selector(applyTapped)];
    [self.view addSubview:applyBtn];

    UIButton *killBtn = [AppTheme primaryButtonWithTitle:@"Kill Zalo + Random + Wipe 100%"
                                                  target:self
                                                  action:@selector(killRandomTapped)];
    killBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.1 alpha:1.0];
    [self.view addSubview:killBtn];

    UIButton *reseedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [reseedBtn setTitle:@"Apply primary (máy/iOS đang active)" forState:UIControlStateNormal];
    [reseedBtn setTitleColor:AppTheme.accent forState:UIControlStateNormal];
    reseedBtn.titleLabel.font = AppTheme.bodyFont;
    reseedBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [reseedBtn addTarget:self action:@selector(reseedTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reseedBtn];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = AppTheme.captionFont;
    self.hintLabel.textColor = AppTheme.textSecondary;
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hintLabel];

    CGFloat pad = 16;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [sub.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [sub.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [self.card.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:16],
        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [stack.topAnchor constraintEqualToAnchor:self.card.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],

        [applyBtn.topAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:16],
        [applyBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [applyBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [applyBtn.heightAnchor constraintEqualToConstant:50],

        [killBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:10],
        [killBtn.leadingAnchor constraintEqualToAnchor:applyBtn.leadingAnchor],
        [killBtn.trailingAnchor constraintEqualToAnchor:applyBtn.trailingAnchor],
        [killBtn.heightAnchor constraintEqualToConstant:50],

        [reseedBtn.topAnchor constraintEqualToAnchor:killBtn.bottomAnchor constant:10],
        [reseedBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.hintLabel.topAnchor constraintEqualToAnchor:reseedBtn.bottomAnchor constant:16],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
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
        [titleLab.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-8],
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
    AppState *st = AppState.shared;
    [st ensureDefaults];
    BOOL empty = Catalog.shared.devices.count == 0;
    if (empty) {
        [self.spinner startAnimating];
        self.card.hidden = YES;
    } else {
        [self.spinner stopAnimating];
        self.card.hidden = NO;
    }

    NSDictionary *dev = [st currentDevice] ?: @{};
    NSDictionary *disp = dev[@"display"] ?: @{};

    self.deviceDetailLabel.text = [NSString stringWithFormat:@"%@\nActive: %@ · %@",
                                   [st devicePoolSummary],
                                   dev[@"MarketingName"] ?: @"—",
                                   dev[@"ProductType"] ?: @"—"];

    NSDictionary *meta = [st currentIOSMeta] ?: @{};
    self.iosDetailLabel.text = [NSString stringWithFormat:@"%@\nActive: iOS %@ · Build %@",
                                [st iosPoolSummary],
                                st.selectedIOS ?: @"—",
                                meta[@"BuildVersion"] ?: @"?"];

    NSUInteger nCompat = [st compatibleIOSForSelectedDevices].count;
    NSUInteger nPairs = 0;
    for (NSString *did in st.selectedDeviceIds) {
        NSDictionary *d = [Catalog.shared deviceWithId:did];
        nPairs += [st selectedIOSCompatibleWithDevice:d ?: @{}].count;
    }

    self.hintLabel.text = [NSString stringWithFormat:
        @"Pool: %lu máy × iOS đã chọn → %lu cặp matrix hợp lệ (random khi Kill Zalo).\n"
        @"Matrix union: %lu bản iOS · Active id: %@\n"
        @"Màn active: %@×%@ @%@\n"
        @"Kill Zalo = random model/iOS + serial/IDFA/IDFV/IMEI/MAC/UA… theo catalog máy.\n%@",
        (unsigned long)st.selectedDeviceIds.count,
        (unsigned long)nPairs,
        (unsigned long)nCompat,
        dev[@"id"] ?: @"",
        disp[@"NativeWidth"] ?: @"?",
        disp[@"NativeHeight"] ?: @"?",
        disp[@"ScreenScale"] ?: @"?",
        st.statusText ?: @""];
}

- (void)pickDevice {
    DeviceListController *vc = [[DeviceListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.selectedIds = AppState.shared.selectedDeviceIds;
    __weak typeof(self) weakSelf = self;
    vc.onChange = ^{
        [weakSelf refreshUI];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pickIOS {
    IOSListController *vc = [[IOSListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    vc.onChange = ^{
        [weakSelf refreshUI];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)applyTapped {
    NSString *msg = [AppState.shared applyRandomFromPool];
    [self alert:@"Apply (random pool)" msg:msg];
}

- (void)killRandomTapped {
    NSString *msg = [AppState.shared killZaloAndRandomizeFromPool];
    [self alert:@"Kill Zalo + Random" msg:msg];
}

- (void)reseedTapped {
    NSString *msg = [AppState.shared applyReseedOnly:YES];
    [self alert:@"Apply primary" msg:msg];
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
