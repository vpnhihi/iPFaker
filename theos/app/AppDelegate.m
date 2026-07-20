#import "AppDelegate.h"
#import "AppTheme.h"
#import "AppState.h"
#import "MainViewController.h"
#import "SelectDevicesViewController.h"
#import "WipeViewController.h"
#import "SettingsViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    self.window.backgroundColor = AppTheme.bg;

    // Warm catalog + selection
    (void)AppState.shared;

    UITabBarController *tabs = [[UITabBarController alloc] init];
    [AppTheme styleTabBar:tabs.tabBar];

    MainViewController *main = [[MainViewController alloc] init];
    UINavigationController *mainNav = [[UINavigationController alloc] initWithRootViewController:main];
    mainNav.tabBarItem = [self itemTitle:@"Trang chủ" systemImage:@"square.grid.2x2.fill" tag:0];

    SelectDevicesViewController *select = [[SelectDevicesViewController alloc] init];
    UINavigationController *selectNav = [[UINavigationController alloc] initWithRootViewController:select];
    selectNav.tabBarItem = [self itemTitle:@"Chọn máy" systemImage:@"iphone" tag:1];

    WipeViewController *wipe = [[WipeViewController alloc] init];
    UINavigationController *wipeNav = [[UINavigationController alloc] initWithRootViewController:wipe];
    wipeNav.tabBarItem = [self itemTitle:@"Xóa app" systemImage:@"trash" tag:2];

    SettingsViewController *settings = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];
    settingsNav.tabBarItem = [self itemTitle:@"Cài đặt" systemImage:@"gearshape.fill" tag:3];

    for (UINavigationController *nav in @[ mainNav, selectNav, wipeNav, settingsNav ]) {
        [AppTheme styleNavigationBar:nav.navigationBar];
    }

    tabs.viewControllers = @[ mainNav, selectNav, wipeNav, settingsNav ];
    tabs.selectedIndex = 0;

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

- (UITabBarItem *)itemTitle:(NSString *)title systemImage:(NSString *)name tag:(NSInteger)tag {
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        img = [UIImage systemImageNamed:name];
    }
    UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:img tag:tag];
    return item;
}

@end
