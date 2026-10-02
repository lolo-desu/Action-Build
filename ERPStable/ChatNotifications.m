#import "ChatNotifications.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <ImageIO/ImageIO.h>

static BOOL VRValidID(id value) {
    return [value isKindOfClass:NSString.class] && [value length]>0 && [value length]<=120 &&
        [value rangeOfString:@"^[A-Za-z0-9_-]+$" options:NSRegularExpressionSearch].location!=NSNotFound;
}
static NSString *VRText(id value, NSUInteger limit, NSString *fallback) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return fallback;
    NSString *text=value;
    if (text.length>limit) text=[text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,limit)]];
    return text;
}
@interface ChatNotifications ()
@property(nonatomic, strong) WKHTTPCookieStore *store;
@property(nonatomic, copy) NSString *userID;
@property(nonatomic, copy) NSDictionary *headers;
@property(nonatomic, strong) NSMutableDictionary *latest;
@property(nonatomic, strong) NSMutableOrderedSet *seen;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSDate *started;
@property(nonatomic, strong) NSTimer *backgroundTimer;
@property(nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property(nonatomic) NSInteger unread;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval detailedAt;
@property(nonatomic) BOOL requesting;
@property(nonatomic, strong) NSCache<NSString *, NSData *> *avatars;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *avatarWaiters;
@end
@implementation ChatNotifications
- (instancetype)initWithCookieStore:(WKHTTPCookieStore *)store {
    if (!(self=[super init])) return nil;
    self.store=store; self.userID=@""; self.activePath=@""; self.headers=@{};
    self.latest=[NSMutableDictionary new]; self.seen=[NSMutableOrderedSet new];
    self.avatars=[NSCache new];self.avatars.countLimit=32;self.avatars.totalCostLimit=4*1024*1024;
    self.avatarWaiters=[NSMutableDictionary new];
    self.backgroundTask=UIBackgroundTaskInvalid; self.unread=-1; self.started=NSDate.date;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=12; config.timeoutIntervalForResource=18;
    config.HTTPShouldSetCookies=NO; self.session=[NSURLSession sessionWithConfiguration:config];
    return self;
}
- (BOOL)authenticated { return self.userID.length>0; }
- (void)remember:(NSString *)messageID {
    [self.seen addObject:messageID]; if(self.seen.count>512) [self.seen removeObjectAtIndex:0];
}
- (void)updateBadge:(NSInteger)count {
    if(count<0||count>100000)return; self.unread=count;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus==UNAuthorizationStatusAuthorized||settings.authorizationStatus==UNAuthorizationStatusProvisional)
            dispatch_async(dispatch_get_main_queue(),^{if(self.unread==count)UIApplication.sharedApplication.applicationIconBadgeNumber=count;});
    }];
}
- (void)deliver:(NSDictionary *)event {
    NSString *messageID=event[@"messageId"], *matchID=event[@"matchId"];
    if(!self.authenticated||!VRValidID(messageID)||!VRValidID(matchID)||[self.seen containsObject:messageID])return;
    [self remember:messageID]; self.detailedAt=NSDate.timeIntervalSinceReferenceDate;
    if([event[@"senderId"] isEqual:self.userID])return;
    NSString *path=[@"/matches/" stringByAppendingString:matchID];
    if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[self.activePath isEqual:path])return;
    [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[@"vrcrp-unread"]];
    [self notifyMessage:event path:path identifier:[@"vrcrp-message-" stringByAppendingString:messageID] thread:matchID];
}
- (NSData *)avatarData:(NSData *)data {
    if(!data.length||data.length>2*1024*1024)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);if(!source)return nil;
    NSDictionary *options=@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@256};
    CGImageRef thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);if(!thumbnail)return nil;
    UIImage *image=[UIImage imageWithCGImage:thumbnail];CGImageRelease(thumbnail);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat new];format.scale=1;
    UIImage *small=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(144,144) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,144,144)] addClip];
        CGFloat scale=MAX(144/image.size.width,144/image.size.height);CGSize size=CGSizeMake(image.size.width*scale,image.size.height*scale);
        [image drawInRect:CGRectMake((144-size.width)/2,(144-size.height)/2,size.width,size.height)];
    }];return UIImagePNGRepresentation(small);
}
- (void)loadAvatar:(NSString *)value completion:(void (^)(NSData *))completion {
    NSURL *url=[value isKindOfClass:NSString.class]&&value.length<4096?[NSURL URLWithString:value]:nil;
    if(![url.scheme.lowercaseString isEqual:@"https"]||!url.host.length||url.user.length||url.password.length){completion(nil);return;}
    NSData *cached=[self.avatars objectForKey:value];if(cached){completion(cached);return;}
    if(self.avatarWaiters[value]){[self.avatarWaiters[value] addObject:[completion copy]];return;}
    self.avatarWaiters[value]=[NSMutableArray arrayWithObject:[completion copy]];NSUInteger generation=self.generation;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.timeoutInterval=3;request.HTTPShouldHandleCookies=NO;
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(generation!=self.generation)return;
            NSData *avatar=!error&&[(NSHTTPURLResponse *)response statusCode]==200?[self avatarData:data]:nil;
            NSArray *waiters=[self.avatarWaiters[value] copy];[self.avatarWaiters removeObjectForKey:value];
            if(avatar)[self.avatars setObject:avatar forKey:value cost:avatar.length];
            for(void (^callback)(NSData *) in waiters)callback(avatar);
        });
    }] resume];
}
- (NSData *)initialAvatar:(NSString *)title {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat new];format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(144,144) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithRed:.22 green:.24 blue:.3 alpha:1] setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,144,144)] fill];
        NSString *initial=title.length?[title substringWithRange:[title rangeOfComposedCharacterSequenceAtIndex:0]]:@"聊";
        NSDictionary *attributes=@{NSFontAttributeName:[UIFont systemFontOfSize:65 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor};
        CGSize size=[initial sizeWithAttributes:attributes];[initial drawAtPoint:CGPointMake((144-size.width)/2,(144-size.height)/2) withAttributes:attributes];
    }];return UIImagePNGRepresentation(image);
}
- (UNMutableNotificationContent *)messageContent:(NSDictionary *)event path:(NSString *)path thread:(NSString *)thread avatar:(NSData *)avatar {
    UNMutableNotificationContent *content=[UNMutableNotificationContent new];
    content.title=VRText(event[@"title"],80,@"新聊天消息");content.body=VRText(event[@"body"],180,@"你有新的聊天消息");
    NSString *displayID=VRText(event[@"displayId"],120,VRText(event[@"senderId"],120,@""));
    if(displayID.length)content.subtitle=[@"ID: " stringByAppendingString:displayID];
    content.sound=UNNotificationSound.defaultSound;if(self.unread>=0)content.badge=@(self.unread);
    content.threadIdentifier=thread;content.categoryIdentifier=@"VRCRP_CHAT";content.userInfo=@{@"path":path};
    NSData *picture=avatar?:[self initialAvatar:content.title];
    NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vrcrp-notification-%@.png",NSUUID.UUID.UUIDString]]];
    if([picture writeToURL:file atomically:YES]){
        UNNotificationAttachment *attachment=[UNNotificationAttachment attachmentWithIdentifier:@"sender-avatar" URL:file options:@{UNNotificationAttachmentOptionsThumbnailHiddenKey:@NO} error:nil];
        if(attachment)content.attachments=@[attachment];
        if(!attachment)[NSFileManager.defaultManager removeItemAtURL:file error:nil];
    }return content;
}
- (void)notifyMessage:(NSDictionary *)event path:(NSString *)path identifier:(NSString *)identifier thread:(NSString *)thread {
    NSUInteger generation=self.generation;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus!=UNAuthorizationStatusAuthorized&&settings.authorizationStatus!=UNAuthorizationStatusProvisional)return;
        dispatch_async(dispatch_get_main_queue(),^{
            __block BOOL finished=NO;
            void (^deliver)(NSData *)=^(NSData *avatar){
                if(finished||generation!=self.generation||!self.authenticated)return;finished=YES;
                if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[self.activePath isEqual:path])return;
                UNMutableNotificationContent *content=[self messageContent:event path:path thread:thread avatar:avatar];
                [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil] withCompletionHandler:nil];
            };
            [self loadAvatar:event[@"avatarURL"] completion:deliver];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,750*NSEC_PER_MSEC),dispatch_get_main_queue(),^{deliver(nil);});
        });
    }];
}
- (void)notifyTitle:(NSString *)title body:(NSString *)body path:(NSString *)path identifier:(NSString *)identifier thread:(NSString *)thread {
    NSUInteger generation=self.generation;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus!=UNAuthorizationStatusAuthorized&&settings.authorizationStatus!=UNAuthorizationStatusProvisional)return;
        dispatch_async(dispatch_get_main_queue(),^{
        if(generation!=self.generation||!self.authenticated)return;
        if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[self.activePath isEqual:path])return;
        UNMutableNotificationContent *content=[UNMutableNotificationContent new];
        content.title=title; content.body=body; content.sound=UNNotificationSound.defaultSound;
        if(self.unread>=0)content.badge=@(self.unread);
        content.threadIdentifier=thread; content.categoryIdentifier=@"VRCRP_CHAT"; content.userInfo=@{@"path":path};
        [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil] withCompletionHandler:nil];
        });
    }];
}
- (void)handleEvent:(NSDictionary *)event {
    NSString *kind=event[@"kind"];
    if([kind isEqual:@"session"]) {
        NSString *user=VRValidID(event[@"userId"])?event[@"userId"]:@"";
        if(![self.userID isEqual:user]) {
            [self endBackgroundSync]; self.generation++; self.userID=user; self.started=NSDate.date;
            [self.latest removeAllObjects]; [self.seen removeAllObjects]; self.unread=-1;
            [self.avatars removeAllObjects];[self.avatarWaiters removeAllObjects];
            if(!user.length) { [self updateBadge:0]; [UNUserNotificationCenter.currentNotificationCenter removeAllDeliveredNotifications]; }
        }
        NSMutableDictionary *headers=[NSMutableDictionary dictionaryWithObject:@"application/json" forKey:@"Accept"];
        if([@[@"sfw",@"mixed",@"r18"] containsObject:event[@"mode"]])headers[@"X-Content-Mode"]=event[@"mode"];
        for(NSString *key in @[@"language",@"userAgent"]) {
            NSString *value=event[key];
            if([value isKindOfClass:NSString.class]&&value.length<600&&[value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound)
                headers[[key isEqual:@"language"]?@"Accept-Language":@"User-Agent"]=value;
        }
        self.headers=headers;
    } else if([kind isEqual:@"counters"]&&[event[@"unread"] isKindOfClass:NSNumber.class]) [self updateBadge:[event[@"unread"] integerValue]];
    else if([kind isEqual:@"chatMessage"]) [self deliver:event];
    else if([kind isEqual:@"genericMessage"]&&self.authenticated&&NSDate.timeIntervalSinceReferenceDate-self.detailedAt>3) {
        [self notifyTitle:@"vrcrp" body:@"你有新的聊天消息" path:@"/matches" identifier:@"vrcrp-unread" thread:@"vrcrp-unread"];
    } else if([kind isEqual:@"snapshot"]&&[event[@"items"] isKindOfClass:NSArray.class]) {
        if([event[@"items"] count]>200)return;
        for(id item in event[@"items"]) if([item isKindOfClass:NSDictionary.class]&&VRValidID(item[@"matchId"])&&VRValidID(item[@"messageId"])) {
            self.latest[item[@"matchId"]]=item[@"messageId"]; [self remember:item[@"messageId"]];
        }
        NSUInteger generation=self.generation;
        [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
            if(settings.authorizationStatus!=UNAuthorizationStatusAuthorized&&settings.authorizationStatus!=UNAuthorizationStatusProvisional)return;
            dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.generation||!self.authenticated)return;
                NSArray *items=event[@"items"];for(NSDictionary *item in [items subarrayWithRange:NSMakeRange(0,MIN(8,items.count))])if([item isKindOfClass:NSDictionary.class])[self loadAvatar:item[@"avatarURL"] completion:^(NSData *data){}];
            });
        }];
    }
}
- (void)beginBackgroundSync {
    if(!self.authenticated||self.backgroundTask!=UIBackgroundTaskInvalid)return;
    __weak ChatNotifications *weakSelf=self;
    self.backgroundTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Finish chat synchronization" expirationHandler:^{[weakSelf endBackgroundSync];}];
    if(self.backgroundTask==UIBackgroundTaskInvalid)return;
    [self backgroundPoll];
    self.backgroundTimer=[NSTimer scheduledTimerWithTimeInterval:10 repeats:NO block:^(NSTimer *timer){[weakSelf backgroundPoll];}];
    UIBackgroundTaskIdentifier task=self.backgroundTask;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(weakSelf.backgroundTask==task)[weakSelf endBackgroundSync];});
}
- (void)endBackgroundSync {
    [self.backgroundTimer invalidate]; self.backgroundTimer=nil;
    if(self.backgroundTask!=UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task=self.backgroundTask; self.backgroundTask=UIBackgroundTaskInvalid;
        [UIApplication.sharedApplication endBackgroundTask:task];
    }
}
- (void)backgroundPoll {
    if(self.backgroundTask==UIBackgroundTaskInvalid||!self.authenticated||self.requesting)return;
    self.requesting=YES; NSUInteger generation=self.generation;
    [self.store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
        if(generation!=self.generation||self.backgroundTask==UIBackgroundTaskInvalid){self.requesting=NO;return;}
        NSMutableArray *owned=[NSMutableArray new];
        for(NSHTTPCookie *cookie in cookies)if([cookie.domain isEqual:@"erp.sex"]||[cookie.domain isEqual:@".erp.sex"]) [owned addObject:cookie];
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://erp.sex/api/v1/matches?state=active"]];
        request.allHTTPHeaderFields=self.headers;
        for(NSString *key in [NSHTTPCookie requestHeaderFieldsWithCookies:owned]) [request setValue:[NSHTTPCookie requestHeaderFieldsWithCookies:owned][key] forHTTPHeaderField:key];
        NSMutableURLRequest *counterRequest=[request mutableCopy]; counterRequest.URL=[NSURL URLWithString:@"https://erp.sex/api/v1/me/counters"];
        [[self.session dataTaskWithRequest:counterRequest completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            dispatch_async(dispatch_get_main_queue(),^{
                if(generation!=self.generation||self.backgroundTask==UIBackgroundTaskInvalid||error||[(NSHTTPURLResponse *)response statusCode]!=200||![value isKindOfClass:NSDictionary.class])return;
                id payload=[value[@"data"] isKindOfClass:NSDictionary.class]?value[@"data"]:value;
                if([payload[@"unreadMessages"] isKindOfClass:NSNumber.class])[self updateBadge:[payload[@"unreadMessages"] integerValue]];
            });
        }] resume];
        [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            dispatch_async(dispatch_get_main_queue(),^{
                self.requesting=NO;
                if(generation!=self.generation||self.backgroundTask==UIBackgroundTaskInvalid)return;
                if([(NSHTTPURLResponse *)response statusCode]==401){[self endBackgroundSync];return;}
                if(error||[(NSHTTPURLResponse *)response statusCode]!=200||![value isKindOfClass:NSDictionary.class])return;
                id payload=[value[@"data"] isKindOfClass:NSDictionary.class]?value[@"data"]:value;
                if(![payload[@"items"] isKindOfClass:NSArray.class])return;
                NSInteger unread=0;
                for(id item in payload[@"items"])if([item isKindOfClass:NSDictionary.class]){
                    NSInteger count=[item[@"unreadCount"] isKindOfClass:NSNumber.class]?MAX(0,[item[@"unreadCount"] integerValue]):0;
                    unread+=count;
                    id last=item[@"lastMessage"]; NSString *matchID=item[@"id"];
                    if(![last isKindOfClass:NSDictionary.class]||!VRValidID(matchID)||!VRValidID(last[@"id"]))continue;
                    NSString *previous=self.latest[matchID]; self.latest[matchID]=last[@"id"];
                    NSISO8601DateFormatter *formatter=[NSISO8601DateFormatter new]; formatter.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds;
                    NSString *timestamp=VRText(last[@"createdAt"],80,@"");
                    NSDate *created=[formatter dateFromString:timestamp];
                    if(!created){formatter.formatOptions=NSISO8601DateFormatWithInternetDateTime;created=[formatter dateFromString:timestamp];}
                    BOOL newMessage=previous?![previous isEqual:last[@"id"]]:(created&&[created compare:self.started]!=NSOrderedAscending);
                    if(newMessage&&count>0&&![last[@"recalled"] isEqual:@YES]){
                        NSString *body=VRText(last[@"text"],180,@"你有新的聊天消息");
                        if([last[@"type"] isEqual:@"image"])body=@"[图片]";
                        if([last[@"type"] isEqual:@"voice"])body=@"[语音]";
                        if([last[@"type"] isEqual:@"vrc_link"])body=@"[VRChat 链接]";
                        NSDictionary *peer=[item[@"user"] isKindOfClass:NSDictionary.class]?item[@"user"]:@{};
                        NSDictionary *media=[peer[@"avatar"] isKindOfClass:NSDictionary.class]?peer[@"avatar"]:@{};
                        NSString *avatar=[media[@"view"] isEqual:@"show"]?VRText(media[@"thumbUrl"],4096,VRText(media[@"url"],4096,@"")):@"";
                        [self deliver:@{@"messageId":last[@"id"],@"matchId":matchID,@"senderId":last[@"senderId"]?:@"",@"displayId":VRText(peer[@"id"],120,VRText(last[@"senderId"],120,@"")),@"avatarURL":avatar,@"title":VRText(peer[@"displayName"],80,@"新聊天消息"),@"body":body}];
                    } else [self remember:last[@"id"]];
                }
                // This response may be paginated: do not replace the account's
                // total badge with the first page's partial count.
                (void)unread;
            });
        }] resume];
    }];
}
#if ERP_TESTING
- (NSDictionary *)verifyNotificationContent {
    NSDictionary *event=@{@"title":@"测试联系人",@"displayId":@"peer-test-id",@"senderId":@"peer-test-id",@"body":@"测试消息内容"};
    NSData *avatar=[self initialAvatar:@"測"];
    UNMutableNotificationContent *content=[self messageContent:event path:@"/matches/thread" thread:@"thread" avatar:avatar];
    UNNotificationAttachment *attachment=content.attachments.firstObject;
    UIImage *image=attachment?[UIImage imageWithContentsOfFile:attachment.URL.path]:nil;
    return @{@"title":content.title,@"subtitle":content.subtitle,@"body":content.body,@"attachmentCount":@(content.attachments.count),@"avatarWidth":@(image.size.width),@"avatarHeight":@(image.size.height),@"thread":content.threadIdentifier,@"path":content.userInfo[@"path"],@"sound":@(content.sound!=nil)};
}
#endif
@end
