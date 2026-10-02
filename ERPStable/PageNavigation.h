#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PageNavigation : NSObject
@property(nonatomic, readonly) BOOL transitioning;
@property(nonatomic, readonly) BOOL interactive;
@property(nonatomic, readonly) BOOL canPreviewParent;
@property(nonatomic, readonly) BOOL canPreviewOverlay;
@property(nonatomic, copy, readonly) NSString *currentKey;
@property(nonatomic, copy, readonly, nullable) NSString *previewKey;
@property(nonatomic, readonly) CGFloat progress;
@property(nonatomic, copy, nullable) void (^onTransitionChange)(BOOL transitioning);
@property(nonatomic, copy, nullable) void (^onRequestBack)(void);
@property(nonatomic, copy, nullable) void (^onHeaderColor)(UIColor *color);
- (instancetype)initWithWebView:(WKWebView *)web navigation:(UIView *)navigation header:(UIView *)header;
- (void)moveToKey:(NSString *)key parent:(nullable NSString *)parent path:(NSString *)path direction:(NSString *)direction;
- (void)settled:(NSString *)key;
- (void)capture;
- (void)cancelCapture;
- (void)layout;
- (BOOL)beginInteractive;
- (BOOL)beginOverlayInteractive;
- (void)updateInteractive:(CGFloat)distance;
- (void)finishInteractive:(CGFloat)distance velocity:(CGFloat)velocity cancelled:(BOOL)cancelled;
- (void)abortReturn;
- (void)clear;
@end
NS_ASSUME_NONNULL_END
