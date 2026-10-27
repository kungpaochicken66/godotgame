/* LanternDefaults (Lantern Lane, tvOS only).
 *
 * A bounded store in the app's NSUserDefaults persistent domain, the only local storage tvOS keeps for
 * sure (Apple TV Programming Guide: 500 KB; UserDefaults warns at 512 KiB and terminates the app at 1 MiB
 * or more). Keys are "lantern." + a short name. Before every write the exact serialized size of the whole
 * candidate domain (binary property list of every key and value, the new value included) is computed and
 * the write is refused above BUDGET, leaving the domain as it was. Values are small byte blobs only (the
 * game's checked copies of its progress files); never images.
 */

#pragma once

#include "core/object/object.h"
#include "core/variant/variant.h"

class LanternDefaults : public Object {
	GDCLASS(LanternDefaults, Object);

protected:
	static void _bind_methods();

public:
	static constexpr int64_t BUDGET = 384 * 1024; // whole serialized domain after the write
	static constexpr int64_t MAX_VALUE = 192 * 1024; // one value
	static constexpr int MAX_NAME = 48;

	// OK; ERR_INVALID_PARAMETER (bad name); ERR_INVALID_DATA (empty or above MAX_VALUE);
	// ERR_OUT_OF_MEMORY (the whole domain would pass BUDGET; nothing written); FAILED (not stored or read back).
	int put_blob(const String &p_name, const PackedByteArray &p_data);
	PackedByteArray get_blob(const String &p_name) const;
	bool erase_blob(const String &p_name);
	int64_t domain_bytes() const;
	int64_t candidate_bytes(const String &p_name, const PackedByteArray &p_data) const;
	PackedStringArray keys(const String &p_prefix) const;
	int64_t budget() const { return BUDGET; }

	static bool valid_name(const String &p_name);
};
