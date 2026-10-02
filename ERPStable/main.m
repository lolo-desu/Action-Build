#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <SafariServices/SafariServices.h>
#import "ThemeNavigation.h"
#import "ChatNotifications.h"
#import "PageNavigation.h"
#import "ExternalBrowser.h"

static BOOL ERPUsesSimulatorFixtures(void) {
#if ERP_TESTING
    NSArray *args=NSProcessInfo.processInfo.arguments;
    return [args containsObject:@"--verify-keyboard"] || [args containsObject:@"--verify-tabs"] || [args containsObject:@"--verify-ux"] || [args containsObject:@"--verify-motion"] || [args containsObject:@"--verify-surfaces"];
#else
    return NO;
#endif
}
static NSString *ERPInjectedScript(NSString *script) {
#if ERP_TESTING
    if(ERPUsesSimulatorFixtures())return [script stringByReplacingOccurrencesOfString:@"https://erp.sex" withString:@"http://127.0.0.1:18765"];
#endif
    return script;
}

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
@property(nonatomic, strong) UIPanGestureRecognizer *edgeBack;
@property(nonatomic, strong) UIPanGestureRecognizer *pullRefresh;
@property(nonatomic, strong) UIView *refreshHint;
@property(nonatomic, strong) UIView *refreshSurface;
@property(nonatomic) CGFloat refreshSpace;
@property(nonatomic, strong) UILabel *refreshLabel;
@property(nonatomic, strong) UIActivityIndicatorView *refreshSpinner;
@property(nonatomic) BOOL refreshable;
@property(nonatomic) BOOL refreshing;
@property(nonatomic) CGFloat pullDistance;
@property(nonatomic) CGFloat pageHeaderHeight;
@property(nonatomic) NSUInteger refreshGeneration;
@property(nonatomic) BOOL profileOverlay;
@property(nonatomic) BOOL editingProfile;
@property(nonatomic) BOOL viewingProfile;
@property(nonatomic, strong) NSArray *horizontalZones;
@property(nonatomic) BOOL textSelected;
@property(nonatomic, strong) PageNavigation *pageNavigation;
@property(nonatomic) BOOL navModelVisible;
@property(nonatomic) BOOL routeShowsTabs;
@property(nonatomic, copy) NSString *sessionContext;
@property(nonatomic, strong) NSURL *pendingURL;
@property(nonatomic) BOOL hasContent;
@property(nonatomic) BOOL canGoBack;
@property(nonatomic) BOOL websiteOverlay;
@property(nonatomic) BOOL chatLayout;
@property(nonatomic, strong) ChatNotifications *chatNotifications;
@property(nonatomic, copy) NSString *pendingChatID;
@property(nonatomic) NSTimeInterval lastHaptic;
@property(nonatomic) NSUInteger snapshotGeneration;
@property(nonatomic) NSUInteger keyboardResizeGeneration;
#if ERP_TESTING
@property(nonatomic) NSUInteger documentLoads;
#endif
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
    NSString *surfaceScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"page-surfaces" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(surfaceScript!=nil,@"Missing page-surfaces.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:ERPInjectedScript(surfaceScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    [configuration.userContentController addScriptMessageHandler:self name:@"erpNativeNotifications"];
    [configuration.userContentController addScriptMessageHandler:self name:@"erpNativeApp"];
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"interaction" withExtension:@"js"];
    NSString *script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    NSAssert(script != nil, @"Missing interaction.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:ERPInjectedScript(script) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    NSString *cacheScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"site-cache" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(cacheScript!=nil,@"Missing site-cache.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:ERPInjectedScript(cacheScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *notificationScript = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"notifications" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(notificationScript != nil, @"Missing notifications.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:ERPInjectedScript(notificationScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *keyboardScript = [NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"keyboard" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(keyboardScript != nil, @"Missing keyboard.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:ERPInjectedScript(keyboardScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *appScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"app-experience" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(appScript!=nil,@"Missing app-experience.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:ERPInjectedScript(appScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *swipeScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"swipe-feedback" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(swipeScript!=nil,@"Missing swipe-feedback.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:ERPInjectedScript(swipeScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *contentScript=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"content-experience" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSAssert(contentScript!=nil,@"Missing content-experience.js");
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:ERPInjectedScript(contentScript) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
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
    self.pageNavigation=[[PageNavigation alloc] initWithWebView:self.web navigation:self.bottomNav header:self.statusBarSurface];
    self.pageNavigation.onTransitionChange=^(BOOL running){[weakSelf restoreNavigation];if(!running)[weakSelf captureSnapshot];};
    self.pageNavigation.onHeaderColor=^(UIColor *color){[weakSelf applyStatusColor:color];};
    self.pageNavigation.onRequestBack=^{
        [weakSelf.web evaluateJavaScript:@"window.__vrcrpPageBack?.() ?? window.__vrcrpBack?.()" completionHandler:^(id result,NSError *error){if(error||![result isEqual:@YES])[weakSelf.pageNavigation abortReturn];}];
    };
    self.bottomNav.onSelect=^(NSInteger slot) {
        [weakSelf haptic:@"selection"];
        [weakSelf.web evaluateJavaScript:[NSString stringWithFormat:@"window.__vrcrpActivateTab?.(%ld)",(long)slot] completionHandler:^(id result,NSError *error){if(error||![result isEqual:@YES])[weakSelf.bottomNav cancelPendingSelection];}];
    };
    self.refreshControl=[UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshPage:) forControlEvents:UIControlEventValueChanged];
    self.edgeBack=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeBack:)];
    self.edgeBack.maximumNumberOfTouches=1; self.edgeBack.delegate=self; self.edgeBack.enabled=NO;
    [self.view addGestureRecognizer:self.edgeBack];
    self.pullRefresh=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pullToRefresh:)];self.pullRefresh.delegate=self;self.pullRefresh.maximumNumberOfTouches=1;self.pullRefresh.cancelsTouchesInView=NO;self.pullRefresh.enabled=NO;[self.view addGestureRecognizer:self.pullRefresh];
    [self createRefreshHint];
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
        NSString *path=[arguments containsObject:@"--verify-tabs"]?@"http://127.0.0.1:18765/discover?fixture=layout":@"http://127.0.0.1:18765/matches/layout-fixture?fixture=layout";
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:path]]];
    } else if ([arguments containsObject:@"--verify-ux"]) {
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:18765/discover"]]];
    } else if ([arguments containsObject:@"--verify-motion"]) {
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:18765/matches"]]];
    } else if ([arguments containsObject:@"--verify-surfaces"]) {
        [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:18765/me?fixture=surfaces"]]];
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
- (void)createRefreshHint {
    self.refreshSurface=[UIView new];self.refreshSurface.userInteractionEnabled=NO;self.refreshSurface.clipsToBounds=YES;self.refreshSurface.hidden=YES;[self.view addSubview:self.refreshSurface];
    self.refreshHint=[UIView new];self.refreshHint.hidden=YES;self.refreshHint.userInteractionEnabled=NO;self.refreshHint.layer.cornerRadius=18;self.refreshHint.layer.borderWidth=1.5;
    self.refreshSpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.refreshLabel=[UILabel new];self.refreshLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];self.refreshLabel.textAlignment=NSTextAlignmentCenter;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.refreshSpinner,self.refreshLabel]];stack.alignment=UIStackViewAlignmentCenter;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.refreshHint addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.refreshHint.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:self.refreshHint.centerYAnchor]]];[self.refreshSurface addSubview:self.refreshHint];
}
- (void)layoutRefreshHint {
    self.refreshSurface.frame=CGRectMake(self.web.frame.origin.x,self.web.frame.origin.y+self.pageHeaderHeight,self.web.bounds.size.width,self.refreshSpace);
    self.refreshHint.frame=CGRectMake((self.web.bounds.size.width-160)/2,MAX(4,(self.refreshSpace-36)/2),160,36);
}
- (void)showPullDistance:(CGFloat)distance {
    self.pullDistance=MAX(0,distance);BOOL visible=distance>5||self.refreshing;self.refreshHint.hidden=!visible;
    self.refreshLabel.text=self.refreshing?@"正在刷新…":distance>=72?@"松开刷新":@"↓ 下拉刷新";
    if(self.refreshing){self.refreshSpinner.hidden=NO;[self.refreshSpinner startAnimating];}else{[self.refreshSpinner stopAnimating];self.refreshSpinner.hidden=YES;}
    CGFloat space=visible?MIN(66,MAX(self.refreshing?58:0,distance*.65)):0;self.refreshSpace=space;self.refreshSurface.hidden=!visible;[self layoutRefreshHint];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"window.__vrcrpPullSurface?.(%.2f)",space] completionHandler:nil];
}
- (void)finishRefresh {
    self.refreshing=NO;self.refreshGeneration++;[self.refreshControl endRefreshing];[self showPullDistance:0];[self updateBackAvailability];
}
- (void)refreshPage:(id)sender {
    if(self.refreshing)return;[self haptic:@"light"];self.refreshing=YES;NSUInteger owner=++self.refreshGeneration;[self showPullDistance:88];
    NSString *script=[self.chatNotifications.activePath isEqual:@"/matches"]?@"await Promise.allSettled([window.__vrcrpSyncChats?.(),window.__vrcrpSiteCache?.refreshPage?.()]);return true;":@"return await window.__vrcrpSiteCache?.refreshPage?.();";
    [self.web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result,NSError *error){
        if(owner!=self.refreshGeneration)return;
        if(error||![result isEqual:@YES])[self.web reload];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(owner==self.refreshGeneration)[self finishRefresh];});
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(owner==self.refreshGeneration)[self finishRefresh];});
}
- (void)pullToRefresh:(UIPanGestureRecognizer *)gesture {
    CGFloat distance=MAX(0,[gesture translationInView:self.view].y);
    if(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged)[self showPullDistance:distance];
    if(gesture.state==UIGestureRecognizerStateEnded){if(distance>=72)[self refreshPage:gesture];else[self showPullDistance:0];}
    if(gesture.state==UIGestureRecognizerStateCancelled)[self showPullDistance:0];
}
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
        if (generation!=self.snapshotGeneration || self.keyboardVisible || self.presentedViewController || self.websiteOverlay || self.profileOverlay || self.pageNavigation.transitioning) return;
        [self.pageNavigation capture];
    });
}
- (void)restoreNavigation {
    self.bottomNav.hidden=!(self.navModelVisible&&self.routeShowsTabs&&!self.keyboardVisible&&!self.websiteOverlay&&!self.pageNavigation.transitioning);
    if(!self.pageNavigation.transitioning)[self.bottomNav layoutForWebFrame:self.web.frame];
}
- (void)applyStatusColor:(UIColor *)color {
    CGFloat r=1,g=1,b=1,a=1;[color getRed:&r green:&g blue:&b alpha:&a];self.statusBarSurface.backgroundColor=color;
    self.statusBarStyle=(.2126*r+.7152*g+.0722*b<.55)?UIStatusBarStyleLightContent:UIStatusBarStyleDarkContent;[self setNeedsStatusBarAppearanceUpdate];
    self.web.backgroundColor=color;self.web.scrollView.backgroundColor=color;
    UIColor *ink=self.statusBarStyle==UIStatusBarStyleLightContent?UIColor.whiteColor:[UIColor colorWithWhite:.12 alpha:1];
    self.refreshHint.backgroundColor=color;self.refreshSurface.backgroundColor=color;self.refreshHint.layer.borderColor=ink.CGColor;self.refreshLabel.textColor=ink;self.refreshSpinner.color=ink;
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];[self.pageNavigation clear];
    [self.web evaluateJavaScript:@"window.__vrcrpSiteCache?.clear()" completionHandler:nil];
}
- (void)updateBackAvailability {
    self.edgeBack.enabled=(self.canGoBack||self.profileOverlay)&&(!self.keyboardVisible||self.editingProfile)&&(!self.websiteOverlay||self.profileOverlay)&&!self.textSelected;
    self.pullRefresh.enabled=self.refreshable&&!self.websiteOverlay&&!self.profileOverlay&&!self.keyboardVisible&&!self.textSelected&&!self.refreshing;
}
- (BOOL)canStartBackAtPoint:(CGPoint)point velocity:(CGPoint)velocity {
    BOOL preview=self.profileOverlay?self.pageNavigation.canPreviewOverlay:self.pageNavigation.canPreviewParent;
    if((!self.canGoBack&&!self.profileOverlay)||(self.keyboardVisible&&!self.editingProfile)||self.textSelected||(self.websiteOverlay&&!self.profileOverlay)||self.presentedViewController||self.web.loading||self.pageNavigation.transitioning||!preview||velocity.x<=fabs(velocity.y)*1.15)return NO;
    if(!CGRectContainsPoint(self.web.bounds,point))return NO;
    if((self.viewingProfile||self.editingProfile||self.profileOverlay)&&point.x<=24)return YES;
    for(id zone in self.horizontalZones)if(CGRectContainsPoint(VRRect(zone),point))return NO;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if(gesture==self.pullRefresh){CGPoint velocity=[self.pullRefresh velocityInView:self.view],point=[gesture locationInView:self.web];for(id zone in self.horizontalZones)if(CGRectContainsPoint(VRRect(zone),point))return NO;return self.refreshable&&!self.refreshing&&!self.websiteOverlay&&!self.profileOverlay&&!self.keyboardVisible&&!self.textSelected&&!self.pageNavigation.transitioning&&self.web.scrollView.contentOffset.y<=.5&&velocity.y>fabs(velocity.x)*1.2;}
    return gesture!=self.edgeBack||[self canStartBackAtPoint:[gesture locationInView:self.web] velocity:[self.edgeBack velocityInView:self.view]];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return ((gesture==self.edgeBack||gesture==self.pullRefresh)&&other==self.web.scrollView.panGestureRecognizer)||((other==self.edgeBack||other==self.pullRefresh)&&gesture==self.web.scrollView.panGestureRecognizer);
}
- (void)edgeBack:(UIPanGestureRecognizer *)gesture {
    CGFloat distance=MAX(0,[gesture translationInView:self.view].x);
    if (gesture.state==UIGestureRecognizerStateBegan) {
        if(self.profileOverlay?[self.pageNavigation beginOverlayInteractive]:[self.pageNavigation beginInteractive]){if(self.editingProfile)[self.web endEditing:YES];[self haptic:@"selection"];[self.pageNavigation updateInteractive:distance];}
    }
    if (gesture.state==UIGestureRecognizerStateChanged) [self.pageNavigation updateInteractive:distance];
    if (gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled) {
        [self.pageNavigation finishInteractive:distance velocity:[gesture velocityInView:self.view].x cancelled:gesture.state==UIGestureRecognizerStateCancelled];
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
    NSUInteger resizeGeneration=++self.keyboardResizeGeneration;
    [self.web evaluateJavaScript:@"window.__vrcrpWillResizeViewport?.()" completionHandler:nil];
    self.keyboardVisible = height > 0;
    [self updateBackAvailability];
    self.webBottomConstraint.constant = -height;
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16;
    [UIView animateWithDuration:duration delay:0 options:curve | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ [self.view layoutIfNeeded]; }
        completion:^(BOOL finished) { [self syncViewport:YES]; if(resizeGeneration==self.keyboardResizeGeneration)[self.web evaluateJavaScript:@"window.__vrcrpDidResizeViewport?.()" completionHandler:nil]; }];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self syncViewport:NO];
    [self.bottomNav layoutForWebFrame:self.web.frame];
    [self.pageNavigation layout];[self layoutRefreshHint];
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
    [self.web evaluateJavaScript:@"window.__vrcrpRefreshSurface?.();window.__vrcrpRefreshChrome?.();window.__vrcrpAppActive?.(true); window.__vrcrpSyncChats?.()" completionHandler:nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.web evaluateJavaScript:@"window.__vrcrpRefreshSurface?.();window.__vrcrpRefreshChrome?.()" completionHandler:nil];
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
        [NSProcessInfo.processInfo.arguments containsObject:@"--verify-motion"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--verify-surfaces"] ||
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
    BOOL trusted=[message.frameInfo.securityOrigin.host isEqualToString:@"erp.sex"] && [message.frameInfo.securityOrigin.protocol isEqualToString:@"https"];
#if ERP_TESTING
    if(ERPUsesSimulatorFixtures() && [message.frameInfo.securityOrigin.host isEqualToString:@"127.0.0.1"] && [message.frameInfo.securityOrigin.protocol isEqualToString:@"http"] && message.frameInfo.securityOrigin.port==18765)trusted=YES;
#endif
    if (!message.frameInfo.isMainFrame || !trusted ||
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
            [self updateBackAvailability];
            self.refreshControl.enabled=!self.websiteOverlay;
            if ([body[@"items"] isKindOfClass:NSArray.class] && [self.bottomNav applyModel:body webFrame:self.web.frame]) {
                self.navModelVisible=[body[@"visible"] isEqual:@YES];[self restoreNavigation];
                for (NSDictionary *item in body[@"items"]) if ([item[@"selected"] boolValue] && [item[@"color"] isKindOfClass:NSArray.class]) {
                    [NSUserDefaults.standardUserDefaults setObject:item[@"color"] forKey:@"VRThemeAccent"];
                    self.loadingCover.tintColor=VRColor(item[@"color"],UIColor.systemRedColor);
                }
                [self.web evaluateJavaScript:@"window.__vrcrpNativeNavReady?.()" completionHandler:nil];
            } else {
                self.navModelVisible=NO;
                self.bottomNav.hidden=YES;
                [self.web evaluateJavaScript:@"window.__vrcrpNativeNavFallback?.()" completionHandler:nil];
            }
        } else if ([kind isEqual:@"pageHeader"]) {
            CGFloat height=[body[@"height"] doubleValue];if(height>=0&&height<=200)self.pageHeaderHeight=height;[self layoutRefreshHint];[self applyStatusColor:VRColor(body[@"color"],self.statusBarSurface.backgroundColor)];
        } else if ([kind isEqual:@"profileOverlay"]) {
            self.profileOverlay=[body[@"visible"] isEqual:@YES];[self updateBackAvailability];if(self.profileOverlay)[self.pageNavigation cancelCapture];else[self.pageNavigation settled:self.pageNavigation.currentKey];
        } else if ([kind isEqual:@"gestureZones"]) {
            if([body[@"zones"] isKindOfClass:NSArray.class]&&[body[@"zones"] count]<=100)self.horizontalZones=body[@"zones"];
        } else if ([kind isEqual:@"selection"]) {
            self.textSelected=[body[@"selected"] isEqual:@YES];[self updateBackAvailability];
        } else if ([kind isEqualToString:@"topSurface"]) {
            UIColor *color=VRColor(body[@"color"],self.statusBarSurface.backgroundColor);
            CGFloat red=1,green=1,blue=1,alpha=1; [color getRed:&red green:&green blue:&blue alpha:&alpha];
            [self applyStatusColor:color];
            [NSUserDefaults.standardUserDefaults setObject:@[@(red),@(green),@(blue),@1] forKey:@"VRHeaderSurface"];
        } else if ([kind isEqual:@"willNavigate"]) {
            if(!self.keyboardVisible&&!self.websiteOverlay&&!self.profileOverlay&&!self.pageNavigation.transitioning)[self.pageNavigation capture];
        } else if ([kind isEqual:@"routeSettled"]) {
            NSString *key=body[@"entryKey"];
            if([key isKindOfClass:NSString.class]&&key.length<=180){[self.pageNavigation settled:key];if(!self.keyboardVisible&&!self.websiteOverlay&&!self.profileOverlay)[self.pageNavigation capture];}
        } else if ([kind isEqual:@"viewUpdated"]) {
            [self captureSnapshot];
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
            self.routeShowsTabs=[body[@"showTabs"] isEqual:@YES];if(!self.routeShowsTabs)self.bottomNav.hidden=YES;
            self.chatNotifications.activePath=path;
            self.editingProfile=[path hasPrefix:@"/profile/edit"];
            self.viewingProfile=[path hasPrefix:@"/u/"];
            [self finishRefresh];
            self.chatLayout=[path rangeOfString:@"^/matches/[^/]+/?$" options:NSRegularExpressionSearch].location!=NSNotFound;
            if (self.chatLayout) [self.web.scrollView setContentOffset:CGPointZero animated:NO];
            self.canGoBack=[body[@"canGoBack"] isEqual:@YES]; [self updateBackAvailability];
            NSString *key=body[@"entryKey"],*parent=body[@"parentKey"],*direction=body[@"direction"];
            if([key isKindOfClass:NSString.class]&&key.length<=180) {
                if(![parent isKindOfClass:NSString.class]||parent.length>180)parent=nil;
                if(![@[@"push",@"pop",@"tab",@"none"] containsObject:direction])direction=@"none";
                [self.pageNavigation moveToKey:key parent:parent path:path direction:direction];
            }
            [self restoreNavigation];
            self.refreshable=[body[@"refreshable"] isEqual:@YES];
            self.web.scrollView.refreshControl=nil;self.web.scrollView.bounces=NO;self.web.scrollView.alwaysBounceVertical=NO;[self updateBackAvailability];
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
        self.loadingCover.backgroundColor=self.view.backgroundColor; self.web.scrollView.backgroundColor=self.statusBarSurface.backgroundColor;self.web.backgroundColor=self.statusBarSurface.backgroundColor;
        self.loadingCover.overrideUserInterfaceStyle=(.2126*red+.7152*green+.0722*blue<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
        [NSUserDefaults.standardUserDefaults setObject:@[@(red),@(green),@(blue),@1] forKey:@"VRThemeBackground"];
        return;
    }
    if([body[@"kind"] isEqual:@"session"]) {
        NSString *context=[NSString stringWithFormat:@"%@|%@|%@",body[@"userId"]?:@"",body[@"mode"]?:@"",body[@"language"]?:@""];
        if(self.sessionContext && ![self.sessionContext isEqual:context]) {
            [self.pageNavigation clear];[self.web evaluateJavaScript:@"window.__vrcrpClearNavigation?.()" completionHandler:nil];
        }
        self.sessionContext=context;
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
    self.documentLoads++;
    if([NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"]) {
        NSDictionary *report=[self.chatNotifications verifyNotificationContent];
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:report options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"notification-content.json"] atomically:YES];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"]) [self verifyKeyboardSequence];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-tabs"]) [self verifyTabsWhenReady:0];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-surfaces"]) [self verifySurfaces];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--verify-ux"]) [self verifyUXSequence];
    if([NSProcessInfo.processInfo.arguments containsObject:@"--verify-motion"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureMotion:@"root"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__fixtureOpen('/matches/thread')" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"document.querySelector('textarea').value='保留草稿'" completionHandler:nil];[self captureMotion:@"push"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.pageNavigation beginInteractive];[self.pageNavigation updateInteractive:self.web.bounds.size.width*.45];[self captureMotion:@"cancel-preview"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.pageNavigation finishInteractive:self.web.bounds.size.width*.45 velocity:-350 cancelled:NO];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureMotion:@"cancelled"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"__fixtureOpen('/u/peer')" completionHandler:nil];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.pageNavigation beginInteractive];[self.pageNavigation updateInteractive:self.web.bounds.size.width*.5];[self captureMotion:@"detail-preview"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.pageNavigation finishInteractive:self.web.bounds.size.width*.5 velocity:500 cancelled:NO];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,13*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureMotion:@"chat-return"];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.pageNavigation beginInteractive];[self.pageNavigation updateInteractive:self.web.bounds.size.width*.6];[self.pageNavigation finishInteractive:self.web.bounds.size.width*.6 velocity:600 cancelled:NO];});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureMotion:@"restored"];});
    }
#endif
}
#if ERP_TESTING
// A cold simulator can finish its document before SVG rasterization supplies
// the native navigation model. Begin the tap test only once it is actionable;
// the selected state is still checked synchronously, before any JS reply.
- (void)verifyTabsWhenReady:(NSUInteger)attempt {
    BOOL ready=!self.bottomNav.hidden && self.bottomNav.bounds.size.width>100 && self.bottomNav.buttons.lastObject.accessibilityLabel.length>0;
    if(!ready && attempt<100) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self verifyTabsWhenReady:attempt+1];});return;
    }
    [self.bottomNav.buttons[3] sendActionsForControlEvents:UIControlEventTouchDown];
    NSDictionary *onPress=[self.bottomNav verifySelection];
    [self.bottomNav verifyIntermediateWebColor];
    NSDictionary *afterWebColor=[self.bottomNav verifySelection];
    [self.bottomNav.buttons[3] sendActionsForControlEvents:UIControlEventTouchUpInside];
    NSMutableArray *selected=[NSMutableArray new];
    for(UIButton *button in self.bottomNav.buttons)if(button.accessibilityTraits&UIAccessibilityTraitSelected)[selected addObject:@(button.tag)];
    NSDictionary *data=@{@"selectedImmediately":selected,@"nativeReady":@(ready),@"onPress":onPress,@"afterIntermediateWebColor":afterWebColor};
    NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:@"tabs-immediate.json"] atomically:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureTabs:@"tabs"];});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self.web evaluateJavaScript:@"const modal=document.createElement('div');modal.id='test-modal';modal.setAttribute('role','dialog');modal.style='position:fixed;inset:0;z-index:999;background:white';document.body.appendChild(modal)" completionHandler:nil];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureTabs:@"modal"];});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.web evaluateJavaScript:@"document.getElementById('test-modal').remove()" completionHandler:nil];});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self captureTabs:@"restored"];});
}
- (void)captureMotion:(NSString *)phase {
    NSMutableDictionary *data=[@{@"currentKey":self.pageNavigation.currentKey?:@"",@"previewKey":self.pageNavigation.previewKey?:NSNull.null,@"progress":@(self.pageNavigation.progress),@"transitioning":@(self.pageNavigation.transitioning),@"interactive":@(self.pageNavigation.interactive),@"canPreviewParent":@(self.pageNavigation.canPreviewParent),@"webTranslation":@(self.web.transform.tx),@"webWidth":@(self.web.bounds.size.width),@"webAlpha":@(self.web.alpha),@"documentLoads":@(self.documentLoads),@"nativeNavVisible":@(!self.bottomNav.hidden),@"fullWidthBack":@(![self.edgeBack isKindOfClass:UIScreenEdgePanGestureRecognizer.class]),@"centerBackAllowed":@([self canStartBackAtPoint:CGPointMake(self.web.bounds.size.width*.55,self.web.bounds.size.height*.45) velocity:CGPointMake(700,0)])} mutableCopy];
    if(self.horizontalZones.count){CGRect zone=VRRect(self.horizontalZones.firstObject);data[@"protectedBackBlocked"]=@(![self canStartBackAtPoint:CGPointMake(CGRectGetMidX(zone),CGRectGetMidY(zone)) velocity:CGPointMake(700,0)]);}
    [self.web evaluateJavaScript:@"({path:location.pathname,index:history.state?.idx,draft:document.querySelector('textarea')?.value || ''})" completionHandler:^(id result,NSError *error){
        if([result isKindOfClass:NSDictionary.class])[data addEntriesFromDictionary:result];if(error)data[@"error"]=error.localizedDescription;
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"motion-%@.json",phase]] atomically:YES];
    }];
}
- (void)captureUX:(NSString *)phase {
    [self captureUX:phase completion:nil];
}
- (void)captureUX:(NSString *)phase completion:(dispatch_block_t)done {
    NSString *script=@"(() => {const t=document.querySelector('textarea');return {path:location.pathname,historyLength:history.length,historyIndex:history.state?.idx,webNavVisibility:getComputedStyle(document.querySelector('.app-bottom')).visibility,headerColor:getComputedStyle(document.querySelector('.app-top')).backgroundColor,inputBottom:t?t.getBoundingClientRect().bottom:null,actions:[...document.querySelectorAll('.act')].map(b=>{const r=b.getBoundingClientRect();return {width:r.width,height:r.height,bottom:r.bottom}})};})()";
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
        if(done)done();
    }];
}
- (BOOL)verifyHeaderRed:(CGFloat)expected {
    CGFloat r=0,g=0,b=0,a=0;[self.statusBarSurface.backgroundColor getRed:&r green:&g blue:&b alpha:&a];return fabs(r-expected)<.001;
}
- (void)verifyJavaScript:(NSString *)script {
    [self.web evaluateJavaScript:script completionHandler:^(id result,NSError *error){if(error)NSLog(@"Verification action failed: %@: %@",script,error);}];
}
- (void)runVerifySteps:(NSArray *)steps index:(NSUInteger)index deadline:(NSTimeInterval)deadline {
    if(index>=steps.count)return;
    NSDictionary *step=steps[index];
    if(deadline==0){dispatch_block_t action=step[@"action"];if(action)action();deadline=NSDate.timeIntervalSinceReferenceDate+35;}
    NSString *condition=step[@"condition"]?:@"true";BOOL (^native)(void)=step[@"native"];
    [self.web evaluateJavaScript:condition completionHandler:^(id result,NSError *error){
        if(!error&&[result isEqual:@YES]&&(!native||native())){
            dispatch_block_t next=^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self runVerifySteps:steps index:index+1 deadline:0];});};
            NSString *phase=step[@"phase"];
            if(!phase.length){next();return;}
            if([NSProcessInfo.processInfo.arguments containsObject:@"--verify-surfaces"])[self captureSurface:phase completion:next];
            else if([NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"])[self captureLayout:phase completion:next];
            else[self captureUX:phase completion:next];
            return;
        }
        if(NSDate.timeIntervalSinceReferenceDate>=deadline){
            NSString *failure=[NSString stringWithFormat:@"Timed out at %@, condition %@, error %@",step[@"phase"]?:@(index),condition,error.localizedDescription?:@"none"];NSLog(@"%@",failure);
            NSDictionary *report=@{@"error":failure};
            NSString *file=[NSProcessInfo.processInfo.arguments containsObject:@"--verify-surfaces"]?@"surfaces-completed.json":[NSProcessInfo.processInfo.arguments containsObject:@"--verify-keyboard"]?@"layout-reopened.json":@"ux-dark.json";
            NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
            [[NSJSONSerialization dataWithJSONObject:report options:0 error:nil] writeToURL:[directory URLByAppendingPathComponent:file] atomically:YES];return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self runVerifySteps:steps index:index deadline:deadline];});
    }];
}
- (void)verifyKeyboardSequence {
    NSDictionary *(^step)(NSString *,NSString *,dispatch_block_t,BOOL(^)(void))=^(NSString *phase,NSString *condition,dispatch_block_t action,BOOL(^native)(void)){return @{@"phase":phase,@"condition":condition,@"action":[action copy],@"native":[native copy]};};
    NSString *ready=@"(() => {const p=document.querySelector('.messages'),v=parseFloat(document.documentElement.style.getPropertyValue('--vrcrp-viewport-height'));return !!p&&p.scrollHeight-p.scrollTop-p.clientHeight<2&&Math.abs(visualViewport.height-v)<1})()";
    NSString *visible=@"(() => {const p=document.querySelector('.messages'),t=document.querySelector('textarea'),last=document.querySelector('[data-last-message]'),v=parseFloat(document.documentElement.style.getPropertyValue('--vrcrp-viewport-height'));return document.activeElement===t&&Math.abs(visualViewport.height-v)<1&&p.scrollHeight-p.scrollTop-p.clientHeight<2&&last.getBoundingClientRect().bottom<=p.getBoundingClientRect().bottom+1&&t.getBoundingClientRect().bottom<=v})()";
    NSArray *steps=@[
        step(@"",ready,^{},^BOOL(void){return !self.keyboardVisible;}),
        step(@"first",visible,^{[self verifyJavaScript:@"document.querySelector('textarea').focus()"];},^BOOL(void){return self.keyboardVisible;}),
        step(@"",ready,^{[self verifyJavaScript:@"document.activeElement.blur()"];},^BOOL(void){return !self.keyboardVisible;}),
        step(@"reopened",visible,^{[self verifyJavaScript:@"document.querySelector('textarea').focus()"];},^BOOL(void){return self.keyboardVisible;})
    ];[self runVerifySteps:steps index:0 deadline:0];
}
- (void)verifyUXSequence {
    NSDictionary *(^step)(NSString *,NSString *,dispatch_block_t,BOOL(^)(void))=^(NSString *phase,NSString *condition,dispatch_block_t action,BOOL(^native)(void)){return @{@"phase":phase,@"condition":condition,@"action":[action copy],@"native":[native copy]};};
    NSArray *steps=@[
        step(@"discover",@"location.pathname==='/discover'",^{},^BOOL(void){return !self.pageNavigation.transitioning&&self.pageNavigation.currentKey.length>0;}),
        step(@"",@"location.pathname==='/matches/thread'&&!!document.querySelector('textarea')",^{[self verifyJavaScript:@"__fixtureOpen('/matches/thread')"];},^BOOL(void){return !self.pageNavigation.transitioning;}),
        step(@"chat",@"document.activeElement===document.querySelector('textarea')",^{[self verifyJavaScript:@"document.querySelector('textarea').focus()"];},^BOOL(void){return self.keyboardVisible&&!self.pageNavigation.transitioning;}),
        step(@"profile",@"location.pathname==='/u/peer'",^{[self verifyJavaScript:@"document.activeElement.blur();__fixtureOpen('/u/peer')"];},^BOOL(void){return !self.keyboardVisible&&!self.pageNavigation.transitioning;}),
        step(@"chat-return",@"location.pathname==='/matches/thread'",^{[self verifyJavaScript:@"__vrcrpBack()"];},^BOOL(void){return !self.pageNavigation.transitioning;}),
        step(@"restored",@"location.pathname==='/discover'",^{[self verifyJavaScript:@"__vrcrpBack()"];},^BOOL(void){return !self.pageNavigation.transitioning&&!self.bottomNav.hidden;}),
        step(@"dark",@"getComputedStyle(document.querySelector('.app-top')).backgroundColor==='rgb(24, 28, 35)'",^{[self verifyJavaScript:@"__fixtureDark()"];},^BOOL(void){return [self verifyHeaderRed:24.0/255];})
    ];[self runVerifySteps:steps index:0 deadline:0];
}
- (BOOL)verifyExternalPath:(NSString *)path back:(BOOL)back forward:(BOOL)forward {
    if(![self.presentedViewController isKindOfClass:ExternalBrowser.class])return NO;
    ExternalBrowser *browser=(ExternalBrowser *)self.presentedViewController;NSDictionary *state=[browser verifyState];
    return browser.view.window&&!browser.isBeingPresented&&![state[@"loading"] boolValue]&&[state[@"url"] hasSuffix:path]&&[state[@"back"] boolValue]==back&&[state[@"forward"] boolValue]==forward;
}
- (void)verifySurfaces {
    NSDictionary *(^step)(NSString *,NSString *,dispatch_block_t,BOOL(^)(void))=^(NSString *phase,NSString *condition,dispatch_block_t action,BOOL(^native)(void)){return @{@"phase":phase,@"condition":condition,@"action":[action copy],@"native":[native copy]};};
    BOOL(^settled)(void)=^BOOL(void){return !self.pageNavigation.transitioning;};
    NSArray *steps=@[
        step(@"",@"!!window.__surfaceOpen",^{},^BOOL(void){return self.pageNavigation.canPreviewOverlay;}),
        step(@"edit-entry",@"location.pathname==='/profile/edit/basics'&&!!document.querySelector('[data-vrcrp-page-back]')",^{[self verifyJavaScript:@"__surfaceOpen('/profile/edit/basics')"];},settled),
        step(@"edit-keyboard",@"document.activeElement===document.querySelector('textarea')",^{[self verifyJavaScript:@"document.querySelector('textarea').focus()"];},^BOOL(void){return self.keyboardVisible;}),
        step(@"edit-tabs",@"location.pathname==='/profile/edit/photos'&&!!document.querySelector('[data-vrcrp-page-back]')",^{[self verifyJavaScript:@"__surfaceOpen('/profile/edit/about');__surfaceOpen('/profile/edit/photos')"];},settled),
        step(@"edit-return",@"location.pathname==='/me'",^{[self verifyJavaScript:@"__vrcrpPageBack()"];},^BOOL(void){return !self.keyboardVisible&&!self.pageNavigation.transitioning;}),
        step(@"chat",@"location.pathname==='/matches/thread'&&document.querySelector('[data-vrcrp-unread]')?.textContent==='7'",^{[self verifyJavaScript:@"__surfaceOpen('/matches/thread');__vrcrpChatUnread(7)"];},settled),
        step(@"profile",@"location.pathname==='/u/peer'&&!!document.querySelector('[data-vrcrp-page-back]')",^{[self verifyJavaScript:@"__surfaceOpen('/u/peer')"];},settled),
        step(@"profile-return",@"location.pathname==='/matches/thread'",^{[self verifyJavaScript:@"__vrcrpPageBack()"];},settled),
        step(@"",@"location.pathname==='/me'",^{[self verifyJavaScript:@"__vrcrpPageBack()"];},settled),
        step(@"",@"location.pathname==='/matches'",^{[self verifyJavaScript:@"__surfaceOpen('/matches')"];},settled),
        step(@"pull",@"document.getElementById('main').hasAttribute('data-vrcrp-pulling')",^{[self showPullDistance:100];},^BOOL(void){return !self.refreshHint.hidden;}),
        step(@"refreshed",@"window.fixtureRefreshes>=1&&!document.getElementById('main').hasAttribute('data-vrcrp-pulling')",^{[self refreshPage:nil];},^BOOL(void){return !self.refreshing&&self.refreshHint.hidden;}),
        step(@"",@"location.pathname==='/discover'",^{[self verifyJavaScript:@"__surfaceOpen('/discover')"];},^BOOL(void){return !self.pageNavigation.transitioning&&self.pageNavigation.canPreviewOverlay;}),
        step(@"",@"!!document.querySelector('[data-vrcrp-profile-overlay]')",^{[self verifyJavaScript:@"__surfaceOverlay()"];},^BOOL(void){return self.profileOverlay;}),
        step(@"overlay-preview",@"!!document.querySelector('[data-vrcrp-profile-overlay]')",^{[self.pageNavigation beginOverlayInteractive];[self.pageNavigation updateInteractive:self.web.bounds.size.width*.4];},^BOOL(void){return self.profileOverlay&&self.pageNavigation.interactive;}),
        step(@"overlay-cancelled",@"!!document.querySelector('[data-vrcrp-profile-overlay]')",^{[self.pageNavigation finishInteractive:self.web.bounds.size.width*.4 velocity:-500 cancelled:NO];},settled),
        step(@"overlay-return",@"!document.querySelector('[data-vrcrp-profile-overlay]')",^{[self.pageNavigation beginOverlayInteractive];[self.pageNavigation updateInteractive:self.web.bounds.size.width*.55];[self.pageNavigation finishInteractive:self.web.bounds.size.width*.55 velocity:800 cancelled:NO];},^BOOL(void){return !self.profileOverlay&&!self.pageNavigation.transitioning;}),
        step(@"external-a",@"true",^{[self verifyJavaScript:@"location.href='http://localhost:18765/external/a'"];},^BOOL(void){return [self verifyExternalPath:@"/external/a" back:NO forward:NO];}),
        step(@"external-b",@"true",^{[(ExternalBrowser *)self.presentedViewController verifyOpenNext];},^BOOL(void){return [self verifyExternalPath:@"/external/b" back:YES forward:NO];}),
        step(@"external-back",@"true",^{[(ExternalBrowser *)self.presentedViewController back:nil];},^BOOL(void){return [self verifyExternalPath:@"/external/a" back:NO forward:YES];}),
        step(@"external-forward",@"true",^{[(ExternalBrowser *)self.presentedViewController forward:nil];},^BOOL(void){return [self verifyExternalPath:@"/external/b" back:YES forward:NO];}),
        step(@"",@"true",^{[(ExternalBrowser *)self.presentedViewController close:nil];},^BOOL(void){return !self.presentedViewController&&self.view.window;}),
        step(@"",@"location.pathname==='/matches'",^{[self verifyJavaScript:@"__surfaceOpen('/matches');document.documentElement.style.setProperty('--surface','24 28 35')"];},^BOOL(void){return [self verifyHeaderRed:24.0/255];}),
        step(@"dark-pull",@"document.getElementById('main').hasAttribute('data-vrcrp-pulling')",^{[self showPullDistance:100];},^BOOL(void){return [self verifyHeaderRed:24.0/255]&&!self.refreshHint.hidden;}),
        step(@"",@"getComputedStyle(document.querySelector('.app-top')).backgroundColor==='rgb(255, 255, 255)'",^{[self showPullDistance:0];[self verifyJavaScript:@"document.documentElement.style.setProperty('--surface','255 255 255')"];},^BOOL(void){return [self verifyHeaderRed:1];}),
        step(@"light-pull",@"document.getElementById('main').hasAttribute('data-vrcrp-pulling')",^{[self showPullDistance:100];},^BOOL(void){return [self verifyHeaderRed:1]&&!self.refreshHint.hidden;}),
        step(@"completed",@"location.pathname==='/discover'",^{[self showPullDistance:0];[self verifyJavaScript:@"__surfaceOpen('/discover')"];},settled)
    ];[self runVerifySteps:steps index:0 deadline:0];
}
- (void)captureSurface:(NSString *)phase {
    [self captureSurface:phase completion:nil];
}
- (void)captureSurface:(NSString *)phase completion:(dispatch_block_t)done {
    CGFloat r,g,b,a;[self.web.scrollView.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
    CGRect hint=[self.refreshHint convertRect:self.refreshHint.bounds toView:self.view];
    NSMutableDictionary *data=[@{@"keyboard":@(self.keyboardVisible),@"backEnabled":@(self.edgeBack.enabled),@"edgeBackAllowed":@([self canStartBackAtPoint:CGPointMake(12,180) velocity:CGPointMake(700,0)]),@"headerHeight":@(self.pageHeaderHeight),@"hintTop":@(hint.origin.y-self.web.frame.origin.y),@"hintVisible":@(!self.refreshHint.hidden&&!self.refreshSurface.hidden),@"hintText":self.refreshLabel.text?:@"",@"bounce":@(self.web.scrollView.bounces),@"surfaceColor":@[@(r),@(g),@(b),@(a)],@"documentLoads":@(self.documentLoads),@"overlay":@(self.profileOverlay),@"interactive":@(self.pageNavigation.interactive),@"transitioning":@(self.pageNavigation.transitioning),@"translation":@(self.web.transform.tx)} mutableCopy];
    if([self.presentedViewController isKindOfClass:ExternalBrowser.class])data[@"external"]=[(ExternalBrowser *)self.presentedViewController verifyState];
    UIWindow *visibleWindow=self.presentedViewController.view.window?:self.view.window;
    if(visibleWindow&&[@[@"chat",@"pull",@"dark-pull",@"light-pull",@"external-a"] containsObject:phase]) {
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:visibleWindow.bounds];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){[visibleWindow drawViewHierarchyInRect:visibleWindow.bounds afterScreenUpdates:NO];}];
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [UIImagePNGRepresentation(image) writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"surfaces-%@.png",phase]] atomically:YES];
    }
    [self.web evaluateJavaScript:@"({path:location.pathname,index:history.state?.idx,historyLength:history.length,globalHeaderHidden:getComputedStyle(document.querySelector('.app-top')).display==='none',chatHeaderTop:document.querySelector('[data-vrcrp-chat-bar]')?.getBoundingClientRect().top ?? null,unread:document.querySelector('[data-vrcrp-unread]')?.textContent ?? null,backButton:!!document.querySelector('[data-vrcrp-page-back]'),refreshes:window.fixtureRefreshes,installHidden:!!navigator.standalone,mainURL:location.href})" completionHandler:^(id result,NSError *error){
        if([result isKindOfClass:NSDictionary.class])[data addEntriesFromDictionary:result];if(error)data[@"error"]=error.localizedDescription;
        NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"surfaces-%@.json",phase]] atomically:YES];
        if(done)done();
    }];
}
- (void)captureLayout:(NSString *)phase {
    [self captureLayout:phase completion:nil];
}
- (void)captureLayout:(NSString *)phase completion:(dispatch_block_t)done {
    NSString *script = @"(() => {const e=document.querySelector('textarea'); const r=e.getBoundingClientRect();return {inputTop:r.top,inputBottom:r.bottom,visualHeight:visualViewport.height,scale:visualViewport.scale,windowHeight:innerHeight,chatHeight:document.querySelector('.h-dvh').getBoundingClientRect().height,editing:document.activeElement===e,href:location.href,messageGap:(()=>{const p=document.querySelector('.messages');return p.scrollHeight-p.scrollTop-p.clientHeight})(),lastMessageBottom:document.querySelector('[data-last-message]')?.getBoundingClientRect().bottom,messagePaneBottom:document.querySelector('.messages').getBoundingClientRect().bottom};})()";
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
        if(done)done();
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
    BOOL internal=[url.host.lowercaseString isEqual:@"erp.sex"];
#if ERP_TESTING
    if(ERPUsesSimulatorFixtures()&&[url.host isEqual:@"127.0.0.1"]&&[url.port isEqual:@18765])internal=YES;
#endif
    if(main&&[@[@"http",@"https"] containsObject:url.scheme.lowercaseString]&&!internal) {
        [self openExternalRequest:action.request];decisionHandler(WKNavigationActionPolicyCancel);return;
    }
    if(main&&tapped&&[@[@"mailto",@"tel",@"vrchat",@"vrcx"] containsObject:url.scheme.lowercaseString]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];decisionHandler(WKNavigationActionPolicyCancel);return;
    }
    if (main) self.pendingURL=url;
    decisionHandler(WKNavigationActionPolicyAllow);
}
- (void)openExternalRequest:(NSURLRequest *)request {
    if(self.presentedViewController)return;[self.web endEditing:YES];
    ExternalBrowser *browser=[[ExternalBrowser alloc] initWithRequest:request surface:self.statusBarSurface.backgroundColor?:UIColor.systemBackgroundColor];
    __weak BrowserController *weakSelf=self;browser.onInternalRequest=^(NSURLRequest *request){[weakSelf.web loadRequest:request];};
    [self presentViewController:browser animated:YES completion:nil];
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if(!action.targetFrame){if([action.request.URL.host.lowercaseString isEqual:@"erp.sex"])[webView loadRequest:action.request];else[self openExternalRequest:action.request];}
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
