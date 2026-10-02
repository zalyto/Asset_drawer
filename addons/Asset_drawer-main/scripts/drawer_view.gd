@tool
extends "res://addons/Asset_drawer-main/scripts/drawer_clipboard.gd"


func _set_fav_state(path: String) -> void:
	var fav := _is_fav(path)
	_set_btn_label(_btn_fav, L.t("Retirer des favoris") if fav else L.t("Ajouter aux favoris"))
	_btn_fav.icon = _icon_from("Favorites") if fav else _icon_from("NonFavorite,Favorites")
	if fav:
		_tint_btn_icon(_btn_fav, COLOR_FAV)
	else:
		_untint_btn_icon(_btn_fav)

func _sync_details_meta() -> void:
	if _details_type_row == null:
		return
	var has_type := _lbl_type.text != "" and _lbl_type.text != "-"
	var has_size := _lbl_size.text != "" and _lbl_size.text != "-"
	var has_date := _lbl_modified.text != "" and _lbl_modified.text != "-"
	_chip_type.visible = has_type
	_chip_size.visible = has_size
	_chip_date.visible = has_date
	_details_type_row.visible = has_type or has_size or has_date
	var path_on := _details_path.text != "" and _details_path.visible
	var uid_on := _lbl_uid.text != "" and _lbl_uid.text != "-"
	_field_path.visible = path_on
	_field_uid.visible = uid_on
	_details_card_sep.visible = path_on and uid_on
	_details_card.visible = path_on or uid_on
	_details_sep_info.visible = _details_card.visible

func _update_details_layout() -> void:
	if _details_scroll == null or _details_dv == null:
		return
	var avail := _details_scroll.size.y
	if avail <= 0.0 or _details_scroll.size.x < 60.0:
		return
	var n := 0
	for b in _btn_labels.keys():
		if b.visible:
			n += 1
	if n == 0:
		return
	var sep := float(_details_btn_box.get_theme_constant("separation"))
	var box_h := _details_btn_box.get_combined_minimum_size().y
	var btn_h := _btn_open.get_combined_minimum_size().y
	var need := _details_dv.get_combined_minimum_size().y - box_h + n * btn_h + (n - 1) * sep + 12.0
	if not _details_compact:
		if avail < need - 0.5:
			_set_details_compact(true)
	elif avail >= need + 2.0:
		_set_details_compact(false)

func _set_details_compact(on: bool) -> void:
	if _details_compact == on:
		return
	_details_compact = on
	_details_btn_box.vertical = not on
	for b in _btn_labels.keys():
		_apply_btn_mode(b)

func _update_nav_buttons() -> void:
	if _btn_back == null:
		return
	_btn_back.disabled = _history_i <= 0
	_btn_fwd.disabled = _history_i >= _history.size() - 1
	_btn_up.disabled = _active_set.is_empty() and current_dir == "res://"


func _set_filter(idx: int) -> void:
	_selected_filter = idx
	_update_filter_pills()
	_refresh()

func _update_filter_pills() -> void:
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	for i in range(_filter_buttons.size()):
		var b := _filter_buttons[i]
		var active := (i == _selected_filter)
		_flat_button(b)
		b.toggle_mode = true
		b.button_pressed = active
		b.add_theme_color_override("font_color", accent if active else TEXT_SECONDARY)
		b.add_theme_color_override("font_hover_color", accent if active else TEXT_PRIMARY)
		b.add_theme_color_override("font_pressed_color", accent)

func _switch_left_tab(idx: int) -> void:
	_active_left_tab = idx
	_tree.visible = (idx == 0)
	_tree_tools.visible = (idx == 0)
	_tab_list.visible = (idx != 0)
	_btn_new_set.visible = (idx == 3)
	_refresh_left_tab_content()

func _refresh_left_tab_content() -> void:
	if _tree == null:
		return
	if _active_left_tab == 0:
		if _tree_dirty:
			_refresh_tree()
		else:
			_sync_tree_selection()
		return
	var base := EditorInterface.get_base_control()
	_tab_list.clear()
	if _active_left_tab == 3:
		for n in _sets.keys():
			var idx := _tab_list.add_item("%s (%d)" % [n, (_sets[n] as Array).size()], _editor_icon("Groups"))
			_tab_list.set_item_metadata(idx, str(n))
			_tab_list.set_item_tooltip(idx, L.t("Clic droit : supprimer le set"))
		return
	if _active_left_tab == 1:
		_sync_favorites()
	var src: PackedStringArray = _favorites if _active_left_tab == 1 else _recents
	var colors: Dictionary = _all_colors()
	for path in src:
		var is_dir := DirAccess.dir_exists_absolute(path)
		var idx := _tab_list.add_item(path.get_file() if path != "res://" else "res://", _editor_icon("Folder" if is_dir else "File"))
		_tab_list.set_item_metadata(idx, path)
		_tab_list.set_item_tooltip(idx, path + (L.t("\nClic droit : retirer") if _active_left_tab == 1 else ""))
		if is_dir:
			var cn := _resolve_color(colors, path)
			if cn in FOLDER_COLORS:
				_tab_list.set_item_icon_modulate(idx, FOLDER_COLORS[cn])

func _on_tab_list_activated(idx: int) -> void:
	var meta := str(_tab_list.get_item_metadata(idx))
	if _active_left_tab == 3:
		_active_set = meta
		_search.text = ""
		_refresh()
	else:
		_open_path(meta)

func _on_tab_list_clicked(idx: int, _at: Vector2, btn: int) -> void:
	if btn != MOUSE_BUTTON_RIGHT:
		return
	var meta := str(_tab_list.get_item_metadata(idx))
	if _active_left_tab == 1:
		_toggle_favorite(meta)
		_refresh()
	elif _active_left_tab == 3:
		_confirm(L.t("Supprimer le set"), L.t("Supprimer le set « %s » ? (les fichiers ne sont pas touchés)") % meta, func() -> void:
			_sets.erase(meta)
			if _active_set == meta:
				_active_set = ""
			_save_cfg()
			_refresh()
		)


