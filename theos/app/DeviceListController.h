#import <UIKit/UIKit.h>

@interface DeviceListController : UITableViewController
@property (nonatomic, copy) NSString *selectedId;
@property (nonatomic, copy) void (^onSelect)(NSDictionary *device);
@end
