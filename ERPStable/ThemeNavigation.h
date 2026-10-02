#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
UIColor *VRColor(id values, UIColor *fallback);
CGRect VRRect(id value);
@interface ThemeNavigation : UIView
@property(nonatomic, strong, readonly) UIView *surface;
@property(nonatomic, strong, readonly) NSArray<UIButton *> *buttons;
@property(nonatomic, copy, nullable) void (^onSelect)(NSInteger slot);
- (BOOL)applyModel:(NSDictionary *)model webFrame:(CGRect)webFrame;
- (void)layoutForWebFrame:(CGRect)webFrame;
- (void)cancelPendingSelection;
@end
NS_ASSUME_NONNULL_END
