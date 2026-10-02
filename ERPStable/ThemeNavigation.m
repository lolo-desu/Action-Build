#import "ThemeNavigation.h"
#import <math.h>

UIColor *VRColor(id values, UIColor *fallback) {
    if (![values isKindOfClass:NSArray.class] || [values count] != 4) return fallback;
    CGFloat components[4];
    for (NSInteger i=0;i<4;i++) {
        if (![values[i] isKindOfClass:NSNumber.class] || !isfinite([values[i] doubleValue])) return fallback;
        components[i] = MAX(0, MIN(1, [values[i] doubleValue]));
    }
    return [UIColor colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
}
CGRect VRRect(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return CGRectZero;
    CGFloat components[4]; NSArray *keys=@[@"x",@"y",@"width",@"height"];
    for (NSInteger i=0;i<4;i++) {
        id number=value[keys[i]];
        if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue]) || fabs([number doubleValue])>20000) return CGRectZero;
        components[i]=[number doubleValue];
    }
    return CGRectMake(components[0],components[1],MAX(0,components[2]),MAX(0,components[3]));
}

@interface ThemeNavigation ()
@property(nonatomic, strong, readwrite) UIView *surface;
@property(nonatomic, strong) UIView *topBorder;
@property(nonatomic, strong, readwrite) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) UIView *selection;
@property(nonatomic, strong) NSArray<UIImageView *> *icons;
@property(nonatomic, strong) NSArray<UILabel *> *titles;
@property(nonatomic, strong) NSArray<UILabel *> *badges;
@property(nonatomic, strong) NSDictionary *model;
@property(nonatomic, copy) NSString *pendingPath;
@property(nonatomic) NSInteger pressedSlot;
@property(nonatomic) NSUInteger selectionGeneration;
@end

