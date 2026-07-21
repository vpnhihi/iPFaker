#import "ProxyAppAttestController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "ProfileBuilder.h"
#import "ProgressOverlay.h"

@interface ProxyAppAttestController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *pasteField;
@property (nonatomic, strong) UISegmentedControl *typeSeg;
@property (nonatomic, strong) UISwitch *enableProxySw;
@property (nonatomic, strong) UISwitch *disableAttestSw;
@property (nonatomic, strong) UISwitch *syncGeoSw;
@property (nonatomic, strong) UILabel *testResultLabel;
@property (nonatomic, assign) BOOL applyingToggle;
@end

@implementation ProxyAppAttestController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IP / Proxy / AppAttest";
    self.view.backgroundColor = AppTheme.bg;
    self.tableView.backgroundColor = AppTheme.bg;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [AppTheme styleNavigationBar:self.navigationController.navigationBar];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Lưu"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(saveTapped)];

    [self buildFields];
    [[AppState shared] loadProxyFromDualPathConfig];
    [self loadFromState];
}

- (UITextField *)fieldPlaceholder:(NSString *)ph secure:(BOOL)sec {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 220, 32)];
    f.placeholder = ph;
    f.font = AppTheme.bodyFont;
    f.textColor = AppTheme.textPrimary;
    f.textAlignment = NSTextAlignmentRight;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.secureTextEntry = sec;
    f.delegate = self;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    return f;
}

- (void)buildFields {
    // Full-width paste: host:port:user:pass
    self.pasteField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 240, 36)];
    self.pasteField.placeholder = @"host:port:user:pass";
    self.pasteField.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.pasteField.textColor = AppTheme.textPrimary;
    self.pasteField.textAlignment = NSTextAlignmentLeft;
    self.pasteField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.pasteField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.pasteField.keyboardType = UIKeyboardTypeURL;
    self.pasteField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.pasteField.delegate = self;
    self.pasteField.borderStyle = UITextBorderStyleRoundedRect;
    self.pasteField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];

    self.typeSeg = [[UISegmentedControl alloc] initWithItems:@[ @"HTTP", @"SOCKS5" ]];
    self.typeSeg.selectedSegmentIndex = 0;

    self.enableProxySw = [[UISwitch alloc] init];
    self.enableProxySw.onTintColor = AppTheme.success;
    [self.enableProxySw addTarget:self action:@selector(enableProxyChanged:) forControlEvents:UIControlEventValueChanged];

    self.disableAttestSw = [[UISwitch alloc] init];
    self.disableAttestSw.onTintColor = AppTheme.success;

    self.syncGeoSw = [[UISwitch alloc] init];
    self.syncGeoSw.onTintColor = AppTheme.success;

    self.testResultLabel = [[UILabel alloc] init];
    self.testResultLabel.font = AppTheme.captionFont;
    self.testResultLabel.textColor = AppTheme.textSecondary;
    self.testResultLabel.numberOfLines = 0;
    self.testResultLabel.text = @" ";
}

