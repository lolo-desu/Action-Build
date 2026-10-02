#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <SafariServices/SafariServices.h>
#import "ThemeNavigation.h"
#import "ChatNotifications.h"

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
#if ERP_TESTING
static UIView *ERPFocusedView(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIView *focused = ERPFocusedView(child);
        if (focused) return focused;
    }
    return nil;
}
#endif

@interface BrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate, UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) UIView *statusBarSurface;
@property(nonatomic) BOOL askedForNotifications;
@property(nonatomic) UIStatusBarStyle statusBarStyle;
@property(nonatomic, strong) NSLayoutConstraint *webBottomConstraint;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic) CGSize lastViewportSize;
@property(nonatomic) BOOL lastViewportKeyboardVisible;
@property(nonatomic, strong) ThemeNavigation *bottomNav;
@property(nonatomic, strong) UIView *loadingCover;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UILabel *loadingCaption;
@property(nonatomic, strong) UIButton *retryButton;
@property(nonatomic, strong) UIRefreshControl *refreshControl;
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *edgeBack;
@property(nonatomic, strong) UIImageView *backPreview;
@property(nonatomic, strong) UIImage *lastSnapshot;
@property(nonatomic, strong) NSURL *pendingURL;
@property(nonatomic) BOOL hasContent;
@property(nonatomic) BOOL canGoBack;
@property(nonatomic) BOOL websiteOverlay;
@property(nonatomic) BOOL chatLayout;
@property(nonatomic, strong) ChatNotifications *chatNotifications;
@property(nonatomic, copy) NSString *pendingChatID;
@property(nonatomic) NSTimeInterval lastHaptic;
@property(nonatomic) NSUInteger snapshotGeneration;
@end

@implementation BrowserController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.backgroundColor=VRColor([NSUserDefaults.standardUserDefaults objectForKey:@"VRThemeBackground"],UIColor.systemBackgroundColor);
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    self.chatNotifications=[[ChatNotifications alloc] initWithCookieStore:configuration.websiteDataStore.httpCookieStore];
    configuration.ignoresViewportScaleLimits = NO;
    configuration.allowsInlineMediaPlayback = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"erpNativeNotifications"];
    [configuration.userContentController addScriptMessageHandler:self name:@"erpNativeApp"];
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
    NSString *appScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"app-experience" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(appScript!=nil,@"Missing app-experience.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:appScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.web.navigationDelegate = self;
    self.web.UIDelegate = self;
    // Website cards use horizontal drags. Native history gestures must not
    // compete with the site's own pointer handlers and animations.
    self.web.allowsBackForwardNavigationGestures = NO;
    self.web.allowsLinkPreview = NO;
    self.web.scrollView.pinchGestureRecognizer.enabled = NO;
    self.web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.web.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    self.web.scrollView.delegate=self;
    self.web.inputAssistantItem.leadingBarButtonGroups = @[];
    self.web.inputAssistantItem.trailingBarButtonGroups = @[];
    self.web.translatesAutoresizingMaskIntoConstraints = NO;
    self.web.opaque=NO; self.web.backgroundColor=UIColor.clearColor;
    self.web.scrollView.backgroundColor=self.view.backgroundColor;
    self.web.scrollView.bounces=NO;
    self.backPreview=[UIImageView new]; self.backPreview.contentMode=UIViewContentModeScaleToFill;
    self.backPreview.hidden=YES; [self.view addSubview:self.backPreview];
    [self.view addSubview:self.web];
    self.webBottomConstraint = [self.web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        self.webBottomConstraint,
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    self.bottomNav=[ThemeNavigation new]; [self.view addSubview:self.bottomNav];
    self.statusBarSurface=[UIView new]; self.statusBarSurface.userInteractionEnabled=NO;
    self.statusBarSurface.backgroundColor=VRColor([NSUserDefaults.standardUserDefaults objectForKey:@"VRHeaderSurface"],UIColor.systemBackgroundColor);
    self.statusBarSurface.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.statusBarSurface];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusBarSurface.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.statusBarSurface.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.statusBarSurface.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusBarSurface.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    __weak BrowserController *weakSelf=self;
    self.bottomNav.onSelect=^(NSInteger slot) {
        [weakSelf haptic:@"selection"];
        [weakSelf.web evaluateJavaScript:[NSString stringWithFormat:@"window.__vrcrpActivateTab?.(%ld)",(long)slot] completionHandler:nil];
    };
    self.refreshControl=[UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshPage:) forControlEvents:UIControlEventValueChanged];
    self.edgeBack=[[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeBack:)];
    self.edgeBack.edges=UIRectEdgeLeft; self.edgeBack.delegate=self; self.edgeBack.enabled=NO;
    [self.view addGestureRecognizer:self.edgeBack];
    [self createLoadingCover];
    ERPPrepareTextInputs(self.web);
    for (NSNotificationName name in @[UIKeyboardWillChangeFrameNotification, UIKeyboardDidChangeFrameNotification, UIKeyboardWillHideNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardFrameChanged:) name:name object:nil];
    }
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    UNNotificationAction *open=[UNNotificationAction actionWithIdentifier:@"VRCRP_OPEN_CHAT" title:@"打开聊天" options:UNNotificationActionOptionForeground];
    [UNUserNotificationCenter.currentNotificationCenter setNotificationCategories:[NSSet setWithObject:[UNNotificationCategory categoryWithIdentifier:@"VRCRP_CHAT" actions:@[open] intentIdentifiers:@[] options:UNNotificationCategoryOptionNone]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appInactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
#if ERP_TESTING
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"--verify-keyboard"] || [arguments containsObject:@"--verify-tabs"]) {
        NSString *fixture = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"layout-fixture" withExtension:@"html"] encoding:NSUTF8StringEncoding error:nil];
        NSString *path=[arguments containsObject:@"--verify-tabs"]?@"https://erp.sex/discover":@"https://erp.sex/matches/layout-fixture";
        [self.web loadHTMLString:fixture baseURL:[NSURL URLWithString:path]];
    } else if ([arguments containsObject:@"--verify-ux"]) {
        NSString *fixture=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"navigation-fixture" withExtension:@"html"] encoding:NSUTF8StringEncoding error:nil];
        [self.web loadHTMLString:fixture baseURL:[NSURL URLWithString:@"https://erp.sex/discover"]];
    } else if ([arguments containsObject:@"--preview-login"]) {
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/login"]]];
    } else