func _refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	_sync_favorites()
	_dirty = false
	var base := EditorInterface.get_base_control()
	var prev_selected := _selected_paths()
	var isz := int(_current_zoom())
	_icon_bucket = _bucket(isz)
	_apply_list_layout()

	_list.clear()
	_path_index.clear()
	_item_colors.clear()
	_dir_paths.clear()
	_file_types.clear()
	_art_ratio.clear()
	_hide_hover()
	var fs := EditorInterface.get_resource_filesystem()
	# dossier supprimé ou masqué : on remonte jusqu'au premier parent valide
	while _active_set.is_empty() and current_dir != "res://" and (fs.get_filesystem_path(current_dir) == null or (not _show_hidden and _is_hidden(current_dir))):
		current_dir = current_dir.trim_suffix("/").get_base_dir()
		if current_dir == "res:":
			current_dir = "res://"
	_refresh_breadcrumbs()
	_update_nav_buttons()
	_refresh_left_tab_content()

	var query := _search.text.strip_edges().to_lower()
	var tokens := query.split(" ", false)
	var entries: Array = []
	if not _active_set.is_empty():
		for p in (_sets.get(_active_set, []) as Array):
			var ps := str(p)
			if not tokens.is_empty() and not _name_matches(ps.trim_suffix("/").get_file().to_lower(), tokens):
				continue
			if DirAccess.dir_exists_absolute(ps):
				entries.append([ps, "Folder", true, ps.trim_suffix("/").get_file()])
			elif FileAccess.file_exists(ps) and _pass_filter(ps, _selected_filter):
				entries.append([ps, fs.get_file_type(ps), false, ps.get_file()])
	elif query.is_empty():
		var dir := fs.get_filesystem_path(current_dir)
		if dir != null:
			for i in dir.get_subdir_count():
				var sub := dir.get_subdir(i)
				if not _show_hidden and _is_hidden(sub.get_path()):
					continue
				entries.append([sub.get_path(), "Folder", true, sub.get_name()])
			for i in dir.get_file_count():
				var fp := dir.get_file_path(i)
				if _pass_filter(fp, _selected_filter) and (_show_hidden or not _is_hidden(fp)):
					entries.append([fp, dir.get_file_type(i), false, dir.get_file(i)])
	else:
		_search_entries(tokens, entries)

	var stats := {}
	if _sort_mode == "date" or _sort_mode == "size":
		for e in entries:
			var ep := str(e[0])
			stats[ep] = [FileAccess.get_modified_time(ep), _file_bytes(ep)]
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		var ra: int = a[4] if a.size() > 4 else 0
		var rb: int = b[4] if b.size() > 4 else 0
		if ra != rb:
			return ra < rb
		if a[2] != b[2]:
			return a[2]
		if _sort_mode == "date" or _sort_mode == "size":
			var col := 0 if _sort_mode == "date" else 1
			var ia: int = int((stats.get(str(a[0]), [0, 0]) as Array)[col])
			var ib: int = int((stats.get(str(b[0]), [0, 0]) as Array)[col])
			if ia != ib:
				return ia > ib if _sort_desc else ia < ib
		else:
			var ka := str(a[3])
			var kb := str(b[3])
			if _sort_mode == "type":
				ka = ("" if a[2] else _type_kind(str(a[0]), str(a[1]))) + "\u0000" + ka
				kb = ("" if b[2] else _type_kind(str(b[0]), str(b[1]))) + "\u0000" + kb
			var cc := ka.naturalnocasecmp_to(kb)
			if cc != 0:
				return cc > 0 if _sort_desc else cc < 0
		return str(a[3]).naturalnocasecmp_to(str(b[3])) < 0
	)
	_truncated = entries.size() > MAX_ITEMS
	if _truncated:
		entries.resize(MAX_ITEMS)

	var custom_colors := _all_colors()
	var folder_tex := _get_hd_folder_icon(_icon_bucket)
	var show_parent := not query.is_empty() and _active_set.is_empty()
	var check_hidden := _show_hidden and not _hidden.is_empty()
	for e in entries:
		var path: String = e[0]
		var type: String = e[1]
		var is_dir: bool = e[2]
		var label: String = e[3]
		var is_hid := check_hidden and _is_hidden(path)
		if show_parent:
			var parent := path.trim_suffix("/").get_base_dir().trim_prefix("res://")
			if parent.is_empty():
				parent = "res://"
			label += ("  ·  " + parent) if _view_list else ("\n" + parent)
		var idx: int
		if is_dir:
			idx = _list.add_item(label, folder_tex)
			var fc := _folder_color(custom_colors, path)
			if is_hid:
				fc.a *= HIDDEN_ALPHA
			_list.set_item_icon_modulate(idx, fc)
			_dir_paths[path] = true
		else:
			_file_types[path] = type
			var tex: Texture2D = _preview_cache.get(path, null)
			if tex == null:
				tex = _get_hd_file_icon(base, path, type, _icon_bucket)
			idx = _list.add_item(label, tex)
			if is_hid:
				_list.set_item_icon_modulate(idx, Color(1, 1, 1, HIDDEN_ALPHA))
		_list.set_item_metadata(idx, path)
		_path_index[path] = idx
		_item_colors.append(Color(0, 0, 0, 0) if is_dir else _type_color(path, type))
		if _is_fav(path):
			_list.set_item_custom_fg_color(idx, COLOR_FAV)
		if is_hid:
			_list.set_item_custom_fg_color(idx, Color(1, 1, 1, HIDDEN_ALPHA))
	var shown := _list.item_count

	var reselect := prev_selected
	if _pending_select != "":
		reselect = PackedStringArray([_pending_select])
	for i in _list.item_count:
		var mp := str(_list.get_item_metadata(i))
		if reselect.has(mp) or reselect.has(mp.trim_suffix("/")):
			_list.select(i, false)
			if _pending_select != "":
				_list.ensure_current_is_visible()
	_pending_select = ""

	_empty_state.visible = (shown == 0)
	_empty_reset.visible = false
	if shown == 0:
		if _selected_filter != 0:
			_empty_lbl.text = L.t("Aucun résultat avec ce filtre")
			_empty_link.visible = false
			_empty_reset.visible = true
		elif not _active_set.is_empty():
			_empty_lbl.text = L.t("Set vide")
			_empty_link.visible = false
		elif not query.is_empty():
			_empty_lbl.text = L.t("Aucun résultat")
			_empty_link.visible = false
		else:
			_empty_lbl.text = L.t("Aucun asset")
			_empty_link.visible = true
	_on_selection_changed(false)
	_schedule_previews()

