@tool
extends "res://addons/Asset_drawer-main/scripts/drawer_view.gd"


func _ready() -> void:
	# sinon Godot retraduit les textes tout seul et la langue choisie est ignorée
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_search_timer = _make_timer(SEARCH_DELAY, _refresh)
	_save_timer = _make_timer(SAVE_DELAY, _flush_cfg)
	_preview_timer = _make_timer(PREVIEW_DELAY, _request_visible_previews)
	_load_cfg()
	_update_palette()
	_setup_style()
	_build_ui()
	_apply_saved_state()

	if _is_docked():
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		is_open = true
		if _grip != null:
			_grip.visible = false
		if not visibility_changed.is_connected(_on_dock_visibility):
			visibility_changed.connect(_on_dock_visibility)
	else:
		visible = false
		modulate.a = 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		z_index = 128
		z_as_relative = false
		clip_contents = false
		if SHOW_HINT:
			_build_hint(EditorInterface.get_base_control())

	var base := EditorInterface.get_base_control()
	if not base.resized.is_connected(_on_editor_resized):
		base.resized.connect(_on_editor_resized)
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_fs_changed):
		fs.filesystem_changed.connect(_on_fs_changed)
	if not fs.resources_reimported.is_connected(_on_reimported):
		fs.resources_reimported.connect(_on_reimported)

func _on_dock_visibility() -> void:
	if not _is_docked():
		return
	if visible:
		is_open = true
		if _dirty:
			_refresh()
		else:
			_schedule_previews()
	else:
		is_open = false
		_hide_hover()
		_hide_gear_panel()
		_flush_cfg()


func _exit_tree() -> void:
	_flush_cfg()
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	if _paste_tween and _paste_tween.is_valid():
		_paste_tween.kill()
	if is_instance_valid(_hint):
		_hint.queue_free()
		_hint = null
	if is_instance_valid(_toast_overlay):
		_toast_overlay.queue_free()
		_toast_overlay = null
	var base := EditorInterface.get_base_control()
	if is_instance_valid(base) and base.resized.is_connected(_on_editor_resized):
		base.resized.disconnect(_on_editor_resized)
	var fs := EditorInterface.get_resource_filesystem()
	if is_instance_valid(fs):
		if fs.filesystem_changed.is_connected(_on_fs_changed):
			fs.filesystem_changed.disconnect(_on_fs_changed)
		if fs.resources_reimported.is_connected(_on_reimported):
			fs.resources_reimported.disconnect(_on_reimported)

func _on_fs_changed() -> void:
	_dirty = true
	_tree_dirty = true
	_index_dirty = true
	if is_open:
		_refresh()

func _on_reimported(paths: PackedStringArray) -> void:
	for p in paths:
		_preview_cache.erase(p)
		_preview_pending.erase(p)
		_svg_px.erase(p)
		_svg_fail.erase(p)

func _apply_saved_state() -> void:
	_configure_zoom()
	_btn_grid.button_pressed = not _view_list
	_btn_list.button_pressed = _view_list
	_btn_pin.button_pressed = pinned
	_btn_details.button_pressed = _details_visible
	_details_panel.visible = _details_visible

func _build_ui() -> void:
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_grip = ColorRect.new()
	_grip.custom_minimum_size = Vector2(0, 6)
	_grip.color = _ov(0.06)
	_grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_grip.gui_input.connect(_on_grip_input)
	root.add_child(_grip)

	var pad := _pad(6, 2)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pad)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 0)
	pad.add_child(main_vbox)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var header_pad := _pad(5, 2)
	header.add_child(header_pad)
	header_pad.add_child(_build_toolbar())
	main_vbox.add_child(header)

	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.split_offset = 0
	main_vbox.add_child(_split)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(180, 0)
	left_panel.add_theme_constant_override("separation", 4)

	var tabs_panel := PanelContainer.new()
	tabs_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var tabs_pad := _pad(3)
	tabs_panel.add_child(tabs_pad)
	var left_tabs := HBoxContainer.new()
	left_tabs.add_theme_constant_override("separation", 2)
	tabs_pad.add_child(left_tabs)
	left_panel.add_child(tabs_panel)

	var left_content := PanelContainer.new()
	left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var left_pad := _pad(4)
	left_content.add_child(left_pad)
	_left_vbox = VBoxContainer.new()
	left_pad.add_child(_left_vbox)
	left_panel.add_child(left_content)
	var tab_group := ButtonGroup.new()
	var tab_names := [L.t("Dossiers"), L.t("Favoris"), L.t("Récents"), "Sets"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.toggle_mode = true
		btn.button_group = tab_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_ghost_button(btn, 4, 3, Color(accent.r, accent.g, accent.b, 0.30))
		btn.button_pressed = (i == 0)
		btn.focus_mode = Control.FOCUS_NONE
		var tab_idx := i
		btn.pressed.connect(func() -> void: _switch_left_tab(tab_idx))
		left_tabs.add_child(btn)
		_left_tab_buttons.append(btn)

	_tree_tools = HBoxContainer.new()
	_tree_tools.add_theme_constant_override("separation", 2)
	_left_vbox.add_child(_tree_tools)
	_add_tree_tool_button("CollapseTree", "⇤", L.t("Tout replier"), _collapse_all_folders)
	_add_tree_tool_button("ExpandTree", "◎", L.t("Localiser le dossier courant"), _sync_tree_selection)

	_tree = Tree.new()
	_tree.hide_root = false
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tree.item_selected.connect(_on_tree_selected)
	_tree.item_collapsed.connect(func(it: TreeItem) -> void:
		if _syncing_tree:
			return
		_collapsed[str(it.get_metadata(0))] = it.collapsed
	)
	_tree.gui_input.connect(_on_tree_gui_input)
	_tree.gui_input.connect(_on_tree_right_click)
	_tree.set_drag_forwarding(_tree_get_drag, _tree_can_drop, _tree_drop)
	_tree.draw.connect(_draw_tree_drop)
	_left_vbox.add_child(_tree)
	_setup_sticky()

	_tab_list = ItemList.new()
	_tab_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tab_list.visible = false
	_tab_list.item_activated.connect(_on_tab_list_activated)
	_tab_list.item_clicked.connect(_on_tab_list_clicked)
	_style_item_list(_tab_list)
	_left_vbox.add_child(_tab_list)

	_btn_new_set = Button.new()
	_btn_new_set.text = L.t("+ Nouveau set")
	_btn_new_set.visible = false
	_btn_new_set.pressed.connect(func() -> void:
		_prompt_string(L.t("Nouveau set"), L.t("mon_set"), func(n: String) -> void:
			if _valid_name(n) and not _sets.has(n):
				_sets[n] = []
				_save_cfg()
				_refresh_left_tab_content()
		)
	)
	_left_vbox.add_child(_btn_new_set)
	_split.add_child(left_panel)

	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var center_pad := _pad(4)
	center_panel.add_child(center_pad)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.max_columns = 0
	_list.select_mode = ItemList.SELECT_MULTI
	_list.same_column_width = true
	_list.max_text_lines = 2
	_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.item_activated.connect(_on_item_activated)
	_list.draw.connect(_draw_type_bars)
	_list.draw.connect(_draw_list_overlay)
	_list.multi_selected.connect(func(_i: int, _s: bool) -> void: _on_selection_changed())
	_list.empty_clicked.connect(func(_p: Vector2, _b: int) -> void:
		_list.deselect_all()
		_on_selection_changed()
	)
	_list.set_drag_forwarding(_get_drag_data_fw, _list_can_drop, _list_drop)
	_list.gui_input.connect(_on_list_gui_input)
	_list.mouse_exited.connect(_hide_hover)
	_style_item_list(_list)
	_list.resized.connect(_schedule_previews)
	_list.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _schedule_previews())
	center_pad.add_child(_list)

	_empty_state = VBoxContainer.new()
	_empty_state.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_state.visible = false
	_empty_lbl = Label.new()
	_empty_lbl.text = L.t("Aucun asset")
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.modulate = TEXT_SECONDARY
	_empty_state.add_child(_empty_lbl)
	_empty_link = LinkButton.new()
	_empty_link.text = L.t("Créer un dossier")
	_empty_link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_link.add_theme_color_override("font_color", accent)
	_empty_link.pressed.connect(_create_folder)
	_empty_state.add_child(_empty_link)
	_empty_reset = Button.new()
	_empty_reset.text = L.t("Réinitialiser les filtres")
	_empty_reset.visible = false
	_empty_reset.focus_mode = Control.FOCUS_NONE
	_empty_reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_reset.pressed.connect(func() -> void: _set_filter(0))
	_empty_state.add_child(_empty_reset)
	center_pad.add_child(_empty_state)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.dragged.connect(_on_details_split_dragged)
	right_split.add_child(center_panel)
	_details_panel = _build_details_panel()
	right_split.add_child(_details_panel)
	right_split.split_offset = -int(maxf(_details_width - DETAILS_MIN_WIDTH, 0.0))
	_split.add_child(right_split)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var footer_pad := _pad(6, 1)
	footer.add_child(footer_pad)
	footer_pad.add_child(_build_footer())
	main_vbox.add_child(footer)

	_ctx_popup = PanelContainer.new()
	_ctx_popup.visible = false
	_ctx_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_ctx_popup.z_index = 350
	var ctx_style := _native_popup_sb()
	if ctx_style != null:
		_ctx_popup.add_theme_stylebox_override("panel", ctx_style)
	var ctx_margin := _pad(8)
	_ctx_popup.add_child(ctx_margin)
	_ctx_vbox = VBoxContainer.new()
	_ctx_vbox.add_theme_constant_override("separation", 2)
	ctx_margin.add_child(_ctx_vbox)

	_build_toast()
	_build_hover()
	_toast_overlay.add_child(_ctx_popup)
	_build_gear_panel()
	_toast_overlay.add_child(_gear_pop)
	_build_paste_pop()

