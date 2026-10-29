#import <AppKit/AppKit.h>

@protocol CPPlaybackLifecycleProtocol <NSObject>
- (void)startWithHandler:(void (^)(NSString *, BOOL))handler;
- (void)stop;
@end

@protocol CPRegistrationClickProtocol <NSObject>
- (void)startSecondaryClickWithHandler:(BOOL (^)(double, double, double, double))handler;
- (void)stopSecondaryClick;
@end

/// A native bundle keeps AppKit-only lifecycle APIs outside the Catalyst target.
@interface CPPlaybackLifecycle : NSObject <CPPlaybackLifecycleProtocol, CPRegistrationClickProtocol>
@property(copy) void (^handler)(NSString *, BOOL);
@property NSMutableArray *tokens;
@property id secondaryMonitor;
@end

@implementation CPPlaybackLifecycle
- (void)startWithHandler:(void (^)(NSString *, BOOL))handler {
    [self stop];
    self.handler = handler;
    self.tokens = [NSMutableArray array];
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    NSDictionary *names = @{
        NSWorkspaceWillSleepNotification: @[@"sleep", @YES],
        NSWorkspaceDidWakeNotification: @[@"sleep", @NO],
        NSWorkspaceScreensDidSleepNotification: @[@"display-sleep", @YES],
        NSWorkspaceScreensDidWakeNotification: @[@"display-sleep", @NO],
        NSWorkspaceSessionDidResignActiveNotification: @[@"user-session", @YES],
        NSWorkspaceSessionDidBecomeActiveNotification: @[@"user-session", @NO]
    };
    __weak CPPlaybackLifecycle *weakSelf = self;
    for (NSNotificationName name in names) {
        NSArray *event = names[name];
        id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                 usingBlock:^(NSNotification *notification) {
            CPPlaybackLifecycle *self = weakSelf;
            if (self.handler) self.handler(event[0], [event[1] boolValue]);
        }];
        [self.tokens addObject:token];
    }
    // Hide is distinct from ordinary loss of input focus.
    for (NSNotificationName name in @[NSApplicationDidHideNotification, NSApplicationDidUnhideNotification]) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                CPPlaybackLifecycle *self = weakSelf;
                if (self.handler) self.handler(@"app-hidden", [name isEqual:NSApplicationDidHideNotification]);
            }];
        [self.tokens addObject:token];
    }
}
- (void)stop {
    for (id token in self.tokens) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:token];
        [NSNotificationCenter.defaultCenter removeObserver:token];
    }
    self.tokens = nil;
    self.handler = nil;
}
- (void)startSecondaryClickWithHandler:(BOOL (^)(double, double, double, double))handler {
    [self stopSecondaryClick];
    self.secondaryMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown
        handler:^NSEvent *(NSEvent *event) {
            NSView *content = event.window.contentView;
            if (!event.window.isKeyWindow || !content) return event;
            NSPoint point = [content convertPoint:event.locationInWindow fromView:nil];
            double y = content.isFlipped ? point.y : NSHeight(content.bounds) - point.y;
            BOOL handled = handler(point.x, y, NSWidth(content.bounds), NSHeight(content.bounds));
            return handled ? nil : event;
        }];
}
- (void)stopSecondaryClick {
    if (self.secondaryMonitor) [NSEvent removeMonitor:self.secondaryMonitor];
    self.secondaryMonitor = nil;
}
- (void)dealloc { [self stop]; [self stopSecondaryClick]; }
@end
