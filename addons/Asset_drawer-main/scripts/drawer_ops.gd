@tool
extends "res://addons/Asset_drawer-main/scripts/drawer_preview.gd"


func _set_folder_color(path: String, color_key: String) -> void:
	var p := path.trim_suffix("/")
	_folder_colors.erase(p)
	_folder_colors.erase(p + "/")
	var colors: Dictionary = _colors().duplicate()
	colors.erase(p)
	colors.erase(p + "/")
	if not color_key.is_empty():
		# un nom de couleur inconnu de Godot rend l'icône transparente, donc on le garde de notre côté
		if color_key in GODOT_COLOR_KEYS:
			colors[p + "/"] = color_key
		else:
			_folder_colors[p + "/"] = color_key
	ProjectSettings.set_setting("file_customization/folder_colors", colors)
	ProjectSettings.save()
	_save_cfg()
	_tree_dirty = true
	_refresh()

# anciennes versions mettaient toutes les couleurs dans les réglages du projet, on sort celles que Godot ne connaît pas
func _migrate_folder_colors() -> void:
	var colors: Dictionary = _colors()
	if colors.is_empty():
		return
	var keep := {}
	var moved := false
	for k in colors.keys():
		if str(colors[k]) in GODOT_COLOR_KEYS:
			keep[k] = colors[k]
		else:
			_folder_colors[k] = colors[k]
			moved = true
	if moved:
		ProjectSettings.set_setting("file_customization/folder_colors", keep)
		ProjectSettings.save()
		_save_cfg()

func _build_index() -> void:
	_index.clear()
	var fs := EditorInterface.get_resource_filesystem().get_filesystem()
	if fs != null:
		_index_dir(fs)
	_index_dirty = false

func _index_dir(dir: EditorFileSystemDirectory) -> void:
	for i in dir.get_subdir_count():
		var sub := dir.get_subdir(i)
		var sname := sub.get_name()
		_index.append([sub.get_path(), "Folder", true, sname, sname.to_lower()])
		_index_dir(sub)
	for i in dir.get_file_count():
		var fname := dir.get_file(i)
		_index.append([dir.get_file_path(i), dir.get_file_type(i), false, fname, fname.to_lower()])

func _search_entries(tokens: PackedStringArray, out: Array) -> void:
	if tokens.is_empty():
		return
	if _index_dirty:
		_build_index()
	var prefix := ""
	if not _search_all:
		prefix = current_dir if current_dir.ends_with("/") else current_dir + "/"
	var check_hidden := not _show_hidden and not _hidden.is_empty()
	var cap := MAX_ITEMS * 4
	var first: String = tokens[0]
	for e in _index:
		var p: String = e[0]
		if prefix != "" and (p == prefix or not p.begins_with(prefix)):
			continue
		var nm: String = e[4]
		if not _name_matches(nm, tokens):
			continue
		if not e[2] and not _pass_filter(p, _selected_filter):
			continue
		if check_hidden and _is_hidden(p):
			continue
		var rank := 2
		if nm.get_basename() == first or nm == first:
			rank = 0
		elif nm.begins_with(first):
			rank = 1
		out.append([p, e[1], e[2], e[3], rank])
		if out.size() > cap:
			break

func _hide_paths(paths: PackedStringArray, hide: bool) -> void:
	for p in paths:
		if p == "res://":
			continue
		var key := _hidden_key(p)
		if hide:
			if not _hidden.has(key):
				_hidden.append(key)
		else:
			var i := _hidden.find(key)
			if i >= 0:
				_hidden.remove_at(i)
	_tree_dirty = true
	_save_cfg()
	_list.deselect_all()
	_refresh()
	if hide and not _show_hidden:
		_flash(L.t("Masqué dans le tiroir · clic droit → « Afficher les éléments masqués »"))
	else:
		_flash(L.t("Masqué dans le tiroir") if hide else L.t("Réaffiché"))

func _set_show_hidden(on: bool) -> void:
	_show_hidden = on
	_tree_dirty = true
	_save_cfg()
	_refresh()

func _scan() -> void:
	EditorInterface.get_resource_filesystem().scan()

func _target_dir() -> String:
	return current_dir

func _create_folder() -> void:
	var dir := _target_dir()
	_prompt_string(L.t("Nouveau dossier"), _unique_path(dir, L.t("nouveau_dossier"), "").get_file(), func(n: String) -> void:
		if not _valid_name(n):
			return
		var p := dir.path_join(n)
		if DirAccess.dir_exists_absolute(p) or FileAccess.file_exists(p):
			_flash(L.t("« %s » existe déjà") % n, true)
			return
		DirAccess.make_dir_recursive_absolute(p)
		_pending_select = p
		_scan()
	)