@implementation ThemeNavigation
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.hidden=YES; self.pressedSlot=-1;
    self.surface=[UIView new]; [self addSubview:self.surface];
    self.topBorder=[UIView new]; self.topBorder.userInteractionEnabled=NO; [self.surface addSubview:self.topBorder];
    self.selection=[UIView new]; self.selection.userInteractionEnabled=NO;
    [self.surface addSubview:self.selection];
    NSMutableArray *buttons=[NSMutableArray new],*icons=[NSMutableArray new],*titles=[NSMutableArray new],*badges=[NSMutableArray new];
    for (NSInteger slot=0;slot<5;slot++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.tag=slot;
        [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(press:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(release:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(cancelPress:) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        UIImageView *icon=[UIImageView new]; icon.contentMode=UIViewContentModeScaleAspectFit;
        UILabel *title=[UILabel new]; title.textAlignment=NSTextAlignmentCenter;
        UILabel *badge=[UILabel new]; badge.textAlignment=NSTextAlignmentCenter; badge.clipsToBounds=YES;
        badge.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        icon.userInteractionEnabled=title.userInteractionEnabled=badge.userInteractionEnabled=NO;
        [button addSubview:icon]; [button addSubview:title]; [button addSubview:badge];
        button.isAccessibilityElement=YES;
        [self.surface addSubview:button]; [buttons addObject:button]; [icons addObject:icon]; [titles addObject:title]; [badges addObject:badge];
    }
    self.buttons=buttons; self.icons=icons; self.titles=titles; self.badges=badges;
    return self;
}
- (void)press:(UIButton *)button { self.pressedSlot=button.tag;[self stageSelection:button]; }
- (void)release:(UIButton *)button { self.pressedSlot=-1; }
- (void)cancelPress:(UIButton *)button { self.pressedSlot=-1;[self cancelPendingSelection]; }
- (BOOL)selected:(NSDictionary *)item { return self.pendingPath.length?[item[@"path"] isEqual:self.pendingPath]:[item[@"selected"] boolValue]; }
- (void)updateSelection {
    NSArray *items=self.model[@"items"];if(items.count!=5)return;
    UIColor *selected=VRColor(self.model[@"selectedColor"],UIColor.systemRedColor),*muted=VRColor(self.model[@"mutedColor"],UIColor.secondaryLabelColor);
    self.selection.hidden=YES;
    for(NSInteger i=0;i<5;i++) {
        NSDictionary *item=items[i];BOOL chosen=[self selected:item];UIColor *color=chosen?selected:muted;
        self.titles[i].textColor=color;self.icons[i].tintColor=color;
        self.titles[i].font=[UIFont systemFontOfSize:self.titles[i].font.pointSize weight:chosen?UIFontWeightSemibold:UIFontWeightMedium];
        self.buttons[i].accessibilityTraits=UIAccessibilityTraitButton|(chosen?UIAccessibilityTraitSelected:0);
        if(chosen){self.selection.frame=CGRectInset(self.buttons[i].frame,3,1);self.selection.layer.cornerRadius=MAX(0,MIN(20,[item[@"radius"] doubleValue]));self.selection.backgroundColor=[color colorWithAlphaComponent:.1];self.selection.hidden=NO;}
    }
}
- (void)cancelPendingSelection { self.pendingPath=nil;self.selectionGeneration++;[self updateSelection]; }
- (void)stageSelection:(UIButton *)button {
    if(button.tag<0||button.tag>=5||!self.model)return;
    NSString *path=self.model[@"items"][button.tag][@"path"];
    if([self.pendingPath isEqual:path])return;
    self.pendingPath=path;self.selectionGeneration++;
    // Crossfade the entire surface, so text, icon and background share exactly
    // the same transition. Never sample the site's intermediate CSS colors.
    if(UIAccessibilityIsReduceMotionEnabled())[UIView performWithoutAnimation:^{[self updateSelection];}];
    else [UIView transitionWithView:self.surface duration:.12 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{[self updateSelection];} completion:nil];
}
- (void)select:(UIButton *)button {
    if(button.tag<0||button.tag>=5||!self.model)return;
    [self stageSelection:button];NSUInteger generation=++self.selectionGeneration;
    if (self.onSelect) self.onSelect(button.tag);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2000*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(generation==self.selectionGeneration)[self cancelPendingSelection];});
}
- (BOOL)applyModel:(NSDictionary *)model webFrame:(CGRect)webFrame {
    NSArray *items=model[@"items"];
    CGRect nav=VRRect(model[@"frame"]);
    NSSet *paths=[NSSet setWithArray:@[@"/discover",@"/likes",@"/matches",@"/posts",@"/me"]];
    if (![items isKindOfClass:NSArray.class] || items.count!=5 || nav.size.width<100 || nav.size.height<35 || nav.size.height>200) { self.hidden=YES; return NO; }
    NSMutableSet *seen=[NSMutableSet new];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![paths containsObject:item[@"path"]] || ![item[@"title"] isKindOfClass:NSString.class] || [item[@"title"] length]>80) { self.hidden=YES; return NO; }
        NSString *icon=item[@"icon"];
        if (![icon isKindOfClass:NSString.class] || icon.length>100000 || ![UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:icon options:0]]) { self.hidden=YES; return NO; }
        [seen addObject:item[@"path"]];
    }
    if (seen.count!=5) { self.hidden=YES; return NO; }
    self.model=model;
    for(NSDictionary *item in items)if(self.pendingPath.length&&[item[@"selected"] boolValue]&&[item[@"path"] isEqual:self.pendingPath]){self.pendingPath=nil;self.selectionGeneration++;break;}
    UIColor *background=VRColor(model[@"background"],UIColor.systemBackgroundColor);
    CGFloat red=0,green=0,blue=0,alpha=1; [background getRed:&red green:&green blue:&blue alpha:&alpha];
    self.overrideUserInterfaceStyle=(.2126*red+.7152*green+.0722*blue<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
    self.surface.backgroundColor=[background colorWithAlphaComponent:1];
    self.topBorder.backgroundColor=VRColor(model[@"borderColor"],UIColor.separatorColor);
    for (NSInteger i=0;i<5;i++) {
        NSDictionary *item=items[i]; UIButton *button=self.buttons[i];
        UILabel *title=self.titles[i]; title.text=item[@"title"];
        CGFloat fontSize=MAX(9,MIN(18,[item[@"fontSize"] doubleValue]));
        title.font=[UIFont systemFontOfSize:fontSize weight:[item[@"bold"] boolValue]?UIFontWeightSemibold:UIFontWeightMedium];
        title.textColor=VRColor(model[@"mutedColor"],UIColor.secondaryLabelColor);
        NSString *encoded=item[@"icon"];
        if ([encoded isKindOfClass:NSString.class] && encoded.length<100000) {
            NSData *data=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
            UIImage *image=data?[UIImage imageWithData:data scale:3]:nil;
            self.icons[i].image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.icons[i].tintColor=title.textColor;
        }
        NSDictionary *badge=item[@"badge"];
        if ([badge isKindOfClass:NSDictionary.class] && [badge[@"title"] isKindOfClass:NSString.class] && [badge[@"title"] length]<8) {
            self.badges[i].hidden=NO; self.badges[i].text=badge[@"title"];
            self.badges[i].textColor=VRColor(badge[@"color"],UIColor.whiteColor);
            self.badges[i].backgroundColor=VRColor(badge[@"background"],title.textColor);
        } else { self.badges[i].hidden=YES; }
        button.accessibilityLabel=title.text;
        button.accessibilityValue=self.badges[i].hidden?nil:self.badges[i].text;
        button.accessibilityTraits=UIAccessibilityTraitButton|([self selected:item]?UIAccessibilityTraitSelected:0);
    }
    [self layoutForWebFrame:webFrame];
    [self updateSelection];
    self.hidden=![model[@"visible"] boolValue];
    return YES;
}
- (void)layoutForWebFrame:(CGRect)webFrame {
    if (!self.model) return;
    CGRect nav=VRRect(self.model[@"frame"]);
    self.frame=CGRectMake(webFrame.origin.x+nav.origin.x,CGRectGetMaxY(webFrame)-nav.size.height,nav.size.width,nav.size.height);
    self.surface.frame=self.bounds;
    self.topBorder.frame=CGRectMake(0,0,nav.size.width,MAX(0,MIN(6,[self.model[@"borderWidth"] doubleValue])));
    self.selection.hidden=YES;
    NSArray *items=self.model[@"items"];
    for (NSInteger i=0;i<5;i++) {
        NSDictionary *item=items[i]; CGRect frame=VRRect(item[@"frame"]); CGRect icon=VRRect(item[@"iconFrame"]);
        self.buttons[i].frame=frame; self.icons[i].frame=icon;
        CGFloat titleY=CGRectGetMaxY(icon)+2;
        CGFloat titleHeight=ceil(self.titles[i].font.lineHeight);
        CGRect label=VRRect(item[@"labelFrame"]);
        self.titles[i].frame=label.size.height>0?CGRectMake(0,label.origin.y,frame.size.width,label.size.height):CGRectMake(0,titleY,frame.size.width,titleHeight);
        if (!self.badges[i].hidden) {
            self.badges[i].frame=VRRect(item[@"badge"][@"frame"]);
            self.badges[i].layer.cornerRadius=self.badges[i].bounds.size.height/2;
        }
        if ([self selected:item]) {
            CGRect selection=CGRectInset(frame,3,1);
            self.selection.frame=selection; self.selection.layer.cornerRadius=MAX(0,MIN(20,[item[@"radius"] doubleValue]));
            self.selection.backgroundColor=[self.titles[i].textColor colorWithAlphaComponent:.1]; self.selection.hidden=NO;
        }
    }
}
#if ERP_TESTING
- (NSDictionary *)verifySelection {
    UIColor *expected=VRColor(self.model[@"selectedColor"],UIColor.systemRedColor);CGFloat r,g,b,a,br,bg,bb,ba,er,eg,eb,ea;
    [expected getRed:&er green:&eg blue:&eb alpha:&ea];
    for(NSInteger i=0;i<5;i++)if(self.buttons[i].accessibilityTraits&UIAccessibilityTraitSelected){
        [self.titles[i].textColor getRed:&r green:&g blue:&b alpha:&a];[self.selection.backgroundColor getRed:&br green:&bg blue:&bb alpha:&ba];
        return @{@"selected":@(i),@"foreground":@[@(r),@(g),@(b)],@"background":@[@(br),@(bg),@(bb)],@"expected":@[@(er),@(eg),@(eb)],@"backgroundAlpha":@(ba)};
    }return @{};
}
- (void)verifyIntermediateWebColor {
    NSMutableDictionary *model=[self.model mutableCopy];NSMutableArray *items=[NSMutableArray new];
    for(NSDictionary *entry in self.model[@"items"]){NSMutableDictionary *item=[entry mutableCopy];item[@"selected"]=@([item[@"path"] isEqual:self.pendingPath]);item[@"color"]=@[@.5,@.5,@.5,@1];[items addObject:item];}
    CGRect nav=VRRect(self.model[@"frame"]);
    CGRect webFrame=CGRectMake(self.frame.origin.x-nav.origin.x,self.frame.origin.y-nav.origin.y,nav.size.width,CGRectGetMaxY(nav));
    model[@"items"]=items;[self applyModel:model webFrame:webFrame];
}
#endif
@end
