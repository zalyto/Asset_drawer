@tool
extends EditorPlugin

const Drawer := preload("res://addons/asset_drawer/drawer.gd")
const L := preload("res://addons/asset_drawer/lang.gd")

# true  : Ctrl+Espace ouvre le tiroir même quand l'éditeur de script a le focus
#         (l'autocomplétion via Ctrl+Espace est alors remplacée par le tiroir).
# false : dans l'éditeur de script, Ctrl+Espace reste l'autocomplétion.
const OPEN_IN_CODE_EDITOR := true

# true : le raccourci d'ouverture est ignoré tant que la caméra est en free look
#        (clic droit maintenu dans la vue 3D, ou free look basculé avec Shift+F).
#        Ça évite d'ouvrir le tiroir quand Ctrl (descendre) + Espace (monter)
#        sont pressés ensemble pour se déplacer.
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

	# Le tiroir suit le thème de l'éditeur (couleur de base, contraste, accent).
	var es := EditorInterface.get_editor_settings()
	if not es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.connect(_on_settings_changed)


func _create_drawer() -> void:
	drawer = Drawer.new()
	drawer.name = "AssetDrawer"
	EditorInterface.get_base_control().add_child(drawer)


func _on_settings_changed() -> void:
	# Différé : on laisse d'abord l'éditeur régénérer son thème avant de relire les couleurs.
	if _theme_check_queued:
		return
	_theme_check_queued = true
	_check_theme.call_deferred()


func _check_theme() -> void:
	_theme_check_queued = false
	if not is_instance_valid(drawer) or not drawer.palette_changed():
		return
	# Recrée le tiroir avec la nouvelle palette. Son état (dossier, hauteur, favoris...)
	# est déjà dans la config, il est relu par le nouveau tiroir.
	var was_open: bool = drawer.is_open
	var old := drawer
	drawer = null
	old.get_parent().remove_child(old)   # déclenche _exit_tree : sauvegarde + nettoyage
	old.queue_free()
	await get_tree().process_frame       # laisse partir l'ancienne pastille / overlay (mêmes noms)
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
	# Pendant le free look, Godot capture la souris (clic droit maintenu OU free look
	# basculé avec Shift+F). Le test du clic droit sert de filet de sécurité.
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(drawer):
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SPACE and key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed and not key.meta_pressed:
		# Free look actif : on laisse passer la touche à l'éditeur (déplacement de la caméra).
		if BLOCK_IN_FREELOOK and _is_freelook_active():
			return
		# Ctrl+Espace sert aussi à l'autocomplétion : voir OPEN_IN_CODE_EDITOR en haut du fichier.
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
		# Colle la ressource copiée dans le tiroir sur le champ ressource de l'Inspecteur survolé par la souris.
		if drawer.try_paste_resource_at_mouse():
			get_viewport().set_input_as_handled()
