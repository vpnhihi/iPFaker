#import "AppTheme.h"

@implementation AppTheme

+ (UIColor *)bg {
    return [UIColor colorWithRed:0.05 green:0.07 blue:0.12 alpha:1.0];
}
+ (UIColor *)card {
    return [UIColor colorWithRed:0.14 green:0.18 blue:0.32 alpha:1.0];
}
+ (UIColor *)cardAlt {
    return [UIColor colorWithRed:0.11 green:0.14 blue:0.24 alpha:1.0];
}
+ (UIColor *)accent {
    return [UIColor colorWithRed:0.12 green:0.48 blue:1.0 alpha:1.0];
}
+ (UIColor *)accentDark {
    return [UIColor colorWithRed:0.08 green:0.35 blue:0.85 alpha:1.0];
}
+ (UIColor *)textPrimary {
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}
+ (UIColor *)textSecondary {
    return [UIColor colorWithWhite:0.72 alpha:1.0];
}
+ (UIColor *)success {
    return [UIColor colorWithRed:0.20 green:0.82 blue:0.45 alpha:1.0];
}
+ (UIColor *)tabBar {
    return [UIColor colorWithRed:0.08 green:0.10 blue:0.18 alpha:1.0];
}
+ (UIColor *)separator {
    return [UIColor colorWithWhite:1.0 alpha:0.08];
}
+ (UIFont *)titleFont {
    return [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
}
+ (UIFont *)sectionFont {
    return [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
}
+ (UIFont *)bodyFont {
    return [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
}
+ (UIFont *)captionFont {
    return [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
}

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    bar.prefersLargeTitles = NO;
    bar.barStyle = UIBarStyleBlack;
    bar.translucent = YES;
    bar.tintColor = [self accent];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundColor = [self bg];
        a.titleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary] };
        a.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary] };
        bar.standardAppearance = a;
        bar.scrollEdgeAppearance = a;
        bar.compactAppearance = a;
    } else {
        bar.barTintColor = [self bg];
        bar.titleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary] };
    }
}

+ (void)styleTabBar:(UITabBar *)tabBar {
    tabBar.barStyle = UIBarStyleBlack;
    tabBar.tintColor = [self accent];
    tabBar.unselectedItemTintColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *a = [[UITabBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundColor = [self tabBar];
        tabBar.standardAppearance = a;
        if (@available(iOS 15.0, *)) {
            tabBar.scrollEdgeAppearance = a;
        }
    } else {
        tabBar.barTintColor = [self tabBar];
    }
}

+ (UIView *)roundedCardIn:(UIView *)parent {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [self card];
    v.layer.cornerRadius = 16;
    v.clipsToBounds = YES;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:v];
    return v;
}

+ (UIButton *)primaryButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.backgroundColor = [self accent];
    b.layer.cornerRadius = 14;
    b.clipsToBounds = YES;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@end
