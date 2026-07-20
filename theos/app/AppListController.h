#import <UIKit/UIKit.h>

/// Multi-select installed apps for wipe (tap toggle, ✓ = selected).
@interface AppListController : UITableViewController
@property (nonatomic, copy) void (^onChange)(void);
@end
