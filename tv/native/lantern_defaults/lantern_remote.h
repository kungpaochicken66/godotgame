/* LanternRemote (Lantern Lane, tvOS only): the Siri Remote's Menu button and the way back to the Home screen.
 *
 * The tvOS view controller of the engine is a GCEventViewController that leaves
 * controllerUserInteractionEnabled at NO, so controller input (the Siri Remote included) goes to the Game
 * Controller framework and never to UIKit: the Menu button never returns to the Apple TV Home screen. Apple's
 * documented pattern (DemoBots) is to set that property to YES only on the game's top screen, so that Menu goes
 * to UIKit there and tvOS returns Home.
 *
 * The engine's controller is found through its own GDTAppDelegateService.viewController (the window's root is a
 * SwiftUI hosting controller on the pinned port), with a bounded search of the view controller tree as fallback.
 *
 * Armed, controller input goes only through UIKit (GCEventViewController delivers to one path at a time), so the
 * game cannot see it: the armed state is bounded in time and ends natively on any other UIKit press.
 *
 * This class counts Menu presses of the Siri Remote only (a controller with a micro gamepad and no extended
 * gamepad), so a game controller's buttons are never taken for it, and lets the game switch the property.
 */

#pragma once

#include "core/object/object.h"

class LanternRemote : public Object {
	GDCLASS(LanternRemote, Object);

protected:
	static void _bind_methods();

public:
	// Menu presses of the Siri Remote since the last call (each counted once, on release).
	int take_menu_presses();
	// YES: controller input also goes through UIKit, so the next Siri Remote Menu press returns Home.
	// Only for the game's top screen; returns whether the root view controller took the setting.
	bool set_system_back(bool p_on);
	// Hands the next Siri Remote Menu press to UIKit for at most p_seconds (1..10), then takes it back by itself.
	// While armed any other UIKit press (select, play/pause, arrows) takes it back at once: controller input
	// reaches only UIKit then, so the game cannot see it.
	bool arm_system_back(double p_seconds);
	bool is_system_back() const;
	bool remote_connected() const;

	LanternRemote();
	~LanternRemote();
};
