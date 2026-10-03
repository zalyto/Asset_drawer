@tool
extends RefCounted
## Customizable shortcuts, stored in Project Settings under "Addons > Asset Drawer > Shortcuts".
##
## Each value is plain text such as "Ctrl+Space", "Shift+A", "F2" or "Alt+V".
## Modifiers: Ctrl, Shift, Alt, Meta (Cmd / Super), CmdOrCtrl (Cmd on macOS, Ctrl elsewhere).
## Key names are Godot's: A-Z, 0-9, F1-F12, Space, Enter, Escape, Backspace, Delete, Tab, Up, Down...
## An empty value disables the shortcut.

# "addons/..." is what makes Godot list the settings in the "Addons" section of Project Settings
# (a first path segment of our own would create a separate top-level section).
const PREFIX := "addons/asset_drawer/shortcuts/"
# Path used by earlier versions: values changed there are carried over (see register()).
const OLD_PREFIX := "asset_drawer/shortcuts/"

# id -> default (the order is the order of the documentation, Godot lists settings alphabetically)
const DEFAULTS := {
	"open_drawer": "Ctrl+Space",
	"close_drawer": "Escape",
	"paste_resource": "Alt+V",
	"focus_search": "Ctrl+F",
	"create_menu": "Shift+A",
	"rename": "F2",
	"duplicate": "Ctrl+D",
	"delete": "Delete",
	"parent_folder": "Backspace",
	"open_item": "Enter",
}

const ALIASES := {
	"esc": "Escape", "del": "Delete", "return": "Enter", "bksp": "Backspace",
	"spacebar": "Space", "pageup": "PageUp", "pagedown": "PageDown",
}

static var _cache: Dictionary = {}   # id -> {"raw": String, "sc": Dictionary}
static var _warned: Dictionary = {}


## Declares the settings (called when the plugin is enabled). Default values are not written
## to project.godot: only the shortcuts you actually change are saved.
static func register() -> void:
	for id in DEFAULTS:
		var path: String = PREFIX + str(id)
		# Migration: a shortcut customized under the old path moves to the new one.
		var old_path: String = OLD_PREFIX + str(id)
		if ProjectSettings.has_setting(old_path):
			if not ProjectSettings.has_setting(path):
				ProjectSettings.set_setting(path, ProjectSettings.get_setting(old_path))
			ProjectSettings.set_setting(old_path, null)   # removes the old entry from project.godot
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, DEFAULTS[id])
		ProjectSettings.set_initial_value(path, DEFAULTS[id])
		ProjectSettings.add_property_info({"name": path, "type": TYPE_STRING})
		if ProjectSettings.has_method("set_as_basic"):
			ProjectSettings.call("set_as_basic", path, true)   # visible without the "Advanced" toggle
	_cache.clear()
	_warned.clear()


static func raw(id: String) -> String:
	return str(ProjectSettings.get_setting(PREFIX + id, DEFAULTS.get(id, ""))).strip_edges()


## Text to display (tooltips, hint pill). `empty_text` is returned when the shortcut is disabled.
static func label(id: String, empty_text: String = "") -> String:
	var t := raw(id)
	return t if not t.is_empty() else empty_text


## "Rename" -> "Rename (F2)", or just "Rename" when the shortcut is disabled.
static func with_hint(text: String, id: String) -> String:
	var l := label(id)
	return text if l.is_empty() else "%s (%s)" % [text, l]


## All the values joined: lets the plugin detect that a shortcut changed.
static func snapshot() -> String:
	var parts: PackedStringArray = []
	for id in DEFAULTS:
		parts.append(raw(str(id)))
	return "|".join(parts)


static func matches(event: InputEventKey, id: String) -> bool:
	var sc := _lookup(id)
	if not sc.valid:
		return false
	var key_ok: bool = event.keycode == sc.keycode or (sc.keycode == KEY_ENTER and event.keycode == KEY_KP_ENTER)
	if not key_ok:
		return false
	var want_ctrl: bool = sc.ctrl
	var want_meta: bool = sc.meta
	if sc.cmd:
		if OS.get_name() == "macOS":
			want_meta = true
		else:
			want_ctrl = true
	return event.ctrl_pressed == want_ctrl and event.shift_pressed == sc.shift \
		and event.alt_pressed == sc.alt and event.meta_pressed == want_meta


# Not named "_get": that name is an Object virtual method (property getter), and a static
# function with that name and a different signature can make the whole script fail to compile.
static func _lookup(id: String) -> Dictionary:
	var r := raw(id)
	var c: Variant = _cache.get(id)
	if c != null and c.raw == r:
		return c.sc
	var sc := _parse(r)
	if not sc.valid and not r.is_empty() and not _warned.has(id + r):
		_warned[id + r] = true
		push_warning("Asset Drawer: invalid shortcut \"%s\" for '%s' (example: Ctrl+Shift+A)" % [r, id])
	_cache[id] = {"raw": r, "sc": sc}
	return sc


static func _parse(text: String) -> Dictionary:
	var out := {"keycode": 0, "ctrl": false, "shift": false, "alt": false, "meta": false, "cmd": false, "valid": false}
	if text.is_empty():
		return out
	var key_token := ""
	for token in text.split("+", false):
		var t := token.strip_edges()
		match t.to_lower():
			"ctrl", "control":
				out.ctrl = true
			"shift":
				out.shift = true
			"alt", "option":
				out.alt = true
			"meta", "cmd", "command", "super", "win":
				out.meta = true
			"cmdorctrl", "cmd_or_ctrl", "command_or_control", "ctrl/cmd":
				out.cmd = true
			_:
				key_token = str(ALIASES.get(t.to_lower(), t))
	if key_token.is_empty():
		return out
	var kc: int = OS.find_keycode_from_string(key_token)
	if kc == KEY_NONE:
		return out
	out.keycode = kc & KEY_CODE_MASK
	out.valid = true
	return out
