#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface ExternalBrowser : UIViewController
@property(nonatomic,copy,nullable) void (^onInternalRequest)(NSURLRequest *request);
- (instancetype)initWithRequest:(NSURLRequest *)request surface:(UIColor *)surface;
#if ERP_TESTING
- (NSDictionary *)verifyState;
- (void)verifyOpenNext;
- (void)back:(id)sender;
- (void)forward:(id)sender;
- (void)close:(id)sender;
#endif
@end
NS_ASSUME_NONNULL_END
