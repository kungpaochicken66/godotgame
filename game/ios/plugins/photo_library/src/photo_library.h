// Lantern Lane: save a photo to the iOS/iPadOS Photos library with add-only access.
// Built on the Mac by ../build.sh against the Godot 4.7.2 headers.
#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"

class PhotoLibrary : public Object {
	GDCLASS(PhotoLibrary, Object);

protected:
	static void _bind_methods();

public:
	// Asks for add-only access if needed, then saves the PNG/JPEG at `path`.
	// Emits save_finished(ok: bool, code: String) on the main thread once the
	// system reports the result. code: "saved", "denied", "failed".
	void save_image(const String &path);
	// 0 not determined, 1 restricted, 2 denied, 3 authorized, 4 limited.
	int authorization_status() const;
	void open_settings();

	PhotoLibrary();
	~PhotoLibrary();
};
