#import <AppKit/AppKit.h>

@protocol CPPlaybackLifecycleProtocol <NSObject>
- (void)startWithHandler:(void (^)(NSString *, BOOL))handler;
- (void)stop;
@end

@protocol CPRegistrationClickProtocol <NSObject>
- (void)startSecondaryClickWithHandler:(BOOL (^)(double, double, double, double))handler;
- (void)stopSecondaryClick;
@end

@protocol CPPlaybackPointerProtocol <NSObject>
- (void)startPointerWithHandler:(BOOL (^)(NSInteger, double, double, double, double, NSInteger, BOOL, double))handler;
- (void)stopPointer;
- (BOOL)keyWindowIsFullScreen;
- (void)setPlaybackToolbarIdentifier:(NSString *)identifier;
- (void)preparePlaybackToolbarWithActivation:(void (^)(NSString *))activate;
- (BOOL)focusPlaybackToolbarBackwards:(BOOL)backwards video:(void (^)(void))video browse:(void (^)(void))browse activate:(void (^)(NSString *))activate;
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
        id<CPRegistrationClickProtocol> input = [[type alloc] init];
        NSCAssert([input conformsToProtocol:@protocol(CPRegistrationClickProtocol)], @"Secondary click boundary conforms");
        [input startSecondaryClickWithHandler:^BOOL(double x, double y, double width, double height) { return NO; }];
        [input startSecondaryClickWithHandler:^BOOL(double x, double y, double width, double height) { return NO; }];
        [input stopSecondaryClick];
        [input stopSecondaryClick];
        id<CPPlaybackPointerProtocol> pointer = [[type alloc] init];
        NSCAssert([pointer conformsToProtocol:@protocol(CPPlaybackPointerProtocol)], @"Pointer boundary conforms");
        for (NSUInteger i = 0; i < 2; i++) {
            [pointer startPointerWithHandler:^BOOL(NSInteger phase, double x, double y, double width, double height,
                                                   NSInteger clicks, BOOL active, double time) { return NO; }];
        }
        [pointer stopPointer]; [pointer stopPointer];
        NSCAssert(![pointer keyWindowIsFullScreen], @"No fullscreen window in this test process");
        [pointer setPlaybackToolbarIdentifier:@"absent-test-window"];
        [pointer preparePlaybackToolbarWithActivation:^(NSString *item) { NSCAssert(NO, @"No toolbar to activate"); }];
        NSCAssert(![pointer focusPlaybackToolbarBackwards:NO video:^{} browse:^{} activate:^(NSString *item) {}],
                  @"Missing scoped window never falls back to another toolbar");
        puts("PASS: scoped toolbar rejects an absent window");
        puts("PASS: pointer typed boundary, monitor replacement and cleanup (event dispatch requires UI acceptance)");
        puts("PASS: secondary-click typed boundary, monitor replacement and cleanup");
        puts("PASS: native bundle loading, typed boundary, sleep/display/session/hide notifications, observer cleanup (synthetic events)");
    }
    return 0;
}
