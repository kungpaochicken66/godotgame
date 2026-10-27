/* LanternDefaults (Lantern Lane, tvOS only): registers the Engine singleton "LanternDefaults". */

#include "register_types.h"

#include "lantern_defaults.h"
#include "lantern_remote.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

static LanternDefaults *lantern_defaults = nullptr;
static LanternRemote *lantern_remote = nullptr;

void initialize_lantern_defaults_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LanternDefaults);
	lantern_defaults = memnew(LanternDefaults);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LanternDefaults", lantern_defaults));
	GDREGISTER_CLASS(LanternRemote);
	lantern_remote = memnew(LanternRemote);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LanternRemote", lantern_remote));
}

void uninitialize_lantern_defaults_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	if (lantern_remote) {
		Engine::get_singleton()->remove_singleton("LanternRemote");
		memdelete(lantern_remote);
		lantern_remote = nullptr;
	}
	if (lantern_defaults) {
		Engine::get_singleton()->remove_singleton("LanternDefaults");
		memdelete(lantern_defaults);
		lantern_defaults = nullptr;
	}
}
