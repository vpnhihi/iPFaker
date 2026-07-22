#import "MainViewController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "Catalog.h"
#import "AboutLabController.h"
#import "ProgressOverlay.h"
#import "ProfileBuilder.h"

@interface MainViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *deviceModelLabel;
@property (nonatomic, strong) UILabel *deviceVersionLabel;
@property (nonatomic, strong) UILabel *deviceIdfaLabel;
@property (nonatomic, strong) UILabel *ipProxyLabel;
@property (nonatomic, strong) UILabel *ipAddrLabel;
@property (nonatomic, strong) UILabel *ipCountryLabel;
@property (nonatomic, strong) UILabel *ipTzLabel;
/// One-profile SoT for Zalo body: mod | osv | ss
@property (nonatomic, strong) UILabel *sotStatusLabel;

// Collapsible proxy on home
@property (nonatomic, strong) UIView *proxyCard;
@property (nonatomic, strong) UIButton *proxyHeaderBtn;
@property (nonatomic, strong) UIView *proxyBody;
@property (nonatomic, strong) UITextField *proxyPasteField;
@property (nonatomic, strong) UISwitch *proxyEnableSw;
@property (nonatomic, strong) NSLayoutConstraint *proxyBodyHeight;
@property (nonatomic, assign) BOOL proxyExpanded;
@property (nonatomic, assign) BOOL applyingProxyToggle;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.navigationItem.title = @"";
    self.navigationController.navigationBarHidden = YES;
    self.proxyExpanded = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshUI)
                                                 name:AppStateDidChangeNotification
                                               object:nil];

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scroll];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView = content;
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
    ver.text = @"Lab rootless · spoof multi-device";
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
    self.ipProxyLabel = [self bodyLabel];
    self.ipAddrLabel = [self bodyLabel];
    self.ipCountryLabel = [self bodyLabel];
    self.ipTzLabel = [self bodyLabel];

    UIStackView *leftCol = [[UIStackView alloc] initWithArrangedSubviews:@[
        devHeader, self.deviceModelLabel, self.deviceVersionLabel, self.deviceIdfaLabel
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

    // SoT bar — only status that matters for body spoof (mod | osv | ss)
    UIView *sotBar = [[UIView alloc] init];
    sotBar.translatesAutoresizingMaskIntoConstraints = NO;
    sotBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    sotBar.layer.cornerRadius = 8;
    [card addSubview:sotBar];

    UILabel *sotTitle = [[UILabel alloc] init];
    sotTitle.text = @"Body SoT";
    sotTitle.font = AppTheme.captionFont;
    sotTitle.textColor = AppTheme.textSecondary;
    sotTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [sotBar addSubview:sotTitle];

    self.sotStatusLabel = [[UILabel alloc] init];
    self.sotStatusLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    self.sotStatusLabel.textColor = AppTheme.textPrimary;
    self.sotStatusLabel.numberOfLines = 2;
    self.sotStatusLabel.adjustsFontSizeToFitWidth = YES;
    self.sotStatusLabel.minimumScaleFactor = 0.7;
    self.sotStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [sotBar addSubview:self.sotStatusLabel];

    // —— Collapsible proxy (home) ——
    self.proxyCard = [AppTheme roundedCardIn:content];
    self.proxyCard.backgroundColor = AppTheme.cardAlt;
    self.proxyCard.clipsToBounds = YES;

    self.proxyHeaderBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.proxyHeaderBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.proxyHeaderBtn.titleLabel.font = AppTheme.sectionFont;
    self.proxyHeaderBtn.tintColor = AppTheme.textPrimary;
    [self.proxyHeaderBtn setTitleColor:AppTheme.textPrimary forState:UIControlStateNormal];
    self.proxyHeaderBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.proxyHeaderBtn addTarget:self action:@selector(toggleProxyExpanded) forControlEvents:UIControlEventTouchUpInside];
    [self.proxyCard addSubview:self.proxyHeaderBtn];

    self.proxyBody = [[UIView alloc] init];
    self.proxyBody.translatesAutoresizingMaskIntoConstraints = NO;
    self.proxyBody.clipsToBounds = YES;
    [self.proxyCard addSubview:self.proxyBody];

    UILabel *enLab = [[UILabel alloc] init];
    enLab.text = @"Bật proxy trên máy";
    enLab.font = AppTheme.bodyFont;
    enLab.textColor = AppTheme.textPrimary;
    enLab.translatesAutoresizingMaskIntoConstraints = NO;

    self.proxyEnableSw = [[UISwitch alloc] init];
    self.proxyEnableSw.onTintColor = AppTheme.success;
    self.proxyEnableSw.translatesAutoresizingMaskIntoConstraints = NO;
    [self.proxyEnableSw addTarget:self action:@selector(homeProxyEnableChanged:) forControlEvents:UIControlEventValueChanged];

    self.proxyPasteField = [[UITextField alloc] init];
    self.proxyPasteField.placeholder = @"host:port:user:pass";
    self.proxyPasteField.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.proxyPasteField.textColor = AppTheme.textPrimary;
    self.proxyPasteField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.proxyPasteField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.proxyPasteField.keyboardType = UIKeyboardTypeURL;
    self.proxyPasteField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.proxyPasteField.borderStyle = UITextBorderStyleRoundedRect;
    self.proxyPasteField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.proxyPasteField.delegate = self;
    self.proxyPasteField.returnKeyType = UIReturnKeyDone;
    self.proxyPasteField.translatesAutoresizingMaskIntoConstraints = NO;

    [self.proxyBody addSubview:enLab];
    [self.proxyBody addSubview:self.proxyEnableSw];
    [self.proxyBody addSubview:self.proxyPasteField];

    self.proxyBodyHeight = [self.proxyBody.heightAnchor constraintEqualToConstant:0];
    self.proxyBody.hidden = YES;

    // Primary actions
    UIButton *resetDataBtn = [AppTheme primaryButtonWithTitle:@"Đặt lại dữ liệu app"
                                                       target:self
                                                       action:@selector(killTapped)];
    resetDataBtn.backgroundColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.32 alpha:1.0];
    resetDataBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    resetDataBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:resetDataBtn];

    UIButton *applyBtn = [AppTheme primaryButtonWithTitle:@"Đặt lại + Lưu dữ liệu"
                                                   target:self
                                                   action:@selector(applyTapped)];
    applyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:applyBtn];

    UIButton *locBtn = [AppTheme primaryButtonWithTitle:@"Đồng bộ Location"
                                                 target:self
                                                 action:@selector(syncLocationTapped)];
    locBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.42 blue:0.72 alpha:1.0];
    locBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:locBtn];

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

        [card.topAnchor constraintEqualToAnchor:ver.bottomAnchor constant:16],
        [card.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [card.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],

        [cols.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [cols.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [cols.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [sotBar.topAnchor constraintEqualToAnchor:cols.bottomAnchor constant:12],
        [sotBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [sotBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [sotBar.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],

        [sotTitle.topAnchor constraintEqualToAnchor:sotBar.topAnchor constant:8],
        [sotTitle.leadingAnchor constraintEqualToAnchor:sotBar.leadingAnchor constant:10],
        [sotTitle.trailingAnchor constraintEqualToAnchor:sotBar.trailingAnchor constant:-10],
        [self.sotStatusLabel.topAnchor constraintEqualToAnchor:sotTitle.bottomAnchor constant:4],
        [self.sotStatusLabel.leadingAnchor constraintEqualToAnchor:sotTitle.leadingAnchor],
        [self.sotStatusLabel.trailingAnchor constraintEqualToAnchor:sotTitle.trailingAnchor],
        [self.sotStatusLabel.bottomAnchor constraintEqualToAnchor:sotBar.bottomAnchor constant:-8],

        // Proxy card
        [self.proxyCard.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:12],
        [self.proxyCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [self.proxyCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],

        [self.proxyHeaderBtn.topAnchor constraintEqualToAnchor:self.proxyCard.topAnchor constant:4],
        [self.proxyHeaderBtn.leadingAnchor constraintEqualToAnchor:self.proxyCard.leadingAnchor constant:14],
        [self.proxyHeaderBtn.trailingAnchor constraintEqualToAnchor:self.proxyCard.trailingAnchor constant:-14],
        [self.proxyHeaderBtn.heightAnchor constraintEqualToConstant:44],

        [self.proxyBody.topAnchor constraintEqualToAnchor:self.proxyHeaderBtn.bottomAnchor],
        [self.proxyBody.leadingAnchor constraintEqualToAnchor:self.proxyCard.leadingAnchor],
        [self.proxyBody.trailingAnchor constraintEqualToAnchor:self.proxyCard.trailingAnchor],
        [self.proxyBody.bottomAnchor constraintEqualToAnchor:self.proxyCard.bottomAnchor constant:-4],
        self.proxyBodyHeight,

        [enLab.topAnchor constraintEqualToAnchor:self.proxyBody.topAnchor constant:4],
        [enLab.leadingAnchor constraintEqualToAnchor:self.proxyBody.leadingAnchor constant:14],
        [self.proxyEnableSw.centerYAnchor constraintEqualToAnchor:enLab.centerYAnchor],
        [self.proxyEnableSw.trailingAnchor constraintEqualToAnchor:self.proxyBody.trailingAnchor constant:-14],

        [self.proxyPasteField.topAnchor constraintEqualToAnchor:enLab.bottomAnchor constant:10],
        [self.proxyPasteField.leadingAnchor constraintEqualToAnchor:self.proxyBody.leadingAnchor constant:14],
        [self.proxyPasteField.trailingAnchor constraintEqualToAnchor:self.proxyBody.trailingAnchor constant:-14],
        [self.proxyPasteField.heightAnchor constraintEqualToConstant:36],

        [resetDataBtn.topAnchor constraintEqualToAnchor:self.proxyCard.bottomAnchor constant:14],
        [resetDataBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [resetDataBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [resetDataBtn.heightAnchor constraintEqualToConstant:56],

        [applyBtn.topAnchor constraintEqualToAnchor:resetDataBtn.bottomAnchor constant:10],
        [applyBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [applyBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [applyBtn.heightAnchor constraintEqualToConstant:48],

        [locBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:10],
        [locBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
        [locBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
        [locBtn.heightAnchor constraintEqualToConstant:48],
        [locBtn.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-28],
    ]];

    [self updateProxyHeaderTitle];
    [self refreshUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [[AppState shared] loadProxyFromDualPathConfig];
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

#pragma mark - Proxy collapse

- (NSString *)currentProxyPasteLine {
    AppState *st = AppState.shared;
    NSString *host = [st proxyHost] ?: @"";
    NSInteger port = [st proxyPort];
    if (!host.length || port <= 0) return @"";
    NSString *user = [st proxyUsername] ?: @"";
    NSString *pass = [st proxyPassword] ?: @"";
    if (user.length || pass.length)
        return [NSString stringWithFormat:@"%@:%ld:%@:%@", host, (long)port, user, pass];
    return [NSString stringWithFormat:@"%@:%ld", host, (long)port];
}

- (void)updateProxyHeaderTitle {
    AppState *st = AppState.shared;
    NSString *chev = self.proxyExpanded ? @"▼" : @"▶";
    NSString *state = [st proxyEnabled] && [st proxyHost].length
        ? [NSString stringWithFormat:@"ON · %@:%ld", [st proxyHost], (long)[st proxyPort]]
        : @"Tắt";
    [self.proxyHeaderBtn setTitle:[NSString stringWithFormat:@"%@  Proxy  ·  %@", chev, state]
                         forState:UIControlStateNormal];
}

- (void)toggleProxyExpanded {
    self.proxyExpanded = !self.proxyExpanded;
    self.proxyBodyHeight.constant = self.proxyExpanded ? 96 : 0;
    self.proxyBody.hidden = !self.proxyExpanded;
    [self updateProxyHeaderTitle];
    [UIView animateWithDuration:0.22 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)homeProxyEnableChanged:(UISwitch *)sw {
    if (self.applyingProxyToggle) return;
    [self.view endEditing:YES];
    self.applyingProxyToggle = YES;

    NSString *err = nil;
    NSString *line = self.proxyPasteField.text ?: @"";
    if (sw.on) {
        if (!line.length || ![[AppState shared] applyProxyPasteLine:line error:&err]) {
            self.applyingProxyToggle = NO;
            sw.on = NO;
            [self showAlertTitle:@"Proxy" message:err ?: @"Dán host:port:user:pass trước khi bật"];
            return;
        }
        [[AppState shared] setProxyEnabled:YES];
    } else {
        if (line.length)
            [[AppState shared] applyProxyPasteLine:line error:nil];
        [[AppState shared] setProxyEnabled:NO];
    }
    [[AppState shared] saveProxyAppAttest];

    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:sw.on ? @"Bật proxy…" : @"Tắt proxy…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = nil;
        if (sw.on) {
            msg = [[AppState shared] applyProxyAppAttestToConfigProgress:^(NSString *s) {
                [ov appendStep:s];
            }];
        } else {
            NSDictionary *keys = [[AppState shared] proxyAppAttestFlatKeys];
            msg = [ProfileBuilder mergeKeysIntoConfig:keys progress:^(NSString *s) {
                [ov appendStep:s];
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.applyingProxyToggle = NO;
            [self updateProxyHeaderTitle];
            [self refreshUI];
            [ov finishWithTitle:sw.on ? @"Proxy ON" : @"Proxy OFF" detail:msg];
            [ov dismissAfter:1.0 completion:nil];
        });
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (textField == self.proxyPasteField && textField.text.length) {
        NSString *err = nil;
        [[AppState shared] applyProxyPasteLine:textField.text error:&err];
        if (err.length) [self showAlertTitle:@"Proxy" message:err];
        else {
            self.proxyPasteField.text = [self currentProxyPasteLine];
            [self updateProxyHeaderTitle];
        }
    }
    return YES;
}

#pragma mark - UI data

/// Read dual-path config for live SoT (prefer disk over in-memory so user sees truth after PC deploy).
- (NSDictionary *)liveFlatForSoT {
    NSDictionary *disk = [ProfileBuilder loadCurrentFlat];
    if (disk.count) return disk;
    return AppState.shared.lastFlat ?: @{};
}

- (void)refreshSoTBar {
    NSDictionary *flat = [self liveFlatForSoT];
    NSString *mod = [flat[@"mod"] description] ?: @"";
    NSString *osv = [flat[@"osv"] description] ?: @"";
    NSString *ss  = [flat[@"ss"] description] ?: @"";
    // Fallbacks so bar is still useful if only Class A present
    if (!mod.length) mod = [flat[@"ProductType"] description] ?: @"";
    if (!osv.length) osv = [flat[@"ProductVersion"] description] ?: @"";
    if (!ss.length) {
        id nw = flat[@"main-screen-width"];
        id nh = flat[@"main-screen-height"];
        if (nw && nh) ss = [NSString stringWithFormat:@"%@x%@", nw, nh];
        else ss = [flat[@"ScreenSizeString"] description] ?: @"";
    }
    BOOL hasMod = mod.length > 0;
    BOOL hasOsv = osv.length > 0;
    BOOL hasSs  = ss.length > 0;
    // Strict: aliases mod/osv/ss present (body rewrite SoT)
    BOOL strict = flat[@"mod"] && flat[@"osv"] && flat[@"ss"]
        && [[flat[@"mod"] description] length]
        && [[flat[@"osv"] description] length]
        && [[flat[@"ss"] description] length];
    // Consistency with Class A
    BOOL match = YES;
    if (strict) {
        NSString *pt = [flat[@"ProductType"] description] ?: @"";
        NSString *pv = [flat[@"ProductVersion"] description] ?: @"";
        if (pt.length && ![mod isEqualToString:pt]) match = NO;
        if (pv.length && ![osv isEqualToString:pv]) match = NO;
    }

    NSString *modShow = hasMod ? mod : @"—";
    NSString *osvShow = hasOsv ? osv : @"—";
    NSString *ssShow  = hasSs  ? ss  : @"—";
    NSString *line = [NSString stringWithFormat:@"%@  |  %@  |  %@", modShow, osvShow, ssShow];

    if (!flat.count) {
        self.sotStatusLabel.text = @"—  |  —  |  —   ·  chưa có config";
        self.sotStatusLabel.textColor = AppTheme.textSecondary;
    } else if (strict && match) {
        self.sotStatusLabel.text = [NSString stringWithFormat:@"%@   ·  OK", line];
        self.sotStatusLabel.textColor = AppTheme.success;
    } else if (hasMod && hasOsv && hasSs) {
        // Values present via fallback only (no explicit mod/osv/ss keys)
        self.sotStatusLabel.text = [NSString stringWithFormat:@"%@   ·  thiếu key mod/osv/ss", line];
        self.sotStatusLabel.textColor = [UIColor colorWithRed:0.95 green:0.7 blue:0.2 alpha:1];
    } else {
        NSMutableArray *miss = [NSMutableArray array];
        if (!hasMod) [miss addObject:@"mod"];
        if (!hasOsv) [miss addObject:@"osv"];
        if (!hasSs)  [miss addObject:@"ss"];
        self.sotStatusLabel.text = [NSString stringWithFormat:@"%@   ·  thiếu %@",
                                    line, [miss componentsJoinedByString:@"+"]];
        self.sotStatusLabel.textColor = [UIColor colorWithRed:0.95 green:0.35 blue:0.3 alpha:1];
    }
}

- (void)refreshUI {
    AppState *st = AppState.shared;
    NSDictionary *dev = [st currentDevice] ?: @{};
    NSDictionary *flat = [self liveFlatForSoT];
    if (!flat.count) flat = st.lastFlat ?: @{};
    NSString *model = flat[@"MarketingName"] ?: dev[@"MarketingName"] ?: @"—";
    NSString *ios = flat[@"ProductVersion"] ?: st.selectedIOS ?: @"—";
    NSString *idfa = flat[@"IDFA"] ?: @"—";
    if (idfa.length > 22) idfa = [[idfa substringToIndex:20] stringByAppendingString:@"…"];

    self.deviceModelLabel.text = [NSString stringWithFormat:@"Model: %@", model];
    self.deviceVersionLabel.text = [NSString stringWithFormat:@"Phiên bản: %@", ios];
    self.deviceIdfaLabel.text = [NSString stringWithFormat:@"IDFA: %@", idfa];

    self.ipProxyLabel.text = [NSString stringWithFormat:@"Loại: %@", flat[@"ProductType"] ?: dev[@"ProductType"] ?: @"—"];
    self.ipAddrLabel.text = [NSString stringWithFormat:@"Sê-ri: %@", flat[@"SerialNumber"] ?: @"—"];
    self.ipCountryLabel.text = [NSString stringWithFormat:@"Vùng: %@", flat[@"RegionCode"] ?: flat[@"PartNumberRegion"] ?: @"VN"];
    self.ipTzLabel.text = [NSString stringWithFormat:@"Chip: %@", flat[@"ChipName"] ?: dev[@"chip"] ?: @"—"];

    if (!self.applyingProxyToggle) {
        self.proxyPasteField.text = [self currentProxyPasteLine];
        self.proxyEnableSw.on = [st proxyEnabled];
    }
    [self updateProxyHeaderTitle];
    [self refreshSoTBar];
}

#pragma mark - Actions

- (void)applyTapped {
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    if (!host) host = self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đặt lại + Lưu…"];
    if (!ov) return;
    self.view.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = nil;
        @try {
            msg = [AppState.shared saveDataThenResetProgress:^(NSString *step) {
                [ov appendStep:step];
            }];
        } @catch (NSException *ex) {
            msg = [NSString stringWithFormat:@"Lỗi: %@", ex.reason ?: @"exception"];
        }
        if (!msg.length) msg = @"Xong";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            // Short overlay only — no extra UIAlert (noise)
            BOOL err = [msg hasPrefix:@"Lỗi"] || [msg containsString:@"FAIL"] || [msg containsString:@"trống"];
            NSString *shortDetail = err ? msg : @"SoT đã ghi · xem Body SoT phía trên";
            if (shortDetail.length > 90)
                shortDetail = [[shortDetail substringToIndex:87] stringByAppendingString:@"…"];
            [ov finishWithTitle:err ? @"Lỗi" : @"OK" detail:shortDetail];
            [self refreshUI];
            [ov dismissAfter:err ? 2.0 : 0.9 completion:nil];
            if (err) [self showAlertTitle:@"Đặt lại + Lưu" message:msg];
        });
    });
}

- (void)killTapped {
    // No confirm dialog — run directly; overlay shows progress
    [self runResetAppData];
}

- (void)runResetAppData {
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    if (!host) host = self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đặt lại dữ liệu app…"];
    if (!ov) return;
    self.view.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = nil;
        @try {
            msg = [AppState.shared killZaloAndRandomizeFromPoolProgress:^(NSString *step) {
                [ov appendStep:step];
            }];
        } @catch (NSException *ex) {
            msg = [NSString stringWithFormat:@"Lỗi: %@", ex.reason ?: @"exception"];
        }
        if (!msg.length) msg = @"Xong";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            BOOL err = [msg hasPrefix:@"Lỗi"] || [msg containsString:@"FAIL"];
            [ov finishWithTitle:err ? @"Lỗi" : @"OK"
                         detail:err ? msg : @"Session wipe · SoT mới"];
            [self refreshUI];
            [ov dismissAfter:err ? 2.0 : 0.9 completion:nil];
            if (err) [self showAlertTitle:@"Đặt lại dữ liệu app" message:msg];
        });
    });
}

- (void)syncLocationTapped {
    [self.view endEditing:YES];
    if (self.proxyPasteField.text.length)
        [[AppState shared] applyProxyPasteLine:self.proxyPasteField.text error:nil];
    UIView *host = self.tabBarController.view ?: self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đồng bộ Location…"];
    self.view.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = [AppState.shared syncLocationNowProgress:^(NSString *step) {
            [ov appendStep:step];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.userInteractionEnabled = YES;
            BOOL ok = [msg containsString:@"Đã đồng bộ"] || [msg containsString:@"random"] || [msg containsString:@"Latitude"]
                || (![msg hasPrefix:@"Bật proxy"] && ![msg containsString:@"FAIL"]);
            NSString *shortDetail = ok ? @"Geo OK" : (msg.length > 80 ? [[msg substringToIndex:77] stringByAppendingString:@"…"] : msg);
            [ov finishWithTitle:ok ? @"OK" : @"Location" detail:shortDetail];
            [self refreshUI];
            [ov dismissAfter:ok ? 0.9 : 1.5 completion:nil];
            if (!ok) [self showAlertTitle:@"Location" message:msg];
        });
    });
}

- (void)openAbout {
    AboutLabController *vc = [[AboutLabController alloc] init];
    vc.device = [AppState.shared currentDevice];
    vc.iosVer = AppState.shared.selectedIOS;
    vc.iosMeta = [AppState.shared currentIOSMeta];
    // Live dual-path SoT (disk) so Lab About matches Settings / config.plist — not stale lastFlat
    NSDictionary *live = [self liveFlatForSoT];
    if (live.count) {
        vc.flat = live;
        AppState.shared.lastFlat = live;
    } else {
        vc.flat = AppState.shared.lastFlat;
    }
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
