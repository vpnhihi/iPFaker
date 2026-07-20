#import <UIKit/UIKit.h>

@interface IOSListController : UITableViewController
@property (nonatomic, copy) NSString *selectedIOS;
@property (nonatomic, strong) NSDictionary *device;
@property (nonatomic, copy) void (^onSelect)(NSString *version);
@end
