@tool
extends "res://addons/Asset_drawer-main/scripts/drawer_core.gd"


func _get_hd_folder_icon(size: int) -> Texture2D:
	var tex := _svg_icon_tex("folder.svg", maxi(2, int(size * ICON_RATIO)), Color.WHITE, size)
	if tex != null:
		return tex
	return ImageTexture.create_from_image(Image.create(size, size, false, Image.FORMAT_RGBA8))

func _get_hd_file_icon(base: Control, path: String, type: String, size: int) -> Texture2D:
	var kind := _type_kind(path, type)
	var file_name: String = TYPE_ICONS.get(kind, "")
	if not file_name.is_empty():
		var tex := _svg_icon_tex(file_name, maxi(2, int(size * ICON_RATIO)), TYPE_COLORS[kind], size)
		if tex != null:
			return tex
	return _editor_file_icon(base, type, size)

func _editor_file_icon(base: Control, type: String, size: int) -> Texture2D:
	var icon_name := _editor_icon_name(type)
	if icon_name.is_empty():
		icon_name = "File"
	var svg := _svg_icon_tex("godot/" + icon_name + ".svg",
		maxi(2, int(size * ICON_RATIO)), ICON_KEEP_COLOR, size)
	if svg != null:
		return svg
	if base == null:
		base = EditorInterface.get_base_control()
	if base == null:
		return null
	if base.has_theme_icon(icon_name + "Big", "EditorIcons"):
		icon_name += "Big"
	if not base.has_theme_icon(icon_name, "EditorIcons"):
		return null
	var cache_key := "file_v3_%s_%d" % [icon_name, size]
	if _hd_icon_cache.has(cache_key):
		return _hd_icon_cache[cache_key]

	var raw_tex := base.get_theme_icon(icon_name, "EditorIcons")
	if raw_tex == null:
		return null
	var raw_img := raw_tex.get_image()
	if raw_img == null:
		return raw_tex
	if raw_img.is_compressed():
		raw_img.decompress()
	raw_img.convert(Image.FORMAT_RGBA8)

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inner_size := int(size * ICON_RATIO)
	raw_img.resize(inner_size, inner_size, Image.INTERPOLATE_LANCZOS)
	var offset := int((size - inner_size) / 2.0)
	img.blend_rect(raw_img, Rect2i(0, 0, inner_size, inner_size), Vector2i(offset, offset))

	var tex := ImageTexture.create_from_image(img)
	return _icon_cache_put(cache_key, tex)


func _schedule_previews() -> void:
	if _preview_timer != null and is_open:
		_preview_timer.start()

func _request_visible_previews() -> void:
	if not is_open or _list == null or _list.item_count == 0:
		return
	if _list.has_method("force_update_list_size"):
		_list.call("force_update_list_size")
	var first := _list.get_item_at_position(Vector2(6, 6), false)
	var last := _list.get_item_at_position(Vector2(_list.size.x - 6, _list.size.y - 6), false)
	if first < 0 or last < first:
		first = 0
		last = mini(_list.item_count - 1, 59)
	var span := maxi(last - first + 1, 24)
	var lo := maxi(first - span, 0)
	var hi := mini(last + span, _list.item_count - 1)
	var previewer := EditorInterface.get_resource_previewer()
	for i in range(lo, hi + 1):
		var path := str(_list.get_item_metadata(i))
		if _dir_paths.has(path) or _preview_pending.has(path):
			continue
		if not _kind_has_preview(path, str(_file_types.get(path, ""))):
			continue
		if path.get_extension().to_lower() == "svg" and not _svg_fail.has(path):
			var target := _svg_target()
			if _preview_cache.has(path) and int(_svg_px.get(path, 0)) >= target:
				continue
			_preview_pending[path] = true
			_svg_queue.append([path, target])
			continue
		if _preview_cache.has(path):
			continue
		if previewer == null:
			continue
		_preview_pending[path] = true
		previewer.queue_resource_preview(path, self, "_on_preview", path)

func _set_preview_tex(tex: Texture2D) -> void:
	_preview.texture = tex
	for sh in _preview_shadows:
		sh.texture = tex

func _svg_target() -> int:
	var base_px := 128
	match _icon_bucket:
		24: base_px = 64
		64: base_px = 128
		96: base_px = 192
		160: base_px = 320
	var ui_scale := clampf(EditorInterface.get_editor_scale(), 1.0, 2.0)
	return mini(int(base_px * ui_scale), 512)

func _pump_svg_queue() -> void:
	if _svg_queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	# 6 ms max par frame pour ne pas faire ramer l'éditeur
	while not _svg_queue.is_empty() and Time.get_ticks_usec() - t0 < 6000:
		var job: Array = _svg_queue.pop_front()
		var path: String = job[0]
		var target: int = job[1]
		var tex := _render_svg(path, target)
		if tex != null:
			_svg_px[path] = target
			_on_preview(path, tex, null, "svg")
		else:
			_svg_fail[path] = true
			_preview_pending.erase(path)
			_schedule_previews()

func _render_svg(path: String, target: int) -> Texture2D:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var img := Image.new()
	if img.load_svg_from_string(text, 1.0) != OK or img.get_width() <= 0 or img.get_height() <= 0:
		return null
	# on rend le SVG directement à la bonne taille plutôt que d'étirer un bitmap
	var longest := maxi(img.get_width(), img.get_height())
	if absf(float(longest) - float(target)) > 2.0:
		var img2 := Image.new()
		if img2.load_svg_from_string(text, float(target) / float(longest)) == OK and img2.get_width() > 0:
			img = img2
	return ImageTexture.create_from_image(img)

func _on_preview(path: String, preview: Texture2D, _thumb: Texture2D, _user) -> void:
	_preview_pending.erase(path)
	if str(_user) != "svg" and _file_types.has(path) and not _kind_has_preview(path, str(_file_types[path])):
		return
	if str(_user) != "svg" and _svg_px.has(path) and _preview_cache.get(path, null) != null:
		return
	if _preview_cache.size() > 4000:
		_preview_cache.clear()
	_preview_cache[path] = preview
	if preview == null or _list == null:
		return
	if _path_index.has(path):
		var i: int = _path_index[path]
		if i < _list.item_count and str(_list.get_item_metadata(i)) == path:
			_list.set_item_icon(i, preview)
	if _context_path == path and _list.get_selected_items().size() <= 1:
		_set_preview_tex(preview)