func _create_scene() -> void:
	var dir := _target_dir()
	_prompt_string(L.t("Nouvelle scène"), _unique_path(dir, L.t("nouvelle_scene"), ".tscn").get_file(), func(n: String) -> void:
		if not _valid_name(n):
			return
		var p := dir.path_join(n if n.ends_with(".tscn") else n + ".tscn")
		if FileAccess.file_exists(p):
			_flash(L.t("« %s » existe déjà") % n, true)
			return
		var node := Node2D.new()
		node.name = p.get_file().get_basename().to_pascal_case()
		var packed := PackedScene.new()
		packed.pack(node)
		ResourceSaver.save(packed, p)
		node.free()
		_pending_select = p
		_scan()
	)

func _has_csharp_project() -> bool:
	var d := DirAccess.open("res://")
	if d == null:
		return false
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.get_extension().to_lower() == "csproj":
			return true
		f = d.get_next()
	return false

func _script_languages() -> Array:
	var out: Array = []
	out.append({"sep": L.t("Scripts")})
	out.append({"name": "GDScript", "ext": "gd"})
	if OS.has_feature("mono"):
		out.append({"name": "C#", "ext": "cs"})
	out.append({"name": L.t("Shader"), "ext": "gdshader"})
	out.append({"sep": L.t("Fichiers texte")})
	out.append({"name": L.t("Texte"), "ext": "txt"})
	out.append({"name": "JSON", "ext": "json"})
	out.append({"name": "Markdown", "ext": "md"})
	out.append({"name": L.t("Configuration"), "ext": "cfg"})
	out.append({"name": "XML", "ext": "xml"})
	out.append({"name": "CSV", "ext": "csv"})
	out.append({"sep": ""})
	out.append({"name": L.t("Personnalisé..."), "ext": ""})
	return out

func _create_script() -> void:
	var dir := _target_dir()
	var langs := _script_languages()

	var d := ConfirmationDialog.new()
	d.title = L.t("Nouveau script")
	d.ok_button_text = L.t("Créer")
	d.cancel_button_text = L.t("Annuler")

	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = 340
	vb.add_theme_constant_override("separation", 8)
	d.add_child(vb)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vb.add_child(lang_row)
	var lang_lbl := Label.new()
	lang_lbl.text = L.t("Langage")
	lang_lbl.custom_minimum_size.x = 70
	lang_row.add_child(lang_lbl)
	var lang_opt := OptionButton.new()
	lang_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry_of_index: Array = []
	for i in langs.size():
		var entry: Dictionary = langs[i]
		if entry.has("sep"):
			lang_opt.add_separator(entry.sep)
			entry_of_index.append(-1)
		else:
			lang_opt.add_item(entry.name)
			entry_of_index.append(i)
	lang_row.add_child(lang_opt)

	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 8)
	custom_row.visible = false
	vb.add_child(custom_row)
	var custom_lbl := Label.new()
	custom_lbl.text = L.t("Extension")
	custom_lbl.custom_minimum_size.x = 70
	custom_row.add_child(custom_lbl)
	var custom_edit := LineEdit.new()
	custom_edit.placeholder_text = "txt"
	custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_row.add_child(custom_edit)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vb.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = L.t("Nom")
	name_lbl.custom_minimum_size.x = 70
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	d.register_text_enter(name_edit)

	var start_idx := 0
	for oi in entry_of_index.size():
		var li: int = entry_of_index[oi]
		if li >= 0:
			start_idx = oi
			if langs[li].ext == _last_script_ext:
				break
	lang_opt.select(start_idx)

	var update_name := func() -> void:
		var entry: Dictionary = langs[entry_of_index[lang_opt.selected]]
		var is_custom: bool = entry.ext.is_empty()
		custom_row.visible = is_custom
		var ext: String = custom_edit.text.strip_edges().trim_prefix(".") if is_custom else entry.ext
		var suffix := ("." + ext) if not ext.is_empty() else ""
		name_edit.text = _unique_path(dir, L.t("nouveau_script"), suffix).get_file().get_basename()
	lang_opt.item_selected.connect(func(_i: int) -> void: update_name.call())
	custom_edit.text_changed.connect(func(_t: String) -> void: update_name.call())
	update_name.call()

	d.confirmed.connect(func() -> void:
		var entry: Dictionary = langs[entry_of_index[lang_opt.selected]]
		var is_custom: bool = entry.ext.is_empty()
		var ext: String = (custom_edit.text.strip_edges().trim_prefix(".").to_lower()) if is_custom else entry.ext
		var base_name := name_edit.text.strip_edges()
		if base_name.is_empty() or ext.is_empty() or not _valid_name(base_name + "." + ext):
			return
		if ext == "cs" and not _has_csharp_project():
			_flash(L.t("Pas de solution C# dans ce projet : créez un premier script C# depuis le dock Fichiers de Godot (il générera le .csproj), puis réessayez ici"), true)
			return
		var fname := base_name + "." + ext
		var p := dir.path_join(fname)
		if FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p):
			_flash(L.t("« %s » existe déjà") % fname, true)
			return
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			_flash(L.t("Impossible de créer « %s »") % fname, true)
			return
		f.store_string(_script_template(ext, base_name))
		f.close()
		_last_script_ext = ext
		_save_cfg()
		_pending_select = p
		_scan()
		if ext == "cs" and EditorInterface.get_resource_filesystem().has_method("scan_sources"):
			EditorInterface.get_resource_filesystem().call("scan_sources")
	)
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free()
	)
	d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(d)
	d.popup_centered(Vector2i(380, 170))
	name_edit.grab_focus()
	name_edit.select_all()