func _configure_zoom() -> void:
	if _zoom == null:
		return
	_zoom.set_block_signals(true)
	if _view_list:
		_zoom.min_value = 16
		_zoom.max_value = 48
		_zoom.step = 2
		_zoom.value = clampf(_zoom_list, 16.0, 48.0)
		_zoom.tooltip_text = L.t("Taille des icônes en liste (Ctrl+molette)")
	else:
		_zoom.min_value = 48
		_zoom.max_value = 160
		_zoom.step = 8
		_zoom.value = clampf(_zoom_grid, 48.0, 160.0)
		_zoom.tooltip_text = L.t("Taille des miniatures en grille (Ctrl+molette)")
	_zoom.set_block_signals(false)

func _apply_list_layout() -> void:
	var s := int(_current_zoom())
	if _view_list:
		_list.icon_mode = ItemList.ICON_MODE_LEFT
		_list.max_columns = 1
		_list.max_text_lines = 1
		_list.fixed_icon_size = Vector2i(s, s)
		_list.fixed_column_width = 0
	else:
		_list.icon_mode = ItemList.ICON_MODE_TOP
		_list.max_columns = 0
		_list.max_text_lines = 2
		_list.fixed_icon_size = Vector2i(s, s)
		_list.fixed_column_width = s + 28

func _on_details_split_dragged(offset: int) -> void:
	_details_width = maxf(DETAILS_MIN_WIDTH - float(offset), DETAILS_MIN_WIDTH)
	_save_cfg()

func _on_zoom_changed(v: float) -> void:
	if _view_list:
		_zoom_list = v
	else:
		_zoom_grid = v
	_save_cfg()
	if not is_open:
		_dirty = true
		return
	_apply_list_layout()
	if _bucket(int(v)) != _icon_bucket:
		_refresh()
	else:
		_schedule_previews()

func _on_scope_toggled(on: bool) -> void:
	_search_all = on
	_update_search_ui()
	_save_cfg()
	if not _search.text.strip_edges().is_empty():
		_refresh()

func _update_search_ui() -> void:
	if _search != null:
		_search.placeholder_text = L.t("Rechercher dans tout le projet... (Ctrl+F)") if _search_all else L.t("Rechercher dans ce dossier... (Ctrl+F)")
	if _btn_scope != null:
		_btn_scope.tooltip_text = L.t("Recherche : tout le projet (cliquer pour limiter au dossier courant)") if _search_all else L.t("Recherche : dossier courant (cliquer pour chercher dans tout le projet)")

func _selected_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	if _list == null:
		return out
	for i in _list.get_selected_items():
		out.append(str(_list.get_item_metadata(i)))
	return out

func _on_selection_changed(select_in_dock: bool = true) -> void:
	var sel := _selected_paths()
	if sel.size() == 0:
		_update_details(current_dir if _active_set.is_empty() else "res://")
	elif sel.size() == 1:
		if select_in_dock:
			EditorInterface.select_file(sel[0])
		_update_details(sel[0])
	else:
		_context_path = sel[0]
		_details_name.text = L.t("%d éléments sélectionnés") % sel.size()
		_details_path.text = ""
		_lbl_type.text = "-"
		_lbl_size.text = "-"
		_lbl_modified.text = "-"
		_lbl_uid.text = "-"
		_set_preview_tex(null)
		_preview.self_modulate = Color.WHITE
		_details_path.visible = false
		_sync_details_meta()
		_update_details_layout.call_deferred()
	_update_status_bar()


func _build_hover() -> void:
	if _toast_overlay == null:
		return
	_hover_pop = PanelContainer.new()
	_hover_pop.name = "AssetDrawerHover"
	_hover_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_pop.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hover_pop.z_index = 260
	_hover_pop.visible = false
	var style := _native_popup_sb()
	if style != null:
		_hover_pop.add_theme_stylebox_override("panel", style)
	var pad := _pad(10, 8)
	_hover_pop.add_child(pad)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	pad.add_child(row)
	_hover_tex = TextureRect.new()
	_hover_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tex.custom_minimum_size = Vector2(HOVER_PREVIEW, HOVER_PREVIEW)
	_hover_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hover_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_hover_tex)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_hover_title = Label.new()
	_hover_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_title.custom_minimum_size = Vector2(HOVER_TEXT_W, 0)
	col.add_child(_hover_title)
	_hover_info = Label.new()
	_hover_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_info.modulate = TEXT_SECONDARY
	col.add_child(_hover_info)
	_hover_path_lbl = Label.new()
	_hover_path_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_path_lbl.modulate = TEXT_MUTED
	_hover_path_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hover_path_lbl.custom_minimum_size = Vector2(HOVER_TEXT_W, 0)
	col.add_child(_hover_path_lbl)
	_hover_meta = Label.new()
	_hover_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_meta.modulate = TEXT_MUTED
	col.add_child(_hover_meta)
	_toast_overlay.add_child(_hover_pop)
	_hover_timer = _make_timer(HOVER_DELAY, _show_hover)

func _on_hover_motion(pos: Vector2) -> void:
	if _hover_pop == null or _list == null or not is_open or _mq_active:
		return
	var i := _list.get_item_at_position(pos, false)
	if i < 0 or i >= _list.item_count:
		_hide_hover()
		return
	var path := str(_list.get_item_metadata(i))
	if path == _hover_path:
		return
	_hide_hover()
	_hover_path = path
	if _hover_timer != null:
		_hover_timer.start()

func _hide_hover() -> void:
	_hover_path = ""
	if _hover_timer != null:
		_hover_timer.stop()
	if is_instance_valid(_hover_pop):
		_hover_pop.visible = false

