@tool
extends "res://addons/Asset_drawer-main/scripts/drawer_ops.gd"


func _copy_resource_to_clipboard(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		_flash(L.t("Impossible de copier un dossier comme ressource"), true)
		return
	if not ResourceLoader.exists(path):
		_flash(L.t("Ce fichier n'est pas une ressource Godot"), true)
		return
	var res := load(path)
	if res == null or not (res is Resource):
		_flash(L.t("Impossible de charger la ressource"), true)
		return
	_clip_resource = res
	_clip_resource_name = path.get_file()
	_flash(L.t("« %s » copiée — survolez un champ ressource de l'Inspecteur") % _clip_resource_name)

func _resource_type_matches(res: Resource, allowed: PackedStringArray) -> bool:
	if allowed.is_empty():
		return true
	var script := res.get_script()
	var global_name := ""
	if script is Script and (script as Script).has_method("get_global_name"):
		global_name = (script as Script).get_global_name()
	for t in allowed:
		var tn: String = String(t).strip_edges()
		if tn.is_empty():
			continue
		if res.is_class(tn):
			return true
		if not global_name.is_empty() and global_name == tn:
			return true
	return false

func _picker_under(control: Control) -> EditorResourcePicker:
	var n: Node = control
	while n:
		if n is EditorResourcePicker:
			return n
		n = n.get_parent()
	return null

func _picker_accepts_clip(picker: EditorResourcePicker) -> bool:
	if picker == null or not is_instance_valid(picker) or _clip_resource == null:
		return false
	return picker.editable and _resource_type_matches(_clip_resource, picker.get_allowed_types())

func try_paste_resource_at_mouse() -> bool:
	if _clip_resource == null or not is_instance_valid(_clip_resource):
		_flash(L.t("Aucune ressource copiée : clic droit sur un fichier → « Copier la ressource »"), true)
		return false
	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null
	var picker := _picker_under(hovered)
	if picker == null:
		_flash(L.t("Survolez un champ ressource de l'Inspecteur puis Alt+V"), true)
		return false
	if not picker.editable:
		_flash(L.t("Ce champ n'est pas modifiable"), true)
		return false
	var allowed := picker.get_allowed_types()
	if not _resource_type_matches(_clip_resource, allowed):
		var attendu := ", ".join(allowed) if not allowed.is_empty() else "?"
		_flash(L.t("Type incompatible : ce champ attend « %s »") % attendu, true)
		return false
	picker.set_edited_resource(_clip_resource)
	# set_edited_resource ne prévient pas l'Inspecteur, il faut émettre le signal à la main
	picker.emit_signal("resource_changed", _clip_resource)
	_flash(L.t("« %s » collée dans l'Inspecteur") % _clip_resource_name)
	return true

func _update_paste_pop_hover() -> void:
	if not is_instance_valid(_paste_pop):
		return
	if _clip_resource == null or not is_instance_valid(_clip_resource):
		if _paste_pop.visible:
			_hide_paste_pop()
		return

	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null

	if hovered != null and (hovered == _paste_pop or _paste_pop.is_ancestor_of(hovered)):
		return

	var picker := _picker_under(hovered)
	if not _picker_accepts_clip(picker):
		if _paste_pop.visible:
			_hide_paste_pop()
		return

	var is_new := picker != _paste_target
	_paste_target = picker
	_position_paste_pop(picker)
	if is_new or not _paste_pop.visible:
		_show_paste_pop()

func _position_paste_pop(picker: EditorResourcePicker) -> void:
	if not is_instance_valid(_toast_overlay) or not is_instance_valid(_paste_pop):
		return
	var rect := picker.get_global_rect()
	var origin: Vector2 = _toast_overlay.global_position
	var btn_size := _paste_pop.size

	var x: float = rect.position.x + 2.0
	x = minf(x, rect.position.x + rect.size.x - btn_size.x - 2.0)
	x = maxf(x, rect.position.x + 1.0)
	var y: float = rect.position.y + (rect.size.y - btn_size.y) * 0.5
	y = clampf(y, rect.position.y + 1.0, rect.position.y + maxf(rect.size.y - btn_size.y - 1.0, 1.0))
	var pos := Vector2(x, y) - origin
	_paste_pop.position = pos

func _show_paste_pop() -> void:
	_paste_hiding = false
	if _paste_tween and _paste_tween.is_valid():
		_paste_tween.kill()
	_paste_pop.visible = true
	_paste_pop.pivot_offset = _paste_pop.size * 0.5
	_paste_pop.modulate.a = 0.0
	_paste_pop.scale = Vector2(0.8, 0.8)
	_paste_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_paste_tween.tween_property(_paste_pop, "modulate:a", 1.0, 0.12)
	_paste_tween.parallel().tween_property(_paste_pop, "scale", Vector2.ONE, 0.16)

func _hide_paste_pop() -> void:
	_paste_target = null
	if _paste_hiding or not is_instance_valid(_paste_pop):
		return
	if _paste_tween and _paste_tween.is_valid():
		_paste_tween.kill()
	_paste_hiding = true
	_paste_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_paste_tween.tween_property(_paste_pop, "modulate:a", 0.0, 0.08)
	_paste_tween.tween_callback(func() -> void:
		_paste_hiding = false
		if is_instance_valid(_paste_pop):
			_paste_pop.visible = false
	)

func _on_paste_pop_pressed() -> void:
	if not _picker_accepts_clip(_paste_target):
		_hide_paste_pop()
		return
	_paste_target.set_edited_resource(_clip_resource)
	_paste_target.emit_signal("resource_changed", _clip_resource)
	_flash(L.t("« %s » collée dans l'Inspecteur") % _clip_resource_name)
	_hide_paste_pop()

func _update_copy_pop_hover() -> void:
	if not is_instance_valid(_copy_pop):
		return
	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null

	if hovered != null and (hovered == _copy_pop or _copy_pop.is_ancestor_of(hovered)):
		return
	if hovered == null or not is_instance_valid(_list) or not (hovered == _list or _list.is_ancestor_of(hovered)):
		if _copy_pop.visible:
			_hide_copy_pop()
		return

	var idx := _list.get_item_at_position(_list.get_local_mouse_position(), true)
	if idx < 0:
		if _copy_pop.visible:
			_hide_copy_pop()
		return
	var path := str(_list.get_item_metadata(idx))
	if path.is_empty() or DirAccess.dir_exists_absolute(path) or not ResourceLoader.exists(path):
		if _copy_pop.visible:
			_hide_copy_pop()
		return

	if not _position_copy_pop(idx):
		if _copy_pop.visible:
			_hide_copy_pop()
		return
	var is_new := path != _copy_target_path or not _copy_pop.visible
	_copy_target_path = path
	if is_new:
		_show_copy_pop()

func _position_copy_pop(idx: int) -> bool:
	var item_rect := _item_rect(idx, false)
	var vbar := _list.get_v_scroll_bar()
	var view_w := _list.size.x - (vbar.size.x if vbar.visible else 0.0)
	var view := Rect2(Vector2.ZERO, Vector2(view_w, _list.size.y))
	var vis := item_rect.intersection(view)
	var btn_size := _copy_pop.size
	if vis.size.x < 8.0 or vis.size.y < minf(btn_size.y * 0.6, 10.0):
		return false
	var origin: Vector2 = _toast_overlay.global_position
	var list_origin: Vector2 = _list.global_position

	var x: float = vis.end.x - btn_size.x - 3.0
	x = maxf(x, vis.position.x + 1.0)
	var y: float = vis.position.y + 3.0
	y = minf(y, vis.position.y + maxf(vis.size.y - btn_size.y - 1.0, 1.0))
	x = clampf(x, 0.0, maxf(view_w - btn_size.x, 0.0))
	y = clampf(y, 0.0, maxf(_list.size.y - btn_size.y, 0.0))
	_copy_pop.position = list_origin + Vector2(x, y) - origin
	return true

func _show_copy_pop() -> void:
	_copy_hiding = false
	if _copy_tween and _copy_tween.is_valid():
		_copy_tween.kill()
	_copy_pop.visible = true
	_copy_pop.pivot_offset = _copy_pop.size * 0.5
	_copy_pop.modulate.a = 0.0
	_copy_pop.scale = Vector2(0.8, 0.8)
	_copy_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_copy_tween.tween_property(_copy_pop, "modulate:a", 1.0, 0.12)
	_copy_tween.parallel().tween_property(_copy_pop, "scale", Vector2.ONE, 0.16)

func _hide_copy_pop() -> void:
	_copy_target_path = ""
	if _copy_hiding or not is_instance_valid(_copy_pop):
		return
	if _copy_tween and _copy_tween.is_valid():
		_copy_tween.kill()
	_copy_hiding = true
	_copy_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_copy_tween.tween_property(_copy_pop, "modulate:a", 0.0, 0.08)
	_copy_tween.tween_callback(func() -> void:
		_copy_hiding = false
		if is_instance_valid(_copy_pop):
			_copy_pop.visible = false
	)

func _on_copy_pop_pressed() -> void:
	if _copy_target_path.is_empty():
		_hide_copy_pop()
		return
	_copy_resource_to_clipboard(_copy_target_path)
	_bounce_to(_copy_pop, Vector2(1.2, 1.2), 0.08)
	get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if is_instance_valid(_copy_pop):
			_bounce_to(_copy_pop, Vector2.ONE, 0.14)
	)
