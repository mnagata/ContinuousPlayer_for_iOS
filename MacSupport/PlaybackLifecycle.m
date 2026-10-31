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
- (void)togglePlaybackFullScreen;
- (void)startPlaybackChromeWithHandler:(void (^)(NSInteger, BOOL))handler;
- (void)stopPlaybackChrome;
- (void)setPlaybackToolbarControlsVisible:(BOOL)visible;
- (void)setPlaybackCursorHidden:(BOOL)hidden;
- (void)setPlaybackToolbarExitHandler:(void (^)(BOOL))handler;
- (BOOL)focusPlaybackToolbarBackwards:(BOOL)backwards video:(void (^)(void))video browse:(void (^)(void))browse activate:(void (^)(NSString *))activate;
- (void)refreshPlaybackToolbar;
- (void)setPlaybackToolbarIdentifier:(NSString *)identifier;
- (void)preparePlaybackToolbarWithActivation:(void (^)(NSString *))activate;
@end

/// Explicit keyboard focus keeps toolbar controls reachable without changing
/// macOS's system-wide keyboard-navigation preference.
@interface CPKeyboardToolbarButton : NSButton
@property BOOL requestsKeyboardFocus;
@property BOOL keyboardFocused;
@property(copy) void (^activate)(NSButton *);
@property(copy) void (^move)(NSInteger, BOOL);
@property(copy) void (^browse)(void);
@property(copy) void (^focusChanged)(void);
@end
@implementation CPKeyboardToolbarButton
- (BOOL)acceptsFirstResponder { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(34, 28); }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return NO; }
- (BOOL)becomeFirstResponder { BOOL accepted = [super becomeFirstResponder]; self.keyboardFocused = accepted; if (self.focusChanged) self.focusChanged(); return accepted; }
- (BOOL)resignFirstResponder { self.keyboardFocused = NO; if (self.focusChanged) self.focusChanged(); return [super resignFirstResponder]; }
- (void)insertTab:(id)sender { if (!NSApp.currentEvent.isARepeat && self.move) self.move(1, YES); }
- (void)insertBacktab:(id)sender { if (!NSApp.currentEvent.isARepeat && self.move) self.move(-1, YES); }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.keyboardFocused && event.keyCode == 48 &&
        !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) {
        if (!event.isARepeat && self.move) self.move((event.modifierFlags & NSEventModifierFlagShift) ? -1 : 1, YES);
        return YES;
    }
    return [super performKeyEquivalent:event];
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.requestsKeyboardFocus && self.window) {
        self.requestsKeyboardFocus = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [self.window makeFirstResponder:self]; });
    }
}
- (void)keyDown:(NSEvent *)event {
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [super keyDown:event]; return;
    }
    switch (event.keyCode) {
        case 36: case 76: case 49: if (!event.isARepeat && self.enabled && self.activate) self.activate(self); return;
        case 48: if (!event.isARepeat && self.move) self.move((event.modifierFlags & NSEventModifierFlagShift) ? -1 : 1, YES); return;
        case 123: case 126: if (!event.isARepeat && self.move) self.move(-1, NO); return;
        case 124: case 125: if (!event.isARepeat && self.move) self.move(1, NO); return;
        case 53:
            if (NSApp.keyWindow.styleMask & NSWindowStyleMaskFullScreen) { [super keyDown:event]; return; }
            if (!event.isARepeat && self.browse) self.browse(); return;
        default: [super keyDown:event];
    }
}
- (void)performActivation:(id)sender { if (self.enabled && self.activate) self.activate(self); }
@end