func _show_hover() -> void:
	if _hover_path.is_empty() or not is_open or _toast_overlay == null:
		return
	if not is_instance_valid(_hover_pop):
		return
	var path := _hover_path
	var is_dir := _dir_paths.has(path)
	var shown := path if path != "res://" else "res://"
	if is_dir and path != "res://":
		shown = path.trim_suffix("/").get_file()
	_hover_title.text = _soft_wrap(shown)
	_hover_title.add_theme_color_override("font_color", COLOR_FAV if _is_fav(path) else Color.WHITE)
	var type_txt := ""
	var bits := PackedStringArray()
	var tex: Texture2D = null
	if is_dir:
		var n := DirAccess.get_directories_at(path).size() + DirAccess.get_files_at(path).size()
		type_txt = L.t("Dossier")
		bits.append(L.t("%d élément%s") % [n, "s" if n > 1 else ""])
		tex = _get_hd_folder_icon(HOVER_PREVIEW)
		_hover_tex.self_modulate = _folder_color(_all_colors(), path)
	else:
		var t := str(_file_types.get(path, ""))
		if t.is_empty():
			t = EditorInterface.get_resource_filesystem().get_file_type(path)
		type_txt = t if not t.is_empty() else path.get_extension().to_upper()
		tex = _preview_cache.get(path, null)
		if tex == null:
			tex = _get_hd_file_icon(EditorInterface.get_base_control(), path, t, HOVER_PREVIEW)
		_hover_tex.self_modulate = Color.WHITE
		var bytes := _file_bytes(path)
		if bytes >= 0:
			bits.append(_fmt_size(bytes))
		var mtime := FileAccess.get_modified_time(path)
		if mtime > 0:
			bits.append(L.t("Modifié") + " " + _rel_time(mtime))
	if _is_hidden(path):
		bits.append(L.t("Masqué dans le tiroir"))
	_hover_tex.texture = tex
	_hover_info.text = type_txt
	_hover_path_lbl.text = path
	_hover_meta.text = "  ·  ".join(bits)
	_hover_pop.visible = true
	_hover_pop.reset_size()
	_hover_pop.size = _hover_pop.get_combined_minimum_size()
	var ov: Vector2 = _toast_overlay.size
	var sz: Vector2 = _hover_pop.size
	var pos: Vector2 = _toast_overlay.get_local_mouse_position() + Vector2(16, 12)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, ov.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, ov.y - sz.y - 4.0))
	_hover_pop.position = pos
	_hover_pop.modulate.a = 0.0
	create_tween().tween_property(_hover_pop, "modulate:a", 1.0, 0.08)

func _update_details(path: String) -> void:
	_context_path = path
	var is_dir := DirAccess.dir_exists_absolute(path)
	_details_name.text = _soft_wrap("res://" if path == "res://" else path.trim_suffix("/").get_file())
	_details_path.text = _soft_wrap(path)
	_details_path.visible = path != "res://"
	if is_dir:
		_lbl_type.text = L.t("Dossier")
		var n := DirAccess.get_directories_at(path).size() + DirAccess.get_files_at(path).size()
		_lbl_size.text = L.t("%d élément%s") % [n, "s" if n > 1 else ""]
		_lbl_modified.text = "-"
		_lbl_uid.text = "-"
		_set_preview_tex(_get_hd_folder_icon(96))
		_preview.self_modulate = _folder_color(_all_colors(), path)
	else:
		var t := EditorInterface.get_resource_filesystem().get_file_type(path)
		_preview.self_modulate = Color.WHITE
		_lbl_type.text = t if t != "" else path.get_extension().to_upper()
		_lbl_size.text = "-"
		_lbl_modified.text = "-"
		_lbl_uid.text = "-"
		if FileAccess.file_exists(path):
			var bytes := _file_bytes(path)
			if bytes >= 0:
				_lbl_size.text = _fmt_size(bytes)
			var mtime := FileAccess.get_modified_time(path)
			if mtime > 0:
				_lbl_modified.text = _rel_time(mtime)
			if ResourceLoader.has_method("get_resource_uid"):
				var uid: int = ResourceLoader.call("get_resource_uid", path)
				if uid != -1:
					_lbl_uid.text = ResourceUID.id_to_text(uid)
			var cached = _preview_cache.get(path, null)
			if cached != null:
				_set_preview_tex(cached)
			else:
				_set_preview_tex(_get_hd_file_icon(EditorInterface.get_base_control(), path, t, 96))
				var previewer := EditorInterface.get_resource_previewer()
				if previewer != null and not _preview_pending.has(path) and _kind_has_preview(path, t):
					_preview_pending[path] = true
					previewer.queue_resource_preview(path, self, "_on_preview", path)
	_set_fav_state(path)
	if is_instance_valid(_btn_copy_res):
		_btn_copy_res.visible = not is_dir
	_sync_details_meta()
	_update_details_layout.call_deferred()

func _refresh_breadcrumbs() -> void:
	var editing := _path_edit != null and _path_edit.visible
	for c in _breadcrumbs.get_children():
		if c == _path_edit:
			continue
		_breadcrumbs.remove_child(c)
		c.queue_free()
	var bold := EditorInterface.get_base_control().get_theme_font("bold", "EditorFonts")
	var parts: Array = []
	if not _active_set.is_empty():
		parts.append(["Sets", ""])
		parts.append([_active_set, ""])
	else:
		var segs := current_dir.split("/", false)
		var build := ""
		for i in range(segs.size()):
			if i == 0 and segs[i] == "res:":
				build = "res://"
				parts.append(["res://", build])
			else:
				build += segs[i] + "/"
				parts.append([segs[i], build])
	for i in range(parts.size()):
		var btn := Button.new()
		btn.text = parts[i][0]
		_style_ghost_button(btn, 6, 2)
		
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", bold)
		var target: String = parts[i][1]
		if target != "":
			btn.pressed.connect(func() -> void: _navigate(target))
		else:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_breadcrumbs.add_child(btn)
		if i < parts.size() - 1:
			var sep := Label.new()
			sep.text = "›"
			sep.modulate = TEXT_MUTED
			_breadcrumbs.add_child(sep)
	for c in _breadcrumbs.get_children():
		if c != _path_edit:
			c.visible = not editing

