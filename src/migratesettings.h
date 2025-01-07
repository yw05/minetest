// Minetest
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "defaultsettings.h"
#include "server.h"

void migrate_settings()
{
	// Converts opaque_water to translucent_liquids
	if (g_settings->existsLocal("opaque_water")) {
		g_settings->set("translucent_liquids",
				g_settings->getBool("opaque_water") ? "false" : "true");
		g_settings->remove("opaque_water");
	}

	// Converts enable_touch to touch_controls/touch_gui
	if (g_settings->existsLocal("enable_touch")) {
		bool value = g_settings->getBool("enable_touch");
		g_settings->setBool("touch_controls", value);
		g_settings->setBool("touch_gui", value);
		g_settings->remove("enable_touch");
	}

	// Disables anticheat
	if (g_settings->existsLocal("disable_anticheat")) {
		if (g_settings->getBool("disable_anticheat")) {
			g_settings->setFlagStr("anticheat_flags", 0, flagdesc_anticheat);
		}
		g_settings->remove("disable_anticheat");
	}

	// Use keycodes for keybindings for missing keys
	// if the keymap was changed in an earlier version
#if USE_SDL2
	if (!g_settings->existsLocal("use_scancodes_for_keybindings"))
		for (const auto &name: g_settings->getNames())
			if (auto value = g_settings->get(name);
					str_starts_with(name, "keymap_") && value.size() > 1 && value.front() != '<') {
				g_settings->setBool("use_scancodes_for_keybindings", false);
				set_keyboard_defaults(g_settings, true);
				break;
			}
#endif
}
