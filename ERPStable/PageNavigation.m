#import "PageNavigation.h"
#import <math.h>

@interface VRPageImage : NSObject
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,strong) UIColor *header;
@property(nonatomic,copy) NSString *path;
@end
@implementation VRPageImage
@end

@interface PageNavigation ()
@property(nonatomic,weak) WKWebView *web;
@property(nonatomic,weak) UIView *navigation;
@property(nonatomic,weak) UIView *header;
@property(nonatomic,strong) NSCache<NSString *,VRPageImage *> *images;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSString *> *paths;
@property(nonatomic,strong) UIImageView *underlay;
@property(nonatomic,strong) UIView *shade;
@property(nonatomic,strong) UIImageView *outgoing;
@property(nonatomic,copy,readwrite) NSString *currentKey;
@property(nonatomic,copy) NSString *parentKey;
@property(nonatomic,copy) NSString *currentPath;
@property(nonatomic,copy,readwrite) NSString *previewKey;
@property(nonatomic,readwrite) BOOL transitioning;
@property(nonatomic,readwrite) BOOL interactive;
@property(nonatomic,readwrite) CGFloat progress;
@property(nonatomic) BOOL waitingReturn;
@property(nonatomic) BOOL animationDone;
@property(nonatomic) BOOL routeReady;
@property(nonatomic,readwrite) BOOL handoff;
@property(nonatomic,strong) UIImageView *handoffView;
@property(nonatomic) BOOL paintRequested;
@property(nonatomic) BOOL foregroundPreview;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger captureGeneration;
@property(nonatomic,strong) UIColor *fromHeader;
@property(nonatomic,strong) UIColor *toHeader;
@end