func _refresh_tree() -> void:
	_tree_dirty = false
	_syncing_tree = true
	_tree.clear()
	_tree_items.clear()
	_sticky_sig = ""
	_row_pitch = 0.0
	_pending_reveal = null
	var fs := EditorInterface.get_resource_filesystem().get_filesystem()
	if fs == null:
		_syncing_tree = false
		return
	var icon := _editor_icon("Folder")
	var root := _tree.create_item()
	root.set_text(0, "res://")
	root.set_metadata(0, "res://")
	root.set_icon(0, icon)
	_tree_items["res:/"] = root
	_fill_tree(root, fs, _all_colors(), icon)
	_syncing_tree = false
	_sync_tree_selection()

func _sync_tree_selection() -> void:
	if _tree == null or not _active_set.is_empty():
		return
	var target: TreeItem = _tree_items.get(current_dir.trim_suffix("/"), null)
	if target == null:
		return
	_syncing_tree = true
	var p := target.get_parent()
	while p != null:
		p.collapsed = false
		p = p.get_parent()
	target.select(0)
	_syncing_tree = false
	_reveal_tree_item.call_deferred(target)

func _fill_tree(parent: TreeItem, dir: EditorFileSystemDirectory, colors: Dictionary, icon: Texture2D) -> void:
	for i in dir.get_subdir_count():
		var sub := dir.get_subdir(i)
		var is_hid := _is_hidden(sub.get_path())
		if is_hid and not _show_hidden:
			continue
		var item := _tree.create_item(parent)
		item.set_text(0, sub.get_name())
		item.set_metadata(0, sub.get_path())
		item.set_icon(0, icon)
		var tint := _folder_color(colors, sub.get_path())
		if is_hid:
			tint.a *= HIDDEN_ALPHA
			item.set_custom_color(0, Color(1, 1, 1, HIDDEN_ALPHA))
		item.set_icon_modulate(0, tint)
		_tree_items[sub.get_path().trim_suffix("/")] = item
		_fill_tree(item, sub, colors, icon)
		item.collapsed = bool(_collapsed.get(sub.get_path(), true))

func _find_tree_item(item: TreeItem, path: String) -> TreeItem:
	var want := path.trim_suffix("/")
	if str(item.get_metadata(0)).trim_suffix("/") == want:
		return item
	for c in item.get_children():
		var r := _find_tree_item(c, path)
		if r:
			return r
	return null

func _on_tree_selected() -> void:
	if _syncing_tree:
		return
	var item := _tree.get_selected()
	if item:
		var p := str(item.get_metadata(0))
		if _active_set.is_empty() and p.trim_suffix("/") == current_dir.trim_suffix("/"):
			return
		_navigate.call_deferred(p)

func _get_row_pitch() -> float:
	if _row_pitch > 0.0:
		return _row_pitch
	var last: TreeItem = _tree.get_item_at_position(Vector2(4.0, 0.0))
	if last == null:
		return 0.0
	var edges: Array[int] = []
	for y in range(1, 200):
		var it: TreeItem = _tree.get_item_at_position(Vector2(4.0, float(y)))
		if it == null:
			break
		if it != last:
			edges.append(y)
			last = it
			if edges.size() == 2:
				break
	if edges.size() == 2 and edges[1] - edges[0] >= 8:
		_row_pitch = float(edges[1] - edges[0])
	return _row_pitch

func _item_depth(item: TreeItem) -> int:
	var d := 0
	var p := item.get_parent()
	while p != null:
		d += 1
		p = p.get_parent()
	return d

func _row_index(target: TreeItem) -> int:
	var idx := 0
	var it: TreeItem = _tree.get_root()
	while it != null:
		if it == target:
			return idx
		idx += 1
		it = it.get_next_visible()
	return -1

func _compute_sticky_chain() -> Array:
	var chain: Array = []
	if _tree.get_root() == null or _tree.get_scroll().y < 1.0:
		return chain
	var pitch := _get_row_pitch()
	if pitch <= 0.0:
		return chain
	var slot := _sticky_row_h(pitch)
	var k := 0
	for _i in range(STICKY_MAX + 1):
		var probe: TreeItem = _tree.get_item_at_position(Vector2(4.0, k * slot + 1.0))
		if probe == null:
			break
		var cand: Array = []
		var p := probe.get_parent()
		while p != null:
			cand.push_front(p)
			p = p.get_parent()
		if cand.size() > STICKY_MAX:
			cand = cand.slice(cand.size() - STICKY_MAX)
		chain = cand
		if cand.size() == k:
			break
		k = cand.size()
	return chain

func _update_sticky() -> void:
	if _sticky_box == null:
		return
	var pitch := _get_row_pitch()
	if _pending_reveal != null:
		var pr := _pending_reveal
		if pitch > 0.0:
			_pending_reveal = null
			if is_instance_valid(pr):
				_reveal_tree_item(pr)
	if _tree.get_scroll().y < 1.0:
		if _sticky_box.visible:
			_sticky_box.visible = false
			_sticky_sig = ""
		return
	var chain := _compute_sticky_chain()
	var w := _tree.size.x
	if _tree_vscroll != null and _tree_vscroll.visible:
		w -= _tree_vscroll.size.x
	var sig := "%d#%s#%d" % [int(w), current_dir, int(pitch)]
	for it in chain:
		sig += "|" + str(it.get_metadata(0))
	if sig == _sticky_sig:
		return
	_sticky_sig = sig
	_rebuild_sticky(chain, w, pitch)

func _sticky_row_h(pitch: float) -> float:
	return pitch

