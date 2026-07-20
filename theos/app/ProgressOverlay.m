#import "ProgressOverlay.h"
#import "AppTheme.h"

@interface ProgressOverlay ()
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *stepLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableString *log;
@end

@implementation ProgressOverlay

+ (instancetype)showOn:(UIView *)host title:(NSString *)title {
    ProgressOverlay *o = [[ProgressOverlay alloc] initWithFrame:host.bounds];
    o.host = host;
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [o buildUI];
    o.titleLabel.text = title ?: @"Đang xử lý…";
    o.alpha = 0;
    [host addSubview:o];
    [UIView animateWithDuration:0.2 animations:^{ o.alpha = 1; }];
    [o.spinner startAnimating];
    return o;
}

- (void)buildUI {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    self.log = [NSMutableString string];

    self.card = [[UIView alloc] init];
    self.card.backgroundColor = AppTheme.card;
    self.card.layer.cornerRadius = 18;
    self.card.clipsToBounds = YES;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.card];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = AppTheme.accent;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.spinner];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.titleLabel.textColor = AppTheme.textPrimary;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.titleLabel];

    self.stepLabel = [[UILabel alloc] init];
    self.stepLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.stepLabel.textColor = AppTheme.accent;
    self.stepLabel.textAlignment = NSTextAlignmentCenter;
    self.stepLabel.numberOfLines = 3;
    self.stepLabel.text = @"…";
    self.stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.stepLabel];

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.selectable = NO;
    self.logView.backgroundColor = AppTheme.cardAlt;
    self.logView.textColor = AppTheme.textSecondary;
    if (@available(iOS 13.0, *)) {
        self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    } else {
        self.logView.font = [UIFont systemFontOfSize:11];
    }
    self.logView.layer.cornerRadius = 10;
    self.logView.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:28],
        [self.card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-28],
        [self.card.heightAnchor constraintEqualToConstant:340],

        [self.spinner.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:20],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:12],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],

        [self.stepLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.stepLabel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [self.stepLabel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],

        [self.logView.topAnchor constraintEqualToAnchor:self.stepLabel.bottomAnchor constant:12],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-12],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-14],
    ]];
}

- (void)setTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.titleLabel.text = title;
    });
}

- (void)appendStep:(NSString *)step {
    if (!step.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.stepLabel.text = step;
        [self.log appendFormat:@"• %@\n", step];
        self.logView.text = self.log;
        if (self.logView.text.length > 0) {
            NSRange r = NSMakeRange(self.logView.text.length - 1, 1);
            [self.logView scrollRangeToVisible:r];
        }
    });
    // Let UI breathe between steps
    [NSThread sleepForTimeInterval:0.03];
}

- (void)finishWithTitle:(NSString *)title detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
        self.titleLabel.text = title ?: @"Xong";
        if (detail.length) {
            self.stepLabel.text = @"Hoàn tất";
            [self.log appendFormat:@"\n%@\n", detail];
            self.logView.text = self.log;
            NSRange r = NSMakeRange(self.logView.text.length - 1, 1);
            [self.logView scrollRangeToVisible:r];
        }
    });
}

- (void)dismissAfter:(NSTimeInterval)delay completion:(void (^)(void))completion {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            self.alpha = 0;
        } completion:^(__unused BOOL fin) {
            [self removeFromSuperview];
            if (completion) completion();
        }];
    });
}

@end
