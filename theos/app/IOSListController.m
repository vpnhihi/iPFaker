#import "IOSListController.h"
#import "Catalog.h"

@interface IOSListController ()
@property (nonatomic, strong) NSArray<NSString *> *versions;
@end

@implementation IOSListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn iOS";
    self.versions = Catalog.shared.iosVersionsSorted.reverseObjectEnumerator.allObjects; // newest first
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.versions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *min = self.device[@"minIOS"];
    NSString *max = self.device[@"maxIOS"];
    if (min || max)
        return [NSString stringWithFormat:@"Gợi ý máy này: min %@ · max %@ · default %@",
                min ?: @"?", max ?: @"?", self.device[@"defaultIOS"] ?: @"?"];
    return @"iOS 19–26 là lab placeholder.";
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