func _rename(path: String) -> void:
	var src := path.trim_suffix("/")
	_prompt_string(L.t("Renommer"), src.get_file(), func(n: String) -> void:
		if not _valid_name(n):
			return
		var dst := src.get_base_dir().path_join(n)
		if dst == src:
			return
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			_flash(L.t("« %s » existe déjà") % n, true)
			return
		EditorInterface.save_all_scenes()
		var is_dir := DirAccess.dir_exists_absolute(src)
		if DirAccess.rename_absolute(src, dst) != OK:
			_flash(L.t("Échec du renommage"), true)
			return
		for ext in [".import", ".uid"]:
			if FileAccess.file_exists(src + ext):
				DirAccess.rename_absolute(src + ext, dst + ext)
		_rewrite_paths(src, dst)
		current_dir = _swap_prefix(current_dir, src, dst)
		for i in _history.size():
			_history[i] = _swap_prefix(_history[i], src, dst)
		_update_references([[src, dst, is_dir]])
		_pending_select = dst
		_scan()
		_flash(L.t("Renommé en « %s »") % n)
	)

func _duplicate(paths: PackedStringArray) -> void:
	var last := ""
	for p in paths:
		var src := p.trim_suffix("/")
		var dir := src.get_base_dir()
		if DirAccess.dir_exists_absolute(src):
			var dst := _unique_path(dir, src.get_file() + L.t("_copie"), "")
			_copy_dir(src, dst)
			last = dst
		else:
			var dst := _unique_path(dir, src.get_file().get_basename() + L.t("_copie"), "." + src.get_extension())
			_copy_file(src, dst)
			last = dst
	_pending_select = last
	_scan()
	_flash(L.t("%d élément(s) dupliqué(s)") % paths.size() if paths.size() > 1 else L.t("Élément dupliqué"))

func _copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		if f.get_extension() == "import" or f.get_extension() == "uid":
			continue
		_copy_file(src.path_join(f), dst.path_join(f))
	for d in DirAccess.get_directories_at(src):
		_copy_dir(src.path_join(d), dst.path_join(d))

func _copy_file(src: String, dst: String) -> void:
	DirAccess.copy_absolute(src, dst)
	if dst.get_extension().to_lower() in ["tscn", "tres"]:
		var text := FileAccess.get_file_as_string(dst)
		var nl := text.find("\n")
		var head := text.substr(0, nl) if nl >= 0 else text
		var a := head.find(" uid=\"")
		if a >= 0:
			var b := head.find("\"", a + 6)
			if b > a:
				var f := FileAccess.open(dst, FileAccess.WRITE)
				if f:
					f.store_string(head.substr(0, a) + head.substr(b + 1) + text.substr(head.length()))
					f.close()

func _confirm_delete(paths: PackedStringArray) -> void:
	var names: PackedStringArray = []
	for p in paths:
		names.append(p.trim_suffix("/").get_file())
	var txt := L.t("Envoyer à la corbeille :\n") + "\n".join(names.slice(0, 8))
	if names.size() > 8:
		txt += "\n... (+%d)" % (names.size() - 8)
	_confirm(L.t("Supprimer"), txt, func() -> void:
		var ok_count := 0
		for p in paths:
			var src := p.trim_suffix("/")
			var err := OS.move_to_trash(ProjectSettings.globalize_path(src))
			if err != OK:
				_flash(L.t("Impossible de mettre « %s » à la corbeille") % src.get_file(), true)
				continue
			for ext in [".import", ".uid"]:
				if FileAccess.file_exists(src + ext):
					OS.move_to_trash(ProjectSettings.globalize_path(src + ext))
			_forget_path(src)
			ok_count += 1
		_save_cfg()
		_scan()
		if ok_count > 0:
			_flash(L.t("%d élément(s) envoyé(s) à la corbeille") % ok_count if ok_count > 1 else L.t("Envoyé à la corbeille"))
	)