- (NSString *)currentPasteLine {
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

- (void)loadFromState {
    AppState *st = AppState.shared;
    self.pasteField.text = [self currentPasteLine];
    NSString *type = [st proxyType] ?: @"HTTP";
    self.typeSeg.selectedSegmentIndex = [type.uppercaseString containsString:@"SOCKS"] ? 1 : 0;
    self.enableProxySw.on = [st proxyEnabled];
    self.disableAttestSw.on = [st disableAppAttest];
    self.syncGeoSw.on = [st syncGeoFromProxyEnabled];
}

- (void)saveToState {
    AppState *st = AppState.shared;
    NSString *err = nil;
    NSString *line = self.pasteField.text ?: @"";
    if (line.length) {
        if (![st applyProxyPasteLine:line error:&err]) {
            // keep existing host if parse fails mid-edit
            if (err.length) self.testResultLabel.text = err;
        }
    }
    [st setProxyType:self.typeSeg.selectedSegmentIndex == 1 ? @"SOCKS5" : @"HTTP"];
    [st setProxyEnabled:self.enableProxySw.on];
    [st setDisableAppAttest:self.disableAttestSw.on];
    [st setSyncGeoFromProxyEnabled:self.syncGeoSw.on];
    [st saveProxyAppAttest];
}

- (void)showScreenAlertTitle:(NSString *)title message:(NSString *)message {
    if (!message.length) message = @"(empty)";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

/// Toggle ON → parse paste + write dual-path config; OFF → disable proxy on device.
- (void)enableProxyChanged:(UISwitch *)sw {
    if (self.applyingToggle) return;
    [self.view endEditing:YES];
    self.applyingToggle = YES;
    [self saveToState];

    UIView *host = self.navigationController.view ?: self.view;
    NSString *title = sw.on ? @"Bật proxy trên máy…" : @"Tắt proxy trên máy…";
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:title];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = nil;
        if (sw.on) {
            NSString *err = nil;
            if (![[AppState shared] applyProxyPasteLine:self.pasteField.text error:&err]) {
                msg = err ?: @"Proxy paste không hợp lệ (host:port:user:pass)";
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.applyingToggle = NO;
                    self.enableProxySw.on = NO;
                    [[AppState shared] setProxyEnabled:NO];
                    [[AppState shared] saveProxyAppAttest];
                    [ov finishWithTitle:@"Lỗi" detail:msg];
                    [ov dismissAfter:1.2 completion:^{
                        [self showScreenAlertTitle:@"Proxy" message:msg];
                    }];
                });
                return;
            }
            [[AppState shared] setProxyEnabled:YES];
            msg = [[AppState shared] applyProxyAppAttestToConfigProgress:^(NSString *s) {
                [ov appendStep:s];
            }];
        } else {
            [[AppState shared] setProxyEnabled:NO];
            [[AppState shared] saveProxyAppAttest];
            NSDictionary *keys = [[AppState shared] proxyAppAttestFlatKeys];
            msg = [ProfileBuilder mergeKeysIntoConfig:keys progress:^(NSString *s) {
                [ov appendStep:s];
            }];
            msg = [NSString stringWithFormat:@"Đã tắt EnableProxy dual-path.\n%@", msg ?: @""];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.applyingToggle = NO;
            [self loadFromState];
            [ov finishWithTitle:sw.on ? @"Proxy ON" : @"Proxy OFF" detail:msg];
            [ov dismissAfter:1.1 completion:^{
                self.testResultLabel.text = msg;
                [self.tableView reloadData];
                [self showScreenAlertTitle:sw.on ? @"Proxy đã bật" : @"Proxy đã tắt" message:msg];
            }];
        });
    });
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSString *err = nil;
    if (self.pasteField.text.length && ![[AppState shared] applyProxyPasteLine:self.pasteField.text error:&err]) {
        [self showScreenAlertTitle:@"Proxy" message:err ?: @"Định dạng sai"];
        return;
    }
    [self saveToState];
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Lưu Proxy / AppAttest…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = [AppState.shared applyProxyAppAttestToConfigProgress:^(NSString *s) {
            [ov appendStep:s];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ov finishWithTitle:@"Đã lưu" detail:msg];
            [ov dismissAfter:1.2 completion:^{
                self.testResultLabel.text = msg;
                [self.tableView reloadData];
                [self showScreenAlertTitle:@"Proxy / AppAttest" message:msg];
            }];
        });
    });
}

- (void)testProxyTapped {
    [self.view endEditing:YES];
    NSString *err = nil;
    if (self.pasteField.text.length)
        [[AppState shared] applyProxyPasteLine:self.pasteField.text error:&err];
    [self saveToState];
    if (![[AppState shared] proxyEnabled])
        [[AppState shared] setProxyEnabled:YES];
    self.testResultLabel.text = @"Đang test proxy…";
    [self.tableView reloadData];
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Test proxy…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *res = [AppState.shared testProxyConnection];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ov finishWithTitle:[res hasPrefix:@"OK"] ? @"Proxy OK" : @"Proxy FAIL" detail:res];
            [ov dismissAfter:1.0 completion:^{
                self.testResultLabel.text = res;
                [self.tableView reloadData];
                [self showScreenAlertTitle:@"Test proxy + geo" message:res];
            }];
        });
    });
}