#endif
    {
        NSString *lastTab=[NSUserDefaults.standardUserDefaults stringForKey:@"VRLastTab"];
        NSSet *tabs=[NSSet setWithArray:@[@"/discover",@"/likes",@"/matches",@"/posts",@"/me"]];
        NSString *path=[tabs containsObject:lastTab]?lastTab:@"/";
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[@"https://erp.sex" stringByAppendingString:path]]]];
    }
}
- (void)createLoadingCover {
    self.loadingCover=[UIView new]; self.loadingCover.backgroundColor=self.view.backgroundColor;
    CGFloat red=1,green=1,blue=1,alpha=1; [self.view.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha];
    self.loadingCover.overrideUserInterfaceStyle=(.2126*red+.7152*green+.0722*blue<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
    self.loadingCover.tintColor=VRColor([NSUserDefaults.standardUserDefaults objectForKey:@"VRThemeAccent"],UIColor.systemRedColor);
    self.loadingCover.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.loadingCover];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingCover.topAnchor constraintEqualToAnchor:self.web.topAnchor], [self.loadingCover.bottomAnchor constraintEqualToAnchor:self.web.bottomAnchor],
        [self.loadingCover.leadingAnchor constraintEqualToAnchor:self.web.leadingAnchor], [self.loadingCover.trailingAnchor constraintEqualToAnchor:self.web.trailingAnchor]]];
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon60x60"]]; icon.contentMode=UIViewContentModeScaleAspectFit;
    icon.layer.cornerRadius=16; icon.clipsToBounds=YES;
    [icon.widthAnchor constraintEqualToConstant:64].active=YES; [icon.heightAnchor constraintEqualToConstant:64].active=YES;
    UILabel *title=[UILabel new]; title.text=@"vrcrp"; title.font=[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; title.textAlignment=NSTextAlignmentCenter; title.textColor=UIColor.labelColor;
    self.loadingCaption=[UILabel new]; self.loadingCaption.text=@"正在连接…"; self.loadingCaption.font=[UIFont systemFontOfSize:14];
    self.loadingCaption.textAlignment=NSTextAlignmentCenter; self.loadingCaption.textColor=UIColor.secondaryLabelColor; self.loadingCaption.numberOfLines=2;
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [self.spinner startAnimating];
    self.retryButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.retryButton setTitle:@"重新连接" forState:UIControlStateNormal]; self.retryButton.hidden=YES;
    [self.retryButton addTarget:self action:@selector(retryPage:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[icon,title,self.loadingCaption,self.spinner,self.retryButton]];
    stack.axis=UILayoutConstraintAxisVertical; stack.alignment=UIStackViewAlignmentCenter; stack.spacing=14;
    stack.translatesAutoresizingMaskIntoConstraints=NO; [self.loadingCover addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.loadingCover.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.loadingCover.centerYAnchor], [stack.widthAnchor constraintLessThanOrEqualToAnchor:self.loadingCover.widthAnchor multiplier:.8]]];
}
- (void)contentReady {
    self.hasContent=YES; [self.refreshControl endRefreshing]; [self.spinner stopAnimating];
    if (self.loadingCover.hidden) return;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:.22 animations:^{ self.loadingCover.alpha=0; }
        completion:^(BOOL finished) { self.loadingCover.hidden=YES; }];
}
- (void)refreshPage:(id)sender { [self haptic:@"light"]; [self.web reload]; }
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // The site's chat is a fixed-height flex page with its own message scroller.
    // WebKit can still auto-scroll the OUTER view after focusing a small editor,
    // even after we resize it for the keyboard. That second movement must not
    // offset the whole page; nested message/editor scrolling remains unchanged.
    if (scrollView==self.web.scrollView && self.chatLayout &&
        (fabs(scrollView.contentOffset.y)>.5 || fabs(scrollView.contentOffset.x)>.5)) {
        [scrollView setContentOffset:CGPointZero animated:NO];
    }
}
- (void)retryPage:(id)sender {
    self.retryButton.hidden=YES; self.loadingCaption.text=@"正在连接…"; [self.spinner startAnimating];
    [self.web loadRequest:[NSURLRequest requestWithURL:self.pendingURL?:self.web.URL?:[NSURL URLWithString:@"https://erp.sex/"]]];
}
- (void)haptic:(NSString *)style {
    NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate;
    if (now-self.lastHaptic<.08) return; self.lastHaptic=now;
    if ([style isEqualToString:@"selection"]) { UISelectionFeedbackGenerator *feedback=[UISelectionFeedbackGenerator new]; [feedback selectionChanged]; }
    else if ([style isEqualToString:@"success"]) { UINotificationFeedbackGenerator *feedback=[UINotificationFeedbackGenerator new]; [feedback notificationOccurred:UINotificationFeedbackTypeSuccess]; }
    else if ([style isEqualToString:@"light"]) { UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feedback impactOccurred]; }
}
- (void)captureSnapshot {
    NSUInteger generation=++self.snapshotGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/3),dispatch_get_main_queue(),^{
        if (generation!=self.snapshotGeneration || self.keyboardVisible || self.presentedViewController) return;
        [self.web takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *image,NSError *error) {
            if (generation==self.snapshotGeneration && image) self.lastSnapshot=image;
        }];
    });
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return gesture!=self.edgeBack || (self.canGoBack && !self.keyboardVisible && !self.websiteOverlay && !self.presentedViewController && !self.web.loading);
}
- (void)edgeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    CGFloat distance=MAX(0,[gesture translationInView:self.view].x), width=self.web.bounds.size.width;
    if (gesture.state==UIGestureRecognizerStateBegan) {
        self.backPreview.hidden=self.backPreview.image==nil; [self haptic:@"selection"];
    }
    if (gesture.state==UIGestureRecognizerStateChanged) self.web.transform=CGAffineTransformMakeTranslation(MIN(width,distance),0);
    if (gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled) {
        BOOL commit=gesture.state==UIGestureRecognizerStateEnded && (distance>width*.32 || [gesture velocityInView:self.view].x>550);
        [UIView animateWithDuration:.2 animations:^{ self.web.transform=commit?CGAffineTransformMakeTranslation(width,0):CGAffineTransformIdentity; }
            completion:^(BOOL finished) {
                if (commit) {
                    self.web.alpha=0; self.web.transform=CGAffineTransformIdentity;
                    [self.web evaluateJavaScript:@"window.__vrcrpBack?.()" completionHandler:nil];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{
                        [UIView animateWithDuration:.16 animations:^{ self.web.alpha=1; } completion:^(BOOL finished){self.backPreview.hidden=YES;}];
                    });
                } else self.backPreview.hidden=YES;
            }];
    }
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
    self.edgeBack.enabled=self.canGoBack && !self.keyboardVisible && !self.websiteOverlay;
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
    [self.bottomNav layoutForWebFrame:self.web.frame];
    self.backPreview.frame=self.web.frame;
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
- (void)appActive:(NSNotification *)notification {
    [self.chatNotifications endBackgroundSync];
    [self.web evaluateJavaScript:@"window.__vrcrpAppActive?.(true); window.__vrcrpSyncChats?.()" completionHandler:nil];
}
- (void)appInactive:(NSNotification *)notification {
    [self.web evaluateJavaScript:@"window.__vrcrpAppActive?.(false)" completionHandler:nil];
}
- (void)appBackground:(NSNotification *)notification { [self.chatNotifications beginBackgroundSync]; }
- (void)requestNotifications {
#if ERP_TESTING
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--verify-tabs"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--verify-ux"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--preview-login"]) return;
#endif
    if(self.askedForNotifications)return; self.askedForNotifications=YES;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus==UNAuthorizationStatusNotDetermined)
            [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound|UNAuthorizationOptionBadge completionHandler:^(BOOL granted,NSError *error){}];
    }];
}
- (void)openPendingChat {
    if(!self.pendingChatID.length||!self.chatNotifications.authenticated)return;
    NSString *identifier=self.pendingChatID; self.pendingChatID=nil;
    NSData *json=[NSJSONSerialization dataWithJSONObject:@[identifier] options:0 error:nil];
    NSString *argument=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"window.__vrcrpOpenChat?.(%@[0])",argument] completionHandler:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame || ![message.frameInfo.securityOrigin.host isEqualToString:@"erp.sex"] ||
        ![message.frameInfo.securityOrigin.protocol isEqualToString:@"https"] ||
        ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    if ([message.name isEqualToString:@"erpNativeApp"]) {
        NSString *kind=body[@"kind"];
        if ([kind isEqualToString:@"ready"]) {
            [self contentReady]; [self captureSnapshot]; [self openPendingChat];
            [self.web evaluateJavaScript:UIApplication.sharedApplication.applicationState==UIApplicationStateActive?@"window.__vrcrpAppActive?.(true)":@"window.__vrcrpAppActive?.(false)" completionHandler:nil];
            NSString *script=[NSString stringWithFormat:@"window.__vrcrpAccessibility?.({reduceTransparency:%@,reduceMotion:%@})",UIAccessibilityIsReduceTransparencyEnabled()?@"true":@"false",UIAccessibilityIsReduceMotionEnabled()?@"true":@"false"];
            [self.web evaluateJavaScript:script completionHandler:nil];
        } else if ([kind isEqualToString:@"navigation"]) {
            self.websiteOverlay=[body[@"overlay"] isEqual:@YES];
            self.edgeBack.enabled=self.canGoBack && !self.keyboardVisible && !self.websiteOverlay;
            self.refreshControl.enabled=!self.websiteOverlay;
            if ([body[@"items"] isKindOfClass:NSArray.class] && [self.bottomNav applyModel:body webFrame:self.web.frame]) {
                for (NSDictionary *item in body[@"items"]) if ([item[@"selected"] boolValue] && [item[@"color"] isKindOfClass:NSArray.class]) {
                    [NSUserDefaults.standardUserDefaults setObject:item[@"color"] forKey:@"VRThemeAccent"];
                    self.loadingCover.tintColor=VRColor(item[@"color"],UIColor.systemRedColor);
                }
                [self.web evaluateJavaScript:@"window.__vrcrpNativeNavReady?.()" completionHandler:nil];
            } else {
                self.bottomNav.hidden=YES;
                [self.web evaluateJavaScript:@"window.__vrcrpNativeNavFallback?.()" completionHandler:nil];
            }
        } else if ([kind isEqualToString:@"topSurface"]) {
            UIColor *color=VRColor(body[@"color"],self.statusBarSurface.backgroundColor);
            CGFloat red=1,green=1,blue=1,alpha=1; [color getRed:&red green:&green blue:&blue alpha:&alpha];
            self.statusBarSurface.backgroundColor=color;
            [NSUserDefaults.standardUserDefaults setObject:@[@(red),@(green),@(blue),@1] forKey:@"VRHeaderSurface"];
            self.statusBarStyle=(.2126*red+.7152*green+.0722*blue<.55)?UIStatusBarStyleLightContent:UIStatusBarStyleDarkContent;
            [self setNeedsStatusBarAppearanceUpdate];
        } else if ([kind isEqualToString:@"notificationSettings"]) {
            [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
                dispatch_async(dispatch_get_main_queue(),^{
                    if(settings.authorizationStatus==UNAuthorizationStatusNotDetermined) {
                        self.askedForNotifications=NO; [self requestNotifications];
                    } else [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                });
            }];
        } else if ([kind isEqualToString:@"haptic"] && [body[@"style"] isKindOfClass:NSString.class]) [self haptic:body[@"style"]];
        else if ([kind isEqualToString:@"route"]) {
            NSString *path=body[@"path"];
            if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"] || path.length>500) return;
            if (![body[@"showTabs"] isEqual:@YES]) self.bottomNav.hidden=YES;
            self.chatNotifications.activePath=path;
            self.chatLayout=[path rangeOfString:@"^/matches/[^/]+/?$" options:NSRegularExpressionSearch].location!=NSNotFound;
            if (self.chatLayout) [self.web.scrollView setContentOffset:CGPointZero animated:NO];
            self.canGoBack=[body[@"canGoBack"] isEqual:@YES]; self.edgeBack.enabled=self.canGoBack && !self.keyboardVisible && !self.websiteOverlay;
            if (self.web.alpha<1) {
                [UIView animateWithDuration:.16 animations:^{ self.web.alpha=1; } completion:^(BOOL finished){ self.backPreview.hidden=YES; }];
            } else self.backPreview.image=self.canGoBack?self.lastSnapshot:nil;
            BOOL refresh=[body[@"refreshable"] isEqual:@YES];
            self.web.scrollView.refreshControl=refresh?self.refreshControl:nil;
            self.web.scrollView.bounces=refresh; self.web.scrollView.alwaysBounceVertical=refresh;
            if ([[NSSet setWithArray:@[@"/discover",@"/likes",@"/matches",@"/posts",@"/me"]] containsObject:path]) [NSUserDefaults.standardUserDefaults setObject:path forKey:@"VRLastTab"];
            [self captureSnapshot];
        }
        return;
    }
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
        self.loadingCover.backgroundColor=self.view.backgroundColor; self.web.scrollView.backgroundColor=self.view.backgroundColor;
        self.loadingCover.overrideUserInterfaceStyle=(.2126*red+.7152*green+.0722*blue<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
        [NSUserDefaults.standardUserDefaults setObject:@[@(red),@(green),@(blue),@1] forKey:@"VRThemeBackground"];
        return;
    }
    [self.chatNotifications handleEvent:body];
    if([body[@"kind"] isEqual:@"session"] && self.chatNotifications.authenticated) {
        [self requestNotifications]; [self openPendingChat];
    }
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
    withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
    withCompletionHandler:(void (^)(void))completionHandler {
    NSString *path=response.notification.request.content.userInfo[@"path"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if([path isKindOfClass:NSString.class] && [path rangeOfString:@"^/matches/[A-Za-z0-9_-]{1,120}$" options:NSRegularExpressionSearch].location!=NSNotFound) {
            self.pendingChatID=[path substringFromIndex:9]; [self openPendingChat];
        } else [self.web evaluateJavaScript:@"window.__vrcrpOpenMatches?.()" completionHandler:nil];
    });
    completionHandler();
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    webView.scrollView.pinchGestureRecognizer.enabled = NO;
    ERPPrepareTextInputs(webView);
    [self syncViewport:YES];
    [self.refreshControl endRefreshing];
