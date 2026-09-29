@tool
extends EditorPlugin

const Drawer := preload("res://addons/asset_drawer/drawer.gd")

var drawer: Control
var _toolbar_btn: Button

func _enter_tree() -> void:
	drawer = Drawer.new()
	drawer.name = "AssetDrawer"
	EditorInterface.get_base_control().add_child(drawer)

	_toolbar_btn = Button.new()
	_toolbar_btn.flat = true
	_toolbar_btn.tooltip_text = "Asset Drawer (Ctrl+Espace)"
	_toolbar_btn.focus_mode = Control.FOCUS_NONE
	var base := EditorInterface.get_base_control()
	var icon_name := "FolderBrowse" if base.has_theme_icon("FolderBrowse", "EditorIcons") else "Folder"
	_toolbar_btn.icon = base.get_theme_icon(icon_name, "EditorIcons")
	_toolbar_btn.pressed.connect(func() -> void: drawer.toggle())
	add_control_to_container(CONTAINER_TOOLBAR, _toolbar_btn)

	add_tool_menu_item("Asset Drawer", Callable(self, "_on_menu_toggle"))
	set_process_input(true)


func _exit_tree() -> void:
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


func _input(event: InputEvent) -> void:
	if not is_instance_valid(drawer):
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SPACE and key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed and not key.meta_pressed:
		# Ctrl+Space sert aussi à l'autocomplétion : on laisse l'éditeur de code tranquille.
		var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner()
		if focus is TextEdit and not drawer.is_ancestor_of(focus):
			return
		if focus is CodeEdit and not drawer.is_ancestor_of(focus):
			return
		drawer.toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and drawer.is_open and not drawer.pinned:
		drawer.close()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_V and key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed and not key.meta_pressed:
		# Colle la ressource copiée dans le tiroir sur le champ ressource de l'Inspecteur survolé par la souris.
		if drawer.try_paste_resource_at_mouse():
			get_viewport().set_input_as_handled()
