// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

class Settings;

/**
 * initialize basic default settings
 * @param settings pointer to settings
 */
void set_default_settings();

/**
 * Use default preset for settings
 * @param settings pointer to settings
 * @param force_keycode whether to unconditionally use keycode-based settings
 */
void set_keyboard_defaults(Settings *settings, bool force_keycode = false);
