// Lantern Lane: add-only Photos saving for the in-game camera.
// Least privilege: PHAccessLevelAddOnly (NSPhotoLibraryAddUsageDescription); the
// game never reads the library. Success is reported only from the system's
// completion handler.
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

#include "photo_library.h"
#include "core/config/engine.h"

static PhotoLibrary *photo_library_instance = nullptr;

static void finish(PhotoLibrary *self, bool ok, const char *code) {
	String c = String(code);
	dispatch_async(dispatch_get_main_queue(), ^{
		self->call_deferred("emit_signal", "save_finished", ok, c);
	});
}

void PhotoLibrary::_bind_methods() {
	ClassDB::bind_method(D_METHOD("save_image", "path"), &PhotoLibrary::save_image);
	ClassDB::bind_method(D_METHOD("authorization_status"), &PhotoLibrary::authorization_status);
	ClassDB::bind_method(D_METHOD("open_settings"), &PhotoLibrary::open_settings);
	ADD_SIGNAL(MethodInfo("save_finished", PropertyInfo(Variant::BOOL, "ok"), PropertyInfo(Variant::STRING, "code")));
}

int PhotoLibrary::authorization_status() const {
	return (int)[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
}

void PhotoLibrary::save_image(const String &path) {
	NSString *file = [NSString stringWithUTF8String:path.utf8().get_data()];
	NSURL *url = [NSURL fileURLWithPath:file];
	if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
		finish(this, false, "failed");
		return;
	}
	PhotoLibrary *self = this;
	[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
											   handler:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			finish(self, false, "denied");
			return;
		}
		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
		} completionHandler:^(BOOL success, NSError *error) {
			finish(self, success, success ? "saved" : "failed");
		}];
	}];
}

void PhotoLibrary::open_settings() {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	});
}

PhotoLibrary::PhotoLibrary() {}
PhotoLibrary::~PhotoLibrary() {}

void photo_library_init() {
	photo_library_instance = memnew(PhotoLibrary);
	Engine::get_singleton()->add_singleton(Engine::Singleton("PhotoLibrary", photo_library_instance));
}

void photo_library_deinit() {
	if (photo_library_instance) {
		memdelete(photo_library_instance);
		photo_library_instance = nullptr;
	}
}
