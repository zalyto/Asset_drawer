@tool
extends EditorPlugin

const Drawer := preload("res://addons/asset_drawer/drawer.gd")
const L := preload("res://addons/asset_drawer/lang.gd")

# true  : Ctrl+Space opens the drawer even when the script editor has focus
#         (Ctrl+Space autocompletion is then replaced by the drawer).
# false : in the script editor, Ctrl+Space stays autocompletion.
const OPEN_IN_CODE_EDITOR := true

# true : the open shortcut is ignored while the camera is in free look
#        (right mouse button held in the 3D view, or free look toggled with Shift+F).
#        This avoids opening the drawer when Ctrl (move down) + Space (move up)
#        are pressed together to move around.
const BLOCK_IN_FREELOOK := true

var drawer: Control
var _toolbar_btn: Button
var _theme_check_queued := false

func _enter_tree() -> void:
	_create_drawer()

	_toolbar_btn = Button.new()
	_toolbar_btn.flat = true
	_toolbar_btn.tooltip_text = L.t("Asset Drawer (Ctrl+Espace)")
	_toolbar_btn.focus_mode = Control.FOCUS_NONE
	var base := EditorInterface.get_base_control()
	var icon_name := "FolderBrowse" if base.has_theme_icon("FolderBrowse", "EditorIcons") else "Folder"
	_toolbar_btn.icon = base.get_theme_icon(icon_name, "EditorIcons")
	_toolbar_btn.pressed.connect(func() -> void:
		if is_instance_valid(drawer):
			drawer.toggle())
	add_control_to_container(CONTAINER_TOOLBAR, _toolbar_btn)

	add_tool_menu_item("Asset Drawer", Callable(self, "_on_menu_toggle"))
	set_process_input(true)

	# The drawer follows the editor theme (base color, contrast, accent).
	var es := EditorInterface.get_editor_settings()
	if not es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.connect(_on_settings_changed)


func _create_drawer() -> void:
	drawer = Drawer.new()
	drawer.name = "AssetDrawer"
	EditorInterface.get_base_control().add_child(drawer)


func _on_settings_changed() -> void:
	# Deferred: we first let the editor regenerate its theme before re-reading the colors.
	if _theme_check_queued:
		return
	_theme_check_queued = true
	_check_theme.call_deferred()


func _check_theme() -> void:
	_theme_check_queued = false
	if not is_instance_valid(drawer) or not drawer.palette_changed():
		return
	# Recreates the drawer with the new palette. Its state (folder, height, favorites...)
	# is already in the config, and is read back by the new drawer.
	var was_open: bool = drawer.is_open
	var old := drawer
	drawer = null
	old.get_parent().remove_child(old)   # triggers _exit_tree: save + cleanup
	old.queue_free()
	await get_tree().process_frame       # lets the old pill / overlay go away (same names)
	if not is_inside_tree():
		return
	_create_drawer()
	if was_open:
		drawer.open.call_deferred()


func _exit_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	if is_instance_valid(es) and es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.disconnect(_on_settings_changed)
	remove_tool_menu_item("Asset Drawer")
	if is_instance_valid(_toolbar_btn):
		remove_control_from_container(CONTAINER_TOOLBAR, _toolbar_btn)
		_toolbar_btn.queue_free()
		_toolbar_btn = null
	if is_instance_valid(drawer):
		drawer.queue_free()
		drawer = null


func _on_menu_toggle() -> void:
	if is_instance_valid(drawer):
		drawer.toggle()


func _is_freelook_active() -> bool:
	# During free look, Godot captures the mouse (right button held OR free look
	# toggled with Shift+F). The right-click test acts as a safety net.
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(drawer):
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SPACE and key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed and not key.meta_pressed:
		# Free look active: we let the key through to the editor (camera movement).
		if BLOCK_IN_FREELOOK and _is_freelook_active():
			return
		# Ctrl+Space is also used for autocompletion: see OPEN_IN_CODE_EDITOR at the top of the file.
		if not OPEN_IN_CODE_EDITOR:
			var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner()
			if focus is TextEdit and not drawer.is_ancestor_of(focus):
				return
		drawer.toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and drawer.is_open and not drawer.pinned:
		drawer.close()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_V and key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed and not key.meta_pressed:
		# Pastes the copied resource from the drawer onto the Inspector resource field hovered by the mouse.
		if drawer.try_paste_resource_at_mouse():
			get_viewport().set_input_as_handled()