/// A native bundle keeps AppKit-only lifecycle APIs outside the Catalyst target.
@interface CPPlaybackLifecycle : NSObject <CPPlaybackLifecycleProtocol, CPRegistrationClickProtocol, CPPlaybackPointerProtocol>
@property(copy) void (^handler)(NSString *, BOOL);
@property NSMutableArray *tokens;
@property id secondaryMonitor;
@property id pointerMonitor;
@property id chromeMonitor;
@property NSMutableArray *chromeTokens;
@property(copy) void (^chromeHandler)(NSInteger, BOOL);
@property(copy) void (^toolbarExit)(BOOL);
@property BOOL changedMouseMoved;
@property BOOL requestedCursorHidden;
@property BOOL loggedChromeMotion;
@property(weak) NSWindow *chromeWindow;
@property(copy, nonatomic) NSString *playbackToolbarIdentifier;
@property(copy) void (^returnToVideo)(void);
@property(copy) void (^browseFromToolbar)(void);
@property(copy) void (^activateToolbar)(NSString *);
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
- (void)startPointerWithHandler:(BOOL (^)(NSInteger, double, double, double, double, NSInteger, BOOL, double))handler {
    [self stopPointer];
    self.pointerMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged
        handler:^NSEvent *(NSEvent *event) {
            NSView *content = event.window.contentView;
            if (!content) return event;
            NSPoint point = [content convertPoint:event.locationInWindow fromView:nil];
            double y = content.isFlipped ? point.y : NSHeight(content.bounds) - point.y;
            NSInteger phase = event.type == NSEventTypeLeftMouseDown ? 0 : (event.type == NSEventTypeLeftMouseDragged ? 1 : 2);
            BOOL consumed = handler(phase, point.x, y, NSWidth(content.bounds), NSHeight(content.bounds),
                                    event.clickCount, event.window.isKeyWindow, event.timestamp);
            return consumed ? nil : event;
        }];
}
- (void)setPlaybackToolbarIdentifier:(NSString *)identifier { _playbackToolbarIdentifier = [identifier copy]; }
- (NSWindow *)playbackWindow {
    if (!self.playbackToolbarIdentifier) return NSApp.keyWindow;
    for (NSWindow *window in NSApp.windows) {
        if ([window.toolbar.identifier isEqual:self.playbackToolbarIdentifier]) return window;
    }
    return nil;
}
- (NSArray<NSToolbarItem *> *)playbackItems {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSToolbarItem *item, NSDictionary *bindings) {
        return [item.itemIdentifier containsString:@"playback."];
    }];
    return [self.playbackWindow.toolbar.items filteredArrayUsingPredicate:predicate] ?: @[];
}
- (void)refreshPlaybackToolbar {
    for (NSToolbarItem *item in [self playbackItems]) {
        if (![item.view isKindOfClass:CPKeyboardToolbarButton.class]) continue;
        CPKeyboardToolbarButton *button = (id)item.view;
        button.image = item.image; button.toolTip = item.toolTip;
        button.accessibilityLabel = item.label; button.enabled = item.enabled;
        // Catalyst can keep a toolbar view while replacing its Swift owner.
        // Refresh the action along with the current item's enabled state.
        // Never capture the item or resolve the clicked window via an old owner.
        NSString *identifier = [item.itemIdentifier copy];
        CPPlaybackLifecycle *owner = self;
        button.activate = ^(NSButton *sender) {
            NSWindow *window = sender.window;
            if (!sender.enabled || !window.isKeyWindow ||
                ![window.toolbar.identifier isEqual:owner.playbackToolbarIdentifier]) return;
            if ([identifier isEqual:@"playback.fullScreen"]) [window toggleFullScreen:nil];
            else if (owner.activateToolbar) owner.activateToolbar(identifier);
        };
        button.target = button; button.action = @selector(performActivation:);
        if (self.chromeHandler) {
            __weak CPPlaybackLifecycle *weakSelf = self;
            button.focusChanged = ^{ dispatch_async(dispatch_get_main_queue(), ^{
                CPPlaybackLifecycle *owner = weakSelf;
                BOOL focused = [owner.playbackWindow.firstResponder isKindOfClass:CPKeyboardToolbarButton.class];
                if (owner.chromeHandler) owner.chromeHandler(2, focused);
            }); };
        }
    }
}
- (void)moveToolbarFrom:(NSButton *)button offset:(NSInteger)offset tab:(BOOL)tab {
    if (!self.playbackWindow.isKeyWindow) return;
    NSArray *items = [[self playbackItems] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSToolbarItem *item, NSDictionary *bindings) { return item.enabled; }]];
    NSUInteger index = [items indexOfObjectPassingTest:^BOOL(NSToolbarItem *item, NSUInteger idx, BOOL *stop) { return item.view == button; }];
    if (index == NSNotFound) return;
    NSInteger next = (NSInteger)index + offset;
    if (next < 0 || next >= (NSInteger)items.count) {
        if (tab) {
            [self.playbackWindow makeFirstResponder:nil];
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-session-state"]) NSLog(@"CPStage5 toolbar exit: callback=%d", self.toolbarExit != nil);
            if (self.toolbarExit) self.toolbarExit(offset < 0);
            else if (self.returnToVideo) self.returnToVideo();
        }
        return;
    }
    [self.playbackWindow makeFirstResponder:((NSToolbarItem *)items[next]).view];
}
- (void)preparePlaybackToolbarWithActivation:(void (^)(NSString *))activate {
    self.activateToolbar = activate;
    [self installToolbarButtonsReplacingCallbacks:NO];
}
- (void)installToolbarButtonsReplacingCallbacks:(BOOL)replace {
    // Toolbar items retain their input owner until the toolbar is removed.
    // The owner does not retain the items or the Swift scene.
    CPPlaybackLifecycle *owner = self;
    for (NSToolbarItem *item in [self playbackItems]) {
        if (!replace && [item.view isKindOfClass:CPKeyboardToolbarButton.class]) continue;
        CPKeyboardToolbarButton *button = [item.view isKindOfClass:CPKeyboardToolbarButton.class] ? (id)item.view : [[CPKeyboardToolbarButton alloc] initWithFrame:NSMakeRect(0, 0, 34, 28)];
        button.bezelStyle = NSBezelStyleTexturedRounded; button.imagePosition = NSImageOnly;
        button.focusRingType = NSFocusRingTypeExterior;
        __weak CPKeyboardToolbarButton *weakButton = button;
        button.target = button; button.action = @selector(performActivation:);
        if (self.chromeHandler) button.focusChanged = ^{ dispatch_async(dispatch_get_main_queue(), ^{
            BOOL focused = [owner.playbackWindow.firstResponder isKindOfClass:CPKeyboardToolbarButton.class];
            if (owner.chromeHandler) owner.chromeHandler(2, focused);
        }); };
        button.move = ^(NSInteger offset, BOOL tab) { [owner moveToolbarFrom:weakButton offset:offset tab:tab]; };
        button.browse = ^{ if (owner.browseFromToolbar) owner.browseFromToolbar(); };
        if (item.view != button) {
            button.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [button.widthAnchor constraintEqualToConstant:34],
                [button.heightAnchor constraintEqualToConstant:28]
            ]];
            item.view = button;
        }
    }
    [self refreshPlaybackToolbar];
}
- (BOOL)focusPlaybackToolbarBackwards:(BOOL)backwards video:(void (^)(void))video browse:(void (^)(void))browse activate:(void (^)(NSString *))activate {
    if (!self.playbackWindow.isKeyWindow) return NO;
    NSArray<NSToolbarItem *> *items = [self playbackItems];
    if (!items.count) return NO;
    self.returnToVideo = video; self.browseFromToolbar = browse; self.activateToolbar = activate;
    [self installToolbarButtonsReplacingCallbacks:YES];
    [self setPlaybackToolbarControlsVisible:YES];
    NSArray *enabled = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSToolbarItem *item, NSDictionary *bindings) { return item.enabled; }]];
    NSToolbarItem *item = backwards ? enabled.lastObject : enabled.firstObject;
    if (!item) return NO;
    NSWindow *window = self.playbackWindow;
    CPKeyboardToolbarButton *button = (id)item.view;
    button.requestsKeyboardFocus = YES;
    if ([window makeFirstResponder:button]) button.requestsKeyboardFocus = NO;
    else {
        // A freshly installed toolbar view attaches on the next layout pass.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (NSApp.keyWindow == window && item.enabled && [window.toolbar.items containsObject:item]) {
                [window.contentView.superview layoutSubtreeIfNeeded];
                [window makeFirstResponder:item.view];
            }
        });
    }
    return YES;
}
- (BOOL)keyWindowIsFullScreen { return (NSApp.keyWindow.styleMask & NSWindowStyleMaskFullScreen) != 0; }
- (void)stopPointer {
    if (self.pointerMonitor) [NSEvent removeMonitor:self.pointerMonitor];
    self.pointerMonitor = nil;
}
- (void)setPlaybackToolbarExitHandler:(void (^)(BOOL))handler { self.toolbarExit = handler; }
- (void)togglePlaybackFullScreen {
    NSWindow *window = self.playbackWindow;
    if (window.isKeyWindow) [window toggleFullScreen:nil];
}
- (void)startPlaybackChromeWithHandler:(void (^)(NSInteger, BOOL))handler {
    NSWindow *window = self.playbackWindow;
    if (window && self.chromeWindow == window) { self.chromeHandler = handler; return; }
    [self stopPlaybackChrome];
    self.chromeHandler = handler;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-session-state"]) {
        NSLog(@"CPStage5 chrome attachment: window=%@ key=%d", window ? @"found" : @"not-yet-attached", window.isKeyWindow);
    }
    if (!window) return;
    self.chromeWindow = window;
    self.changedMouseMoved = !window.acceptsMouseMovedEvents;
    window.acceptsMouseMovedEvents = YES;
    self.chromeTokens = [NSMutableArray array];
    __weak CPPlaybackLifecycle *weakSelf = self;
    for (NSNotificationName name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification,
                                      NSWindowDidResignKeyNotification]) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:window queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                CPPlaybackLifecycle *self = weakSelf;
                [self setPlaybackCursorHidden:NO];
                if (self.chromeHandler) {
                    self.chromeHandler(1, (window.styleMask & NSWindowStyleMaskFullScreen) != 0);
                    self.chromeHandler(3, NO);
                }
            }];
        [self.chromeTokens addObject:token];
    }
    for (NSNotificationName name in @[NSWindowWillMiniaturizeNotification, NSWindowDidMiniaturizeNotification,
                                      NSWindowDidDeminiaturizeNotification]) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:window queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                CPPlaybackLifecycle *self = weakSelf;
                if (self.chromeHandler) self.chromeHandler(4, ![name isEqual:NSWindowDidDeminiaturizeNotification]);
            }];
        [self.chromeTokens addObject:token];
    }
    self.chromeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp
        handler:^NSEvent *(NSEvent *event) {
            CPPlaybackLifecycle *self = weakSelf;
            if (self.chromeHandler && event.window == self.chromeWindow && event.window.isKeyWindow) {
                if (!self.loggedChromeMotion && [NSProcessInfo.processInfo.arguments containsObject:@"--ui-session-state"]) {
                    self.loggedChromeMotion = YES; NSLog(@"CPStage5 native pointer activity received");
                }
                self.chromeHandler(0, YES);
                BOOL hovered = NO;
                for (NSToolbarItem *item in [self playbackItems]) {
                    NSView *view = item.view;
                    if (view.window && NSPointInRect([view convertPoint:event.locationInWindow fromView:nil], view.bounds)) { hovered = YES; break; }
                }
                self.chromeHandler(3, hovered);
            }
            return event;
        }];
    [self refreshPlaybackToolbar];
    handler(1, (window.styleMask & NSWindowStyleMaskFullScreen) != 0);
    handler(4, window.isMiniaturized);
}
- (void)setPlaybackToolbarControlsVisible:(BOOL)visible {
    for (NSToolbarItem *item in [self playbackItems]) item.view.hidden = !visible;
}
- (void)setPlaybackCursorHidden:(BOOL)hidden {
    NSWindow *window = self.chromeWindow;
    if (!hidden) {
        if (self.requestedCursorHidden) [NSCursor setHiddenUntilMouseMoves:NO];
        self.requestedCursorHidden = NO;
        return;
    }
    NSPoint point = [window mouseLocationOutsideOfEventStream];
    if (window.isKeyWindow && NSPointInRect(point, window.contentView.frame)) {
        [NSCursor setHiddenUntilMouseMoves:YES]; self.requestedCursorHidden = YES;
    }
}
- (void)stopPlaybackChrome {
    if (self.chromeMonitor) [NSEvent removeMonitor:self.chromeMonitor];
    for (id token in self.chromeTokens) [NSNotificationCenter.defaultCenter removeObserver:token];
    if (self.changedMouseMoved) self.chromeWindow.acceptsMouseMovedEvents = NO;
    [self setPlaybackCursorHidden:NO];
    self.chromeMonitor = nil; self.chromeTokens = nil; self.chromeHandler = nil;
    self.toolbarExit = nil; self.chromeWindow = nil; self.changedMouseMoved = NO;
}
- (void)dealloc { [self stop]; [self stopSecondaryClick]; [self stopPointer]; [self stopPlaybackChrome]; }
@end