func _forget_path(src: String) -> void:
	var fav := Array(_favorites)
	var rec := Array(_recents)
	fav = fav.filter(func(p) -> bool: return not _is_under(str(p), src))
	rec = rec.filter(func(p) -> bool: return not _is_under(str(p), src))
	_favorites = PackedStringArray(fav)
	_push_favorites()
	_recents = PackedStringArray(rec)
	_hidden = PackedStringArray(Array(_hidden).filter(func(p) -> bool: return not _is_under(str(p), src)))
	for k in _sets.keys():
		var arr: Array = _sets[k]
		_sets[k] = arr.filter(func(p) -> bool: return not _is_under(str(p), src))

func _collect_text_files(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		_collect_text_files(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in REF_EXTS:
			out.append(dir.path_join(f))

func _update_references(moves: Array) -> void:
	if moves.is_empty():
		return
	var files: Array = []
	_collect_text_files("res://", files)
	var changed_files := 0
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var new_text := text
		for m in moves:
			var src: String = m[0]
			var dst: String = m[1]
			new_text = new_text.replace('"' + src + '"', '"' + dst + '"')
			if m[2]:
				new_text = new_text.replace('"' + src + "/", '"' + dst + "/")
		if new_text != text:
			var w := FileAccess.open(path, FileAccess.WRITE)
			if w:
				w.store_string(new_text)
				w.close()
				changed_files += 1
	if changed_files > 0:
		for scene in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(scene)

func _rewrite_paths(src: String, dst: String) -> void:
	for i in _favorites.size():
		_favorites[i] = _swap_prefix(_favorites[i], src, dst)
	_push_favorites()
	for i in _recents.size():
		_recents[i] = _swap_prefix(_recents[i], src, dst)
	for i in _hidden.size():
		_hidden[i] = _swap_prefix(_hidden[i], src, dst)
	_tree_dirty = true
	for k in _sets.keys():
		var arr: Array = _sets[k]
		for i in arr.size():
			arr[i] = _swap_prefix(str(arr[i]), src, dst)
	var colors: Dictionary = _colors()
	var nc := {}
	var changed := false
	for k in colors.keys():
		var nk := _swap_prefix(str(k), src, dst)
		changed = changed or nk != str(k)
		nc[nk] = colors[k]
	if changed:
		ProjectSettings.set_setting("file_customization/folder_colors", nc)
		ProjectSettings.save()
	# les couleurs propres au tiroir suivent aussi le dossier déplacé ou renommé
	var own := {}
	for k in _folder_colors.keys():
		own[_swap_prefix(str(k), src, dst)] = _folder_colors[k]
	_folder_colors = own
	_save_cfg()


func _prompt_string(title: String, val: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.ok_button_text = L.t("Valider")
	d.cancel_button_text = L.t("Annuler")
	var le := LineEdit.new()
	le.text = val
	le.custom_minimum_size.x = 320
	d.add_child(le)
	d.register_text_enter(le)
	d.confirmed.connect(func() -> void: on_ok.call(le.text.strip_edges()))
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free()
	)
	d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(d)
	d.popup_centered(Vector2i(360, 100))
	le.grab_focus()
	le.select(0, val.get_basename().length() if val.contains(".") else val.length())

func _confirm(title: String, text: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.ok_button_text = L.t("Confirmer")
	d.cancel_button_text = L.t("Annuler")
	d.confirmed.connect(func() -> void: on_ok.call())
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free()
	)
	d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(d)
	d.popup_centered()


func _sync_favorites() -> void:
	var es := EditorInterface.get_editor_settings()
	if es == null or not es.has_method("get_favorites"):
		return
	var godot_favs := PackedStringArray()
	for p in es.get_favorites():
		var n := str(p)
		n = "res:/" if n == "res://" else n.trim_suffix("/")
		if not godot_favs.has(n):
			godot_favs.append(n)
	if not _fav_migrated:
		_fav_migrated = true
		var added := false
		for p in _favorites:
			if not godot_favs.has(p) and (FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p)):
				godot_favs.append(p)
				added = true
		_favorites = godot_favs
		if added:
			_push_favorites()
		_save_cfg()
		return
	_favorites = godot_favs

func _push_favorites() -> void:
	var es := EditorInterface.get_editor_settings()
	if es == null or not es.has_method("set_favorites"):
		return
	var out := PackedStringArray()
	for p in _favorites:
		if p == "res:/":
			out.append("res://")
		elif DirAccess.dir_exists_absolute(p):
			out.append(p + "/")
		else:
			out.append(p)
	es.set_favorites(out)

func _is_fav(path: String) -> bool:
	return _favorites.has(path.trim_suffix("/"))

func _toggle_favorite(path: String) -> void:
	_sync_favorites()
	var p := path.trim_suffix("/")
	if _favorites.has(p):
		var arr := Array(_favorites)
		arr.erase(p)
		_favorites = PackedStringArray(arr)
	else:
		_favorites.append(p)
	_push_favorites()
	_save_cfg()

func _push_recent(path: String) -> void:
	var arr := Array(_recents)
	arr.erase(path)
	arr.push_front(path)
	if arr.size() > 20:
		arr.resize(20)
	_recents = PackedStringArray(arr)
	_save_cfg()

func _load_cfg() -> void:
	var c := ConfigFile.new()
	if _cfg_read(c):
		current_dir = c.get_value("state", "current_dir", "res://")
		if int(c.get_value("state", "cfg_version", 1)) >= CFG_VERSION:
			_height_ratio = c.get_value("state", "height_ratio", HEIGHT_RATIO)
		_fav_migrated = bool(c.get_value("state", "fav_migrated", false))
		pinned = c.get_value("state", "pinned", false)
		_view_list = c.get_value("state", "view_list", false)
		_details_visible = c.get_value("state", "details_visible", true)
		_favorites = c.get_value("state", "favorites", PackedStringArray())
		_recents = c.get_value("state", "recents", PackedStringArray())
		_sets = c.get_value("state", "sets", {})
		_zoom_grid = float(c.get_value("state", "zoom", 80.0))
		_zoom_list = float(c.get_value("state", "zoom_list", 22.0))
		_details_width = maxf(float(c.get_value("state", "details_width", 190.0)), DETAILS_MIN_WIDTH)
		_hidden = c.get_value("state", "hidden", PackedStringArray())
		_show_hidden = bool(c.get_value("state", "show_hidden", false))
		_search_all = bool(c.get_value("state", "search_all", true))
		_last_script_ext = str(c.get_value("state", "script_ext", "gd"))
		_language = str(c.get_value("state", "language", "auto"))
		_sort_mode = str(c.get_value("state", "sort", "name"))
		_sort_desc = bool(c.get_value("state", "sort_desc", false))
		_folder_colors = c.get_value("state", "folder_colors", {})
		_reload_on_enable = bool(c.get_value("state", "reload_on_enable", true))
		_last_reload_stamp = int(c.get_value("state", "last_reload", 0))
	_history = PackedStringArray([current_dir])
	L.set_override(_language)
	_migrate_folder_colors()
	if _cfg_resave:
		_save_cfg()
		_flush_cfg()

func _save_cfg() -> void:
	_save_dirty = true
	if _save_timer != null and _save_timer.is_inside_tree():
		_save_timer.start()

func _flush_cfg() -> void:
	if not _save_dirty:
		return
	_save_dirty = false
	var c := ConfigFile.new()
	c.set_value("state", "current_dir", current_dir)
	c.set_value("state", "cfg_version", CFG_VERSION)
	c.set_value("state", "fav_migrated", _fav_migrated)
	c.set_value("state", "height_ratio", _height_ratio)
	c.set_value("state", "pinned", pinned)
	c.set_value("state", "view_list", _view_list)
	c.set_value("state", "details_visible", _details_visible)
	c.set_value("state", "favorites", _favorites)
	c.set_value("state", "recents", _recents)
	c.set_value("state", "sets", _sets)
	c.set_value("state", "zoom", _zoom_grid)
	c.set_value("state", "zoom_list", _zoom_list)
	c.set_value("state", "details_width", _details_width)
	c.set_value("state", "hidden", _hidden)
	c.set_value("state", "show_hidden", _show_hidden)
	c.set_value("state", "search_all", _search_all)
	c.set_value("state", "script_ext", _last_script_ext)
	c.set_value("state", "language", _language)
	c.set_value("state", "sort", _sort_mode)
	c.set_value("state", "sort_desc", _sort_desc)
	c.set_value("state", "folder_colors", _folder_colors)
	c.set_value("state", "reload_on_enable", _reload_on_enable)
	c.set_value("state", "last_reload", _last_reload_stamp)
	_cfg_write(c)


# vide exprès, drawer_view.gd la redéfinit (une couche n'appelle que vers le bas)
func _refresh() -> void:
	pass