func _rebuild_sticky(chain: Array, w: float, pitch: float) -> void:
	for c in _sticky_box.get_children():
		_sticky_box.remove_child(c)
		c.queue_free()
	if chain.is_empty() or pitch <= 0.0:
		_sticky_box.visible = false
		return
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var margin := maxi(_tree.get_theme_constant("item_margin"), 8)
	var slot := _sticky_row_h(pitch)
	var y := 0.0
	for it in chain:
		var r := _make_sticky_row(it, pitch, margin, accent)
		_sticky_box.add_child(r)
		r.position = Vector2(0.0, y)
		r.size = Vector2(w, slot)
		y += slot
	var line := ColorRect.new()
	line.color = Color(accent.r, accent.g, accent.b, 0.55)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticky_box.add_child(line)
	line.position = Vector2(0.0, y)
	line.size = Vector2(w, 1.0)
	_sticky_box.position = Vector2.ZERO
	_sticky_box.size = Vector2(w, y + 1.0)
	_sticky_box.visible = true

func _sticky_row_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_bottom = 1
	s.border_color = Color(0, 0, 0, 0.35)
	return s

func _make_sticky_row(it: TreeItem, pitch: float, margin: int, accent: Color) -> Control:
	var path := str(it.get_metadata(0))
	var depth := _item_depth(it)
	var slot := _sticky_row_h(pitch)
	var is_cur := path.trim_suffix("/") == current_dir.trim_suffix("/")
	var bg := _hover_c(COLOR_LEFT_PANEL)
	if is_cur:
		bg = bg.lerp(accent, 0.30)
	bg.a = 1.0
	var hover_bg := _hover_c(bg)
	hover_bg.a = 1.0
	var sb_normal := _sticky_row_style(bg)
	var sb_hover := _sticky_row_style(hover_bg)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, slot)
	row.clip_contents = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = path
	row.add_theme_stylebox_override("panel", sb_normal)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", sb_hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", sb_normal))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", depth * margin + 4)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(hb)

	var arrow := TextureRect.new()
	arrow.custom_minimum_size = Vector2(margin, 0)
	arrow.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tree.has_theme_icon("arrow", "Tree"):
		arrow.texture = _tree.get_theme_icon("arrow", "Tree")
	hb.add_child(arrow)

	var icon := TextureRect.new()
	icon.texture = it.get_icon(0)
	icon.modulate = it.get_icon_modulate(0)
	var isz := clampf(slot - 6.0, 10.0, 20.0)
	icon.custom_minimum_size = Vector2(isz, isz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)

	var lbl := Label.new()
	lbl.text = it.get_text(0)
	lbl.clip_text = true
	
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)

	var arrow_end := float(depth * margin + margin + 2)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
				return
			row.accept_event()
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				if mb.position.x < arrow_end:
					_on_sticky_arrow(path)
				else:
					_on_sticky_clicked(path)
		elif ev is InputEventMouseMotion:
			row.accept_event()
	)
	return row

func _sticky_item(path: String) -> TreeItem:
	var v: Variant = _tree_items.get(path.trim_suffix("/"), null)
	if v != null and is_instance_valid(v):
		return v as TreeItem
	return null

func _on_sticky_clicked(path: String) -> void:
	if path.trim_suffix("/") != current_dir.trim_suffix("/"):
		_navigate.call_deferred(path)
	var it := _sticky_item(path)
	if it != null:
		_reveal_tree_item.call_deferred(it)

func _on_sticky_arrow(path: String) -> void:
	var it := _sticky_item(path)
	if it == null:
		return
	it.collapsed = true
	_reveal_tree_item.call_deferred(it)

func _reveal_tree_item(item: TreeItem) -> void:
	if item == null or not is_instance_valid(item) or _tree == null:
		return
	_tree.scroll_to_item(item)
	if _tree_vscroll == null:
		return
	var pitch := _get_row_pitch()
	if pitch <= 0.0:
		_pending_reveal = item
		return
	var idx := _row_index(item)
	if idx < 0:
		return
	var need := mini(_item_depth(item), STICKY_MAX) * _sticky_row_h(pitch)
	var y_top := idx * pitch - _tree.get_scroll().y
	if y_top < need - 0.5:
		_tree_vscroll.value = maxf(0.0, _tree_vscroll.value - (need - y_top))

func _on_tree_gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or mb.double_click:
		return
	var item := _tree.get_item_at_position(mb.position)
	if item == null:
		return
	var path := str(item.get_metadata(0))
	var was_current := path.trim_suffix("/") == current_dir.trim_suffix("/")
	# on laisse Godot plier/déplier l'item d'abord, on regarde après ce qui a changé
	_after_tree_click.call_deferred(item, item.collapsed, was_current)

func _after_tree_click(item: TreeItem, was_collapsed: bool, was_current: bool) -> void:
	if not is_instance_valid(item) or item.collapsed != was_collapsed:
		return
	var path := str(item.get_metadata(0))
	if item.get_first_child() != null:
		if was_current:
			item.collapsed = not was_collapsed
		elif was_collapsed:
			item.collapsed = false
	_center_tree_item_soon(path)

func _center_tree_item_soon(path: String) -> void:
	# deux frames, sinon l'arbre n'a pas encore sa nouvelle taille
	await get_tree().process_frame
	await get_tree().process_frame
	_center_tree_item(_sticky_item(path))

