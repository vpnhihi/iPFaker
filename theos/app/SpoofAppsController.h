#import <UIKit/UIKit.h>

/// lab flat Multi-app spoof: chọn app nhận inject spoof (filter TweakInject).
@interface SpoofAppsController : UITableViewController
@property (nonatomic, copy, nullable) void (^onChange)(void);
@end
