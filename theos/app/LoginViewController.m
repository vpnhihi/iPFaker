#import "LoginViewController.h"
#import "AppTheme.h"
#import "IPFLicenseManager.h"

@interface LoginViewController ()
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UILabel *deviceIdLabel;
@property (nonatomic, strong) UILabel *msgLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@property (nonatomic, strong) UIButton *activateBtn;
@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.navigationItem.title = @"Kích hoạt";

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIView *c = [[UIView alloc] init];
    c.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:c];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"iPFaker · Đăng nhập key";
    title.font = AppTheme.titleFont;
    title.textColor = AppTheme.textPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *hint = [[UILabel alloc] init];
    hint.numberOfLines = 0;
    hint.font = AppTheme.captionFont;
    hint.textColor = AppTheme.textSecondary;
    hint.text =
        @"1) Copy ID máy bên dưới → dán vào cột D trên Google Sheet (cùng dòng key).\n"
        @"2) Cột B = Key · Cột C = số ngày · Cột E = Chạy.\n"
        @"3) Nhập key → Kích hoạt.\n\n"
        @"Sheet phải chia sẻ: Anyone with the link → Viewer.";
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *idTitle = [[UILabel alloc] init];
    idTitle.text = @"ID máy (cột D)";
    idTitle.font = AppTheme.sectionFont;
    idTitle.textColor = AppTheme.textPrimary;
    idTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.deviceIdLabel = [[UILabel alloc] init];
    self.deviceIdLabel.text = [IPFLicenseManager.shared deviceId];
    self.deviceIdLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    self.deviceIdLabel.textColor = AppTheme.accent;
    self.deviceIdLabel.numberOfLines = 2;
    self.deviceIdLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *copyBtn = [AppTheme primaryButtonWithTitle:@"Copy ID máy" target:self action:@selector(copyId)];
    copyBtn.backgroundColor = [UIColor colorWithRed:0.25 green:0.45 blue:0.75 alpha:1];

    UILabel *keyTitle = [[UILabel alloc] init];
    keyTitle.text = @"Key (cột B)";
    keyTitle.font = AppTheme.sectionFont;
    keyTitle.textColor = AppTheme.textPrimary;
    keyTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.keyField = [[UITextField alloc] init];
    self.keyField.placeholder = @"Ví dụ: Key1";
    self.keyField.borderStyle = UITextBorderStyleRoundedRect;
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyField.backgroundColor = AppTheme.card;
    self.keyField.textColor = AppTheme.textPrimary;
    self.keyField.translatesAutoresizingMaskIntoConstraints = NO;

    self.activateBtn = [AppTheme primaryButtonWithTitle:@"Kích hoạt" target:self action:@selector(activate)];
    self.activateBtn.backgroundColor = AppTheme.success;

    self.msgLabel = [[UILabel alloc] init];
    self.msgLabel.numberOfLines = 0;
    self.msgLabel.font = AppTheme.captionFont;
    self.msgLabel.textColor = AppTheme.textSecondary;
    self.msgLabel.translatesAutoresizingMaskIntoConstraints = NO;

    if (@available(iOS 13.0, *)) {
        self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.spin.translatesAutoresizingMaskIntoConstraints = NO;
    self.spin.hidesWhenStopped = YES;

    for (UIView *v in @[ title, hint, idTitle, self.deviceIdLabel, copyBtn, keyTitle, self.keyField, self.activateBtn, self.msgLabel, self.spin ]) {
        [c addSubview:v];
    }

    CGFloat p = 20;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [c.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [c.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [c.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [c.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [c.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],

        [title.topAnchor constraintEqualToAnchor:c.topAnchor constant:24],
        [title.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:p],
        [title.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-p],

        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [hint.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [idTitle.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:20],
        [idTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],

        [self.deviceIdLabel.topAnchor constraintEqualToAnchor:idTitle.bottomAnchor constant:8],
        [self.deviceIdLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.deviceIdLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [copyBtn.topAnchor constraintEqualToAnchor:self.deviceIdLabel.bottomAnchor constant:12],
        [copyBtn.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [copyBtn.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [copyBtn.heightAnchor constraintEqualToConstant:48],

        [keyTitle.topAnchor constraintEqualToAnchor:copyBtn.bottomAnchor constant:22],
        [keyTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],

        [self.keyField.topAnchor constraintEqualToAnchor:keyTitle.bottomAnchor constant:8],
        [self.keyField.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.keyField.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.keyField.heightAnchor constraintEqualToConstant:44],

        [self.activateBtn.topAnchor constraintEqualToAnchor:self.keyField.bottomAnchor constant:16],
        [self.activateBtn.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.activateBtn.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.activateBtn.heightAnchor constraintEqualToConstant:52],

        [self.spin.topAnchor constraintEqualToAnchor:self.activateBtn.bottomAnchor constant:16],
        [self.spin.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],

        [self.msgLabel.topAnchor constraintEqualToAnchor:self.spin.bottomAnchor constant:12],
        [self.msgLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.msgLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.msgLabel.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-40],
    ]];
}

- (void)copyId {
    UIPasteboard.generalPasteboard.string = [IPFLicenseManager.shared deviceId];
    self.msgLabel.textColor = AppTheme.success;
    self.msgLabel.text = @"Đã copy ID máy — dán vào cột D trên Sheet.";
}

- (void)activate {
    [self.view endEditing:YES];
    NSString *key = self.keyField.text ?: @"";
    self.activateBtn.enabled = NO;
    [self.spin startAnimating];
    self.msgLabel.textColor = AppTheme.textSecondary;
    self.msgLabel.text = @"Đang kiểm tra Sheet…";
    __weak typeof(self) weakSelf = self;
    [IPFLicenseManager.shared activateWithKey:key completion:^(BOOL ok, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        [self.spin stopAnimating];
        self.activateBtn.enabled = YES;
        self.msgLabel.text = message;
        self.msgLabel.textColor = ok ? AppTheme.success : [UIColor colorWithRed:0.9 green:0.35 blue:0.3 alpha:1];
        if (ok && self.onSuccess) self.onSuccess();
    }];
}

@end