func _center_tree_item(item: TreeItem) -> void:
	if item == null or not is_instance_valid(item) or _tree_vscroll == null:
		return
	if not _tree.is_visible_in_tree():
		return
	var pitch := _get_row_pitch()
	if pitch <= 0.0:
		return
	var idx := _row_index(item)
	if idx < 0:
		return
	var reserved := mini(_item_depth(item), STICKY_MAX) * _sticky_row_h(pitch)
	var available := maxf(_tree.size.y - reserved, pitch)
	var context_rows := mini(idx, floori((available * 0.5) / pitch))
	var target := (idx - context_rows) * pitch - reserved
	var max_v := maxf(0.0, _tree_vscroll.max_value - _tree_vscroll.page)
	target = clampf(target, 0.0, max_v)
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_tween = create_tween()
	_center_tween.tween_property(_tree_vscroll, "value", target, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _collapse_all_folders() -> void:
	var root := _tree.get_root()
	if root == null:
		return
	for c in root.get_children():
		_collapse_rec(c)
	_sync_tree_selection()

func _collapse_rec(it: TreeItem) -> void:
	for c in it.get_children():
		_collapse_rec(c)
	if not it.collapsed:
		it.collapsed = true


func toggle() -> void:
	if _is_docked():
		return
	if is_open:
		close()
	elif Time.get_ticks_msec() - _outside_close_msec > 250:
		open()

func open() -> void:
	if _is_docked():
		return
	var base := EditorInterface.get_base_control()
	_sync_favorites()
	is_open = true
	_set_hint_visible(false)
	_layout(base)
	position.y = base.size.y + 20.0
	modulate.a = 0.0
	scale = Vector2(0.965, 0.935)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	visible = true
	if _dirty:
		_refresh()
	else:
		_schedule_previews()
	_animate_open(base)
	_list.grab_focus()

func close() -> void:
	if _is_docked():
		if _ctx_popup != null:
			_ctx_popup.hide()
		return
	if not is_open:
		return
	is_open = false
	_hide_hover()
	_hide_gear_panel()
	_flush_cfg()
	if _ctx_popup != null:
		_ctx_popup.hide()
	var base := EditorInterface.get_base_control()
	if base == null:
		visible = false
		scale = Vector2.ONE
		_set_hint_visible(true)
		return
	_animate_close(base)
	if _tween == null:
		return
	_tween.finished.connect(func() -> void:
		if not is_open:
			visible = false
			scale = Vector2.ONE
			_set_hint_visible(true)
	, CONNECT_ONE_SHOT)

func _open_y(base: Control) -> float:
	return base.size.y - size.y - BOTTOM_GAP

func _layout(base: Control) -> void:
	var h := clampf(base.size.y * _height_ratio, MIN_HEIGHT, base.size.y * 0.85)
	var w := maxf(minf(base.size.x - SIDE_GAP * 2.0, MAX_WIDTH), 320.0)
	size = Vector2(w, h)
	position.x = (base.size.x - size.x) * 0.5
	position.y = _open_y(base) if is_open else base.size.y + 20.0

func _on_editor_resized() -> void:
	if _is_docked():
		return
	_layout_hint()
	if is_inside_tree() and is_open:
		_layout(EditorInterface.get_base_control())


func _build_hint(base: Control) -> void:
	var accent: Color = base.get_theme_color("accent_color", "Editor")
	_hint = PanelContainer.new()
	_hint.name = "AssetDrawerHint"
	_hint.z_index = 200
	_hint.z_as_relative = false
	_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint.modulate.a = 0.65
	_hint.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hint.tooltip_text = L.t("Cliquer pour ouvrir le tiroir d'assets")
	var hint_style := _make_stylebox(COLOR_HEADER, Color(accent.r, accent.g, accent.b, 0.7), 8, 1)
	_hint.add_theme_stylebox_override("panel", hint_style)
	var pad := _pad(10, 4)
	_hint.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pad.add_child(row)
	var title := Label.new()
	title.text = "Asset Drawer"
	title.add_theme_font_override("font", base.get_theme_font("bold", "EditorFonts"))
	
	row.add_child(title)
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", _make_stylebox(_ov(0.06), _ov(0.25), 4, 1))
	var key_pad := _pad(6, 1)
	key.add_child(key_pad)
	var key_lbl := Label.new()
	key_lbl.text = L.t("Ctrl+Espace")
	key_lbl.modulate = Color(1, 1, 1, 0.8)
	
	key_pad.add_child(key_lbl)
	row.add_child(key)
	_ignore_mouse(pad)

	_hint.mouse_entered.connect(func() -> void: _hint.modulate.a = 1.0)
	_hint.mouse_exited.connect(func() -> void: _hint.modulate.a = 0.65)
	_hint.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			open()
	)
	base.add_child(_hint)
	_layout_hint.call_deferred()
	_breathe_hint(hint_style, accent)

func _breathe_hint(style: StyleBoxFlat, accent: Color) -> void:
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween().set_loops()
	_hint_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(style, "border_color", Color(accent.r, accent.g, accent.b, 0.95), 1.4)
	_hint_tween.tween_property(style, "border_color", Color(accent.r, accent.g, accent.b, 0.45), 1.4)

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)

func _layout_hint() -> void:
	if not is_instance_valid(_hint):
		return
	var base := EditorInterface.get_base_control()
	var sz := _hint.get_combined_minimum_size()
	_hint.size = sz
	_hint.position = Vector2((base.size.x - sz.x) * 0.5, base.size.y - sz.y - HINT_BOTTOM)

func _set_hint_visible(on: bool) -> void:
	if is_instance_valid(_hint):
		_hint.visible = on
		if on:
			_layout_hint()

func _animate_open(base: Control) -> void:
	if _tween:
		_tween.kill()
	pivot_offset = Vector2(size.x * 0.5, size.y)
	var dur := ANIM_TIME * 1.4
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:y", _open_y(base), dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, dur * 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_pulse_glow)

func _animate_close(base: Control) -> void:
	if _tween:
		_tween.kill()
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	var dur := ANIM_TIME * 0.85
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "position:y", base.size.y + 20.0, dur)
	_tween.tween_property(self, "scale", Vector2(0.972, 0.955), dur)
	_tween.tween_property(self, "modulate:a", 0.0, dur * 0.85)

func _pulse_glow() -> void:
	if _panel_style == null or not is_open:
		return
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_panel_style.shadow_size = 12
	_glow_tween = create_tween()
	_glow_tween.set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_panel_style, "shadow_color", Color(accent.r, accent.g, accent.b, 0.35), 0.15).set_ease(Tween.EASE_OUT)
	_glow_tween.parallel().tween_property(_panel_style, "shadow_size", 16.0, 0.15).set_ease(Tween.EASE_OUT)
	_glow_tween.tween_property(_panel_style, "shadow_color", Color(0, 0, 0, 0.30), 0.6).set_ease(Tween.EASE_IN)
	_glow_tween.parallel().tween_property(_panel_style, "shadow_size", 12.0, 0.6).set_ease(Tween.EASE_IN)

