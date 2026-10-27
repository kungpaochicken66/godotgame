/* LanternRemote (Lantern Lane, tvOS only). See lantern_remote.h.
 * Written to work with or without ARC: only autoreleased Foundation objects and blocks owned by UIKit/GC.
 *
 * Apple's headers come first, before any Godot header: GameController's GCPhysicalInputElementCollection<Key, ...>
 * is otherwise ambiguous with Godot's enum class Key (core/variant/variant_caster.h), as in the engine's own files. */

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#include "lantern_remote.h"

#include "core/object/class_db.h"
#include "core/string/print_string.h"

#import "drivers/apple_embedded/godot_app_delegate_service_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_controller.h"

#include <atomic>

static std::atomic<int> menu_presses(0);
static std::atomic<int> arm_generation(0);
static id connect_observer = nil;
static UITapGestureRecognizer *other_press_watch = nil;

// While Menu is handed to UIKit, controller input goes through UIKit too (GCEventViewController delivers to one
// path at a time), so the game sees none of it. Any UIKit press that is not Menu (select, play/pause, arrows:
// from a game controller or the remote) ends the armed state at once, before it can be taken for anything.
@interface LanternPressWatcher : NSObject
- (void)pressed:(UITapGestureRecognizer *)recognizer;
@end

static LanternPressWatcher *press_target = nil;

// The Siri Remote: a micro gamepad without an extended gamepad (a game controller always has one).
static bool is_siri_remote(GCController *p_controller) {
	return p_controller.microGamepad != nil && p_controller.extendedGamepad == nil;
}

static void watch(GCController *p_controller) {
	if (!is_siri_remote(p_controller)) {
		return;
	}
	if (@available(tvOS 14.0, *)) {
		p_controller.microGamepad.buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
			if (!pressed) {
				menu_presses.fetch_add(1);
			}
		};
	}
}

// The engine's GCEventViewController. On the pinned port the window's root is a SwiftUI hosting controller
// (GodotWindowScene / UIViewControllerRepresentable), so the root itself is never it: use the engine's own
// published controller (GDTAppDelegateService.viewController), else search the view controller tree a
// bounded number of levels down from each window's root.
static GCEventViewController *find_event_controller(UIViewController *p_vc, int p_depth) {
	if (p_vc == nil || p_depth > 4) {
		return nil;
	}
	if ([p_vc isKindOfClass:[GCEventViewController class]]) {
		return (GCEventViewController *)p_vc;
	}
	for (UIViewController *child in p_vc.childViewControllers) {
		GCEventViewController *found = find_event_controller(child, p_depth + 1);
		if (found != nil) {
			return found;
		}
	}
	return find_event_controller(p_vc.presentedViewController, p_depth + 1);
}

static GCEventViewController *root_controller() {
	GDTViewController *engine = GDTAppDelegateService.viewController;
	if (engine != nil && [engine isKindOfClass:[GCEventViewController class]]) {
		return (GCEventViewController *)engine;
	}
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]) {
			for (UIWindow *window in ((UIWindowScene *)scene).windows) {
				GCEventViewController *found = find_event_controller(window.rootViewController, 0);
				if (found != nil) {
					return found;
				}
			}
		}
	}
	return nil;
}

static void set_interaction(bool p_on) {
	GCEventViewController *controller = root_controller();
	if (controller != nil) {
		controller.controllerUserInteractionEnabled = p_on ? YES : NO;
	}
	if (other_press_watch != nil) {
		other_press_watch.enabled = p_on ? YES : NO;
	}
}

@implementation LanternPressWatcher
- (void)pressed:(UITapGestureRecognizer *)recognizer {
	arm_generation.fetch_add(1);   // any pending timeout is void
	set_interaction(false);
}
@end

