// Lantern Lane: a full-screen WKWebView above Godot's view, for the Three.js city
// (design/city-threejs.md). iOS and iPadOS only: tvOS has no WebKit.
// Built on the Mac by ../build.sh against the Godot 4.7.2 headers.
#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// The Engine singleton is named "WebView". The C++ class has another name because
// Apple's WebKit already has an Objective-C class called WebView.
class LanternWebView : public Object {
	GDCLASS(LanternWebView, Object);

protected:
	static void _bind_methods();

public:
	// Shows the page lantern://city/index.html?<query>, served from the folder
	// `root_dir` (an absolute path of real files; index.html must be in it).
	// False when the folder, the query or the window is not usable.
	bool open(const String &p_root_dir, const String &p_query);
	// Hides the page, frees the web view and discards unread messages.
	void close();
	// Calls window.LL.recv(<json>) on the page. `json` must be JSON text. Never
	// waits. False when the message was dropped (counted in stats().dropped):
	// no page is loaded, or too many calls are still in flight.
	bool post(const String &p_json);
	// The texts the page sent with window.webkit.messageHandlers.godot.postMessage
	// since the last poll, oldest first.
	PackedStringArray poll();
	bool is_open() const;
	// thermal (0..3), footprint_mb (this app's process), dropped,
	// web_process_terminated; also poll_dropped, js_errors, in_flight, loaded.
	Dictionary stats() const;

	LanternWebView();
	~LanternWebView();
};

void web_view_init();
void web_view_deinit();
