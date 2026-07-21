#import "ProxyAppAttestController.h"
#import "AppTheme.h"
#import "AppState.h"
#import "ProfileBuilder.h"
#import "ProgressOverlay.h"

@interface ProxyAppAttestController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passField;
@property (nonatomic, strong) UISegmentedControl *typeSeg;
@property (nonatomic, strong) UISwitch *enableProxySw;
@property (nonatomic, strong) UISwitch *disableAttestSw;
@property (nonatomic, strong) UILabel *testResultLabel;
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
    [self loadFromState];
}

- (UITextField *)fieldPlaceholder:(NSString *)ph secure:(BOOL)sec {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 180, 32)];
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
    self.hostField = [self fieldPlaceholder:@"192.168.0.1" secure:NO];
    self.hostField.keyboardType = UIKeyboardTypeURL;
    self.portField = [self fieldPlaceholder:@"12345" secure:NO];
    self.portField.keyboardType = UIKeyboardTypeNumberPad;
    self.userField = [self fieldPlaceholder:@"optional" secure:NO];
    self.passField = [self fieldPlaceholder:@"optional" secure:YES];
    self.typeSeg = [[UISegmentedControl alloc] initWithItems:@[ @"HTTP", @"SOCKS5" ]];
    self.typeSeg.selectedSegmentIndex = 0;
    self.enableProxySw = [[UISwitch alloc] init];
    self.enableProxySw.onTintColor = AppTheme.success;
    self.disableAttestSw = [[UISwitch alloc] init];
    self.disableAttestSw.onTintColor = AppTheme.success;
    self.testResultLabel = [[UILabel alloc] init];
    self.testResultLabel.font = AppTheme.captionFont;
    self.testResultLabel.textColor = AppTheme.textSecondary;
    self.testResultLabel.numberOfLines = 3;
    self.testResultLabel.text = @" ";
}

- (void)loadFromState {
    AppState *st = AppState.shared;
    self.hostField.text = [st proxyHost] ?: @"";
    NSInteger port = [st proxyPort];
    self.portField.text = port > 0 ? [NSString stringWithFormat:@"%ld", (long)port] : @"";
    self.userField.text = [st proxyUsername] ?: @"";
    self.passField.text = [st proxyPassword] ?: @"";
    NSString *type = [st proxyType] ?: @"HTTP";
    self.typeSeg.selectedSegmentIndex = [type.uppercaseString containsString:@"SOCKS"] ? 1 : 0;
    self.enableProxySw.on = [st proxyEnabled];
    self.disableAttestSw.on = [st disableAppAttest];
}

- (void)saveToState {
    AppState *st = AppState.shared;
    [st setProxyHost:self.hostField.text ?: @""];
    [st setProxyPort:[self.portField.text integerValue]];
    [st setProxyUsername:self.userField.text ?: @""];
    [st setProxyPassword:self.passField.text ?: @""];
    [st setProxyType:self.typeSeg.selectedSegmentIndex == 1 ? @"SOCKS5" : @"HTTP"];
    [st setProxyEnabled:self.enableProxySw.on];
    [st setDisableAppAttest:self.disableAttestSw.on];
    [st saveProxyAppAttest];
}

- (void)saveTapped {
    [self.view endEditing:YES];
    [self saveToState];
    UIView *host = self.navigationController.view ?: self.view;
    ProgressOverlay *ov = [ProgressOverlay showOn:host title:@"Lưu Proxy / AppAttest…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *msg = [AppState.shared applyProxyAppAttestToConfigProgress:^(NSString *s) {
            [ov appendStep:s];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ov finishWithTitle:@"Đã lưu" detail:msg];
            [ov dismissAfter:1.5 completion:nil];
            self.testResultLabel.text = msg;
            [self.tableView reloadData];
        });
    });
}

- (void)testProxyTapped {
    [self.view endEditing:YES];
    [self saveToState];
    self.testResultLabel.text = @"Đang test proxy…";
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *res = [AppState.shared testProxyConnection];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testResultLabel.text = res;
            [self.tableView reloadData];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 7; // host port type user pass enable test
    if (section == 1) return 1; // appattest
    return 1; // result
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Proxy settings";
    if (section == 1) return @"AppAttest";
    return @"Trạng thái";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return @"Bật Enable proxy + Lưu để ghi vào config.plist (dylib đọc khi inject). HTTP hoặc SOCKS5.";
    if (section == 1)
        return @"Tắt App Attest / DeviceCheck assertion trong app spoof (lab). Không bypass server-side trust.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *cid = @"px";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = AppTheme.cardAlt;
        cell.textLabel.textColor = AppTheme.textPrimary;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = nil;
        cell.detailTextLabel.text = nil;
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Host";
                cell.accessoryView = self.hostField;
                break;
            case 1:
                cell.textLabel.text = @"Port";
                cell.accessoryView = self.portField;
                break;
            case 2:
                cell.textLabel.text = @"Type";
                cell.accessoryView = self.typeSeg;
                break;
            case 3:
                cell.textLabel.text = @"Username";
                cell.accessoryView = self.userField;
                break;
            case 4:
                cell.textLabel.text = @"Password";
                cell.accessoryView = self.passField;
                break;
            case 5:
                cell.textLabel.text = @"Enable proxy";
                cell.accessoryView = self.enableProxySw;
                break;
            default: {
                cell.textLabel.text = @"Test proxy";
                cell.textLabel.textColor = AppTheme.accent;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
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
    cell.accessoryView = nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 6)
        [self testProxyTapped];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
