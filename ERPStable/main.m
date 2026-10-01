#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

// Only the focused responder inside this web view is changed. Keep WebKit's
// existing input, selection, autofill and keyboard implementations intact.
static id ERPNoAccessory(id object, SEL selector) { return nil; }
static UIView *ERPFirstResponder(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIView *found = ERPFirstResponder(child);
        if (found) return found;
    }
    return nil;
}
static void ERPRemoveAccessory(UIView *responder) {
    if (!responder) return;
    responder.inputAssistantItem.leadingBarButtonGroups = @[];
    responder.inputAssistantItem.trailingBarButtonGroups = @[];
    Class original = object_getClass(responder);
    if ([NSStringFromClass(original) hasPrefix:@"ERPNoAccessory_"]) return;
    NSString *name = [@"ERPNoAccessory_" stringByAppendingString:NSStringFromClass(original)];
    Class replacement = NSClassFromString(name);
    if (!replacement) {
        replacement = objc_allocateClassPair(original, name.UTF8String, 0);
        if (!replacement) return;
        class_addMethod(replacement, @selector(inputAccessoryView), (IMP)ERPNoAccessory, "@@:");
        objc_registerClassPair(replacement);
    }
    object_setClass(responder, replacement);
    [responder reloadInputViews];
}

@interface BrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic) BOOL askedForNotifications;
@property(nonatomic) UIStatusBarStyle statusBarStyle;
@end

@implementation BrowserController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    configuration.ignoresViewportScaleLimits = NO;
    configuration.allowsInlineMediaPlayback = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"erpNativeNotifications"];
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"interaction" withExtension:@"js"];
    NSString *script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    NSAssert(script != nil, @"Missing interaction.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    NSString *notificationScript = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"notifications" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(notificationScript != nil, @"Missing notifications.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:notificationScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.web.navigationDelegate = self;
    self.web.UIDelegate = self;
    self.web.allowsBackForwardNavigationGestures = YES;
    self.web.scrollView.pinchGestureRecognizer.enabled = NO;
    self.web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.web.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.web.inputAssistantItem.leadingBarButtonGroups = @[];
    self.web.inputAssistantItem.trailingBarButtonGroups = @[];
    self.web.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.web];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/"]]];
}
- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return self.statusBarStyle; }
- (void)keyboardWillShow:(NSNotification *)notification {
    ERPRemoveAccessory(ERPFirstResponder(self.web));
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.askedForNotifications || [NSUserDefaults.standardUserDefaults boolForKey:@"ERPNotificationPromptShown"]) return;
    self.askedForNotifications = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"ERPNotificationPromptShown"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"聊天提醒"
        message:@"可将网页收到的新聊天消息显示为 iOS 通知，不包含聊天内容。此版本需要网页保持运行；锁屏、后台或关闭应用后不能保证收消息。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"暂不开启" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:
            UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge
            completionHandler:^(BOOL granted, NSError *error) {}];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame || ![message.frameInfo.securityOrigin.host isEqualToString:@"erp.sex"] ||
        ![message.frameInfo.securityOrigin.protocol isEqualToString:@"https"] ||
        ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    if ([body[@"kind"] isEqual:@"appearance"]) {
        NSString *hex = body[@"color"];
        if (![hex isKindOfClass:NSString.class] || hex.length != 7 || ![hex hasPrefix:@"#"]) return;
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
        unsigned int rgb = 0;
        if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return;
        CGFloat red = ((rgb >> 16) & 255) / 255.0;
        CGFloat green = ((rgb >> 8) & 255) / 255.0;
        CGFloat blue = (rgb & 255) / 255.0;
        self.view.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1];
        self.statusBarStyle = (0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.55) ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
        [self setNeedsStatusBarAppearanceUpdate];
        return;
    }
    NSNumber *count = body[@"unread"];
    if (![count isKindOfClass:NSNumber.class] || count.integerValue < 0 || count.integerValue > 100000) return;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized && settings.authorizationStatus != UNAuthorizationStatusProvisional) return;
        dispatch_async(dispatch_get_main_queue(), ^{ UIApplication.sharedApplication.applicationIconBadgeNumber = count.integerValue; });
        if (![body[@"notify"] isEqual:@YES]) return;
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = @"聊";
        content.body = @"你有新的聊天消息";
        content.sound = UNNotificationSound.defaultSound;
        content.badge = count;
        content.userInfo = @{ @"path": @"/matches" };
        [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:
            [UNNotificationRequest requestWithIdentifier:@"erp-new-chat" content:content trigger:nil]
            withCompletionHandler:nil];
    }];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
    withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
    withCompletionHandler:(void (^)(void))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/matches"]]];
    });
    completionHandler();
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    webView.scrollView.pinchGestureRecognizer.enabled = NO;
}
- (void)showError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"页面加载失败"
        message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame) [webView loadRequest:action.request];
    return nil;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"聊" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"聊" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completionHandler(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(YES); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [BrowserController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
