#import "MainViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "Catalog.h"
#import "AboutLabController.h"
#import "ProgressOverlay.h"

@interface MainViewController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *deviceModelLabel;
@property (nonatomic, strong) UILabel *deviceVersionLabel;
@property (nonatomic, strong) UILabel *deviceIdfaLabel;
@property (nonatomic, strong) UILabel *deviceStatusLabel;
@property (nonatomic, strong) UILabel *ipProxyLabel;
@property (nonatomic, strong) UILabel *ipAddrLabel;
@property (nonatomic, strong) UILabel *ipCountryLabel;
@property (nonatomic, strong) UILabel *ipTzLabel;
@property (nonatomic, strong) UILabel *statusFooter;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.navigationItem.title = @"";
    self.navigationController.navigationBarHidden = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshUI)
                                                 name:AppStateDidChangeNotification
                                               object:nil];

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:self.scroll.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.scroll.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scroll.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scroll.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scroll.widthAnchor],
    ]];

    // Header
    UILabel *title = [[UILabel alloc] init];
    title.text = @"iPFaker";
    title.font = AppTheme.titleFont;
    title.textColor = AppTheme.textPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *ver = [[UILabel alloc] init];
    ver.text = @"Phiên bản: 2.6.2 · Công cụ lab thiết bị";
    ver.font = AppTheme.captionFont;
    ver.textColor = AppTheme.textSecondary;
    ver.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *aboutBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [aboutBtn setImage:[UIImage systemImageNamed:@"person.circle"] forState:UIControlStateNormal];
    } else {
        [aboutBtn setTitle:@"ⓘ" forState:UIControlStateNormal];
    }
    aboutBtn.tintColor = AppTheme.accent;
    aboutBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [aboutBtn addTarget:self action:@selector(openAbout) forControlEvents:UIControlEventTouchUpInside];

    [content addSubview:title];
    [content addSubview:ver];
    [content addSubview:aboutBtn];

    // Info card
    UIView *card = [AppTheme roundedCardIn:content];

    UILabel *devHeader = [self boldLabel:@"Thông tin máy"];
    UILabel *ipHeader = [self boldLabel:@"Hồ sơ ảo"];

    self.deviceModelLabel = [self bodyLabel];
    self.deviceVersionLabel = [self bodyLabel];
    self.deviceIdfaLabel = [self bodyLabel];
    self.deviceStatusLabel = [self bodyLabel];
    self.ipProxyLabel = [self bodyLabel];
    self.ipAddrLabel = [self bodyLabel];
    self.ipCountryLabel = [self bodyLabel];
    self.ipTzLabel = [self bodyLabel];

    UIStackView *leftCol = [[UIStackView alloc] initWithArrangedSubviews:@[
        devHeader, self.deviceModelLabel, self.deviceVersionLabel, self.deviceIdfaLabel, self.deviceStatusLabel
    ]];
    leftCol.axis = UILayoutConstraintAxisVertical;
    leftCol.spacing = 6;
    leftCol.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *rightCol = [[UIStackView alloc] initWithArrangedSubviews:@[
        ipHeader, self.ipProxyLabel, self.ipAddrLabel, self.ipCountryLabel, self.ipTzLabel
    ]];
    rightCol.axis = UILayoutConstraintAxisVertical;
    rightCol.spacing = 6;
    rightCol.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *cols = [[UIStackView alloc] initWithArrangedSubviews:@[leftCol, rightCol]];
    cols.axis = UILayoutConstraintAxisHorizontal;
    cols.distribution = UIStackViewDistributionFillEqually;
    cols.spacing = 12;
    cols.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cols];

    UILabel *contact = [[UILabel alloc] init];
    contact.text = @"Công cụ lab · không can thiệp Cài đặt hệ thống";
    contact.font = AppTheme.captionFont;
    contact.textColor = AppTheme.accent;
    contact.numberOfLines = 2;
    contact.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:contact];

    // Nút: Đặt lại dữ liệu app | Đặt lại + Lưu dữ liệu
    UIButton *resetDataBtn = [AppTheme primaryButtonWithTitle:@"Đặt lại dữ liệu app"
                                                       target:self
                                                       action:@selector(killTapped)];
    resetDataBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.1 alpha:1.0];
    UIButton *applyBtn = [AppTheme primaryButtonWithTitle:@"Đặt lại + Lưu dữ liệu"
                                                   target:self
                                                   action:@selector(applyTapped)];

    UIStackView *btnRow = [[UIStackView alloc] initWithArrangedSubviews:@[resetDataBtn, applyBtn]];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 12;
    btnRow.distribution = UIStackViewDistributionFillEqually;
    btnRow.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:btnRow];

    // Quick toggles (subset)
    UIView *toggleCard = [AppTheme roundedCardIn:content];
    toggleCard.backgroundColor = AppTheme.cardAlt;
    NSArray *quick = @[
        @[ @"Giả lập thiết bị", @"FakeDevice" ],
        @[ @"Giả lập màn hình", @"FakeScreen" ],
        @[ @"Giả lập mạng", @"FakeNetwork" ],
        @[ @"Ẩn jailbreak", @"HideJailbreak" ],
    ];
    UIStackView *toggles = [[UIStackView alloc] init];
    toggles.axis = UILayoutConstraintAxisVertical;
    toggles.spacing = 0;
    toggles.translatesAutoresizingMaskIntoConstraints = NO;
    [toggleCard addSubview:toggles];
    for (NSArray *row in quick) {
        [toggles addArrangedSubview:[self toggleRowTitle:row[0] key:row[1]]];
    }

    // Terms / disclaimer card (replaces old kill button area)
    UIView *termsCard = [AppTheme roundedCardIn:content];
    termsCard.backgroundColor = AppTheme.cardAlt;
    UILabel *termsTitle = [[UILabel alloc] init];
    termsTitle.text = @"Điều khoản · Trách nhiệm · Miễn trừ";
    termsTitle.font = AppTheme.sectionFont;
    termsTitle.textColor = AppTheme.textPrimary;
    termsTitle.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *termsBody = [[UILabel alloc] init];
    termsBody.numberOfLines = 0;
    termsBody.font = AppTheme.captionFont;
    termsBody.textColor = AppTheme.textSecondary;
    termsBody.text =
        @"ĐIỀU KHOẢN DỊCH VỤ\n"
        @"Công cụ này chỉ dành cho mục đích nghiên cứu, kiểm thử kỹ thuật trên thiết bị do bạn sở hữu hợp pháp.\n\n"
        @"TRÁCH NHIỆM KHÁCH HÀNG\n"
        @"Bạn chịu toàn bộ trách nhiệm về cách sử dụng, cấu hình và hậu quả phát sinh từ việc dùng tool. Không chia sẻ cấu hình để lừa đảo, mạo danh, hoặc can thiệp trái phép hệ thống của bên thứ ba.\n\n"
        @"MIỄN TRỪ TRÁCH NHIỆM / CẢNH BÁO\n"
        @"Cấm sử dụng tool vào mục đích vi phạm pháp luật Việt Nam (bao gồm nhưng không giới hạn: lừa đảo, gian lận, xâm phạm dữ liệu, mạo danh). Nhà phát triển không chịu trách nhiệm hình sự/dân sự nếu người dùng cố ý sử dụng sai mục đích. Tiếp tục dùng tool đồng nghĩa bạn đã đọc và chấp nhận các điều khoản trên.";
    termsBody.translatesAutoresizingMaskIntoConstraints = NO;
    [termsCard addSubview:termsTitle];
    [termsCard addSubview:termsBody];

    self.statusFooter = [[UILabel alloc] init];
    self.statusFooter.font = AppTheme.captionFont;
    self.statusFooter.textColor = AppTheme.textSecondary;
    self.statusFooter.numberOfLines = 0;
    self.statusFooter.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.statusFooter];

    CGFloat pad = 16;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [ver.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [ver.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [aboutBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [aboutBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [aboutBtn.widthAnchor constraintEqualToConstant:36],
        [aboutBtn.heightAnchor constraintEqualToConstant:36],

        [card.topAnchor constraintEqualToAnchor:ver.bottomAnchor constant:18],
        [card.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [card.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],

        [cols.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [cols.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [cols.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [contact.topAnchor constraintEqualToAnchor:cols.bottomAnchor constant:14],
        [contact.leadingAnchor constraintEqualToAnchor:cols.leadingAnchor],
        [contact.trailingAnchor constraintEqualToAnchor:cols.trailingAnchor],
        [contact.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],

        [btnRow.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:14],
        [btnRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [btnRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [resetDataBtn.heightAnchor constraintEqualToConstant:56],
        [applyBtn.heightAnchor constraintEqualToConstant:56],

        [toggleCard.topAnchor constraintEqualToAnchor:btnRow.bottomAnchor constant:16],
        [toggleCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [toggleCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],

        [toggles.topAnchor constraintEqualToAnchor:toggleCard.topAnchor constant:4],
        [toggles.leadingAnchor constraintEqualToAnchor:toggleCard.leadingAnchor constant:14],
        [toggles.trailingAnchor constraintEqualToAnchor:toggleCard.trailingAnchor constant:-14],
        [toggles.bottomAnchor constraintEqualToAnchor:toggleCard.bottomAnchor constant:-4],

        [termsCard.topAnchor constraintEqualToAnchor:toggleCard.bottomAnchor constant:14],
        [termsCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [termsCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],

        [termsTitle.topAnchor constraintEqualToAnchor:termsCard.topAnchor constant:12],
        [termsTitle.leadingAnchor constraintEqualToAnchor:termsCard.leadingAnchor constant:14],
        [termsTitle.trailingAnchor constraintEqualToAnchor:termsCard.trailingAnchor constant:-14],
        [termsBody.topAnchor constraintEqualToAnchor:termsTitle.bottomAnchor constant:8],
        [termsBody.leadingAnchor constraintEqualToAnchor:termsTitle.leadingAnchor],
        [termsBody.trailingAnchor constraintEqualToAnchor:termsTitle.trailingAnchor],
        [termsBody.bottomAnchor constraintEqualToAnchor:termsCard.bottomAnchor constant:-12],

        [self.statusFooter.topAnchor constraintEqualToAnchor:termsCard.bottomAnchor constant:14],
        [self.statusFooter.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [self.statusFooter.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [self.statusFooter.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-28],
    ]];

    [self refreshUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [self refreshUI];
}

- (UILabel *)boldLabel:(NSString *)t {
    UILabel *l = [[UILabel alloc] init];
    l.text = t;
    l.font = AppTheme.sectionFont;
    l.textColor = AppTheme.textPrimary;
    return l;
}

- (UILabel *)bodyLabel {
    UILabel *l = [[UILabel alloc] init];
    l.font = AppTheme.bodyFont;
    l.textColor = AppTheme.textSecondary;
    l.numberOfLines = 2;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.75;
    return l;
}

- (UIView *)toggleRowTitle:(NSString *)title key:(NSString *)key {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lab = [[UILabel alloc] init];
    lab.text = title;
    lab.font = AppTheme.bodyFont;
    lab.textColor = AppTheme.textPrimary;
    lab.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = AppTheme.success;
    sw.on = [AppState.shared toggleForKey:key defaultOn:YES];
    sw.accessibilityIdentifier = key;
    [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    sw.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:lab];
    [row addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:48],
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [lab.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8],
    ]];
    return row;
}

- (void)toggleChanged:(UISwitch *)sw {
    NSString *key = sw.accessibilityIdentifier;
    if (key.length) [AppState.shared setToggle:sw.on forKey:key];
}

- (void)refreshUI {
    AppState *st = AppState.shared;
    NSDictionary *dev = [st currentDevice] ?: @{};
    NSDictionary *flat = st.lastFlat ?: @{};
    NSString *model = flat[@"MarketingName"] ?: dev[@"MarketingName"] ?: @"—";
    NSString *ios = flat[@"ProductVersion"] ?: st.selectedIOS ?: @"—";
    NSString *idfa = flat[@"IDFA"] ?: @"— (Apply để sinh)";
    if (idfa.length > 22) idfa = [[idfa substringToIndex:20] stringByAppendingString:@"…"];
    BOOL worked = flat.count > 0;

    self.deviceModelLabel.text = [NSString stringWithFormat:@"Model: %@", model];
    self.deviceVersionLabel.text = [NSString stringWithFormat:@"Phiên bản: %@", ios];
    self.deviceIdfaLabel.text = [NSString stringWithFormat:@"IDFA: %@", idfa];
    self.deviceStatusLabel.text = worked ? @"Trạng thái: Đã áp dụng" : @"Trạng thái: Chưa áp dụng";
    self.deviceStatusLabel.textColor = worked ? AppTheme.success : AppTheme.textSecondary;

    self.ipProxyLabel.text = [NSString stringWithFormat:@"Loại: %@", flat[@"ProductType"] ?: dev[@"ProductType"] ?: @"—"];
    self.ipAddrLabel.text = [NSString stringWithFormat:@"Sê-ri: %@", flat[@"SerialNumber"] ?: @"—"];
    self.ipCountryLabel.text = [NSString stringWithFormat:@"Vùng: %@", flat[@"RegionCode"] ?: flat[@"PartNumberRegion"] ?: @"VN"];
    self.ipTzLabel.text = [NSString stringWithFormat:@"Chip: %@", flat[@"ChipName"] ?: dev[@"chip"] ?: @"—"];

    NSUInteger nDev = Catalog.shared.devices.count;
    NSUInteger nIOS = Catalog.shared.iosReleases.count;
    self.statusFooter.text = [NSString stringWithFormat:@"%@\nDanh mục: %lu máy · %lu iOS",
                              st.statusText ?: @"",
                              (unsigned long)nDev, (unsigned long)nIOS];
}

- (void)applyTapped {
    // Đặt lại + Lưu: random identity + ghi config
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đang đặt lại + lưu…"];
    self.view.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [ov appendStep:@"Đang chọn ngẫu nhiên máy + iOS…"];
        NSString *msg = [AppState.shared applyRandomFromPool];
        [ov appendStep:@"Đã ghi hồ sơ cấu hình"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            [ov finishWithTitle:@"Đã lưu" detail:msg];
            [self refreshUI];
            [ov dismissAfter:1.2 completion:^{
                [self showAlertTitle:@"Đặt lại + Lưu dữ liệu" message:msg];
            }];
        });
    });
}

- (void)killTapped {
    // Đặt lại dữ liệu app: random spoof + xóa data
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đang đặt lại dữ liệu app…"];
    self.view.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = [AppState.shared killZaloAndRandomizeFromPoolProgress:^(NSString *step) {
            [ov appendStep:step];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            [ov finishWithTitle:@"Hoàn tất" detail:msg];
            [self refreshUI];
            [ov dismissAfter:1.6 completion:^{
                [self showAlertTitle:@"Đặt lại dữ liệu app" message:msg];
            }];
        });
    });
}

- (void)openAbout {
    AboutLabController *vc = [[AboutLabController alloc] init];
    vc.device = [AppState.shared currentDevice];
    vc.iosVer = AppState.shared.selectedIOS;
    vc.iosMeta = [AppState.shared currentIOSMeta];
    vc.flat = AppState.shared.lastFlat;
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAlertTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