#if ERP_TESTING
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.web evaluateJavaScript:@"document.querySelector('textarea').focus()" completionHandler:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self captureLayout:@"first"]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.web evaluateJavaScript:@"document.activeElement.blur()" completionHandler:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.web evaluateJavaScript:@"document.querySelector('textarea').focus()" completionHandler:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 7 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self captureLayout:@"reopened"]; });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-tabs"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [self.bottomNav.buttons[3] sendActionsForControlEvents:UIControlEventTouchUpInside];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self captureTabs:@"tabs"]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [self.web evaluateJavaScript:@"const modal=document.createElement('div');modal.id='test-modal';modal.setAttribute('role','dialog');modal.style='position:fixed;inset:0;z-index:999;background:white';document.body.appendChild(modal)" completionHandler:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self captureTabs:@"modal"]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [self.web evaluateJavaScript:@"document.getElementById('test-modal').remove()" completionHandler:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self captureTabs:@"restored"]; });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-ux"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"discover"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__fixtureOpen('/matches/thread')" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"document.querySelector('textarea').focus()" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"chat"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"document.activeElement.blur();__fixtureOpen('/u/peer')" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"profile"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__vrcrpBack()" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,13*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"chat-return"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__vrcrpBack()" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"restored"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,18*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__fixtureDark()" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureUX:@"dark"];});
    }
