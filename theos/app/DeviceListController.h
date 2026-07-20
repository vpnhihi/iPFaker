#import <UIKit/UIKit.h>

/// Multi-select device list: tap = toggle, ✓ = selected. Stay on screen until Done.
@interface DeviceListController : UITableViewController
@property (nonatomic, strong) NSArray<NSString *> *selectedIds; // initial; not live-synced
@property (nonatomic, copy) void (^onChange)(void); // called after each toggle
@end
