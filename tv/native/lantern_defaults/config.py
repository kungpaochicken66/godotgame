# LanternDefaults: Lantern Lane's bounded persistent store on Apple TV (tvOS only).
# Built with the engine: scons platform=tvos target=template_debug custom_modules=<path to tv/native>


def can_build(env, platform):
    return platform == "tvos"


def configure(env):
    pass

