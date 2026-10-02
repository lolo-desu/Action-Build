#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface ChatNotifications : NSObject
@property(nonatomic, copy) NSString *activePath;
@property(nonatomic, readonly) BOOL authenticated;
- (instancetype)initWithCookieStore:(WKHTTPCookieStore *)store;
- (void)handleEvent:(NSDictionary *)event;
- (void)beginBackgroundSync;
- (void)endBackgroundSync;
#if ERP_TESTING
- (NSDictionary *)verifyNotificationContent;
#endif
@end
NS_ASSUME_NONNULL_END