- (void)syncGeoNowTapped {
    [self.view endEditing:YES];
    [self saveToState];
    [AppState.shared setSyncGeoFromProxyEnabled:YES];
    self.syncGeoSw.on = YES;
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Đồng bộ geo theo proxy…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *full = [AppState.shared attachProxyGeoRandomInCityProgress:^(NSString *s) {
            [ov appendStep:s];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = [full containsString:@"Đã đồng bộ"] || [full containsString:@"random"];
            [ov finishWithTitle:ok ? @"Đã đồng bộ geo" : @"Geo / lưu xong" detail:full];
            [ov dismissAfter:1.0 completion:^{
                self.testResultLabel.text = full;
                [self.tableView reloadData];
                [self showScreenAlertTitle:@"Đồng bộ Map / Thời tiết" message:full];
            }];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; // enable, paste, type, test
    if (section == 1) return 1; // appattest
    if (section == 2) return 2; // sync geo + sync now
    return 1; // result
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Proxy (dán 1 dòng)";
    if (section == 1) return @"AppAttest";
    if (section == 2) return @"Thời gian / Map / Thời tiết";
    return @"Trạng thái";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Định dạng: host:port:user:pass (user/pass có thể trống).\nBật công tắc = ghi proxy vào config dual-path (dylib đọc khi inject).";
    if (section == 1)
        return @"Tắt App Attest / DeviceCheck phía client (lab). Không bypass SE server.";
    if (section == 2)
        return @"Geo random trong thành phố proxy → FakeLocation (Maps/Weather/app spoof).";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1) return 52;
    if (indexPath.section == 3) return UITableViewAutomaticDimension;
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        // Separate reuse ids so paste field never sticks on other rows
        NSString *cid = (indexPath.row == 1) ? @"px_paste" : @"px";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.numberOfLines = 1;
        cell.textLabel.text = nil;
        // Detach paste field if this is not the paste row (avoid reuse leak)
        if (indexPath.row != 1 && self.pasteField.superview == cell.contentView)
            [self.pasteField removeFromSuperview];
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Bật proxy trên máy";
                cell.accessoryView = self.enableProxySw;
                break;
            case 1: {
                cell.textLabel.text = @"";
                CGFloat w = tableView.bounds.size.width - 48;
                self.pasteField.frame = CGRectMake(16, 8, MAX(120, w), 36);
                if (self.pasteField.superview != cell.contentView) {
                    [self.pasteField removeFromSuperview];
                    [cell.contentView addSubview:self.pasteField];
                }
                break;
            }
            case 2:
                cell.textLabel.text = @"Type";
                cell.accessoryView = self.typeSeg;
                break;
            default:
                cell.textLabel.text = @"Test proxy";
                cell.textLabel.textColor = AppTheme.accent;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
        }
        return cell;
    }
    if (indexPath.section == 1) {
        static NSString *cid = @"aa";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.textLabel.text = @"Disable App Attest";
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = self.disableAttestSw;
        return cell;
    }
    if (indexPath.section == 2) {
        static NSString *cid = @"geo";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.accessoryView = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Đồng bộ geo theo proxy";
            cell.textLabel.textColor = AppTheme.textPrimary;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryView = self.syncGeoSw;
        } else {
            cell.textLabel.text = @"Đồng bộ ngay (random trong thành phố)";
            cell.textLabel.textColor = AppTheme.accent;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }
    static NSString *cid = @"st";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    cell.backgroundColor = AppTheme.cardAlt;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = AppTheme.captionFont;
    cell.textLabel.textColor = AppTheme.textSecondary;
    cell.textLabel.text = self.testResultLabel.text.length ? self.testResultLabel.text : @"Chưa test / chưa lưu";
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1) {
        CGFloat w = tableView.bounds.size.width - 48;
        self.pasteField.frame = CGRectMake(16, 8, MAX(120, w), 36);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3)
        [self testProxyTapped];
    if (indexPath.section == 2 && indexPath.row == 1)
        [self syncGeoNowTapped];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (textField == self.pasteField) {
        NSString *err = nil;
        [[AppState shared] applyProxyPasteLine:textField.text error:&err];
        if (err.length) self.testResultLabel.text = err;
        else [self loadFromState];
        [self.tableView reloadData];
    }
    return YES;
}

@end