func _build_paste_pop() -> void:

	_paste_pop = Button.new()
	_paste_pop.text = ""
	_paste_pop.tooltip_text = L.t("Coller la ressource copiée ici")
	_paste_pop.custom_minimum_size = Vector2(22, 22)
	_paste_pop.expand_icon = true
	_paste_pop.visible = false
	_paste_pop.modulate.a = 0.0
	_paste_pop.focus_mode = Control.FOCUS_NONE
	_paste_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_paste_pop.z_index = 200
	_paste_pop.icon = _editor_icon("ActionPaste")
	if _paste_pop.icon == null:
		_paste_pop.icon = _editor_icon("ActionCopy")
	_paste_pop.add_theme_color_override("icon_normal_color", Color.WHITE)
	_paste_pop.add_theme_color_override("icon_hover_color", Color.WHITE)
	_paste_pop.add_theme_color_override("icon_pressed_color", Color.WHITE)
	_paste_pop.add_theme_stylebox_override("normal", _make_stylebox(Color(COLOR_RES_ACTION.r, COLOR_RES_ACTION.g, COLOR_RES_ACTION.b, 0.95), Color(1, 1, 1, 0.55), 5, 1))
	_paste_pop.add_theme_stylebox_override("hover", _make_stylebox(Color(COLOR_RES_ACTION.r, COLOR_RES_ACTION.g, COLOR_RES_ACTION.b, 1.0), Color(1, 1, 1, 0.85), 5, 1))
	_paste_pop.add_theme_stylebox_override("pressed", _make_stylebox(_press_c(COLOR_RES_ACTION), Color.WHITE, 5, 1))
	_paste_pop.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_paste_pop.pressed.connect(_on_paste_pop_pressed)
	_add_press_bounce(_paste_pop, 1.12, 0.88)
	_toast_overlay.add_child(_paste_pop)

	_build_copy_pop()

func _build_copy_pop() -> void:
	_copy_pop = Button.new()
	_copy_pop.text = ""
	_copy_pop.tooltip_text = L.t("Copier la ressource")
	_copy_pop.custom_minimum_size = Vector2(22, 22)
	_copy_pop.expand_icon = true
	_copy_pop.visible = false
	_copy_pop.modulate.a = 0.0
	_copy_pop.focus_mode = Control.FOCUS_NONE
	_copy_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_copy_pop.z_index = 200
	_copy_pop.icon = _editor_icon("ActionCopy")
	if _copy_pop.icon == null:
		_copy_pop.icon = _editor_icon("Duplicate")
	_copy_pop.add_theme_color_override("icon_normal_color", Color.WHITE)
	_copy_pop.add_theme_color_override("icon_hover_color", Color.WHITE)
	_copy_pop.add_theme_color_override("icon_pressed_color", Color.WHITE)
	_copy_pop.add_theme_stylebox_override("normal", _make_stylebox(Color(COLOR_RES_ACTION.r, COLOR_RES_ACTION.g, COLOR_RES_ACTION.b, 0.95), Color(1, 1, 1, 0.55), 5, 1))
	_copy_pop.add_theme_stylebox_override("hover", _make_stylebox(Color(COLOR_RES_ACTION.r, COLOR_RES_ACTION.g, COLOR_RES_ACTION.b, 1.0), Color(1, 1, 1, 0.85), 5, 1))
	_copy_pop.add_theme_stylebox_override("pressed", _make_stylebox(_press_c(COLOR_RES_ACTION), Color.WHITE, 5, 1))
	_copy_pop.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_copy_pop.pressed.connect(_on_copy_pop_pressed)
	_add_press_bounce(_copy_pop, 1.12, 0.88)
	_toast_overlay.add_child(_copy_pop)

func _build_toast() -> void:
	var base := EditorInterface.get_base_control()
	_toast_overlay = Control.new()
	_toast_overlay.name = "AssetDrawerToastOverlay"
	_toast_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_overlay.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	base.add_child(_toast_overlay)

	var bottom_bar := CenterContainer.new()
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -58
	bottom_bar.offset_bottom = -14
	_toast_overlay.add_child(bottom_bar)

	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast.z_index = 300
	var toast_style := _native_popup_sb()
	if toast_style != null:
		_toast.add_theme_stylebox_override("panel", toast_style)
	var pad := _pad(14, 7)
	_toast.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pad.add_child(row)
	_toast_lbl = Label.new()
	
	row.add_child(_toast_lbl)
	bottom_bar.add_child(_toast)

func _build_gear_panel() -> void:
	_gear_pop = PanelContainer.new()
	_gear_pop.name = "AssetDrawerSettings"
	_gear_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_gear_pop.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_gear_pop.z_index = 340
	_gear_pop.visible = false
	var style := _native_popup_sb()
	if style != null:
		_gear_pop.add_theme_stylebox_override("panel", style)
	var pad := _pad(12, 10)
	_gear_pop.add_child(pad)
	_gear_vbox = VBoxContainer.new()
	_gear_vbox.add_theme_constant_override("separation", 6)
	_gear_vbox.custom_minimum_size.x = 470
	pad.add_child(_gear_vbox)

func _toggle_gear_panel() -> void:
	if is_instance_valid(_gear_pop) and _gear_pop.visible:
		_hide_gear_panel()
	else:
		_show_gear_panel()

