#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LoginViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onSuccess)(void);
@end

NS_ASSUME_NONNULL_END
