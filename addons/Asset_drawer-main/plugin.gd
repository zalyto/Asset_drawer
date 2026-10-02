@tool
extends EditorPlugin

const Drawer := preload("res://addons/Asset_drawer-main/scripts/drawer.gd")
const L := preload("res://addons/Asset_drawer-main/scripts/lang.gd")

# false = Ctrl+Espace ne fait rien quand on tape dans l'éditeur de code
const OPEN_IN_CODE_EDITOR := true

# évite d'ouvrir le tiroir en vue 3D (clic droit maintenu / souris capturée)
const BLOCK_IN_FREELOOK := true

var drawer: Control
var dock: EditorDock
var _toolbar_btn: Button
var _theme_check_queued := false

func _enter_tree() -> void:
	_create_dock()

	_toolbar_btn = Button.new()
	_toolbar_btn.flat = true
	_toolbar_btn.tooltip_text = L.t("Asset Drawer (Ctrl+Espace)")
	_toolbar_btn.focus_mode = Control.FOCUS_NONE
	var base := EditorInterface.get_base_control()
	var tex := _addon_icon()
	if tex == null and base != null:
		var icon_name := "FolderBrowse" if base.has_theme_icon("FolderBrowse", "EditorIcons") else "Folder"
		if base.has_theme_icon(icon_name, "EditorIcons"):
			tex = base.get_theme_icon(icon_name, "EditorIcons")
	if tex != null:
		_toolbar_btn.icon = tex
	_toolbar_btn.pressed.connect(_toggle_drawer)
	add_control_to_container(CONTAINER_TOOLBAR, _toolbar_btn)

	add_tool_menu_item("Asset Drawer", Callable(self, "_on_menu_toggle"))
	set_process_input(true)

	var es := EditorInterface.get_editor_settings()
	if not es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.connect(_on_settings_changed)


func _create_dock() -> void:
	dock = EditorDock.new()
	dock.title = "Asset Drawer"
	dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	dock.closable = true
	add_dock(dock)
	_create_drawer()
	var icon := _addon_icon()
	if icon != null:
		dock.dock_icon = icon


func _create_drawer() -> void:
	if dock == null:
		return
	drawer = Drawer.new()
	drawer.name = "AssetDrawer"
	dock.add_child(drawer)
	if drawer.has_signal("rebuild_requested") and not drawer.is_connected("rebuild_requested", _rebuild_drawer):
		drawer.connect("rebuild_requested", _rebuild_drawer)


func _toggle_drawer() -> void:
	if dock == null:
		return
	if is_instance_valid(drawer) and drawer.is_open:
		dock.close()
	else:
		dock.open()
		dock.make_visible()


func _on_settings_changed() -> void:
	if _theme_check_queued:
		return
	_theme_check_queued = true
	_check_theme.call_deferred()


func _check_theme() -> void:
	_theme_check_queued = false
	# le thème de l'éditeur a changé : on refait le tiroir pour reprendre les couleurs
	if not is_instance_valid(drawer) or not drawer.palette_changed():
		return
	var was_open: bool = drawer.is_open
	var old := drawer
	drawer = null
	var old_parent := old.get_parent()
	if old_parent != null:
		old_parent.remove_child(old)
	old.queue_free()
	await get_tree().process_frame
	if not is_inside_tree() or dock == null:
		return
	_create_drawer()
	if was_open:
		dock.make_visible()


func _rebuild_drawer() -> void:
	if not is_instance_valid(drawer):
		return
	var was_open: bool = drawer.is_open
	var old := drawer
	drawer = null
	var old_parent := old.get_parent()
	if old_parent != null:
		old_parent.remove_child(old)
	old.queue_free()
	await get_tree().process_frame
	if not is_inside_tree() or dock == null:
		return
	_create_drawer()
	if was_open:
		dock.make_visible()


func _exit_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	if is_instance_valid(es) and es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.disconnect(_on_settings_changed)
	remove_tool_menu_item("Asset Drawer")
	if is_instance_valid(_toolbar_btn):
		remove_control_from_container(CONTAINER_TOOLBAR, _toolbar_btn)
		_toolbar_btn.queue_free()
		_toolbar_btn = null
	if dock != null:
		remove_dock(dock)
		dock.queue_free()
		dock = null
	drawer = null


func _enable_plugin() -> void:
	_after_plugin_enabled.call_deferred()


func _after_plugin_enabled() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(drawer):
		await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(drawer):
		return
	drawer.on_plugin_enabled()


func _addon_icon() -> Texture2D:
	if is_instance_valid(drawer):
		return drawer._addon_icon_tex(16)
	return null


func _get_plugin_icon() -> Texture2D:
	return _addon_icon()


func _on_menu_toggle() -> void:
	_toggle_drawer()


func _is_freelook_active() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(drawer):
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SPACE and key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed and not key.meta_pressed:
		if BLOCK_IN_FREELOOK and _is_freelook_active():
			return
		if not OPEN_IN_CODE_EDITOR:
			var base := EditorInterface.get_base_control()
			var vp: Viewport = base.get_viewport() if base != null else null
			var focus: Control = vp.gui_get_focus_owner() if vp != null else null
			if focus is TextEdit and not drawer.is_ancestor_of(focus):
				return
		_toggle_drawer()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_V and key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed and not key.meta_pressed:
		if drawer.try_paste_resource_at_mouse():
			get_viewport().set_input_as_handled()
