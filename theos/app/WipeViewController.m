#import "WipeViewController.h"
#import "AppTheme.h"
#import "AppState.h"

@implementation WipeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppTheme.bg;
    self.title = @"Wipe App";
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"Wipe / Reset";
    header.font = AppTheme.titleFont;
    header.textColor = AppTheme.textPrimary;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UILabel *note = [[UILabel alloc] init];
    note.text = @"Kill Zalo = random máy+iOS + XÓA SẠCH 100% data Zalo (container, App Group, prefs, keychain best-effort). Mở lại = màn login mới.";
    note.font = AppTheme.bodyFont;
    note.textColor = AppTheme.textSecondary;
    note.numberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:note];

    UIButton *kill = [AppTheme primaryButtonWithTitle:@"Kill Zalo + Random + Wipe 100%"
                                               target:self
                                               action:@selector(killTapped)];
    UIButton *reseed = [AppTheme primaryButtonWithTitle:@"Apply primary (giữ data Zalo)"
                                                 target:self
                                                 action:@selector(reseedTapped)];
    reseed.backgroundColor = AppTheme.accentDark;

    UIButton *wipe = [UIButton buttonWithType:UIButtonTypeSystem];
    [wipe setTitle:@"Chỉ xóa sạch data Zalo (không random)" forState:UIControlStateNormal];
    [wipe setTitleColor:UIColor.systemOrangeColor forState:UIControlStateNormal];
    wipe.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    wipe.backgroundColor = AppTheme.card;
    wipe.layer.cornerRadius = 14;
    wipe.translatesAutoresizingMaskIntoConstraints = NO;
    [wipe addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[kill, reseed, wipe]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    CGFloat pad = 16;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [note.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [note.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [note.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [stack.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-pad],
        [kill.heightAnchor constraintEqualToConstant:54],
        [reseed.heightAnchor constraintEqualToConstant:54],
        [wipe.heightAnchor constraintEqualToConstant:54],
    ]];
}

- (void)killTapped {
    [AppState.shared killZalo];
    [self alert:@"Kill Zalo" msg:AppState.shared.statusText];
}

- (void)reseedTapped {
    NSString *m = [AppState.shared applyReseedOnly:YES];
    [self alert:@"Reseed" msg:m];
}

- (void)wipeTapped {
    NSString *m = [AppState.shared wipeZaloLab];
    [self alert:@"Wipe" msg:m];
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t
                                                               message:m
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
