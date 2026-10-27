/* LanternDefaults (Lantern Lane, tvOS only). See lantern_defaults.h.
 * Written to work with or without ARC: only autoreleased Foundation objects are created here. */

#include "lantern_defaults.h"

#include "core/object/class_db.h"

#import <Foundation/Foundation.h>

static NSString *const KEY_PREFIX = @"lantern.";

static NSString *ns_string(const String &p_str) {
	return [NSString stringWithUTF8String:p_str.utf8().get_data()];
}

static NSString *full_key(const String &p_name) {
	return [KEY_PREFIX stringByAppendingString:ns_string(p_name)];
}

static NSString *domain_name() {
	NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
	return bundle ? bundle : @"";
}

// The app's own persistent domain: every key the app (and the engine) stored, not the system defaults.
static NSDictionary *current_domain() {
	NSDictionary *d = [[NSUserDefaults standardUserDefaults] persistentDomainForName:domain_name()];
	return d ? d : @{};
}

// The exact size of a domain written as a binary property list (how UserDefaults keeps it), or -1.
static int64_t serialized_size(NSDictionary *p_domain) {
	NSError *error = nil;
	NSData *plist = [NSPropertyListSerialization dataWithPropertyList:p_domain
															   format:NSPropertyListBinaryFormat_v1_0
															  options:0
																error:&error];
	return plist ? (int64_t)plist.length : -1;
}

bool LanternDefaults::valid_name(const String &p_name) {
	if (p_name.is_empty() || p_name.length() > MAX_NAME) {
		return false;
	}
	for (int i = 0; i < p_name.length(); i++) {
		const char32_t c = p_name[i];
		if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.')) {
			return false;
		}
	}
	return true;
}

int64_t LanternDefaults::domain_bytes() const {
	return serialized_size(current_domain());
}

int64_t LanternDefaults::candidate_bytes(const String &p_name, const PackedByteArray &p_data) const {
	if (!valid_name(p_name)) {
		return -1;
	}
	NSMutableDictionary *candidate = [NSMutableDictionary dictionaryWithDictionary:current_domain()];
	candidate[full_key(p_name)] = [NSData dataWithBytes:p_data.ptr() length:(NSUInteger)p_data.size()];
	return serialized_size(candidate);
}

int LanternDefaults::put_blob(const String &p_name, const PackedByteArray &p_data) {
	if (!valid_name(p_name)) {
		return ERR_INVALID_PARAMETER;
	}
	if (p_data.is_empty() || p_data.size() > MAX_VALUE) {
		return ERR_INVALID_DATA;
	}
	const int64_t after = candidate_bytes(p_name, p_data);
	if (after < 0) {
		return FAILED;
	}
	if (after > BUDGET) {
		return ERR_OUT_OF_MEMORY; // nothing written: the old value and the whole domain stay as they were
	}
	NSData *value = [NSData dataWithBytes:p_data.ptr() length:(NSUInteger)p_data.size()];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:value forKey:full_key(p_name)];
	NSData *back = [defaults dataForKey:full_key(p_name)];
	return (back && [back isEqualToData:value]) ? OK : FAILED;
}

PackedByteArray LanternDefaults::get_blob(const String &p_name) const {
	PackedByteArray out;
	if (!valid_name(p_name)) {
		return out;
	}
	NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:full_key(p_name)];
	if (!data || data.length == 0 || (int64_t)data.length > MAX_VALUE) {
		return out;
	}
	out.resize((int64_t)data.length);
	memcpy(out.ptrw(), data.bytes, data.length);
	return out;
}

bool LanternDefaults::erase_blob(const String &p_name) {
	if (!valid_name(p_name)) {
		return false;
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:full_key(p_name)];
	return [defaults objectForKey:full_key(p_name)] == nil;
}

PackedStringArray LanternDefaults::keys(const String &p_prefix) const {
	PackedStringArray out;
	NSString *want = full_key(p_prefix);
	for (NSString *key in current_domain()) {
		if ([key hasPrefix:want]) {
			out.push_back(String::utf8([[key substringFromIndex:KEY_PREFIX.length] UTF8String]));
		}
	}
	out.sort();
	return out;
}

void LanternDefaults::_bind_methods() {
	ClassDB::bind_method(D_METHOD("put_blob", "name", "data"), &LanternDefaults::put_blob);
	ClassDB::bind_method(D_METHOD("get_blob", "name"), &LanternDefaults::get_blob);
	ClassDB::bind_method(D_METHOD("erase_blob", "name"), &LanternDefaults::erase_blob);
	ClassDB::bind_method(D_METHOD("domain_bytes"), &LanternDefaults::domain_bytes);
	ClassDB::bind_method(D_METHOD("candidate_bytes", "name", "data"), &LanternDefaults::candidate_bytes);
	ClassDB::bind_method(D_METHOD("keys", "prefix"), &LanternDefaults::keys);
	ClassDB::bind_method(D_METHOD("budget"), &LanternDefaults::budget);
}
