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
@property(copy) void (^activate)(void);
@property(copy) void (^move)(NSInteger, BOOL);
@property(copy) void (^browse)(void);
@end
@implementation CPKeyboardToolbarButton
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return NO; }
- (BOOL)becomeFirstResponder { BOOL accepted = [super becomeFirstResponder]; self.keyboardFocused = accepted; return accepted; }
- (BOOL)resignFirstResponder { self.keyboardFocused = NO; return [super resignFirstResponder]; }
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
        case 36: case 76: case 49: if (!event.isARepeat && self.enabled && self.activate) self.activate(); return;
        case 48: if (!event.isARepeat && self.move) self.move((event.modifierFlags & NSEventModifierFlagShift) ? -1 : 1, YES); return;
        case 123: case 126: if (!event.isARepeat && self.move) self.move(-1, NO); return;
        case 124: case 125: if (!event.isARepeat && self.move) self.move(1, NO); return;
        case 53:
            if (NSApp.keyWindow.styleMask & NSWindowStyleMaskFullScreen) { [super keyDown:event]; return; }
            if (!event.isARepeat && self.browse) self.browse(); return;
        default: [super keyDown:event];
    }
}
- (void)performActivation:(id)sender { if (self.enabled && self.activate) self.activate(); }
@end

/// A native bundle keeps AppKit-only lifecycle APIs outside the Catalyst target.
@interface CPPlaybackLifecycle : NSObject <CPPlaybackLifecycleProtocol, CPRegistrationClickProtocol, CPPlaybackPointerProtocol>
@property(copy) void (^handler)(NSString *, BOOL);
@property NSMutableArray *tokens;
@property id secondaryMonitor;
@property id pointerMonitor;
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
        button.target = button; button.action = @selector(performActivation:);
    }
}
- (void)moveToolbarFrom:(NSButton *)button offset:(NSInteger)offset tab:(BOOL)tab {
    if (!self.playbackWindow.isKeyWindow) return;
    NSArray *items = [[self playbackItems] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSToolbarItem *item, NSDictionary *bindings) { return item.enabled; }]];
    NSUInteger index = [items indexOfObjectPassingTest:^BOOL(NSToolbarItem *item, NSUInteger idx, BOOL *stop) { return item.view == button; }];
    if (index == NSNotFound) return;
    NSInteger next = (NSInteger)index + offset;
    if (next < 0 || next >= (NSInteger)items.count) {
        if (tab && self.returnToVideo) { [self.playbackWindow makeFirstResponder:nil]; self.returnToVideo(); }
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
        __weak NSToolbarItem *weakItem = item;
        __weak CPKeyboardToolbarButton *weakButton = button;
        button.activate = ^{ NSToolbarItem *item = weakItem; if (item.enabled && owner.activateToolbar) owner.activateToolbar(item.itemIdentifier); };
        button.target = button; button.action = @selector(performActivation:);
        button.move = ^(NSInteger offset, BOOL tab) { [owner moveToolbarFrom:weakButton offset:offset tab:tab]; };
        button.browse = ^{ if (owner.browseFromToolbar) owner.browseFromToolbar(); };
        if (item.view != button) item.view = button;
    }
    [self refreshPlaybackToolbar];
}
- (BOOL)focusPlaybackToolbarBackwards:(BOOL)backwards video:(void (^)(void))video browse:(void (^)(void))browse activate:(void (^)(NSString *))activate {
    if (!self.playbackWindow.isKeyWindow) return NO;
    NSArray<NSToolbarItem *> *items = [self playbackItems];
    if (!items.count) return NO;
    self.returnToVideo = video; self.browseFromToolbar = browse; self.activateToolbar = activate;
    [self installToolbarButtonsReplacingCallbacks:YES];
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
- (void)dealloc { [self stop]; [self stopSecondaryClick]; [self stopPointer]; }
@end