func _show_gear_panel() -> void:
	if _gear_vbox == null or _toast_overlay == null:
		return
	_hide_hover()
	if _ctx_popup != null:
		_ctx_popup.hide()
	for c in _gear_vbox.get_children():
		_gear_vbox.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = L.t("Paramètres")
	_gear_vbox.add_child(title)
	_gear_vbox.add_child(HSeparator.new())
	_add_language_row(_gear_vbox, _hide_gear_panel)
	_gear_vbox.add_child(HSeparator.new())
	_gear_section(L.t("DÉMARRAGE"))
	var cb := CheckBox.new()
	cb.text = L.t("Recharger le projet à l'activation")
	cb.button_pressed = _reload_on_enable
	cb.focus_mode = Control.FOCUS_NONE
	_style_ghost_button(cb, 8, 3)
	cb.toggled.connect(func(on: bool) -> void:
		_reload_on_enable = on
		_save_cfg()
		_flush_cfg()
	)
	_gear_vbox.add_child(cb)
	_gear_vbox.add_child(_gear_btn(L.t("Recharger le projet maintenant"), func() -> void: _reload_project()))
	_gear_vbox.add_child(HSeparator.new())
	_gear_section(L.t("AIDE"))
	_gear_vbox.add_child(_gear_help())
	_gear_vbox.add_child(HSeparator.new())
	var where := Label.new()
	where.text = L.t("Préférences enregistrées ici :") + "\n" + _cfg_file_path()
	where.modulate = TEXT_MUTED
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.custom_minimum_size.x = 450
	_gear_vbox.add_child(where)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	bottom.add_child(_gear_btn(L.t("Fermer le tiroir"), func() -> void: _close_drawer_from_panel()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	bottom.add_child(_gear_btn(L.t("Fermer"), func() -> void: _hide_gear_panel()))
	_gear_vbox.add_child(bottom)
	_place_gear_panel()

func _gear_section(title: String) -> void:
	if _gear_vbox == null:
		return
	var lbl := Label.new()
	lbl.text = title
	lbl.modulate = TEXT_MUTED
	_gear_vbox.add_child(lbl)

func _gear_btn(title: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_ghost_button(b, 8, 3)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _gear_help() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for row in HELP_ROWS:
		var key_lbl := Label.new()
		key_lbl.text = L.t(str(row[0]))
		key_lbl.modulate = TEXT_SECONDARY
		key_lbl.custom_minimum_size.x = 140
		key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		grid.add_child(key_lbl)
		var desc := Label.new()
		desc.text = L.t(str(row[1]))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 290
		grid.add_child(desc)
	return scroll

func _place_gear_panel() -> void:
	if _gear_pop == null or _toast_overlay == null or _btn_gear == null:
		return
	_gear_pop.visible = true
	_gear_pop.reset_size()
	_gear_pop.size = _gear_pop.get_combined_minimum_size()
	var origin: Vector2 = _toast_overlay.get_global_rect().position
	var r: Rect2 = _btn_gear.get_global_rect()
	var sz: Vector2 = _gear_pop.size
	var pos := Vector2(r.position.x - origin.x + r.size.x - sz.x, r.position.y - origin.y + r.size.y + 6.0)
	if pos.y + sz.y > _toast_overlay.size.y - 4.0:
		pos.y = (r.position.y - origin.y) - sz.y - 6.0
	pos.x = clampf(pos.x, 4.0, maxf(4.0, _toast_overlay.size.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, _toast_overlay.size.y - sz.y - 4.0))
	_gear_pop.position = pos
	_gear_pop.modulate.a = 0.0
	create_tween().tween_property(_gear_pop, "modulate:a", 1.0, 0.08)

func _close_drawer_from_panel() -> void:
	_hide_gear_panel()
	if _is_docked() and get_parent() is EditorDock:
		(get_parent() as EditorDock).close()
	else:
		close()

func _reload_project() -> void:
	_hide_gear_panel()
	_flush_cfg()
	EditorInterface.restart_editor(true)

func on_plugin_enabled() -> void:
	_dirty = true
	_tree_dirty = true
	_index_dirty = true
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
	if not _reload_on_enable:
		return
	# pas de rechargement juste après le lancement de l'éditeur, ni en boucle
	if Time.get_ticks_msec() < RELOAD_MIN_UPTIME:
		return
	var now := int(Time.get_unix_time_from_system())
	if now - _last_reload_stamp < RELOAD_COOLDOWN:
		return
	_last_reload_stamp = now
	_save_cfg()
	_flush_cfg()
	var probe := ConfigFile.new()
	if not _cfg_read(probe) or int(probe.get_value("state", "last_reload", 0)) != now:
		return
	_flash(L.t("Recharger le projet..."))
	# le temps d'afficher le message avant de redémarrer
	await get_tree().create_timer(0.8).timeout
	EditorInterface.restart_editor(true)

func _build_toolbar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	wrap.add_child(row)

	var accent_bar: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")

	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 2)
	row.add_child(_bar_panel(nav_row))

	_btn_back = _icon_btn("Back", "<")
	_btn_back.tooltip_text = L.t("Précédent (bouton souris 4)")
	_btn_back.pressed.connect(func() -> void: _hist_go(-1))
	nav_row.add_child(_btn_back)
	_btn_fwd = _icon_btn("Forward", ">")
	_btn_fwd.tooltip_text = L.t("Suivant (bouton souris 5)")
	_btn_fwd.pressed.connect(func() -> void: _hist_go(1))
	nav_row.add_child(_btn_fwd)
	_btn_up = _icon_btn("ArrowUp", "^")
	_btn_up.tooltip_text = L.t("Dossier parent (Retour arrière)")
	_btn_up.pressed.connect(_go_up)
	nav_row.add_child(_btn_up)

	_breadcrumbs = HBoxContainer.new()
	_breadcrumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breadcrumbs.clip_contents = true
	row.add_child(_bar_panel(_breadcrumbs, true))
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = L.t("Chemin du dossier... (Entrée pour valider)")
	_path_edit.tooltip_text = L.t("Ctrl+L : aller à un chemin") + " · " + L.t("Tab : compléter le nom")
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.visible = false
	_path_edit.text_submitted.connect(_on_path_submitted)
	_path_edit.focus_exited.connect(_close_path_edit)
	_path_edit.gui_input.connect(_on_path_edit_input)
	_breadcrumbs.add_child(_path_edit)

	_search = LineEdit.new()
	_search.placeholder_text = L.t("Rechercher... (Ctrl+F)")
	_search.tooltip_text = L.t("Tab : compléter le nom")
	_search.clear_button_enabled = true
	_search.right_icon = _editor_icon("Search")
	_search.custom_minimum_size = Vector2(170, BAR_H)
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	row.add_child(_search)

	_btn_scope = _icon_btn("Filesystem,Folder", L.t("Projet"))
	_btn_scope.toggle_mode = true
	_btn_scope.button_pressed = _search_all
	_btn_scope.toggled.connect(_on_scope_toggled)
	_style_ghost_button(_btn_scope, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	row.add_child(_bar_panel(_btn_scope))
	_update_search_ui()

	var view_box := HBoxContainer.new()
	view_box.add_theme_constant_override("separation", 2)
	row.add_child(_bar_panel(view_box))
	var view_group := ButtonGroup.new()
	_btn_grid = _icon_btn("FileThumbnail,Grid,TileMap", L.t("Grille"))
	_btn_grid.tooltip_text = L.t("Vue grille")
	_btn_grid.toggle_mode = true
	_btn_grid.button_group = view_group
	_btn_grid.pressed.connect(func() -> void:
		_view_list = false
		_configure_zoom()
		_save_cfg()
		_refresh()
	)
	view_box.add_child(_btn_grid)
	_btn_list = _icon_btn("FileList", L.t("Liste"))
	_btn_list.tooltip_text = L.t("Vue liste")
	_btn_list.toggle_mode = true
	_btn_list.button_group = view_group
	_btn_list.pressed.connect(func() -> void:
		_view_list = true
		_configure_zoom()
		_save_cfg()
		_refresh()
	)
	view_box.add_child(_btn_list)
	_style_ghost_button(_btn_grid, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	_style_ghost_button(_btn_list, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	_btn_sort = Button.new()
	_btn_sort.focus_mode = Control.FOCUS_NONE
	_style_ghost_button(_btn_sort, 6, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	_btn_sort.pressed.connect(_show_sort_menu)
	view_box.add_child(_btn_sort)
	_update_sort_button()

	_zoom = HSlider.new()
	_zoom.min_value = 48
	_zoom.max_value = 160
	_zoom.step = 8
	_zoom.value = 64
	_zoom.tooltip_text = L.t("Taille des miniatures (Ctrl+molette)")
	_zoom.custom_minimum_size.x = 80
	_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom.value_changed.connect(_on_zoom_changed)
	_style_zoom_slider(accent_bar)
	row.add_child(_bar_panel(_zoom, false, 8))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	row.add_child(_bar_panel(actions))

	_btn_details = _icon_btn("ControlLayout", L.t("Détails"))
	var details_icon := _svg_icon_tex("details.svg", 16, Color.WHITE)
	if details_icon != null:
		_btn_details.icon = details_icon
	_btn_details.tooltip_text = L.t("Panneau de détails")
	_btn_details.toggle_mode = true
	_btn_details.toggled.connect(func(on: bool) -> void:
		_details_visible = on
		_details_panel.visible = on
		_save_cfg()
	)
	_style_ghost_button(_btn_details, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	actions.add_child(_btn_details)

	_btn_pin = _icon_btn("Pin", L.t("Épingler"))
	_btn_pin.tooltip_text = L.t("Épingler (reste ouvert)")
	_btn_pin.toggle_mode = true
	_btn_pin.toggled.connect(func(on: bool) -> void:
		pinned = on
		_save_cfg()
	)
	_style_ghost_button(_btn_pin, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.30))
	actions.add_child(_btn_pin)

	var dock_btn := Button.new()
	dock_btn.text = "DOCK"
	dock_btn.tooltip_text = L.t("Afficher ce dossier dans le dock Fichiers")
	dock_btn.focus_mode = Control.FOCUS_NONE
	
	_style_ghost_button(dock_btn, 6, 2)
	dock_btn.pressed.connect(func() -> void: _show_in_dock(current_dir))
	actions.add_child(dock_btn)

	_btn_gear = Button.new()
	_btn_gear.focus_mode = Control.FOCUS_NONE
	_style_ghost_button(_btn_gear, 5, 2)
	var gear_tex := _png_icon(GEAR_ICON_PATH, 16)
	if gear_tex != null:
		_btn_gear.icon = gear_tex
		_tint_btn_icon(_btn_gear, EditorInterface.get_base_control().get_theme_color("font_color", "Button"))
	else:
		_btn_gear.icon = _icon_from("Tools")
		if _btn_gear.icon == null:
			_btn_gear.text = "?"
	_btn_gear.tooltip_text = L.t("Paramètres et aide")
	_btn_gear.pressed.connect(_toggle_gear_panel)
	actions.add_child(_btn_gear)

	var close_btn := _icon_btn("Close", "X")
	close_btn.tooltip_text = L.t("Fermer (Échap)")
	close_btn.pressed.connect(close)
	actions.add_child(close_btn)

	var filters_box := HBoxContainer.new()
	filters_box.add_theme_constant_override("separation", 3)
	var filters := [L.t("Tout"), L.t("Scènes"), "Scripts", L.t("Modèles"), "Images", "Audio", "Shaders"]
	for i in range(filters.size()):
		var btn := Button.new()
		btn.text = filters[i]
		btn.focus_mode = Control.FOCUS_NONE
		var idx := i
		btn.pressed.connect(func() -> void: _set_filter(idx))
		_filter_buttons.append(btn)
		filters_box.add_child(btn)
	wrap.add_child(filters_box)
	_update_filter_pills()
	return wrap

func _build_details_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAILS_MIN_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_details_scroll = ScrollContainer.new()
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_scroll.resized.connect(_update_details_layout)
	panel.add_child(_details_scroll)
	var margin := _pad(5)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_scroll.add_child(margin)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	margin.add_child(dv)
	_details_dv = dv

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	dv.add_child(head)

	var thumb_pad := _pad(4)
	thumb_pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(thumb_pad)
	var thumb_stack := Control.new()
	thumb_stack.custom_minimum_size = Vector2(44, 44)
	thumb_pad.add_child(thumb_stack)
	for layer in [[3.0, 0.07], [2.0, 0.09], [1.0, 0.12]]:
		var e: float = layer[0]
		var sh := TextureRect.new()
		sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh.self_modulate = Color(0, 0, 0, layer[1])
		sh.anchor_right = 1.0
		sh.anchor_bottom = 1.0
		sh.offset_left = -e
		sh.offset_right = e
		sh.offset_top = -e + 2.0
		sh.offset_bottom = e + 2.0
		thumb_stack.add_child(sh)
		_preview_shadows.append(sh)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.anchor_right = 1.0
	_preview.anchor_bottom = 1.0
	thumb_stack.add_child(_preview)

	var head_txt := VBoxContainer.new()
	head_txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_txt.add_theme_constant_override("separation", 1)
	head.add_child(head_txt)

	_details_name = Label.new()
	_details_name.add_theme_font_override("font", EditorInterface.get_base_control().get_theme_font("bold", "EditorFonts"))
	
	_details_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_txt.add_child(_details_name)

	var accent_h: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	_details_type_row = HFlowContainer.new()
	_details_type_row.add_theme_constant_override("h_separation", 2)
	_details_type_row.add_theme_constant_override("v_separation", 1)
	head_txt.add_child(_details_type_row)
	_lbl_type = Label.new()
	_lbl_size = Label.new()
	_lbl_modified = Label.new()
	_chip_type = _make_chip(_lbl_type, Color(accent_h.r, accent_h.g, accent_h.b, 0.25))
	_chip_size = _make_chip(_lbl_size, _ov(0.09))
	_chip_date = _make_chip(_lbl_modified, _ov(0.09))
	_details_type_row.add_child(_chip_type)
	_details_type_row.add_child(_chip_size)
	_details_type_row.add_child(_chip_date)

	_details_sep_info = _detail_sep()
	dv.add_child(_details_sep_info)

	_details_card = PanelContainer.new()
	_details_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	dv.add_child(_details_card)
	var card_pad := _pad(6, 3)
	_details_card.add_child(card_pad)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 3)
	card_pad.add_child(card_box)

	_details_path = Label.new()
	_field_path = _make_field(L.t("Chemin"), _details_path)
	card_box.add_child(_field_path)

	_details_card_sep = _detail_sep()
	card_box.add_child(_details_card_sep)

	_lbl_uid = Label.new()
	_field_uid = _make_field("UID", _lbl_uid)
	card_box.add_child(_field_uid)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(spacer)

	dv.add_child(_detail_sep())

	_details_btn_box = BoxContainer.new()
	_details_btn_box.vertical = true
	_details_btn_box.add_theme_constant_override("separation", 3)
	dv.add_child(_details_btn_box)
	_btn_labels.clear()

	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")

	_btn_open = _detail_btn("Load,Folder", L.t("Ouvrir"))
	_btn_open.add_theme_stylebox_override("normal", _make_stylebox(accent, Color.TRANSPARENT, 4))
	_btn_open.add_theme_stylebox_override("hover", _make_stylebox(_hover_c(accent), Color.TRANSPARENT, 4))
	_btn_open.add_theme_stylebox_override("pressed", _make_stylebox(_press_c(accent), Color.TRANSPARENT, 4))
	_tint_btn_icon(_btn_open, Color.WHITE)
	_btn_open.pressed.connect(func() -> void: _open_path(_context_path))
	_details_btn_box.add_child(_btn_open)

	_btn_copy_res = _detail_btn("ActionCopy,Duplicate", L.t("Copier la ressource"),
		L.t("Puis survolez un champ ressource de l'Inspecteur (ex. Mesh d'un MeshInstance3D) : un bouton « Coller » apparaît (ou Alt+V au clavier)"))
	_btn_copy_res.add_theme_stylebox_override("normal", _make_stylebox(COLOR_RES_ACTION, Color.TRANSPARENT, 4))
	_btn_copy_res.add_theme_stylebox_override("hover", _make_stylebox(_hover_c(COLOR_RES_ACTION), Color(1, 1, 1, 0.55), 4, 1))
	_btn_copy_res.add_theme_stylebox_override("pressed", _make_stylebox(_press_c(COLOR_RES_ACTION), Color.WHITE, 4, 1))
	_btn_copy_res.add_theme_color_override("font_color", Color.WHITE)
	_btn_copy_res.add_theme_color_override("font_hover_color", Color.WHITE)
	_btn_copy_res.add_theme_color_override("font_pressed_color", Color.WHITE)
	_tint_btn_icon(_btn_copy_res, Color.WHITE)
	_btn_copy_res.resized.connect(func() -> void: _btn_copy_res.pivot_offset = _btn_copy_res.size * 0.5)
	_btn_copy_res.pressed.connect(func() -> void:
		_copy_resource_to_clipboard(_context_path)
		_bounce_to(_btn_copy_res, Vector2(1.08, 1.08), 0.08)
		get_tree().create_timer(0.08).timeout.connect(func() -> void: _bounce_to(_btn_copy_res, Vector2.ONE, 0.14))
	)
	_details_btn_box.add_child(_btn_copy_res)

	_btn_copy_path = _detail_btn("CopyNodePath,ActionCopy,Link", L.t("Copier le chemin"))
	_btn_copy_path.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_context_path)
		_flash(L.t("Chemin copié"))
	)
	_details_btn_box.add_child(_btn_copy_path)

	_btn_fav = _detail_btn("NonFavorite,Favorites", L.t("Ajouter aux favoris"))
	_btn_fav.resized.connect(func() -> void: _btn_fav.pivot_offset = _btn_fav.size * 0.5)
	_btn_fav.pressed.connect(func() -> void:
		var was_fav := _is_fav(_context_path)
		_toggle_favorite(_context_path)
		_update_details(_context_path)
		_refresh()
		_bounce_to(_btn_fav, Vector2(1.15, 1.15), 0.1)
		get_tree().create_timer(0.1).timeout.connect(func() -> void: _bounce_to(_btn_fav, Vector2.ONE, 0.14))
		_flash(L.t("Retiré des favoris") if was_fav else L.t("Ajouté aux favoris"))
	)
	_details_btn_box.add_child(_btn_fav)
	_sync_details_meta()
	return panel

func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	_status = Label.new()
	_status.modulate = TEXT_SECONDARY
	
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	footer.add_child(_status)

	var btn_f := _icon_btn("Folder", L.t("+Dossier"))
	btn_f.tooltip_text = L.t("Nouveau dossier")
	btn_f.pressed.connect(_create_folder)
	footer.add_child(btn_f)
	var btn_sc := Button.new()
	btn_sc.text = L.t("+Scène")
	_style_ghost_button(btn_sc, 6, 2)
	btn_sc.pressed.connect(_create_scene)
	footer.add_child(btn_sc)
	var btn_st := Button.new()
	btn_st.text = "+Script"
	_style_ghost_button(btn_st, 6, 2)
	btn_st.pressed.connect(_create_script)
	footer.add_child(btn_st)
	return footer

func _draw_type_bars() -> void:
	if not SHOW_TYPE_BAR or _list == null:
		return
	var n := mini(_list.item_count, _item_colors.size())
	if n == 0:
		return
	if _bar_style == null:
		_bar_style = StyleBoxFlat.new()
		_bar_style.set_corner_radius_all(2)
		_bar_style.border_color = Color(0, 0, 0, 0.55)
		_bar_style.set_border_width_all(1)
	var view_h := _list.size.y
	var icon_w := float(_list.fixed_icon_size.x)
	var margin := float(_list.get_theme_constant("icon_margin"))
	var thick := clampf(margin - 1.0, 3.0, 5.0)
	for i in n:
		var c := _item_colors[i]
		if c.a <= 0.0:
			continue
		var r := _item_rect(i, true)
		if r.end.y < 0.0:
			continue
		if r.position.y > view_h:
			break
		_bar_style.bg_color = Color(c.r, c.g, c.b, 0.95)
		if _view_list:
			_list.draw_style_box(_bar_style, Rect2(r.position.x + 1.0, r.position.y + 3.0, 3.0, maxf(r.size.y - 6.0, 4.0)))
		else:
			var bar_w := icon_w * _icon_art_ratio(_list.get_item_icon(i))
			var x := r.position.x + floorf((r.size.x - bar_w) * 0.5)
			var y := r.position.y + margin + icon_w - thick - 1.0
			_list.draw_style_box(_bar_style, Rect2(x, y, bar_w, thick))

func _draw_list_overlay() -> void:
	if _list == null:
		return
	var acc: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var view_h := _list.size.y

	if not _view_list:
		for i in _list.get_selected_items():
			var r := _item_rect(i, true)
			if r.end.y < 0.0:
				continue
			if r.position.y > view_h:
				break
			var c := Vector2(r.end.x - 11.0, r.position.y + 11.0)
			_list.draw_circle(c, 7.5, acc)
			_list.draw_polyline(PackedVector2Array([c + Vector2(-3.2, 0.3), c + Vector2(-0.8, 2.7), c + Vector2(3.4, -2.3)]), Color.WHITE if acc.get_luminance() < 0.6 else Color.BLACK, 1.6, true)

	if _drop_whole:
		_list.draw_style_box(_make_stylebox(Color(acc.r, acc.g, acc.b, 0.06), Color(acc.r, acc.g, acc.b, 0.75), 8, 2), Rect2(Vector2.ZERO, _list.size))

	if _drop_list_idx >= 0 and _drop_list_idx < _list.item_count:
		var r2 := _item_rect(_drop_list_idx, true)
		var glow := _make_stylebox(Color(acc.r, acc.g, acc.b, 0.26), acc, 9, 2)
		glow.shadow_color = Color(acc.r, acc.g, acc.b, 0.5)
		glow.shadow_size = 8
		_list.draw_style_box(glow, r2)
		var font := _list.get_theme_font("font")
		var fs := 10
		var txt := L.t("Déplacer ici")
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pr := Rect2(r2.position.x + (r2.size.x - (tw + 14.0)) * 0.5, r2.position.y + 3.0, tw + 14.0, 16.0)
		_list.draw_style_box(_make_stylebox(acc, Color.TRANSPARENT, 8), pr)
		_list.draw_string(font, Vector2(pr.position.x + 7.0, pr.position.y + 11.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if acc.get_luminance() < 0.6 else Color.BLACK)

	if _mq_active and _mq_moved:
		var sv := Vector2(_mq_start.x, _mq_start.y - _list.get_v_scroll_bar().value)
		var mr := Rect2(sv, _mq_cur - sv).abs()
		_list.draw_style_box(_make_stylebox(Color(acc.r, acc.g, acc.b, 0.16), Color(acc.r, acc.g, acc.b, 0.9), 3, 1), mr)

func _draw_tree_drop() -> void:
	if _drop_tree_item == null or not is_instance_valid(_drop_tree_item):
		return
	var acc: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var r := _tree.get_item_area_rect(_drop_tree_item, 0).grow(-1.0)
	var st := _make_stylebox(Color(acc.r, acc.g, acc.b, 0.25), acc, 6, 2)
	st.shadow_color = Color(acc.r, acc.g, acc.b, 0.4)
	st.shadow_size = 5
	_tree.draw_style_box(st, r)


func _add_tree_tool_button(icon_name: String, fallback: String, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.icon = _editor_icon(icon_name)
	if b.icon == null:
		b.text = fallback
	b.pressed.connect(cb)
	_tree_tools.add_child(b)

func _setup_sticky() -> void:
	_sticky_box = Control.new()
	_sticky_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticky_box.clip_contents = true
	_sticky_box.visible = false
	_tree.clip_contents = true
	_tree.add_child(_sticky_box)
	for c in _tree.get_children(true):
		if c is VScrollBar:
			_tree_vscroll = c
			break

func _process(_delta: float) -> void:
	if _tree != null and _tree.is_visible_in_tree():
		_update_sticky()
	_update_paste_pop_hover()
	_update_copy_pop_hover()
	_pump_svg_queue()
	if SHOW_HINT and is_instance_valid(_hint) and _hint.visible == is_open:
		_hint.visible = not is_open


func _input(event: InputEvent) -> void:
	if _ctx_popup != null and _ctx_popup.visible:
		if event is InputEventMouseButton and event.pressed:
			if not _ctx_popup.get_global_rect().has_point((event as InputEventMouseButton).global_position):
				_ctx_popup.hide()
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_ctx_popup.hide()
			get_viewport().set_input_as_handled()
			return
	if _gear_pop != null and _gear_pop.visible:
		if event is InputEventMouseButton and event.pressed:
			if not _gear_pop.get_global_rect().has_point((event as InputEventMouseButton).global_position):
				_hide_gear_panel()
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_hide_gear_panel()
			get_viewport().set_input_as_handled()
			return
	if is_open and event is InputEventMouseButton and event.pressed:
		var xb := event as InputEventMouseButton
		if xb.button_index == MOUSE_BUTTON_XBUTTON1 or xb.button_index == MOUSE_BUTTON_XBUTTON2:
			if get_global_rect().has_point(xb.global_position):
				_hist_go(-1 if xb.button_index == MOUSE_BUTTON_XBUTTON1 else 1)
				get_viewport().set_input_as_handled()
			return
	if is_open and not _is_docked() and not pinned and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var is_wheel := mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
		if not is_wheel and not _resizing and not _ctx_popup.visible and not get_global_rect().has_point(mb.global_position):
			_outside_close_msec = Time.get_ticks_msec()
			close()
		return
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return
	if k.ctrl_pressed and k.keycode == KEY_F:
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed and k.keycode == KEY_L:
		_open_path_edit()
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_TAB and k.shift_pressed == false and k.ctrl_pressed == false and k.alt_pressed == false:
		if _path_edit != null and focus == _path_edit:
			_complete_path()
			get_viewport().set_input_as_handled()
			return
		if _search != null and focus == _search:
			_complete_search()
			get_viewport().set_input_as_handled()
			return
	if focus is LineEdit or focus is TextEdit:
		return
	if focus != null and focus != _list and k.keycode != KEY_BACKSPACE:
		return
	var sel := _selected_paths()
	var handled := true
	match k.keycode:
		KEY_F2:
			if sel.size() == 1:
				_rename(sel[0])
		KEY_DELETE:
			if not sel.is_empty():
				_confirm_delete(sel)
		KEY_D:
			if k.ctrl_pressed and not sel.is_empty():
				_duplicate(sel)
			else:
				handled = false
		KEY_BACKSPACE:
			_go_up()
		KEY_ENTER, KEY_KP_ENTER:
			if sel.size() == 1:
				_open_path(sel[0])
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _on_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_hover_motion((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_hide_hover()
	if event is InputEventMouseMotion and _mq_active:
		var mm := event as InputEventMouseMotion
		_marquee_update(mm.position, mm.button_mask)
		return
	if event is InputEventMouseButton and not event.pressed and _mq_active \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_marquee_end()
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.double_click \
			and _list.item_count > 0 and _list.get_item_at_position(mb.position, true) < 0:
		_marquee_begin(mb)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_context_from_tree = false
		var idx := _list.get_item_at_position(mb.position, true)
		if idx >= 0:
			if not _list.is_selected(idx):
				_list.deselect_all()
				_list.select(idx, true)
				_on_selection_changed()
			_context_path = str(_list.get_item_metadata(idx))
		else:
			_list.deselect_all()
			_on_selection_changed()
			_context_path = current_dir
		_show_context()
		_list.accept_event()
	elif mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var zstep := 4.0 if _view_list else 8.0
		_zoom.value += zstep if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -zstep
		_list.accept_event()

func _on_tree_right_click(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	_context_from_tree = true
	_context_path = ""
	var item := _tree.get_item_at_position(mb.position)
	if item != null:
		_context_path = str(item.get_metadata(0))
		_syncing_tree = true
		item.select(0)
		_syncing_tree = false
	_show_context()
	_tree.accept_event()

func _marquee_begin(mb: InputEventMouseButton) -> void:
	_mq_active = true
	_mq_moved = false
	var additive := mb.ctrl_pressed or mb.shift_pressed
	_mq_base = _list.get_selected_items() if additive else PackedInt32Array()
	_mq_start = Vector2(mb.position.x, mb.position.y + _list.get_v_scroll_bar().value)
	_mq_cur = mb.position

func _marquee_update(pos: Vector2, mask: int) -> void:
	if (mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_marquee_end()
		return
	_mq_cur = pos
	var vs := _list.get_v_scroll_bar()
	if not _mq_moved:
		if Vector2(_mq_start.x, _mq_start.y - vs.value).distance_to(pos) < 4.0:
			return
		_mq_moved = true
	if pos.y < 14.0:
		vs.value -= 18.0
	elif pos.y > _list.size.y - 14.0:
		vs.value += 18.0
	var sv := Vector2(_mq_start.x, _mq_start.y - vs.value)
	var rect := Rect2(sv, pos - sv).abs()
	_list.deselect_all()
	for i in _mq_base:
		_list.select(i, false)
	for i in _list.item_count:
		var r := _item_rect(i, true).grow(-4.0)
		if r.position.y > rect.end.y:
			break
		if r.end.y < rect.position.y:
			continue
		if r.intersects(rect):
			_list.select(i, false)
	_list.queue_redraw()

func _marquee_end() -> void:
	var was_moved := _mq_moved
	_mq_active = false
	_mq_moved = false
	_list.queue_redraw()
	if was_moved:
		_on_selection_changed()

func _get_drag_data_fw(_at: Vector2) -> Variant:
	if _mq_active:
		return null
	var files := _selected_paths()
	if files.is_empty():
		return null
	var base := EditorInterface.get_base_control()
	var accent: Color = base.get_theme_color("accent_color", "Editor")
	var first: String = files[0]
	var is_dir := DirAccess.dir_exists_absolute(first)

	var wrap := Control.new()
	var card := PanelContainer.new()
	card.rotation = deg_to_rad(-3.0)
	card.add_theme_stylebox_override("panel", _make_stylebox(COLOR_CARD_BG, Color(accent.r, accent.g, accent.b, 0.9), 7, 1))
	var pad := _pad(8, 5)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pad.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _editor_icon("Folder" if is_dir else "File")
	if is_dir:
		icon.modulate = _folder_color(_all_colors(), first)
	row.add_child(icon)
	var lbl := Label.new()
	lbl.text = first.trim_suffix("/").get_file() + (" (+%d)" % (files.size() - 1) if files.size() > 1 else "")
	
	row.add_child(lbl)
	wrap.add_child(card)
	set_drag_preview(wrap)
	return {"type": "files", "files": files}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_hl()

func _drag_paths(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if data is Dictionary:
		var t := str(data.get("type", ""))
		if t == "files" or t == "files_and_dirs":
			for f in data.get("files", []):
				var p := str(f)
				if p != "res://":
					p = p.trim_suffix("/")
				if not p.is_empty() and not out.has(p):
					out.append(p)
	return out

func _can_move_one(src: String, dst_dir: String) -> bool:
	if src.is_empty() or src == "res://":
		return false
	if src.get_base_dir() == dst_dir or src == dst_dir:
		return false
	if _is_under(dst_dir, src):
		return false
	return FileAccess.file_exists(src) or DirAccess.dir_exists_absolute(src)

func _can_move_any(files: PackedStringArray, dst_dir: String) -> bool:
	for f in files:
		if _can_move_one(f, dst_dir):
			return true
	return false

func _drop_hl_color() -> Color:
	var acc: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	return Color(acc.r, acc.g, acc.b, 0.38)

func _set_drop_hl_list(idx: int, whole: bool = false) -> void:
	if _list == null:
		return
	if idx == _drop_list_idx and whole == _drop_whole:
		return
	_drop_list_idx = idx
	_drop_whole = whole
	_list.queue_redraw()

func _set_drop_hl_tree(item: TreeItem) -> void:
	if item == _drop_tree_item:
		return
	_drop_tree_item = item
	if _tree != null:
		_tree.queue_redraw()

func _clear_drop_hl() -> void:
	_set_drop_hl_list(-1)
	_set_drop_hl_tree(null)

func _list_drop_target(at: Vector2) -> Dictionary:
	var idx := _list.get_item_at_position(at, true)
	if idx >= 0:
		var p := str(_list.get_item_metadata(idx))
		if _dir_paths.has(p):
			return {"dir": _norm_dir(p), "idx": idx}
	if not _active_set.is_empty() or not _search.text.strip_edges().is_empty():
		return {"dir": "", "idx": -1}
	return {"dir": _norm_dir(current_dir), "idx": -1}

func _list_can_drop(at: Vector2, data: Variant) -> bool:
	var files := _drag_paths(data)
	if files.is_empty():
		_set_drop_hl_list(-1)
		return false
	var tgt := _list_drop_target(at)
	var dst: String = tgt["dir"]
	var ok := not dst.is_empty() and _can_move_any(files, dst)
	_set_drop_hl_list(int(tgt["idx"]) if ok else -1, ok and int(tgt["idx"]) < 0)
	return ok

func _list_drop(at: Vector2, data: Variant) -> void:
	var files := _drag_paths(data)
	var dst: String = _list_drop_target(at)["dir"]
	_clear_drop_hl()
	if dst.is_empty():
		return
	_move_paths(files, dst)

func _tree_drop_dir(at: Vector2) -> String:
	var it := _tree.get_item_at_position(at)
	if it == null:
		return ""
	return _norm_dir(str(it.get_metadata(0)))

func _tree_can_drop(at: Vector2, data: Variant) -> bool:
	var files := _drag_paths(data)
	var it := _tree.get_item_at_position(at)
	if files.is_empty() or it == null:
		_set_drop_hl_tree(null)
		return false
	var ok := _can_move_any(files, _norm_dir(str(it.get_metadata(0))))
	_set_drop_hl_tree(it if ok else null)
	return ok

func _tree_drop(at: Vector2, data: Variant) -> void:
	var files := _drag_paths(data)
	var dst := _tree_drop_dir(at)
	_clear_drop_hl()
	if dst.is_empty():
		return
	_move_paths(files, dst)

func _tree_get_drag(at: Vector2) -> Variant:
	var it := _tree.get_item_at_position(at)
	if it == null:
		return null
	var p := _norm_dir(str(it.get_metadata(0)))
	if p == "res://":
		return null
	var lbl := Label.new()
	lbl.text = "  " + p.get_file() + "  "
	lbl.add_theme_stylebox_override("normal", _make_stylebox(COLOR_CARD_BG, _drop_hl_color(), 6, 1))
	set_drag_preview(lbl)
	return {"type": "files", "files": PackedStringArray([p])}

func _move_paths(files: PackedStringArray, dst_dir: String) -> void:
	EditorInterface.save_all_scenes()
	var moved := 0
	var moves: Array = []
	for p in files:
		var src := p.trim_suffix("/")
		if not _can_move_one(src, dst_dir):
			continue
		var dst := dst_dir.path_join(src.get_file())
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			_flash(L.t("« %s » existe déjà") % src.get_file(), true)
			continue
		var is_dir := DirAccess.dir_exists_absolute(src)
		if DirAccess.rename_absolute(src, dst) != OK:
			_flash(L.t("Échec du déplacement"), true)
			continue
		moves.append([src, dst, is_dir])
		for ext in [".import", ".uid"]:
			if FileAccess.file_exists(src + ext):
				DirAccess.rename_absolute(src + ext, dst + ext)
		_rewrite_paths(src, dst)
		current_dir = _swap_prefix(current_dir, src, dst)
		for i in _history.size():
			_history[i] = _swap_prefix(_history[i], src, dst)
		moved += 1
	if moved == 0:
		return
	_update_references(moves)
	_scan()
	_flash(L.t("%d élément(s) déplacé(s)") % moved if moved > 1 else L.t("Élément déplacé"))


func _ctx_btn(title: String, callback: Callable, color: Color = Color.TRANSPARENT, icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_ghost_button(b, 8, 3)
	if color != Color.TRANSPARENT:
		b.add_theme_color_override("font_color", color)
	if not icon_name.is_empty():
		b.icon = _editor_icon(icon_name)
		if b.icon != null:
			b.add_theme_constant_override("h_separation", 8)
	b.pressed.connect(func() -> void:
		_ctx_popup.hide()
		callback.call()
	)
	_ctx_vbox.add_child(b)
	return b

func _ctx_sep() -> void:
	_ctx_vbox.add_child(HSeparator.new())

func _ctx_check(title: String, checked: bool, on_toggle: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = title
	cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = checked
	_style_ghost_button(cb, 8, 3)
	var fc: Color = EditorInterface.get_base_control().get_theme_color("font_color", "Button")
	for n in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(n, fc)
	cb.toggled.connect(func(on: bool) -> void:
		_ctx_popup.hide()
		on_toggle.call(on)
	)
	_ctx_vbox.add_child(cb)
	return cb

func _place_ctx_popup() -> void:
	_ctx_popup.visible = true
	_ctx_popup.reset_size()
	_ctx_popup.size = _ctx_popup.get_combined_minimum_size()
	var ov: Vector2 = _toast_overlay.size
	var pos: Vector2 = _toast_overlay.get_local_mouse_position()
	var sz: Vector2 = _ctx_popup.size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, ov.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, ov.y - sz.y - 4.0))
	_ctx_popup.position = pos
	_ctx_popup.modulate.a = 0.0
	create_tween().tween_property(_ctx_popup, "modulate:a", 1.0, 0.08)

func _update_sort_button() -> void:
	if _btn_sort == null:
		return
	var arrow := " ↑" if not _sort_desc else " ↓"
	_btn_sort.text = L.t(_sort_label(_sort_mode)) + arrow
	_btn_sort.tooltip_text = L.t("Tri des éléments")

func _show_sort_menu() -> void:
	if _ctx_vbox == null:
		return
	for c in _ctx_vbox.get_children():
		_ctx_vbox.remove_child(c)
		c.queue_free()
	for mode in ["name", "date", "size", "type"]:
		var m: String = mode
		var d := _sort_desc if m == _sort_mode else (m == "date" or m == "size")
		_ctx_check(L.t(_sort_label(m)), m == _sort_mode, func() -> void: _set_sort(m, d))
	_ctx_sep()
	_ctx_check(L.t("Décroissant"), _sort_desc, func() -> void: _set_sort(_sort_mode, not _sort_desc))
	_place_ctx_popup()

func _set_sort(mode: String, desc: bool) -> void:
	if mode == _sort_mode and desc == _sort_desc:
		return
	_sort_mode = mode
	_sort_desc = desc
	_ctx_popup.hide()
	_update_sort_button()
	_save_cfg()
	_flush_cfg()
	_refresh()

func _open_path_edit() -> void:
	if _path_edit == null or not is_open:
		return
	_hide_hover()
	_path_edit.text = current_dir
	_path_edit.visible = true
	for c in _breadcrumbs.get_children():
		if c != _path_edit:
			c.visible = false
	_path_edit.grab_focus()
	_path_edit.select_all()

func _close_path_edit() -> void:
	if _path_edit == null or not _path_edit.visible:
		return
	_path_edit.visible = false
	for c in _breadcrumbs.get_children():
		if c != _path_edit:
			c.visible = true

func _on_path_edit_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	var k := ev as InputEventKey
	if k.keycode == KEY_ESCAPE:
		_close_path_edit()
		_path_edit.accept_event()
	elif k.keycode == KEY_TAB:
		_complete_path()
		_path_edit.accept_event()

func _complete_path() -> void:
	var t := _path_edit.text.strip_edges()
	var dir := _norm_dir(t)
	var part := ""
	if not t.ends_with("/"):
		dir = _norm_dir(t.get_base_dir())
		part = t.get_file()
	var node := EditorInterface.get_resource_filesystem().get_filesystem_path(dir)
	if node == null:
		return
	var hits := PackedStringArray()
	for i in node.get_subdir_count():
		var nm := node.get_subdir(i).get_name()
		if nm.to_lower().begins_with(part.to_lower()):
			hits.append(nm)
	if hits.is_empty():
		_flash(L.t("Aucune correspondance"))
		return
	var common := hits[0]
	for h in hits:
		while not common.is_empty() and not h.to_lower().begins_with(common.to_lower()):
			common = common.substr(0, common.length() - 1)
	if hits.size() == 1:
		_path_edit.text = dir.path_join(hits[0]) + "/"
	elif common.length() > part.length():
		_path_edit.text = dir.path_join(common)
	_path_edit.caret_column = _path_edit.text.length()

func _complete_search() -> void:
	var t := _search.text
	if t.strip_edges().is_empty():
		return
	var head := ""
	var part := t
	var sp := t.rfind(" ")
	if sp >= 0:
		head = t.substr(0, sp + 1)
		part = t.substr(sp + 1)
	if part.is_empty():
		return
	if _index_dirty:
		_build_index()
	var scope := ""
	if not _search_all:
		scope = current_dir if current_dir.ends_with("/") else current_dir + "/"
	var low := part.to_lower()
	var hits := PackedStringArray()
	for e in _index:
		var p: String = e[0]
		if scope != "" and (p == scope or not p.begins_with(scope)):
			continue
		if not e[2] and not _pass_filter(p, _selected_filter):
			continue
		if not _show_hidden and _is_hidden(p):
			continue
		var nm: String = e[3]
		if nm.to_lower().begins_with(low) and not hits.has(nm):
			hits.append(nm)
	if hits.is_empty():
		_flash(L.t("Aucune correspondance"))
		return
	var common: String = hits[0]
	for h in hits:
		while not common.is_empty() and not h.to_lower().begins_with(common.to_lower()):
			common = common.substr(0, common.length() - 1)
	var word := part
	if hits.size() == 1:
		word = hits[0]
	elif common.length() > part.length():
		word = common
	if word == part:
		return
	_search.text = head + word
	_search.caret_column = _search.text.length()
	_search_timer.stop()
	_refresh()

func _on_path_submitted(entry: String) -> void:
	var target := _normalize_input_path(entry)
	_close_path_edit()
	if target.is_empty() or not DirAccess.dir_exists_absolute(target):
		_flash(L.t("Dossier introuvable"), true)
		return
	_pending_select = ""
	_navigate(target)

func _normalize_input_path(entry: String) -> String:
	var p := entry.strip_edges()
	if p.is_empty():
		return ""
	if not p.begins_with("res://"):
		var local := ProjectSettings.localize_path(ProjectSettings.globalize_path(p))
		if not local.begins_with("res://"):
			return ""
		p = local
	return _norm_dir(p)

func _add_color_row(target: String) -> void:
	var color_lbl := Label.new()
	color_lbl.text = L.t("COULEUR DU DOSSIER")
	color_lbl.modulate = TEXT_MUTED
	
	_ctx_vbox.add_child(color_lbl)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for key in FOLDER_COLORS.keys():
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(16, 16)
		cb.flat = false
		cb.tooltip_text = str(key).capitalize()
		cb.add_theme_stylebox_override("normal", _make_stylebox(FOLDER_COLORS[key], Color.TRANSPARENT, 8))
		cb.add_theme_stylebox_override("hover", _make_stylebox(FOLDER_COLORS[key], Color.WHITE, 8, 2))
		_add_press_bounce(cb, 1.25, 0.85)
		var ck: String = key
		cb.pressed.connect(func() -> void:
			_ctx_popup.hide()
			_set_folder_color(target, ck)
		)
		grid.add_child(cb)
	_ctx_vbox.add_child(grid)

	_ctx_btn(L.t("Couleur par défaut"), func() -> void: _set_folder_color(target, ""), Color.TRANSPARENT, "Folder")

func _add_language_row(target: VBoxContainer = null, on_pick: Callable = Callable()) -> void:
	var box: VBoxContainer = target if target != null else _ctx_vbox
	if box == null:
		return
	var lbl := Label.new()
	lbl.text = L.t("LANGUE")
	lbl.modulate = TEXT_MUTED
	box.add_child(lbl)
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for it in [["auto", L.t("Automatique")], ["fr", "Français"], ["en", "English"]]:
		var code: String = str(it[0])
		var rb := Button.new()
		rb.text = str(it[1])
		rb.toggle_mode = true
		rb.button_pressed = _language == code
		rb.focus_mode = Control.FOCUS_NONE
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_ghost_button(rb, 8, 3)
		if _language == code:
			rb.add_theme_color_override("font_pressed_color", accent)
			rb.add_theme_color_override("font_hover_pressed_color", accent)
		rb.pressed.connect(func() -> void:
			if on_pick.is_valid():
				on_pick.call()
			elif is_instance_valid(_ctx_popup):
				_ctx_popup.hide()
			_set_language(code)
		)
		row.add_child(rb)
	box.add_child(row)

func _set_language(lang: String) -> void:
	if lang == _language:
		return
	_language = lang
	L.set_override(lang)
	_save_cfg()
	_flush_cfg()
	rebuild_requested.emit()

func _show_context() -> void:
	for c in _ctx_vbox.get_children():
		_ctx_vbox.remove_child(c)
		c.queue_free()
	var sel := _selected_paths()
	if _context_from_tree:
		sel = PackedStringArray([_context_path]) if not _context_path.is_empty() else PackedStringArray()
	var on_item := not sel.is_empty()
	var target := _context_path
	var is_dir := DirAccess.dir_exists_absolute(target)
	var single := sel.size() == 1

	if on_item:
		if single:
			_ctx_btn(L.t("Ouvrir"), func() -> void: _open_path(target), Color.TRANSPARENT, "Load")
			if not is_dir and _is_model(target):
				_ctx_btn(L.t("Import avancé..."), func() -> void: _open_advanced_import(target), Color.TRANSPARENT, "Tools")
				if _is_model_scene(target):
					_ctx_btn(L.t("Nouvelle scène héritée"), func() -> void: _new_inherited_scene(target), Color.TRANSPARENT, "PackedScene")
		_ctx_btn(L.t("Afficher dans le dock Fichiers"), func() -> void: _show_in_dock(target), Color.TRANSPARENT, "Filesystem")
		_ctx_btn(L.t("Afficher dans l'explorateur"), func() -> void:
			OS.shell_show_in_file_manager(ProjectSettings.globalize_path(target.trim_suffix("/")))
		, Color.TRANSPARENT, "ExternalLink")
		if single and _active_set.is_empty() and not _search.text.strip_edges().is_empty():
			_ctx_btn(L.t("Afficher dans son dossier"), func() -> void:
				_pending_select = target
				_navigate(target)
			, Color.TRANSPARENT, "Folder")
		_ctx_sep()
		_ctx_btn(L.t("Copier le chemin"), func() -> void:
			DisplayServer.clipboard_set("\n".join(sel))
			_flash(L.t("Chemin copié"))
		, Color.TRANSPARENT, "ActionCopy")
		_ctx_btn(L.t("Copier le chemin absolu"), func() -> void:
			var abs_paths: PackedStringArray = []
			for p in sel:
				abs_paths.append(ProjectSettings.globalize_path(p))
			DisplayServer.clipboard_set("\n".join(abs_paths))
			_flash(L.t("Chemin absolu copié"))
		, Color.TRANSPARENT, "ActionCopy")
		if single and not is_dir:
			_ctx_btn(L.t("Copier la ressource   (bouton Coller au survol)"), func() -> void:
				_copy_resource_to_clipboard(target)
			, COLOR_RES_ACTION, "ActionCopy")
		if single and not is_dir and ResourceLoader.has_method("get_resource_uid"):
			_ctx_btn(L.t("Copier l'UID"), func() -> void:
				var uid: int = ResourceLoader.call("get_resource_uid", target)
				if uid != -1:
					DisplayServer.clipboard_set(ResourceUID.id_to_text(uid))
					_flash(L.t("UID copié"))
			, Color.TRANSPARENT, "ActionCopy")
		_ctx_sep()

	if not on_item:
		var in_set := not _active_set.is_empty()
		var here := current_dir
		if not in_set:
			_ctx_btn(L.t("Ouvrir le dossier dans l'explorateur"), func() -> void:
				OS.shell_show_in_file_manager(ProjectSettings.globalize_path(here))
			, Color.TRANSPARENT, "ExternalLink")
			_ctx_btn(L.t("Afficher dans le dock Fichiers"), func() -> void: _show_in_dock(here), Color.TRANSPARENT, "Filesystem")
			_ctx_btn(L.t("Copier le chemin du dossier"), func() -> void:
				DisplayServer.clipboard_set(here)
				_flash(L.t("Chemin copié"))
			, Color.TRANSPARENT, "ActionCopy")
			_ctx_btn(L.t("Copier le chemin absolu du dossier"), func() -> void:
				DisplayServer.clipboard_set(ProjectSettings.globalize_path(here))
				_flash(L.t("Chemin absolu copié"))
			, Color.TRANSPARENT, "ActionCopy")
			if here != "res://":
				_ctx_btn(L.t("Retirer le dossier des favoris") if _is_fav(here) else L.t("Ajouter le dossier aux favoris"), func() -> void:
					var was_fav := _is_fav(here)
					_toggle_favorite(here)
					_refresh()
					_flash(L.t("Retiré des favoris") if was_fav else L.t("Ajouté aux favoris"))
				, Color.TRANSPARENT, "Favorites")
			_ctx_sep()
		_ctx_btn(L.t("Actualiser"), func() -> void:
			_scan()
			_refresh()
			_flash(L.t("Actualisé"))
		, Color.TRANSPARENT, "Reload")
		_ctx_btn(L.t("Passer en vue grille") if _view_list else L.t("Passer en vue liste"), func() -> void:
			var btn: Button = _btn_grid if _view_list else _btn_list
			btn.button_pressed = true
			btn.pressed.emit()
		, Color.TRANSPARENT, "Grid" if _view_list else "FileList")
		_ctx_check(L.t("Afficher les éléments masqués"), _show_hidden, _set_show_hidden)
		_add_language_row()
		_ctx_sep()

	_ctx_btn(L.t("Nouveau dossier"), _create_folder, Color.TRANSPARENT, "Folder")
	_ctx_btn(L.t("Nouvelle scène"), _create_scene, Color.TRANSPARENT, "PackedScene")
	_ctx_btn(L.t("Nouveau script"), _create_script, Color.TRANSPARENT, "Script")

	if not on_item and _active_set.is_empty() and current_dir != "res://":
		_ctx_sep()
		_add_color_row(current_dir)

	if on_item:
		_ctx_sep()
		if single:
			_ctx_btn(L.t("Renommer (F2)"), func() -> void: _rename(target), Color.TRANSPARENT, "Rename")
		_ctx_btn(L.t("Dupliquer (Ctrl+D)"), func() -> void: _duplicate(sel), Color.TRANSPARENT, "Duplicate")
		_ctx_btn(L.t("Retirer des favoris") if _is_fav(target) else L.t("Ajouter aux favoris"), func() -> void:
			var was_fav := _is_fav(target)
			for p in sel:
				_toggle_favorite(p)
			_refresh()
			_flash(L.t("Retiré des favoris") if was_fav else L.t("Ajouté aux favoris"))
		, Color.TRANSPARENT, "Favorites")
		_ctx_btn(L.t("Ajouter à un set..."), func() -> void:
			var default_name := str(_sets.keys()[0]) if not _sets.is_empty() else L.t("mon_set")
			_prompt_string(L.t("Ajouter au set"), default_name, func(n: String) -> void:
				if not _valid_name(n):
					return
				var arr: Array = _sets.get(n, [])
				for p in sel:
					if not arr.has(p):
						arr.append(p)
				_sets[n] = arr
				_save_cfg()
				_refresh_left_tab_content()
				_flash(L.t("Ajouté au set « %s »") % n)
			)
		, Color.TRANSPARENT, "Groups")
		if not _active_set.is_empty():
			_ctx_btn(L.t("Retirer de ce set"), func() -> void:
				var arr: Array = _sets.get(_active_set, [])
				for p in sel:
					arr.erase(p)
				_sets[_active_set] = arr
				_save_cfg()
				_refresh()
			)
		var to_hide: PackedStringArray = []
		var to_unhide: PackedStringArray = []
		for hp in sel:
			if _hidden.has(_hidden_key(hp)):
				to_unhide.append(hp)
			elif hp != "res://" and not _is_hidden(hp):
				to_hide.append(hp)
		if not to_hide.is_empty():
			_ctx_btn(L.t("Masquer dans le tiroir"), func() -> void: _hide_paths(to_hide, true), Color.TRANSPARENT, "GuiVisibilityHidden")
		if not to_unhide.is_empty():
			_ctx_btn(L.t("Ne plus masquer"), func() -> void: _hide_paths(to_unhide, false), Color.TRANSPARENT, "GuiVisibilityVisible")
		_ctx_check(L.t("Afficher les éléments masqués"), _show_hidden, _set_show_hidden)
		if not is_dir:
			_ctx_btn(L.t("Réimporter"), func() -> void:
				var files: PackedStringArray = []
				for p in sel:
					if not DirAccess.dir_exists_absolute(p):
						files.append(p)
				EditorInterface.get_resource_filesystem().reimport_files(files)
			, Color.TRANSPARENT, "Reload")
		if is_dir and single and target != "res://":
			_ctx_sep()
			_add_color_row(target)
		_ctx_sep()
		_ctx_btn(L.t("Supprimer (Suppr)"), func() -> void: _confirm_delete(sel), COLOR_DANGER, "Remove")

	_place_ctx_popup()
	_ctx_vbox.modulate.a = 0.0
	create_tween().tween_property(_ctx_vbox, "modulate:a", 1.0, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
