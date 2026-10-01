#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

// Only the focused responder inside this web view is changed. Keep WebKit's
// existing input, selection, autofill and keyboard implementations intact.
static id ERPNoAccessory(id object, SEL selector) { return nil; }
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
    // Install before editing starts. Reloading while the keyboard is appearing
    // changes its frame mid-transition and can leave WebKit's viewport stale.
}
static void ERPPrepareTextInputs(UIView *view) {
    if ([view conformsToProtocol:@protocol(UITextInput)] ||
        [NSStringFromClass(object_getClass(view)) containsString:@"WKContentView"]) {
        ERPRemoveAccessory(view);
    }
    for (UIView *child in view.subviews) ERPPrepareTextInputs(child);
}

@interface BrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic) BOOL askedForNotifications;
@property(nonatomic) UIStatusBarStyle statusBarStyle;
@property(nonatomic, strong) NSLayoutConstraint *webBottomConstraint;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic) CGSize lastViewportSize;
@property(nonatomic) BOOL lastViewportKeyboardVisible;
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
    NSString *keyboardScript = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"keyboard" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(keyboardScript != nil, @"Missing keyboard.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:keyboardScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
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
    self.webBottomConstraint = [self.web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        self.webBottomConstraint,
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    ERPPrepareTextInputs(self.web);
    for (NSNotificationName name in @[UIKeyboardWillChangeFrameNotification, UIKeyboardDidChangeFrameNotification, UIKeyboardWillHideNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardFrameChanged:) name:name object:nil];
    }
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/"]]];
}
- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return self.statusBarStyle; }
- (void)keyboardFrameChanged:(NSNotification *)notification {
    UIWindow *window = self.view.window;
    if (!window) return;
    CGRect screenFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrame = [self.view convertRect:screenFrame fromCoordinateSpace:window.screen.coordinateSpace];
    CGRect overlap = CGRectIntersection(self.view.bounds, keyboardFrame);
    BOOL docked = !CGRectIsNull(overlap) && CGRectGetHeight(overlap) > 0 &&
        CGRectGetMaxY(keyboardFrame) >= CGRectGetMaxY(self.view.bounds) - 1 &&
        CGRectGetWidth(overlap) >= CGRectGetWidth(self.view.bounds) * 0.5;
    CGFloat height = docked ? CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(overlap) : 0;
    if ([notification.name isEqualToString:UIKeyboardWillHideNotification]) height = 0;
    self.keyboardVisible = height > 0;
    self.webBottomConstraint.constant = -height;
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16;
    [UIView animateWithDuration:duration delay:0 options:curve | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ [self.view layoutIfNeeded]; }
        completion:^(BOOL finished) { [self syncViewport:YES]; }];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self syncViewport:NO];
}
- (void)syncViewport:(BOOL)force {
    CGSize size = self.web.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    if (!force && CGSizeEqualToSize(size, self.lastViewportSize) &&
        self.lastViewportKeyboardVisible == self.keyboardVisible) return;
    self.lastViewportSize = size;
    self.lastViewportKeyboardVisible = self.keyboardVisible;
    NSString *script = [NSString stringWithFormat:
        @"window.__vrcrpSetViewport?.({width:%.2f,height:%.2f,keyboardVisible:%@})",
        size.width, size.height, self.keyboardVisible ? @"true" : @"false"];
    [self.web evaluateJavaScript:script completionHandler:nil];
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
        content.title = @"vrcrp";
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
    ERPPrepareTextInputs(webView);
    [self syncViewport:YES];
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    ERPPrepareTextInputs(webView);
    [self syncViewport:YES];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"vrcrp" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completionHandler(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"vrcrp" message:message preferredStyle:UIAlertControllerStyleAlert];
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
