#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppTheme : NSObject
+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)cardAlt;
+ (UIColor *)accent;
+ (UIColor *)accentDark;
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)success;
+ (UIColor *)tabBar;
+ (UIColor *)separator;
+ (UIFont *)titleFont;
+ (UIFont *)sectionFont;
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;
+ (void)styleNavigationBar:(UINavigationBar *)bar;
+ (void)styleTabBar:(UITabBar *)tabBar;
+ (UIView *)roundedCardIn:(UIView *)parent;
+ (UIButton *)primaryButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@end

NS_ASSUME_NONNULL_END
