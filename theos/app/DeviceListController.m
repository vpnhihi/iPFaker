#import "DeviceListController.h"
#import "Catalog.h"

@interface DeviceListController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@end

@implementation DeviceListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn iPhone";
    self.items = Catalog.shared.devices;
    self.filtered = self.items;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"15 Pro, iphone16, A17…";
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"d";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    NSDictionary *d = self.filtered[indexPath.row];
    NSDictionary *disp = d[@"display"] ?: @{};
    BOOL lab = [d[@"lab"] boolValue];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", d[@"MarketingName"] ?: @"?", lab ? @" ★" : @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ MB · %@x%@ · %@",
                                 d[@"ProductType"] ?: @"",
                                 d[@"chip"] ?: @"",
                                 d[@"PhysicalMemoryMB"] ?: @"",
                                 disp[@"NativeWidth"] ?: @"",
                                 disp[@"NativeHeight"] ?: @"",
                                 d[@"id"] ?: @""];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = [d[@"id"] isEqualToString:self.selectedId]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *d = self.filtered[indexPath.row];
    self.selectedId = d[@"id"];
    if (self.onSelect) self.onSelect(d);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString ?: @"";
    if (q.length == 0) {
        self.filtered = self.items;
    } else {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in self.items) {
            NSString *blob = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                               d[@"id"], d[@"MarketingName"], d[@"ProductType"], d[@"chip"], d[@"HWModelStr"]] lowercaseString];
            if ([blob containsString:q]) [out addObject:d];
        }
        self.filtered = out;
    }
    [self.tableView reloadData];
}

@end
