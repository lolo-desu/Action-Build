#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface ChatNotifications : NSObject
@property(nonatomic, copy) NSString *activePath;
@property(nonatomic, readonly) BOOL authenticated;
- (instancetype)initWithCookieStore:(WKHTTPCookieStore *)store;
- (void)handleEvent:(NSDictionary *)event;
- (void)beginBackgroundSync;
- (void)endBackgroundSync;
@end
NS_ASSUME_NONNULL_END
