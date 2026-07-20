#import <UIKit/UIKit.h>

@interface AboutLabController : UITableViewController
@property (nonatomic, strong) NSDictionary *device;
@property (nonatomic, copy) NSString *iosVer;
@property (nonatomic, strong) NSDictionary *iosMeta;
@property (nonatomic, strong) NSDictionary *flat; // applied profile if any
@end
