#import <AppKit/AppKit.h>

@protocol CPPlaybackLifecycleProtocol <NSObject>
- (void)startWithHandler:(void (^)(NSString *, BOOL))handler;
- (void)stop;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"Pass the built native bundle path");
        NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
        Class type = bundle.principalClass;
        NSCAssert(type != Nil, @"Bundle loads");
        id<CPPlaybackLifecycleProtocol> bridge = [[type alloc] init];
        NSCAssert([bridge conformsToProtocol:@protocol(CPPlaybackLifecycleProtocol)], @"Typed boundary conforms");
        NSMutableArray *events = [NSMutableArray array];
        [bridge startWithHandler:^(NSString *reason, BOOL blocked) {
            [events addObject:@[reason, @(blocked)]];
        }];
        NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
        [workspace postNotificationName:NSWorkspaceWillSleepNotification object:nil];
        [workspace postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
        [workspace postNotificationName:NSWorkspaceDidWakeNotification object:nil];
        [workspace postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
        [workspace postNotificationName:NSWorkspaceSessionDidResignActiveNotification object:nil];
        [workspace postNotificationName:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidHideNotification object:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidUnhideNotification object:nil];
        NSCAssert(events.count == 8, @"Sleep/display/session/hide each deliver both edges");
        NSCAssert(([events[0] isEqual:@[@"sleep", @YES]] && [events[2] isEqual:@[@"sleep", @NO]]), @"Sleep mapping");
        [bridge stop];
        [workspace postNotificationName:NSWorkspaceWillSleepNotification object:nil];
        NSCAssert(events.count == 8, @"Stop removes observers");
        puts("PASS: native bundle loading, typed boundary, sleep/display/session/hide notifications, observer cleanup (synthetic events)");
    }
    return 0;
}