#endif
}
#if ERP_TESTING
- (void)captureUX:(NSString *)phase {
    NSString *script=@"(() => {const t=document.querySelector('textarea');return {path:location.pathname,webNavVisibility:getComputedStyle(document.querySelector('.app-bottom')).visibility,headerColor:getComputedStyle(document.querySelector('.app-top')).backgroundColor,inputBottom:t?t.getBoundingClientRect().bottom:null,actions:[...document.querySelectorAll('.act')].map(b=>{const r=b.getBoundingClientRect();return {width:r.width,height:r.height,bottom:r.bottom}})};})()";
    [self.web evaluateJavaScript:script completionHandler:^(id result,NSError *error){
        NSMutableDictionary *data=[result isKindOfClass:NSDictionary.class]?[result mutableCopy]:[NSMutableDictionary new];
        data[@"nativeNavVisible"]=@(!self.bottomNav.hidden); data[@"navTop"]=@(self.bottomNav.frame.origin.y-self.web.frame.origin.y);
        data[@"nativeHeight"]=@(self.web.bounds.size.height); data[@"keyboardVisible"]=@(self.keyboardVisible);
        data[@"edgeBackEnabled"]=@(self.edgeBack.enabled); data[@"canGoBack"]=@(self.canGoBack); data[@"overlay"]=@(self.websiteOverlay);
        CGFloat r=1,g=1,b=1,a=1;[self.statusBarSurface.backgroundColor getRed:&r green:&g blue:&b alpha:&a]; data[@"statusColor"]=@[@(r),@(g),@(b),@(a)];
        data[@"statusStyle"]=@(self.statusBarStyle); data[@"plainNavigation"]=@(![self.bottomNav.surface isKindOfClass:UIVisualEffectView.class]);
        if(error)data[@"error"]=error.localizedDescription;
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"ux-%@.json",phase]] atomically:YES];
    }];
}
- (void)captureLayout:(NSString *)phase {
    NSString *script = @"(() => {const e=document.querySelector('textarea'); const r=e.getBoundingClientRect();return {inputTop:r.top,inputBottom:r.bottom,visualHeight:visualViewport.height,scale:visualViewport.scale,windowHeight:innerHeight,chatHeight:document.querySelector('.h-dvh').getBoundingClientRect().height,editing:document.activeElement===e,href:location.href};})()";
    [self.web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        NSMutableDictionary *data = [result isKindOfClass:NSDictionary.class] ? [result mutableCopy] : [NSMutableDictionary new];
        data[@"nativeHeight"] = @(self.web.bounds.size.height);
        data[@"keyboardVisible"] = @(self.keyboardVisible);
        data[@"keyboardHeight"] = @(-self.webBottomConstraint.constant);
        UIView *focused = ERPFocusedView(self.web);
        data[@"accessoryRemoved"] = @(focused && focused.inputAccessoryView == nil);
        data[@"nativeNavVisible"]=@(!self.bottomNav.hidden);
        data[@"nativeTabCount"]=@(self.bottomNav.buttons.count);
        data[@"plainNavigation"]=@(![self.bottomNav.surface isKindOfClass:UIVisualEffectView.class]);
        if (error) data[@"error"] = error.localizedDescription;
        NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"layout-%@.json", phase]] atomically:YES];
    }];
}
- (void)captureTabs:(NSString *)phase {
    NSString *script=@"({path:location.pathname,originalClicks:window.__fixtureClicks,webNavOpacity:getComputedStyle(document.querySelector('.app-bottom')).opacity,webCenters:[...document.querySelectorAll('.app-bottom a')].map(a=>{const r=a.getBoundingClientRect();return [r.x+r.width/2,r.y+r.height/2]})})";
    [self.web evaluateJavaScript:script completionHandler:^(id result,NSError *error) {
        NSMutableDictionary *data=[result isKindOfClass:NSDictionary.class]?[result mutableCopy]:[NSMutableDictionary new];
        data[@"nativeNavVisible"]=@(!self.bottomNav.hidden); data[@"nativeTabCount"]=@(self.bottomNav.buttons.count);
        data[@"plainNavigation"]=@(![self.bottomNav.surface isKindOfClass:UIVisualEffectView.class]);
        NSMutableArray *centers=[NSMutableArray new],*titles=[NSMutableArray new];
        for (UIButton *button in self.bottomNav.buttons) {
            CGPoint point=[button convertPoint:CGPointMake(button.bounds.size.width/2,button.bounds.size.height/2) toView:self.web];
            [centers addObject:@[@(point.x),@(point.y)]]; [titles addObject:button.accessibilityLabel?:@""];
        }
        data[@"nativeCenters"]=centers; data[@"nativeTitles"]=titles;
        if (error) data[@"error"]=error.localizedDescription;
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"tabs-%@.json",phase]] atomically:YES];
    }];
}
#endif
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    ERPPrepareTextInputs(webView);
    [self syncViewport:YES];
}
- (void)showError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    [self.refreshControl endRefreshing];
    if (!self.hasContent) {
        self.loadingCover.hidden=NO; self.loadingCover.alpha=1; [self.spinner stopAnimating];
        self.loadingCaption.text=@"暂时无法连接，请检查网络后重试。"; self.retryButton.hidden=NO;
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"页面加载失败"
        message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self retryPage:action];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url=action.request.URL;
    BOOL main=action.targetFrame.isMainFrame || !action.targetFrame;
    BOOL tapped=action.navigationType==WKNavigationTypeLinkActivated;
    BOOL authentication=[url.path.lowercaseString containsString:@"auth"] || [url.path.lowercaseString containsString:@"login"];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([[NSSet setWithArray:@[@"client_id",@"redirect_uri",@"code_challenge"]] containsObject:item.name]) authentication=YES;
    }
    if (main && tapped && !authentication && ([@"https" isEqualToString:url.scheme] || [@"http" isEqualToString:url.scheme]) && ![url.host isEqualToString:@"erp.sex"] && !self.presentedViewController) {
        [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil]; decisionHandler(WKNavigationActionPolicyCancel); return;
    }
    if (main && tapped && [[NSSet setWithArray:@[@"mailto",@"tel",@"vrchat",@"vrcx"]] containsObject:url.scheme]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; decisionHandler(WKNavigationActionPolicyCancel); return;
    }
    if (main) self.pendingURL=url;
    decisionHandler(WKNavigationActionPolicyAllow);
}
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