static void ensure_press_watch() {
	if (other_press_watch != nil) {
		return;
	}
	GCEventViewController *controller = root_controller();
	if (controller == nil || controller.view == nil) {
		return;
	}
	press_target = [LanternPressWatcher new];
	other_press_watch = [[UITapGestureRecognizer alloc] initWithTarget:press_target action:@selector(pressed:)];
	other_press_watch.allowedTouchTypes = @[];
	other_press_watch.allowedPressTypes = @[ @(UIPressTypeSelect), @(UIPressTypePlayPause), @(UIPressTypeUpArrow),
		@(UIPressTypeDownArrow), @(UIPressTypeLeftArrow), @(UIPressTypeRightArrow) ];
	other_press_watch.cancelsTouchesInView = NO;
	other_press_watch.enabled = NO;
	[controller.view addGestureRecognizer:other_press_watch];
}

// One diagnostic line when Home is armed (class names only, no game or player data): the responder chain
// above the engine's controller and the focused item, which decide where UIKit sends the next Menu press.
static void log_press_route(GCEventViewController *p_controller) {
	NSMutableArray<NSString *> *chain = [NSMutableArray array];
	UIResponder *responder = p_controller;
	for (int i = 0; responder != nil && i < 12; i++) {
		[chain addObject:NSStringFromClass([responder class])];
		responder = responder.nextResponder;
	}
	id<UIFocusItem> focused = [UIFocusSystem focusSystemForEnvironment:p_controller].focusedItem;
	NSString *line = [NSString stringWithFormat:@"[tvOS Menu] armed: interaction %@; chain %@; focused %@",
			p_controller.controllerUserInteractionEnabled ? @"YES" : @"NO",
			[chain componentsJoinedByString:@" > "],
			focused != nil ? NSStringFromClass([(NSObject *)focused class]) : @"none"];
	print_line(String::utf8([line UTF8String]));
}

LanternRemote::LanternRemote() {
	for (GCController *controller in [GCController controllers]) {
		watch(controller);
	}
	connect_observer = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
																		 object:nil
																		  queue:[NSOperationQueue mainQueue]
																	 usingBlock:^(NSNotification *note) {
																		 watch((GCController *)note.object);
																	 }];
}

LanternRemote::~LanternRemote() {
	if (connect_observer != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:connect_observer];
		connect_observer = nil;
	}
}

int LanternRemote::take_menu_presses() {
	return menu_presses.exchange(0);
}

bool LanternRemote::set_system_back(bool p_on) {
	GCEventViewController *controller = root_controller();
	if (controller == nil) {
		return false;
	}
	arm_generation.fetch_add(1);   // a direct switch voids any pending timeout
	if (p_on) {
		ensure_press_watch();
	}
	set_interaction(p_on);
	return controller.controllerUserInteractionEnabled == (p_on ? YES : NO);
}

bool LanternRemote::arm_system_back(double p_seconds) {
	if (!set_system_back(true)) {
		return false;
	}
	log_press_route(root_controller());
	// Never left armed: after the given time (bounded to 1..10 s) Menu goes back to the game by itself.
	const double seconds = p_seconds < 1.0 ? 1.0 : (p_seconds > 10.0 ? 10.0 : p_seconds);
	const int generation = arm_generation.load();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (arm_generation.load() == generation) {
			set_interaction(false);
		}
	});
	return true;
}

bool LanternRemote::is_system_back() const {
	GCEventViewController *controller = root_controller();
	return controller != nil && controller.controllerUserInteractionEnabled;
}

bool LanternRemote::remote_connected() const {
	for (GCController *controller in [GCController controllers]) {
		if (is_siri_remote(controller)) {
			return true;
		}
	}
	return false;
}

void LanternRemote::_bind_methods() {
	ClassDB::bind_method(D_METHOD("take_menu_presses"), &LanternRemote::take_menu_presses);
	ClassDB::bind_method(D_METHOD("set_system_back", "on"), &LanternRemote::set_system_back);
	ClassDB::bind_method(D_METHOD("arm_system_back", "seconds"), &LanternRemote::arm_system_back);
	ClassDB::bind_method(D_METHOD("is_system_back"), &LanternRemote::is_system_back);
	ClassDB::bind_method(D_METHOD("remote_connected"), &LanternRemote::remote_connected);
}
