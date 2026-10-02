#import "GlassNavigation.h"
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

@interface GlassNavigation ()
@property(nonatomic, strong, readwrite) UIVisualEffectView *material;
@property(nonatomic, strong, readwrite) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) UIView *selection;
@property(nonatomic, strong) NSArray<UIImageView *> *icons;
@property(nonatomic, strong) NSArray<UILabel *> *titles;
@property(nonatomic, strong) NSArray<UILabel *> *badges;
@property(nonatomic, strong) NSDictionary *model;
@end

@implementation GlassNavigation
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.hidden=YES;
    UIVisualEffect *effect;
    if (@available(iOS 26.0,*)) {
        UIGlassEffect *glass=[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive=YES; effect=glass;
    } else { effect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]; }
    self.material=[[UIVisualEffectView alloc] initWithEffect:effect];
    self.material.clipsToBounds=YES;
    [self addSubview:self.material];
    self.selection=[UIView new]; self.selection.userInteractionEnabled=NO;
    [self.material.contentView addSubview:self.selection];
    NSMutableArray *buttons=[NSMutableArray new],*icons=[NSMutableArray new],*titles=[NSMutableArray new],*badges=[NSMutableArray new];
    for (NSInteger slot=0;slot<5;slot++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.tag=slot;
        [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(press:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(release:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        UIImageView *icon=[UIImageView new]; icon.contentMode=UIViewContentModeScaleAspectFit;
        UILabel *title=[UILabel new]; title.textAlignment=NSTextAlignmentCenter;
        UILabel *badge=[UILabel new]; badge.textAlignment=NSTextAlignmentCenter; badge.clipsToBounds=YES;
        badge.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        icon.userInteractionEnabled=title.userInteractionEnabled=badge.userInteractionEnabled=NO;
        [button addSubview:icon]; [button addSubview:title]; [button addSubview:badge];
        button.isAccessibilityElement=YES;
        [self.material.contentView addSubview:button]; [buttons addObject:button]; [icons addObject:icon]; [titles addObject:title]; [badges addObject:badge];
    }
    self.buttons=buttons; self.icons=icons; self.titles=titles; self.badges=badges;
    return self;
}
- (void)press:(UIButton *)button {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:.1 animations:^{ button.transform=CGAffineTransformMakeScale(.96,.96); }];
}
- (void)release:(UIButton *)button {
    [UIView animateWithDuration:.16 animations:^{ button.transform=CGAffineTransformIdentity; }];
}
- (void)select:(UIButton *)button { if (self.onSelect) self.onSelect(button.tag); }
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
    UIColor *background=VRColor(model[@"background"],UIColor.systemBackgroundColor);
    CGFloat red=0,green=0,blue=0,alpha=1; [background getRed:&red green:&green blue:&blue alpha:&alpha];
    self.overrideUserInterfaceStyle=(.2126*red+.7152*green+.0722*blue<.5)?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
    if (@available(iOS 26.0,*)) {
        UIGlassEffect *glass=[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive=YES; glass.tintColor=[background colorWithAlphaComponent:.12];
        self.material.effect=glass;
    }
    self.material.contentView.backgroundColor=UIAccessibilityIsReduceTransparencyEnabled()?background:UIColor.clearColor;
    for (NSInteger i=0;i<5;i++) {
        NSDictionary *item=items[i]; UIButton *button=self.buttons[i];
        UILabel *title=self.titles[i]; title.text=item[@"title"];
        CGFloat fontSize=MAX(9,MIN(18,[item[@"fontSize"] doubleValue]));
        title.font=[UIFont systemFontOfSize:fontSize weight:[item[@"bold"] boolValue]?UIFontWeightSemibold:UIFontWeightMedium];
        title.textColor=VRColor(item[@"color"],UIColor.labelColor);
        NSString *encoded=item[@"icon"];
        if ([encoded isKindOfClass:NSString.class] && encoded.length<100000) {
            NSData *data=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
            UIImage *image=data?[UIImage imageWithData:data scale:3]:nil;
            self.icons[i].image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        NSDictionary *badge=item[@"badge"];
        if ([badge isKindOfClass:NSDictionary.class] && [badge[@"title"] isKindOfClass:NSString.class] && [badge[@"title"] length]<8) {
            self.badges[i].hidden=NO; self.badges[i].text=badge[@"title"];
            self.badges[i].textColor=VRColor(badge[@"color"],UIColor.whiteColor);
            self.badges[i].backgroundColor=VRColor(badge[@"background"],title.textColor);
        } else { self.badges[i].hidden=YES; }
        button.accessibilityLabel=title.text;
        button.accessibilityValue=self.badges[i].hidden?nil:self.badges[i].text;
        button.accessibilityTraits=UIAccessibilityTraitButton|([item[@"selected"] boolValue]?UIAccessibilityTraitSelected:0);
    }
    [self layoutForWebFrame:webFrame];
    self.hidden=![model[@"visible"] boolValue];
    return YES;
}
- (void)layoutForWebFrame:(CGRect)webFrame {
    if (!self.model) return;
    CGRect nav=VRRect(self.model[@"frame"]);
    self.frame=CGRectMake(webFrame.origin.x+nav.origin.x,CGRectGetMaxY(webFrame)-nav.size.height,nav.size.width,nav.size.height);
    CGFloat bottom=MAX(0,MIN(60,[self.model[@"bottomPadding"] doubleValue]));
    CGFloat height=MAX(50,nav.size.height-bottom);
    self.material.frame=CGRectMake(8,0,nav.size.width-16,height);
    self.material.layer.cornerRadius=height/2;
    self.selection.hidden=YES;
    NSArray *items=self.model[@"items"];
    for (NSInteger i=0;i<5;i++) {
        NSDictionary *item=items[i]; CGRect frame=VRRect(item[@"frame"]); CGRect icon=VRRect(item[@"iconFrame"]);
        CGRect buttonFrame=frame; buttonFrame.origin.x-=self.material.frame.origin.x; buttonFrame.origin.y-=self.material.frame.origin.y;
        self.buttons[i].frame=buttonFrame; self.icons[i].frame=icon;
        CGFloat titleY=CGRectGetMaxY(icon)+2;
        CGFloat titleHeight=ceil(self.titles[i].font.lineHeight);
        CGRect label=VRRect(item[@"labelFrame"]);
        self.titles[i].frame=label.size.height>0?CGRectMake(0,label.origin.y,frame.size.width,label.size.height):CGRectMake(0,titleY,frame.size.width,titleHeight);
        if (!self.badges[i].hidden) {
            self.badges[i].frame=VRRect(item[@"badge"][@"frame"]);
            self.badges[i].layer.cornerRadius=self.badges[i].bounds.size.height/2;
        }
        if ([item[@"selected"] boolValue]) {
            CGRect selection=CGRectInset(frame,3,1);
            selection.origin.x-=self.material.frame.origin.x; selection.origin.y-=self.material.frame.origin.y;
            self.selection.frame=selection; self.selection.layer.cornerRadius=selection.size.height/2;
            self.selection.backgroundColor=[self.titles[i].textColor colorWithAlphaComponent:.1]; self.selection.hidden=NO;
        }
    }
}
@end
