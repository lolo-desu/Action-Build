#import "ExternalBrowser.h"

@interface ExternalBrowser () <WKNavigationDelegate,WKUIDelegate>
@property(nonatomic,strong) NSURLRequest *request;
@property(nonatomic,strong) UIColor *surface;
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UIView *bar;
@property(nonatomic,strong) UILabel *hostLabel;
@property(nonatomic,strong) UILabel *pageLabel;
@property(nonatomic,strong) UIButton *backButton;
@property(nonatomic,strong) UIButton *forwardButton;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIProgressView *progress;
@property(nonatomic) BOOL observing;
@end
@implementation ExternalBrowser
- (instancetype)initWithRequest:(NSURLRequest *)request surface:(UIColor *)surface {
    if(!(self=[super init]))return nil;self.request=request;self.surface=surface;self.modalPresentationStyle=UIModalPresentationFullScreen;return self;
}
- (UIButton *)button:(NSString *)symbol title:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];button.accessibilityLabel=title;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:44].active=YES;[button.heightAnchor constraintEqualToConstant:44].active=YES;return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=self.surface;
    CGFloat r=1,g=1,b=1,a=1;[self.surface getRed:&r green:&g blue:&b alpha:&a];
    self.overrideUserInterfaceStyle=(.2126*r+.7152*g+.0722*b<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;config.allowsInlineMediaPlayback=YES;
    self.web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];self.web.navigationDelegate=self;self.web.UIDelegate=self;
    self.web.allowsBackForwardNavigationGestures=YES;self.web.translatesAutoresizingMaskIntoConstraints=NO;
    self.bar=[UIView new];self.bar.backgroundColor=self.surface;self.bar.translatesAutoresizingMaskIntoConstraints=NO;
    self.backButton=[self button:@"chevron.left" title:@"返回上一个网站页面" action:@selector(back:)];
    self.forwardButton=[self button:@"chevron.right" title:@"前进" action:@selector(forward:)];
    self.closeButton=[self button:@"xmark" title:@"关闭外部网站" action:@selector(close:)];
    self.hostLabel=[UILabel new];self.hostLabel.textColor=UIColor.labelColor;self.hostLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];self.hostLabel.textAlignment=NSTextAlignmentCenter;self.hostLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    self.pageLabel=[UILabel new];self.pageLabel.font=[UIFont systemFontOfSize:11];self.pageLabel.textColor=UIColor.secondaryLabelColor;self.pageLabel.textAlignment=NSTextAlignmentCenter;
    UIStackView *titles=[[UIStackView alloc] initWithArrangedSubviews:@[self.hostLabel,self.pageLabel]];titles.axis=UILayoutConstraintAxisVertical;titles.spacing=2;
    [titles setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.backButton,self.forwardButton,titles,self.closeButton]];stack.spacing=2;stack.alignment=UIStackViewAlignmentCenter;stack.translatesAutoresizingMaskIntoConstraints=NO;
    self.progress=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];self.progress.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.web];[self.view addSubview:self.bar];[self.bar addSubview:stack];[self.bar addSubview:self.progress];
    [NSLayoutConstraint activateConstraints:@[
        [self.bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.bar.heightAnchor constraintEqualToConstant:56],
        [stack.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor constant:6],[stack.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor constant:-6],[stack.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],
        [self.progress.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor],[self.progress.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor],[self.progress.bottomAnchor constraintEqualToAnchor:self.bar.bottomAnchor],
        [self.web.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor],[self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    for(NSString *key in @[@"URL",@"title",@"canGoBack",@"canGoForward",@"estimatedProgress",@"loading"])[self.web addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew context:NULL];self.observing=YES;
    [self update];[self.web loadRequest:self.request];
}
- (void)dealloc { if(self.observing)for(NSString *key in @[@"URL",@"title",@"canGoBack",@"canGoForward",@"estimatedProgress",@"loading"])[self.web removeObserver:self forKeyPath:key]; }
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context { if(object==self.web)[self update];else[super observeValueForKeyPath:key ofObject:object change:change context:context]; }
- (void)update {
    NSURL *url=self.web.URL?:self.request.URL;self.hostLabel.text=url.host?:@"外部网站";self.hostLabel.accessibilityLabel=[@"当前网站：" stringByAppendingString:self.hostLabel.text];
    self.pageLabel.text=self.web.title.length?self.web.title:([url.scheme isEqual:@"https"]?@"安全连接":@"网站浏览");
    self.backButton.enabled=self.web.canGoBack;self.forwardButton.enabled=self.web.canGoForward;self.progress.progress=self.web.estimatedProgress;self.progress.hidden=!self.web.loading;
}
- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return self.overrideUserInterfaceStyle==UIUserInterfaceStyleDark?UIStatusBarStyleLightContent:UIStatusBarStyleDarkContent; }
- (void)back:(id)sender { if(self.web.canGoBack)[self.web goBack]; }
- (void)forward:(id)sender { if(self.web.canGoForward)[self.web goForward]; }
- (void)close:(id)sender { [self.web stopLoading];[self dismissViewControllerAnimated:YES completion:nil]; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))reply {
    NSURL *url=action.request.URL;BOOL main=action.targetFrame.isMainFrame||!action.targetFrame;
    BOOL internal=[url.host.lowercaseString isEqual:@"erp.sex"];
#if ERP_TESTING
    if([url.host isEqual:@"127.0.0.1"]&&[url.port isEqual:@18765])internal=YES;
#endif
    if(main&&internal){reply(WKNavigationActionPolicyCancel);NSURLRequest *request=action.request;[self dismissViewControllerAnimated:YES completion:^{if(self.onInternalRequest)self.onInternalRequest(request);}];return;}
    if(main&&![@[@"http",@"https",@"about",@"blob",@"data"] containsObject:url.scheme.lowercaseString]){reply(WKNavigationActionPolicyCancel);[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];return;}
    reply(WKNavigationActionPolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features { if(!action.targetFrame)[webView loadRequest:action.request];return nil; }
- (void)showError:(NSError *)error {
    if(error.code==NSURLErrorCancelled||self.presentedViewController)return;
    self.pageLabel.text=@"加载失败，可返回或关闭";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"网站暂时无法加载" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self.web reload];}]];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self showError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))done {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:self.hostLabel.text message:message preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){done();}]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))done {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:self.hostLabel.text message:message preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){done(YES);}]];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){done(NO);}]];[self presentViewController:alert animated:YES completion:nil];
}
#if ERP_TESTING
- (NSDictionary *)verifyState { return @{@"host":self.hostLabel.text?:@"",@"url":self.web.URL.absoluteString?:@"",@"back":@(self.backButton.enabled),@"forward":@(self.forwardButton.enabled),@"loading":@(self.web.loading),@"title":self.web.title?:@"",@"close":@(!self.closeButton.hidden),@"barBottom":@(CGRectGetMaxY(self.bar.frame)),@"webTop":@(self.web.frame.origin.y),@"statusVisible":@(!self.prefersStatusBarHidden)}; }
- (void)verifyOpenNext { [self.web evaluateJavaScript:@"document.querySelector('a').click()" completionHandler:nil]; }
#endif
@end
