#import <UIKit/UIKit.h>

/// Multi-select iOS list filtered by matrix of selected devices. Tap toggle, ✓ = selected.
@interface IOSListController : UITableViewController
@property (nonatomic, copy) void (^onChange)(void);
@end