@implementation PageNavigation
- (instancetype)initWithWebView:(WKWebView *)web navigation:(UIView *)navigation header:(UIView *)header {
    if(!(self=[super init]))return nil;
    self.web=web;self.navigation=navigation;self.header=header;self.currentKey=@"";self.currentPath=@"";
    self.images=[NSCache new];self.images.countLimit=12;self.images.totalCostLimit=60*1024*1024;self.paths=[NSMutableDictionary new];
    self.underlay=[UIImageView new];self.underlay.contentMode=UIViewContentModeScaleToFill;self.underlay.hidden=YES;self.underlay.userInteractionEnabled=NO;
    [web.superview insertSubview:self.underlay belowSubview:web];
    self.shade=[UIView new];self.shade.backgroundColor=UIColor.blackColor;[self.underlay addSubview:self.shade];
    self.outgoing=[UIImageView new];self.outgoing.contentMode=UIViewContentModeScaleToFill;self.outgoing.hidden=YES;self.outgoing.userInteractionEnabled=NO;
    [web.superview addSubview:self.outgoing];
    return self;
}
- (CGRect)viewport { CGSize size=self.web.bounds.size;return CGRectMake(self.web.center.x-size.width/2,self.web.center.y-size.height/2,size.width,size.height); }
- (void)layout {
    CGRect frame=[self viewport];
    for(UIView *view in @[self.underlay,self.outgoing]){view.bounds=CGRectMake(0,0,frame.size.width,frame.size.height);view.center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));}
    self.shade.frame=self.underlay.bounds;
    self.web.layer.shadowPath=[UIBezierPath bezierPathWithRect:self.web.bounds].CGPath;
}
- (BOOL)canPreviewParent { return self.parentKey.length && [self.images objectForKey:self.parentKey]!=nil; }
- (BOOL)canPreviewOverlay { return [self.images objectForKey:self.currentKey]!=nil; }
- (void)cancelCapture { self.captureGeneration++; }
- (void)capture {
    if(!self.currentKey.length||!self.routeReady||self.transitioning||self.handoff||self.web.alpha<.99)return;
    NSString *key=self.currentKey,*path=self.currentPath;NSUInteger generation=++self.captureGeneration;
    CGRect viewport=[self viewport];if(viewport.size.width<100||viewport.size.height<100)return;
    WKSnapshotConfiguration *config=[WKSnapshotConfiguration new];config.afterScreenUpdates=YES;
    [self.web takeSnapshotWithConfiguration:config completionHandler:^(UIImage *image,NSError *error){
        if(!image||generation!=self.captureGeneration||![self.currentKey isEqual:key]||self.transitioning||self.handoff)return;
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=MIN(2,UIScreen.mainScreen.scale);format.opaque=YES;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:viewport.size format:format];
        UIImage *composite=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            [image drawInRect:CGRectMake(0,0,viewport.size.width,viewport.size.height)];
            if(!self.navigation.hidden) {
                CGRect nav=self.navigation.frame;CGContextSaveGState(context.CGContext);
                CGContextTranslateCTM(context.CGContext,nav.origin.x-viewport.origin.x,nav.origin.y-viewport.origin.y);
                [self.navigation.layer renderInContext:context.CGContext];CGContextRestoreGState(context.CGContext);
            }
        }];
        VRPageImage *page=[VRPageImage new];page.image=composite;page.header=self.header.backgroundColor?:UIColor.systemBackgroundColor;page.path=path;
        NSUInteger cost=(NSUInteger)(composite.size.width*composite.size.height*format.scale*format.scale*4);
        [self.images setObject:page forKey:key cost:cost];self.paths[path]=key;
        if(self.paths.count>20){for(NSString *p in self.paths.allKeys)if(![self.images objectForKey:self.paths[p]])[self.paths removeObjectForKey:p];}
    }];
}
- (void)setRunning:(BOOL)value {
    // Animation is presentation, never a lock on the router or its controls.
    self.transitioning=value;self.web.userInteractionEnabled=YES;
    if(self.onTransitionChange)self.onTransitionChange(value);
}
- (void)shadow:(BOOL)visible {
    self.web.layer.shadowColor=UIColor.blackColor.CGColor;self.web.layer.shadowOpacity=visible?.2:0;
    self.web.layer.shadowRadius=12;self.web.layer.shadowOffset=CGSizeMake(-4,0);
}
- (void)headerAtProgress:(CGFloat)progress {
    CGFloat a[4]={1,1,1,1},b[4]={1,1,1,1};[self.fromHeader getRed:&a[0] green:&a[1] blue:&a[2] alpha:&a[3]];[self.toHeader getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]];
    UIColor *color=[UIColor colorWithRed:a[0]+(b[0]-a[0])*progress green:a[1]+(b[1]-a[1])*progress blue:a[2]+(b[2]-a[2])*progress alpha:1];
    if(self.onHeaderColor)self.onHeaderColor(color);
}
- (void)complete {
    self.generation++;self.waitingReturn=NO;self.interactive=NO;self.progress=0;
    self.handoff=NO;self.handoffView=nil;self.paintRequested=NO;self.foregroundPreview=NO;
    [self.web.layer removeAllAnimations];[self.underlay.layer removeAllAnimations];[self.outgoing.layer removeAllAnimations];[self.shade.layer removeAllAnimations];
    self.web.transform=CGAffineTransformIdentity;self.web.alpha=1;[self shadow:NO];
    self.underlay.hidden=YES;self.underlay.image=nil;self.underlay.transform=CGAffineTransformIdentity;
    self.outgoing.hidden=YES;self.outgoing.image=nil;self.outgoing.transform=CGAffineTransformIdentity;self.previewKey=nil;
    self.underlay.alpha=1;self.outgoing.alpha=1;[self.web.superview insertSubview:self.underlay belowSubview:self.web];
    [self setRunning:NO];
}
- (void)holdCover:(UIImageView *)cover {
    self.generation++;self.handoff=YES;self.handoffView=cover;self.paintRequested=NO;self.animationDone=YES;
    cover.hidden=NO;cover.alpha=1;cover.transform=CGAffineTransformIdentity;
    self.web.transform=CGAffineTransformIdentity;[self shadow:NO];[self setRunning:NO];
    // This cover never owns input. A new gesture/navigation can replace it.
    NSUInteger owner=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(owner!=self.generation||!self.handoff||self.waitingReturn)return;
        self.routeReady=YES;[self revealPaintedPage];
    });
    [self revealPaintedPage];
}
- (void)revealPaintedPage {
    if(!self.handoff||self.waitingReturn||self.interactive||!self.routeReady||self.paintRequested)return;
    self.paintRequested=YES;NSUInteger owner=self.generation;NSString *key=self.currentKey;UIImageView *cover=self.handoffView;
    WKSnapshotConfiguration *config=[WKSnapshotConfiguration new];config.afterScreenUpdates=YES;
    [self.web takeSnapshotWithConfiguration:config completionHandler:^(UIImage *image,NSError *error){
        if(owner!=self.generation||![key isEqual:self.currentKey]||cover!=self.handoffView)return;
        // The snapshot is a WebKit rendering barrier, not a cached route signal.
        // Keep a single parent surface throughout the handoff, then reveal live UI.
        if(image)cover.image=image;
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:.08 delay:0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{cover.alpha=0;}
          completion:^(BOOL finished){if(owner==self.generation)[self complete];}];
    }];
}
- (void)moveToKey:(NSString *)key parent:(NSString *)parent path:(NSString *)path direction:(NSString *)direction {
    if(!key.length)return;
    NSString *oldKey=self.currentKey,*oldPath=self.currentPath;VRPageImage *old=[self.images objectForKey:oldKey];UIImage *oldImage=self.handoff?self.handoffView.image:old.image;
    self.currentKey=key;self.parentKey=parent;self.currentPath=path;
    if([oldKey isEqual:key]&&[oldPath isEqual:path])return;
    [self cancelCapture];self.routeReady=NO;
    BOOL returned=self.waitingReturn;
    if(returned){
        self.waitingReturn=NO;self.routeReady=NO;
        [self holdCover:self.handoffView?:self.underlay];return;
    }
    if(self.transitioning||self.handoff)[self complete];
    if(!oldKey.length||[oldKey isEqual:key]||[direction isEqual:@"none"]||[direction isEqual:@"tab"]||UIAccessibilityIsReduceMotionEnabled())return;
    [self layout];NSUInteger generation=++self.generation;CGFloat width=self.web.bounds.size.width;
    self.routeReady=NO;self.animationDone=NO;[self setRunning:YES];
    if([direction isEqual:@"push"]) {
        self.underlay.image=old.image;self.underlay.hidden=old==nil;self.previewKey=oldKey;
        self.underlay.transform=CGAffineTransformIdentity;self.shade.alpha=0;
        VRPageImage *warm=[self.images objectForKey:self.paths[path]?:@""];
        self.outgoing.image=warm.image;self.outgoing.hidden=warm==nil;
        self.outgoing.transform=CGAffineTransformMakeTranslation(width,0);
        self.web.transform=CGAffineTransformMakeTranslation(width,0);[self shadow:YES];
        [UIView animateWithDuration:.24 delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.web.transform=CGAffineTransformIdentity;self.outgoing.transform=CGAffineTransformIdentity;self.underlay.transform=CGAffineTransformMakeTranslation(-width*.27,0);self.shade.alpha=.2;
        } completion:^(BOOL finished){if(generation!=self.generation)return;self.animationDone=YES;if(warm)[self holdCover:self.outgoing];else[self complete];}];
    } else {
        VRPageImage *target=[self.images objectForKey:key]?:[self.images objectForKey:self.paths[path]?:@""];
        self.underlay.image=target.image;self.underlay.hidden=target==nil;self.previewKey=key;
        self.underlay.backgroundColor=target.header?:self.header.backgroundColor;self.underlay.hidden=NO;
        [self.web.superview insertSubview:self.underlay aboveSubview:self.web];
        self.underlay.transform=CGAffineTransformMakeTranslation(-width*.27,0);self.shade.alpha=.2;
        self.outgoing.image=oldImage;self.outgoing.hidden=oldImage==nil;
        // Keep WebKit visible so painting, focus and JS acknowledgements run.
        [UIView animateWithDuration:.22 delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.outgoing.transform=CGAffineTransformMakeTranslation(width,0);self.underlay.transform=CGAffineTransformIdentity;self.shade.alpha=0;
        } completion:^(BOOL finished){if(generation!=self.generation)return;self.outgoing.hidden=YES;[self holdCover:self.underlay];}];
    }
}
- (void)settled:(NSString *)key {
    // Restored scroll/draft state does not establish that WebKit painted it.
}
- (void)painted:(NSString *)key {
    if(![key isEqual:self.currentKey]||self.waitingReturn)return;
    self.routeReady=YES;[self revealPaintedPage];
}
- (BOOL)beginInteractive {
    return [self beginInteractiveKey:self.parentKey];
}
- (BOOL)beginOverlayInteractive { return [self beginInteractiveKey:self.currentKey]; }
- (BOOL)beginInteractiveKey:(NSString *)key {
    if(!key.length||self.interactive||self.waitingReturn)return NO;
    BOOL foreground=self.handoff,painted=self.routeReady;UIImage *front=self.handoffView.image;UIColor *frontColor=self.handoffView.backgroundColor;
    if(self.transitioning||self.handoff)[self complete];
    VRPageImage *target=[self.images objectForKey:key];
    [self layout];self.generation++;
    // A cold/evicted snapshot reduces preview detail, never back availability.
    self.underlay.image=target.image;self.underlay.backgroundColor=target.header?:self.header.backgroundColor;self.underlay.hidden=NO;self.previewKey=key;
    self.fromHeader=self.header.backgroundColor;self.toHeader=target.header?:self.fromHeader;
    self.interactive=YES;self.waitingReturn=NO;self.animationDone=NO;self.routeReady=painted;self.progress=0;
    self.foregroundPreview=foreground;self.outgoing.image=front;self.outgoing.backgroundColor=frontColor;self.outgoing.hidden=!foreground;
    [self shadow:YES];[self setRunning:YES];[self updateInteractive:0];return YES;
}
- (void)updateInteractive:(CGFloat)distance {
    if(!self.interactive)return;CGFloat width=self.web.bounds.size.width;if(width<=0)return;
    self.progress=MAX(0,MIN(1,distance/width));self.web.transform=CGAffineTransformMakeTranslation(width*self.progress,0);
    if(self.foregroundPreview)self.outgoing.transform=self.web.transform;
    self.underlay.transform=CGAffineTransformMakeTranslation(-width*.27*(1-self.progress),0);self.shade.alpha=.2*(1-self.progress);[self headerAtProgress:self.progress];
}
- (void)finishInteractive:(CGFloat)distance velocity:(CGFloat)velocity cancelled:(BOOL)cancelled {
    if(!self.interactive)return;CGFloat width=self.web.bounds.size.width;
    BOOL commit=!cancelled&&velocity>-150&&(distance+velocity*.16>width*.36 || (velocity>700&&distance>12));
    NSUInteger generation=self.generation;CGFloat endpoint=commit?1:0;
    NSTimeInterval duration=MAX(.12,MIN(.32,.3*fabs(endpoint-self.progress)));
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{[self updateInteractive:endpoint*width];}
      completion:^(BOOL finished){
        if(generation!=self.generation)return;
        if(!commit){[self headerAtProgress:0];self.interactive=NO;if(self.foregroundPreview){self.underlay.hidden=YES;[self holdCover:self.outgoing];}else[self complete];return;}
        self.interactive=NO;self.waitingReturn=YES;self.routeReady=NO;self.foregroundPreview=NO;self.outgoing.hidden=YES;
        // Promote the already-visible parent before restoring WebKit's frame.
        // Removing it on route announcement would expose the departing child.
        [self.web.superview insertSubview:self.underlay aboveSubview:self.web];[self holdCover:self.underlay];
        if(self.onRequestBack)self.onRequestBack();else[self abortReturn];
        NSUInteger requestOwner=self.generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(requestOwner==self.generation&&self.waitingReturn)[self abortReturn];});
      }];
}
- (void)abortReturn { if(self.fromHeader&&self.onHeaderColor)self.onHeaderColor(self.fromHeader);[self complete]; }
- (void)clear { [self complete];[self.images removeAllObjects];[self.paths removeAllObjects];self.captureGeneration++; }
@end
