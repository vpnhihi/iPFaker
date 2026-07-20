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
    sub.text = @"Dòng trên: Chọn đời máy  ·  Dòng dưới: Chọn iOS";
    sub.font = AppTheme.captionFont;
    sub.textColor = AppTheme.textSecondary;
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

    // —— Row 1: Chọn đời máy ——
    UIControl *deviceRow = [self makeRowTitle:@"Chọn đời máy"
                                 detailOut:&_deviceDetailLabel
                                    action:@selector(pickDevice)];

    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = AppTheme.separator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    // —— Row 2: Chọn iOS ——
    UIControl *iosRow = [self makeRowTitle:@"Chọn iOS"
                               detailOut:&_iosDetailLabel
                                  action:@selector(pickIOS)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[deviceRow, sep, iosRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:stack];
    [sep.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;

    UIButton *applyBtn = [AppTheme primaryButtonWithTitle:@"Apply Profile"
                                                   target:self
                                                   action:@selector(applyTapped)];
    [self.view addSubview:applyBtn];

    UIButton *reseedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [reseedBtn setTitle:@"Reseed Identity (giữ model/iOS)" forState:UIControlStateNormal];
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

        [self.card.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:20],
        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [stack.topAnchor constraintEqualToAnchor:self.card.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],

        [applyBtn.topAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:20],
        [applyBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [applyBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [applyBtn.heightAnchor constraintEqualToConstant:54],

        [reseedBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:12],
        [reseedBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.hintLabel.topAnchor constraintEqualToAnchor:reseedBtn.bottomAnchor constant:20],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self refreshUI];
}

/// One picker row: bold title + secondary detail + chevron. detailOut receives the detail label.
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
    detail.numberOfLines = 2;
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
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:76],
        [titleLab.topAnchor constraintEqualToAnchor:row.topAnchor constant:16],
        [titleLab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [titleLab.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-8],
        [detail.topAnchor constraintEqualToAnchor:titleLab.bottomAnchor constant:6],
        [detail.leadingAnchor constraintEqualToAnchor:titleLab.leadingAnchor],
        [detail.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-8],
        [detail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-16],
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

    self.deviceDetailLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ · RAM %@ MB",
                                   dev[@"MarketingName"] ?: @"Chạm để chọn đời máy",
                                   dev[@"ProductType"] ?: @"—",
                                   dev[@"chip"] ?: @"—",
                                   dev[@"PhysicalMemoryMB"] ?: @"?"];

    NSDictionary *meta = [st currentIOSMeta] ?: @{};
    BOOL lab = [meta[@"lab"] boolValue];
    self.iosDetailLabel.text = [NSString stringWithFormat:@"iOS %@ · Build %@%@",
                                st.selectedIOS ?: @"—",
                                meta[@"BuildVersion"] ?: @"?",
                                lab ? @" · lab" : @""];

    NSArray *sup = [Catalog.shared supportedIOSForDevice:dev];
    self.hintLabel.text = [NSString stringWithFormat:
        @"Matrix: min %@ · max %@ · default %@ · %lu bản iOS hợp lệ\n"
        @"Màn: %@×%@ @%@ · id: %@\n%@",
        dev[@"minIOS"] ?: @"?",
        dev[@"maxIOS"] ?: @"?",
        dev[@"defaultIOS"] ?: @"?",
        (unsigned long)sup.count,
        disp[@"NativeWidth"] ?: @"?",
        disp[@"NativeHeight"] ?: @"?",
        disp[@"ScreenScale"] ?: @"?",
        dev[@"id"] ?: @"",
        st.statusText ?: @""];
}

- (void)pickDevice {
    DeviceListController *vc = [[DeviceListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.selectedId = AppState.shared.selectedDeviceId;
    __weak typeof(self) weakSelf = self;
    vc.onSelect = ^(NSDictionary *device) {
        AppState.shared.selectedDeviceId = device[@"id"];
        NSString *cur = AppState.shared.selectedIOS;
        if (!cur.length || ![Catalog.shared device:device supportsIOS:cur]) {
            AppState.shared.selectedIOS = device[@"defaultIOS"] ?: cur;
        }
        [AppState.shared postDidChange];
        [weakSelf refreshUI];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pickIOS {
    IOSListController *vc = [[IOSListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.selectedIOS = AppState.shared.selectedIOS;
    vc.device = [AppState.shared currentDevice];
    __weak typeof(self) weakSelf = self;
    vc.onSelect = ^(NSString *ver) {
        AppState.shared.selectedIOS = ver;
        [AppState.shared postDidChange];
        [weakSelf refreshUI];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)applyTapped {
    NSString *msg = [AppState.shared applyReseedOnly:NO];
    [self alert:@"Apply Profile" msg:msg];
}

- (void)reseedTapped {
    NSString *msg = [AppState.shared applyReseedOnly:YES];
    [self alert:@"Reseed Identity" msg:msg];
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Kill Zalo" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
        [AppState.shared killZalo];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
