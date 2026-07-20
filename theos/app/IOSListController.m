#import "IOSListController.h"
#import "Catalog.h"

@interface IOSListController ()
@property (nonatomic, strong) NSArray<NSString *> *versions;
@end

@implementation IOSListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn iOS";
    // Strict matrix: only iOS builds this device actually supports
    NSArray *sup = [Catalog.shared supportedIOSForDevice:self.device ?: @{}];
    if (sup.count == 0)
        sup = Catalog.shared.iosVersionsSorted;
    self.versions = [[sup reverseObjectEnumerator] allObjects]; // newest first
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.versions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *min = self.device[@"minIOS"];
    NSString *max = self.device[@"maxIOS"];
    NSUInteger n = self.versions.count;
    if (min || max)
        return [NSString stringWithFormat:
                @"Chỉ iOS hợp lệ cho máy này (matrix): %lu bản · min %@ · max %@ · default %@",
                (unsigned long)n, min ?: @"?", max ?: @"?", self.device[@"defaultIOS"] ?: @"?"];
    return @"Không có iOS trong matrix cho máy này.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"i";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    NSString *ver = self.versions[indexPath.row];
    NSDictionary *meta = Catalog.shared.iosReleases[ver];
    BOOL lab = [meta[@"lab"] boolValue];
    cell.textLabel.text = [NSString stringWithFormat:@"iOS %@%@", ver, lab ? @"  [lab]" : @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Build %@", meta[@"BuildVersion"] ?: @"?"];
    cell.accessoryType = [ver isEqualToString:self.selectedIOS]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *ver = self.versions[indexPath.row];
    self.selectedIOS = ver;
    if (self.onSelect) self.onSelect(ver);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
