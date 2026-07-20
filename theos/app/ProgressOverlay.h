#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Center-screen dark progress card: title + spinner + live step log.
@interface ProgressOverlay : UIView
+ (instancetype)showOn:(UIView *)host title:(NSString *)title;
- (void)setTitle:(NSString *)title;
- (void)appendStep:(NSString *)step;
- (void)finishWithTitle:(NSString *)title detail:(nullable NSString *)detail;
- (void)dismissAfter:(NSTimeInterval)delay completion:(nullable void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