func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if not event.pressed:
			_save_cfg()
	elif event is InputEventMouseMotion and _resizing:
		var base := EditorInterface.get_base_control()
		var new_h: float = base.size.y - BOTTOM_GAP - (position.y + event.relative.y)
		_height_ratio = clampf(new_h / base.size.y, 0.04, 0.85)
		_layout(base)


func _navigate(path: String) -> void:
	var dir := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	if dir == "res:":
		dir = "res://"
	current_dir = dir
	_active_set = ""
	_search.text = ""
	if _history_i < _history.size() - 1:
		_history.resize(_history_i + 1)
	if _history[_history_i] != current_dir:
		_history.append(current_dir)
		_history_i = _history.size() - 1
	_refresh()
	_save_cfg()

func _hist_go(delta: int) -> void:
	var ni := _history_i + delta
	if ni >= 0 and ni < _history.size():
		_history_i = ni
		current_dir = _history[_history_i]
		_active_set = ""
		_search.text = ""
		_refresh()

func _go_up() -> void:
	if not _active_set.is_empty():
		_active_set = ""
		_refresh()
	elif current_dir != "res://":
		_navigate(current_dir.trim_suffix("/").get_base_dir())

func _show_in_dock(path: String) -> void:
	var dock := EditorInterface.get_file_system_dock()
	if dock and dock.has_method("navigate_to_path"):
		dock.navigate_to_path(path)

func _on_item_activated(index: int) -> void:
	_open_path(str(_list.get_item_metadata(index)))

func _is_model(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_EXTS

func _is_model_scene(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_SCENE_EXTS

func _show_import_settings(path: String) -> void:
	EditorInterface.select_file(path)
	get_tree().create_timer(0.08).timeout.connect(_focus_import_dock)
	if not pinned:
		close()

func _focus_import_dock() -> void:
	var dock := _find_node_by_class(EditorInterface.get_base_control(), "ImportDock")
	if dock == null:
		return
	var child: Node = dock
	var parent: Node = dock.get_parent()
	while parent != null and not (parent is TabContainer):
		child = parent
		parent = parent.get_parent()
	if parent is TabContainer and child is Control:
		var tc := parent as TabContainer
		var idx := tc.get_tab_idx_from_control(child as Control)
		if idx >= 0:
			tc.current_tab = idx

func _find_node_by_class(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find_node_by_class(c, cls)
		if r != null:
			return r
	return null

func _open_advanced_import(path: String) -> void:
	if not _is_model_scene(path):
		_show_import_settings(path)
		return
	EditorInterface.select_file(path)
	if not pinned:
		close()
	_try_advanced_import(path, 0)

func _try_advanced_import(path: String, attempt: int) -> void:
	await get_tree().create_timer(0.15).timeout
	if _activate_in_filesystem_dock(path):
		return
	var dock := _find_node_by_class(EditorInterface.get_base_control(), "ImportDock")
	if dock != null and _import_dock_shows(dock, path):
		var btn := _find_advanced_button(dock)
		if btn != null:
			btn.pressed.emit()
			return
	if attempt < 12:
		_try_advanced_import(path, attempt + 1)
	else:
		_focus_import_dock()
		_flash(L.t("Import avancé indisponible pour ce fichier"), true)

func _activate_in_filesystem_dock(path: String) -> bool:
	var fsd: Node = EditorInterface.get_file_system_dock()
	if fsd == null:
		return false
	return _activate_in_node(fsd, path)

func _activate_in_node(n: Node, path: String) -> bool:
	if n is ItemList:
		var il := n as ItemList
		for i in il.item_count:
			var m: Variant = il.get_item_metadata(i)
			if (m is String or m is StringName) and str(m) == path:
				il.select(i)
				il.item_activated.emit(i)
				return true
	elif n is Tree:
		var t := n as Tree
		var root := t.get_root()
		if root != null:
			var it := _find_fs_tree_item(root, path)
			if it != null:
				it.select(0)
				t.item_activated.emit()
				return true
	for c in n.get_children():
		if _activate_in_node(c, path):
			return true
	return false

func _find_fs_tree_item(item: TreeItem, path: String) -> TreeItem:
	var m: Variant = item.get_metadata(0)
	if (m is String or m is StringName) and str(m) == path:
		return item
	for c in item.get_children():
		var r := _find_fs_tree_item(c, path)
		if r != null:
			return r
	return null

func _import_dock_shows(n: Node, path: String) -> bool:
	if n is Label and (n as Label).text.contains(path.get_file()):
		return true
	for c in n.get_children():
		if _import_dock_shows(c, path):
			return true
	return false

func _find_advanced_button(root: Node) -> Button:
	var buttons: Array[Button] = []
	_collect_buttons(root, buttons)
	for b in buttons:
		var t := b.text.strip_edges()
		if b.visible and not b.disabled and (t.begins_with("Advanced") or t.begins_with("Avanc")):
			return b
	for b in buttons:
		var t := b.text.strip_edges()
		if b.visible and not b.disabled and b.get_class() == "Button" and (t.ends_with("...") or t.ends_with("…")):
			return b
	return null

func _collect_buttons(n: Node, out: Array[Button]) -> void:
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		_collect_buttons(c, out)

func _new_inherited_scene(path: String) -> void:
	EditorInterface.open_scene_from_path(path)
	if not pinned:
		close()

func _open_path(path: String) -> void:
	if path.is_empty():
		return
	if DirAccess.dir_exists_absolute(path):
		_navigate(path)
		return
	_push_recent(path)
	var ext := path.get_extension().to_lower()
	if ext in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(path)
	elif _is_model(path):
		_open_advanced_import(path)
	elif ResourceLoader.exists(path):
		var res := load(path)
		if res is Script:
			EditorInterface.edit_script(res)
		elif res is PackedScene:
			EditorInterface.open_scene_from_path(path)
		else:
			EditorInterface.edit_resource(res)
	else:
		OS.shell_open(ProjectSettings.globalize_path(path))
		return
	if not pinned:
		close()
