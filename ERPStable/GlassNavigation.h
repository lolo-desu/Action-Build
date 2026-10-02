#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
UIColor *VRColor(id values, UIColor *fallback);
CGRect VRRect(id value);
@interface GlassNavigation : UIView
@property(nonatomic, strong, readonly) UIVisualEffectView *material;
@property(nonatomic, strong, readonly) NSArray<UIButton *> *buttons;
@property(nonatomic, copy, nullable) void (^onSelect)(NSInteger slot);
- (BOOL)applyModel:(NSDictionary *)model webFrame:(CGRect)webFrame;
- (void)layoutForWebFrame:(CGRect)webFrame;
@end
NS_ASSUME_NONNULL_END
