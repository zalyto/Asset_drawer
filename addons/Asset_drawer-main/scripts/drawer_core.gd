@tool
extends PanelContainer

signal rebuild_requested

const HEIGHT_RATIO := 0.15
const MIN_HEIGHT := 60.0
const CFG_VERSION := 4
const SIDE_GAP := 40.0
const BOTTOM_GAP := 40.0
const MAX_WIDTH := 2200.0
const DETAILS_MIN_WIDTH := 140.0
const ANIM_TIME := 0.2
const SHOW_HINT := true
const HINT_BOTTOM := 44.0
const MAX_ITEMS := 3000
const SEARCH_DELAY := 0.18
const SAVE_DELAY := 0.6
# cooldown en secondes, uptime minimum en millisecondes
const RELOAD_COOLDOWN := 600
const RELOAD_MIN_UPTIME := 60000
const PREVIEW_DELAY := 0.08
const STICKY_MAX := 3
# tailles d'icônes fixes : on prend la plus proche du zoom au lieu de tout recalculer
const ICON_BUCKETS := [24, 64, 96, 160]
const HIDDEN_ALPHA := 0.45
const CFG_PATH := "res://.godot/asset_drawer.cfg"
const CFG_DIR_NAME := "asset_drawer"
const CFG_FILE_NAME := "asset_drawer.cfg"
const L := preload("res://addons/Asset_drawer-main/scripts/lang.gd")

var COLOR_BG_MAIN := Color(0.045, 0.05, 0.067, 1.0)
var COLOR_HEADER := Color(0.083, 0.097, 0.14, 1.0)
var COLOR_LEFT_PANEL := Color(0.083, 0.097, 0.14, 1.0)
var COLOR_CENTER_PANEL := Color(0.083, 0.097, 0.14, 1.0)
var COLOR_RIGHT_PANEL := Color(0.083, 0.097, 0.14, 1.0)
var COLOR_FOOTER := Color(0.084, 0.091, 0.114)
var COLOR_BORDER := Color(0.26, 0.30, 0.37, 0.65)
var COLOR_PATH_BG := Color(0.062, 0.068, 0.086)
const BAR_H := 26.0

var TEXT_PRIMARY := Color(0.93, 0.94, 0.97)
var TEXT_SECONDARY := Color(0.93, 0.94, 0.97, 0.62)
var TEXT_MUTED := Color(0.93, 0.94, 0.97, 0.38)
var COLOR_POPUP_BG := Color(0.09, 0.10, 0.13, 0.97)
var COLOR_CARD_BG := Color(0.10, 0.12, 0.15, 0.96)
var COLOR_TRACK := Color(0.42, 0.46, 0.54)
var _font_color := Color(0.93, 0.94, 0.97)
var _palette_sig := ""

const COLOR_FAV := Color(0.98, 0.78, 0.32)
const COLOR_RES_ACTION := Color(0.34, 0.76, 0.48)
const COLOR_DANGER := Color(0.90, 0.36, 0.40)

const GODOT_COLOR_KEYS := [
	"red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "gray"
]

const FOLDER_COLORS := {
	"red": Color(0.95, 0.35, 0.35), "orange": Color(0.98, 0.58, 0.25),
	"yellow": Color(0.96, 0.80, 0.25), "green": Color(0.35, 0.78, 0.45),
	"teal": Color(0.25, 0.78, 0.75), "cyan": Color(0.35, 0.75, 0.95),
	"blue": Color(0.35, 0.65, 0.98), "purple": Color(0.68, 0.45, 0.95),
	"pink": Color(0.95, 0.45, 0.72), "gray": Color(0.60, 0.62, 0.68),
	"crimson": Color(0.88, 0.22, 0.38), "coral": Color(0.98, 0.50, 0.42),
	"salmon": Color(0.98, 0.63, 0.56), "peach": Color(0.99, 0.74, 0.58),
	"apricot": Color(0.97, 0.68, 0.36), "amber": Color(0.96, 0.72, 0.15),
	"gold": Color(0.85, 0.75, 0.32), "lime": Color(0.63, 0.85, 0.25),
	"mint": Color(0.50, 0.91, 0.66), "emerald": Color(0.22, 0.75, 0.50),
	"jade": Color(0.30, 0.70, 0.58), "turquoise": Color(0.28, 0.82, 0.85),
	"sky": Color(0.45, 0.79, 0.98), "azure": Color(0.26, 0.60, 0.95),
	"indigo": Color(0.42, 0.45, 0.90), "violet": Color(0.60, 0.38, 0.92),
	"magenta": Color(0.88, 0.32, 0.82), "fuchsia": Color(0.93, 0.40, 0.70),
	"lavender": Color(0.72, 0.66, 0.96), "plum": Color(0.66, 0.35, 0.60),
	"brown": Color(0.68, 0.46, 0.32), "chocolate": Color(0.55, 0.36, 0.25),
	"tan": Color(0.82, 0.68, 0.50), "sand": Color(0.86, 0.79, 0.62),
	"khaki": Color(0.74, 0.72, 0.44), "olive": Color(0.58, 0.62, 0.28),
	"moss": Color(0.42, 0.55, 0.32), "slate": Color(0.48, 0.55, 0.66),
	"steel": Color(0.60, 0.68, 0.78), "silver": Color(0.78, 0.80, 0.84)
}
const DEFAULT_FOLDER_COLOR := Color(0.35, 0.65, 0.98)

const ICON_DIR := "res://addons/Asset_drawer-main/Icon/"
const GODOT_ICON_DIR := "res://addons/Asset_drawer-main/Icon/godot/"
const GEAR_ICON_PATH := ICON_DIR + "gear.png"
const ADDON_ICON := "res://addons/Asset_drawer-main/icon.svg"
const HELP_ROWS := [
	["Ctrl + Espace", "Ouvrir / fermer le tiroir"],
	["Ctrl + F", "Chercher un asset dans tout le projet"],
	["Tab", "Compléter le nom tapé (recherche ou chemin)"],
	["Ctrl + L", "Aller à un dossier : tape son chemin"],
	["F2 / Ctrl + D / Suppr", "Renommer / dupliquer / mettre à la corbeille"],
	["Clic droit", "Couleur de dossier, favoris, sets, masquer, copier la ressource"],
	["Alt + V", "Coller la ressource copiée sur un champ de l'Inspecteur"],
	["Survol", "Aperçu rapide : image, taille, date, chemin"],
	["Glisser-déposer", "Déposer un asset dans l'Inspecteur ou la scène ouverte"],
	["En haut à droite", "Tri, vue grille/liste, taille des miniatures, panneau de détails"],
	["Échap", "Fermer le tiroir"],
]
# place prise par l'icône dans sa case, la même partout pour que tout reste aligné
const ICON_RATIO := 0.62
const HOVER_DELAY := 0.25
const HOVER_PREVIEW := 96
const HOVER_TEXT_W := 150
const ICON_KEEP_COLOR := Color(0, 0, 0, 0)

const SHOW_TYPE_BAR := true
const TYPE_COLORS := {
	"scene": Color(0.30, 0.58, 0.98),
	"script": Color(0.35, 0.78, 0.45),
	"model": Color(0.68, 0.45, 0.95),
	"image": Color(0.98, 0.50, 0.16),
	"audio": Color(0.95, 0.80, 0.18),
	"shader": Color(0.95, 0.45, 0.72),
	"material": Color(0.20, 0.80, 0.55),
	"animation": Color(0.35, 0.68, 0.98),
	"font": Color(0.85, 0.72, 0.55),
	"resource": Color(0.60, 0.62, 0.68),
}

const TYPE_ICONS := {
	"model": "3D.svg",
	"animation": "animation.svg",
	"script": "code-json.svg",
	"image": "texture.svg",
	"audio": "music.svg",
	"font": "police.svg",
}

const PREVIEW_KINDS := ["image", "model", "scene", "script", "audio", "material"]

var is_open := false
var pinned := false
var current_dir := "res://"
var _history: PackedStringArray = PackedStringArray(["res://"])
var _history_i := 0
var _favorites: PackedStringArray = PackedStringArray()
var _fav_migrated := false
var _recents: PackedStringArray = PackedStringArray()
var _sets: Dictionary = {}
var _active_set := ""
var _collapsed: Dictionary = {}
var _tween: Tween
var _glow_tween: Tween
var _panel_style: StyleBoxFlat
var _toast: PanelContainer
var _toast_overlay: Control
var _toast_lbl: Label
var _toast_tween: Tween
var _height_ratio := HEIGHT_RATIO
var _resizing := false
var _view_list := false
var _details_visible := true
var _context_path := ""
var _clip_resource: Resource
var _clip_resource_name := ""
var _paste_pop: Button
var _paste_target: EditorResourcePicker
var _paste_tween: Tween
var _copy_pop: Button
var _copy_target_path := ""
var _copy_tween: Tween
var _pending_select := ""
var _selected_filter := 0
var _hidden: PackedStringArray = PackedStringArray()
var _folder_colors: Dictionary = {}
var _language := "auto"
var _context_from_tree := false
var _show_hidden := false
var _search_all := true
var _last_script_ext := "gd"
var _index: Array = []
var _index_dirty := true
var _btn_scope: Button
var _active_left_tab := 0
var _syncing_tree := false
var _zoom_grid := 64.0
var _zoom_list := 22.0

var _split: HSplitContainer
var _left_vbox: VBoxContainer
var _tree: Tree
var _tree_tools: HBoxContainer
var _sticky_box: Control
var _tree_vscroll: VScrollBar
var _sticky_sig := ""
var _row_pitch := 0.0
var _pending_reveal: TreeItem
var _center_tween: Tween
var _tab_list: ItemList
var _btn_new_set: Button
var _breadcrumbs: HBoxContainer
var _search: LineEdit
var _zoom: HSlider
var _list: ItemList
var _empty_state: VBoxContainer
var _empty_lbl: Label
var _empty_link: LinkButton
var _status: Label
var _details_panel: PanelContainer
var _details_width := 190.0
var _preview: TextureRect
var _preview_shadows: Array[TextureRect] = []
var _details_name: Label
var _details_path: Label
var _lbl_type: Label
var _lbl_size: Label
var _lbl_modified: Label
var _lbl_uid: Label
var _btn_open: Button
var _btn_fav: Button
var _btn_copy_res: Button
var _btn_copy_path: Button
var _details_scroll: ScrollContainer
var _details_dv: VBoxContainer
var _details_btn_box: BoxContainer
var _details_type_row: HFlowContainer
var _chip_type: PanelContainer
var _chip_size: PanelContainer
var _chip_date: PanelContainer
var _field_path: VBoxContainer
var _field_uid: VBoxContainer
var _details_card: PanelContainer
var _details_sep_info: ColorRect
var _details_card_sep: ColorRect
var _btn_labels: Dictionary = {}
var _details_compact := false
var _btn_grid: Button
var _btn_list: Button
var _btn_details: Button
var _btn_pin: Button
var _filter_buttons: Array[Button] = []
var _left_tab_buttons: Array[Button] = []
var _ctx_popup: PanelContainer
var _gear_pop: PanelContainer
var _gear_vbox: VBoxContainer
var _btn_gear: Button
var _copy_hiding := false
var _paste_hiding := false
var _ctx_vbox: VBoxContainer
var _grip: ColorRect
var _hd_icon_cache := {}
var _hint: PanelContainer
var _hint_tween: Tween
var _btn_back: Button
var _empty_reset: Button
var _btn_fwd: Button
var _btn_up: Button
var _outside_close_msec := -1000
var _preview_cache := {}
var _preview_pending := {}
var _svg_queue: Array = []
var _svg_px := {}
var _svg_fail := {}
var _path_index := {}
var _item_colors := PackedColorArray()
var _bar_style: StyleBoxFlat
var _dir_paths := {}
var _file_types := {}
var _art_ratio := {}
var _sort_mode := "name"
var _sort_desc := false
var _btn_sort: Button
var _path_edit: LineEdit
var _hover_pop: PanelContainer
var _hover_tex: TextureRect
var _hover_title: Label
var _hover_info: Label
var _hover_path_lbl: Label
var _hover_meta: Label
var _hover_timer: Timer
var _hover_path := ""
var _drop_list_idx := -1
var _drop_tree_item: TreeItem
var _drop_whole := false
var _mq_active := false
var _mq_moved := false
var _mq_start := Vector2.ZERO
var _mq_cur := Vector2.ZERO
var _mq_base: PackedInt32Array = PackedInt32Array()
var _tree_items := {}
var _dirty := true
var _tree_dirty := true
var _save_dirty := false
var _reload_on_enable := true
var _last_reload_stamp := 0
var _cfg_global_path := ""
var _cfg_resave := false
var _truncated := false
var _icon_bucket := 0
var _search_timer: Timer
var _save_timer: Timer
var _preview_timer: Timer


var _rect_includes_scroll := -1

const MODEL_EXTS := ["glb", "gltf", "fbx", "blend", "dae", "obj"]

const MODEL_SCENE_EXTS := ["glb", "gltf", "fbx", "blend", "dae"]

const REF_EXTS := ["tscn", "tres", "gd", "gdshader", "gdshaderinc", "godot", "cfg"]

func _make_timer(delay: float, cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	t.timeout.connect(cb)
	add_child(t)
	return t

func _update_palette() -> void:
	var base := EditorInterface.get_base_control()
	var es := EditorInterface.get_editor_settings()
	var base_c := Color(0.21, 0.24, 0.29)
	var contrast := 0.3
	if es.has_setting("interface/theme/base_color"):
		base_c = es.get_setting("interface/theme/base_color")
	if es.has_setting("interface/theme/contrast"):
		contrast = float(es.get_setting("interface/theme/contrast"))
	if base.has_theme_color("base_color", "Editor"):
		base_c = base.get_theme_color("base_color", "Editor")
	var black := Color(0, 0, 0, 1)
	var d1 := base_c.lerp(black, contrast)
	var d2 := base_c.lerp(black, contrast * 1.5)
	var d3 := base_c.lerp(black, contrast * 2.0)
	if base.has_theme_color("dark_color_1", "Editor"):
		d1 = base.get_theme_color("dark_color_1", "Editor")
	if base.has_theme_color("dark_color_2", "Editor"):
		d2 = base.get_theme_color("dark_color_2", "Editor")
	if base.has_theme_color("dark_color_3", "Editor"):
		d3 = base.get_theme_color("dark_color_3", "Editor")
	base_c = _solid(base_c)
	d1 = _solid(d1)
	d2 = _solid(d2)
	d3 = _solid(d3)

	var font := Color(0.93, 0.94, 0.97) if base_c.get_luminance() < 0.5 else Color(0.10, 0.11, 0.13)
	if base.has_theme_color("font_color", "Editor"):
		font = base.get_theme_color("font_color", "Editor")
	font = _solid(font)

	_font_color = font
	COLOR_BG_MAIN = d2
	COLOR_HEADER = d1
	COLOR_LEFT_PANEL = d1
	COLOR_CENTER_PANEL = d1
	COLOR_RIGHT_PANEL = d1
	COLOR_FOOTER = d1
	COLOR_PATH_BG = d2
	COLOR_BORDER = _with_a(base_c.lerp(font, 0.22), 0.65)
	COLOR_POPUP_BG = _with_a(d1, 0.97)
	COLOR_CARD_BG = _with_a(d1, 0.96)
	COLOR_TRACK = base_c.lerp(font, 0.35)
	TEXT_PRIMARY = font
	TEXT_SECONDARY = _with_a(font, 0.62)
	TEXT_MUTED = _with_a(font, 0.38)
	_palette_sig = _palette_signature()

func _palette_signature() -> String:
	var base := EditorInterface.get_base_control()
	var es := EditorInterface.get_editor_settings()
	var parts := PackedStringArray()
	for k in ["interface/theme/base_color", "interface/theme/contrast", "interface/theme/accent_color"]:
		parts.append(str(es.get_setting(k)) if es.has_setting(k) else "-")
	for n in ["base_color", "dark_color_1", "dark_color_2", "dark_color_3", "font_color", "accent_color"]:
		parts.append(str(base.get_theme_color(n, "Editor")) if base.has_theme_color(n, "Editor") else "-")
	return "|".join(parts)

func palette_changed() -> bool:
	return _palette_signature() != _palette_sig

func _solid(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0)

func _with_a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

func _ov(a: float) -> Color:
	return Color(_font_color.r, _font_color.g, _font_color.b, a)

func _native_panel_sb() -> StyleBox:
	var base := EditorInterface.get_base_control()
	if base != null and base.has_theme_stylebox("panel", "Panel"):
		return base.get_theme_stylebox("panel", "Panel")
	return null

func _native_popup_sb() -> StyleBox:
	var base := EditorInterface.get_base_control()
	for t in ["PopupPanel", "PopupMenu"]:
		if base != null and base.has_theme_stylebox("panel", t):
			return base.get_theme_stylebox("panel", t)
	return null

func _flat_button(b: Button) -> void:
	var base := EditorInterface.get_base_control()
	if base != null and base.has_theme_stylebox("normal", "FlatButton"):
		b.theme_type_variation = "FlatButton"

func _make_stylebox(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 4, border_w: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border != Color.TRANSPARENT:
		style.border_color = border
		style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	return style

func _hover_c(c: Color) -> Color:
	return c.lightened(0.09)

func _press_c(c: Color) -> Color:
	return c.darkened(0.16)

func _setup_style() -> void:
	var sb := _native_panel_sb()
	if sb != null:
		add_theme_stylebox_override("panel", sb)
	_panel_style = null

func _pad(margin: int, top_bottom: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	var tb := margin if top_bottom < 0 else top_bottom
	m.add_theme_constant_override("margin_left", margin)
	m.add_theme_constant_override("margin_right", margin)
	m.add_theme_constant_override("margin_top", tb)
	m.add_theme_constant_override("margin_bottom", tb)
	return m

func _make_chip(lbl: Label, tint: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _make_stylebox(tint, Color.TRANSPARENT, 3))
	var pad := _pad(2, 0)
	pad.add_theme_constant_override("margin_top", -2)
	pad.add_theme_constant_override("margin_bottom", -2)
	chip.add_child(pad)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_constant_override("line_spacing", 0)
	lbl.add_theme_constant_override("outline_size", 0)
	pad.add_child(lbl)
	return chip

func _make_field(title: String, val: Label) -> VBoxContainer:
	var f := VBoxContainer.new()
	f.add_theme_constant_override("separation", 1)
	var t := Label.new()
	t.text = title
	t.modulate = TEXT_MUTED
	f.add_child(t)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_child(val)
	return f

func _soft_wrap(t: String) -> String:
	var zw := char(0x200B)
	return t.replace("_", "_" + zw).replace(".", "." + zw).replace("/", "/" + zw).replace("-", "-" + zw)

func _detail_sep() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COLOR_BORDER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _detail_btn(icon_names: String, label: String, tip: String = "") -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.expand_icon = false
	b.icon = _icon_from(icon_names)
	_btn_labels[b] = [label, tip]
	_apply_btn_mode(b)
	return b

func _svg_file_image(path: String, px: int, tint: Color) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return null
	var probe := Image.new()
	if probe.load_svg_from_string(src, 1.0) != OK:
		return null
	var longest := maxi(probe.get_width(), probe.get_height())
	if longest <= 0:
		return null
	var img := Image.new()
	if img.load_svg_from_string(src, float(px) / float(longest)) != OK:
		return null
	if img.get_width() <= 0 or img.get_height() <= 0:
		return null
	img.convert(Image.FORMAT_RGBA8)
	if tint.a > 0.0:
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, img.get_pixel(x, y).a))
	return img

func _global_cfg_path() -> String:
	if not _cfg_global_path.is_empty():
		return _cfg_global_path
	var ep := EditorInterface.get_editor_paths()
	if ep == null:
		return ""
	var dir := ep.get_data_dir()
	if dir.is_empty():
		return ""
	dir = dir.path_join(CFG_DIR_NAME)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	_cfg_global_path = dir.path_join(CFG_FILE_NAME)
	return _cfg_global_path

func _cfg_read(c: ConfigFile) -> bool:
	var g := _global_cfg_path()
	if not g.is_empty():
		if c.load(g) == OK:
			return true
		if c.load(g + ".bak") == OK:
			_cfg_resave = true
			return true
	if FileAccess.file_exists(CFG_PATH) and c.load(CFG_PATH) == OK:
		_cfg_resave = true
		return true
	return false

func _cfg_write(c: ConfigFile) -> String:
	var g := _global_cfg_path()
	var target := g if not g.is_empty() else CFG_PATH
	if FileAccess.file_exists(target):
		var probe := ConfigFile.new()
		if probe.load(target) == OK:
			DirAccess.copy_absolute(target, target + ".bak")
	var err := c.save(target)
	if err != OK and target != CFG_PATH:
		if c.save(CFG_PATH) == OK:
			return CFG_PATH
	return target

func _hide_gear_panel() -> void:
	if is_instance_valid(_gear_pop):
		_gear_pop.visible = false

func _cfg_file_path() -> String:
	var g := _global_cfg_path()
	if not g.is_empty():
		return g
	return CFG_PATH

func _png_icon(path: String, px: int) -> Texture2D:
	var key := "png|%s|%d" % [path, px]
	if _hd_icon_cache.has(key):
		return _hd_icon_cache[key]
	if not ResourceLoader.exists(path):
		return null
	var src: Texture2D = load(path)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(maxi(2, px), maxi(2, px), Image.INTERPOLATE_LANCZOS)
	return _icon_cache_put(key, ImageTexture.create_from_image(img))

func _icon_cache_put(key: String, tex: Texture2D) -> Texture2D:
	if _hd_icon_cache.size() > 1200:
		_hd_icon_cache.clear()
	_hd_icon_cache[key] = tex
	return tex

func _svg_icon_tex(file_name: String, px: int, tint: Color, box: int = 0) -> Texture2D:
	var cache_key := "svg|%s|%d|%s|%d" % [file_name, px, tint.to_html(), box]
	if _hd_icon_cache.has(cache_key):
		return _hd_icon_cache[cache_key]
	var raw := _svg_file_image(ICON_DIR + file_name, px, tint)
	if raw == null:
		return null
	var out := raw
	if box > 0:
		out = Image.create(box, box, false, Image.FORMAT_RGBA8)
		out.blend_rect(raw, Rect2i(0, 0, raw.get_width(), raw.get_height()),
			Vector2i((box - raw.get_width()) / 2, (box - raw.get_height()) / 2))
	var tex := ImageTexture.create_from_image(out)
	return _icon_cache_put(cache_key, tex)

func _addon_icon_tex(px: int) -> Texture2D:
	var key := "addon|%d" % px
	if _hd_icon_cache.has(key):
		return _hd_icon_cache[key]
	var raw := _svg_file_image(ADDON_ICON, px, ICON_KEEP_COLOR)
	if raw == null:
		return null
	return _icon_cache_put(key, ImageTexture.create_from_image(raw))

func _icon_art_ratio(tex: Texture2D) -> float:
	if tex == null:
		return ICON_RATIO
	var key := tex.get_instance_id()
	if _art_ratio.has(key):
		return _art_ratio[key]
	var ratio := ICON_RATIO
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		if img.get_width() > 0:
			# les icônes ont des marges transparentes, on mesure ce qui est vraiment dessiné
			var used := img.get_used_rect()
			if used.size.x > 0:
				ratio = clampf(float(used.size.x) / float(img.get_width()), 0.2, 1.0)
	_art_ratio[key] = ratio
	return ratio

func _editor_icon_available(name: String) -> bool:
	if name.is_empty():
		return false
	if FileAccess.file_exists(GODOT_ICON_DIR + name + ".svg"):
		return true
	var base := EditorInterface.get_base_control()
	return base != null and base.has_theme_icon(name, "EditorIcons")

func _editor_icon_name(name: String) -> String:
	var n := name
	var guard := 0
	while guard < 32 and not n.is_empty():
		guard += 1
		if _editor_icon_available(n):
			return n
		if not ClassDB.class_exists(n):
			break
		n = ClassDB.get_parent_class(n)
	return ""

func _editor_icon(name: String) -> Texture2D:
	var real := _editor_icon_name(name)
	if real.is_empty():
		return null
	var tex := _svg_icon_tex("godot/" + real + ".svg", 16, ICON_KEEP_COLOR)
	if tex != null:
		return tex
	var base := EditorInterface.get_base_control()
	if base != null and base.has_theme_icon(real, "EditorIcons"):
		return base.get_theme_icon(real, "EditorIcons")
	return null

func _icon_from(names: String) -> Texture2D:
	for n in names.split(","):
		var tex := _editor_icon(n)
		if tex != null:
			return tex
	return null

func _tint_btn_icon(b: Button, c: Color) -> void:
	for n in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(n, c)

func _untint_btn_icon(b: Button) -> void:
	for n in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		b.remove_theme_color_override(n)

func _set_btn_label(b: Button, label: String) -> void:
	var d: Array = _btn_labels.get(b, ["", ""])
	d[0] = label
	_btn_labels[b] = d
	_apply_btn_mode(b)

func _apply_btn_mode(b: Button) -> void:
	var d: Array = _btn_labels.get(b, ["", ""])
	var label: String = d[0]
	var tip: String = d[1]
	if _details_compact:
		b.text = ""
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = label if tip == "" else label + "\n" + tip
	else:
		b.text = label
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = tip

func _bar_panel(inner: Control, expand: bool = false, pad_h: int = 3) -> Control:
	var p := _pad(pad_h, 2)
	p.custom_minimum_size = Vector2(0, BAR_H)
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(inner)
	return p

func _icon_btn(icon_name: String, fallback: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	_style_ghost_button(b, 5, 2)
	b.icon = _icon_from(icon_name)
	if b.icon == null:
		b.text = fallback
	return b

func _style_ghost_button(b: Button, _h: int = 6, _v: int = 3, _active_bg: Color = Color.TRANSPARENT) -> void:
	_flat_button(b)

func _add_press_bounce(_b: Button, _hover_scale: float = 1.08, _press_scale: float = 0.9) -> void:
	pass

func _bounce_to(node: Control, target: Vector2, dur: float) -> void:
	if not is_instance_valid(node):
		return
	var tw: Tween = node.get_meta("_bounce_tween") if node.has_meta("_bounce_tween") else null
	if tw != null and tw.is_valid():
		tw.kill()
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", target, dur)
	node.set_meta("_bounce_tween", t)

func _is_docked() -> bool:
	return get_parent() is EditorDock

func _style_item_list(_list: ItemList) -> void:
	pass


func _bucket(size: int) -> int:
	for b in ICON_BUCKETS:
		if size <= int(b):
			return int(b)
	return int(ICON_BUCKETS[ICON_BUCKETS.size() - 1])


func _colors() -> Dictionary:
	return ProjectSettings.get_setting("file_customization/folder_colors", {})

# couleurs connues de Godot + celles qu'il ne connaît pas (gardées chez nous)
func _all_colors() -> Dictionary:
	if _folder_colors.is_empty():
		return _colors()
	var out: Dictionary = _colors().duplicate()
	for k in _folder_colors.keys():
		out[k] = _folder_colors[k]
	return out

func _resolve_color(colors: Dictionary, path: String) -> String:
	var p := path.trim_suffix("/")
	var guard := 0
	while guard < 64:
		guard += 1
		var v := str(colors.get(p + "/", colors.get(p, "")))
		if v != "":
			return v
		if p == "res:" or p == "res:/" or p == "" or p == "res://":
			break
		var parent := p.get_base_dir()
		if parent == p:
			break
		p = parent
	return ""

func _folder_color(colors: Dictionary, path: String) -> Color:
	return FOLDER_COLORS.get(_resolve_color(colors, path), DEFAULT_FOLDER_COLOR)

func _type_kind(path: String, type: String) -> String:
	var ext := path.get_extension().to_lower()
	var known := type != "" and ClassDB.class_exists(type)
	if ext in ["obj", "fbx", "glb", "gltf", "blend", "dae"] or (known and ClassDB.is_parent_class(type, "Mesh")):
		return "model"
	if ext in ["tscn", "scn"] or type == "PackedScene":
		return "scene"
	if ext in ["gd", "cs", "cpp", "h"] or (known and ClassDB.is_parent_class(type, "Script")):
		return "script"
	if ext in ["png", "jpg", "jpeg", "svg", "webp", "bmp", "tga", "exr", "hdr", "dds", "ktx"] or (known and ClassDB.is_parent_class(type, "Texture")):
		return "image"
	if ext in ["wav", "ogg", "mp3"] or (known and ClassDB.is_parent_class(type, "AudioStream")):
		return "audio"
	if ext in ["gdshader", "shader", "gdshaderinc"] or (known and ClassDB.is_parent_class(type, "Shader")):
		return "shader"
	if known and ClassDB.is_parent_class(type, "Material"):
		return "material"
	if type.begins_with("Animation") or (known and ClassDB.is_parent_class(type, "Animation")):
		return "animation"
	if ext in ["ttf", "otf", "woff", "woff2", "fnt"] or (known and ClassDB.is_parent_class(type, "Font")):
		return "font"
	return "resource"

func _kind_has_preview(path: String, type: String) -> bool:
	return PREVIEW_KINDS.has(_type_kind(path, type))

func _type_color(path: String, type: String) -> Color:
	return TYPE_COLORS[_type_kind(path, type)]

func _item_rect(i: int, expand: bool = true) -> Rect2:
	var r := _list.get_item_rect(i, expand)
	var sv := _list.get_v_scroll_bar().value
	if sv <= 0.0:
		return r
	if _rect_includes_scroll < 0:
		_detect_rect_scroll(sv)
	if _rect_includes_scroll == 0:
		r.position.y -= sv
	return r

func _detect_rect_scroll(sv: float) -> void:
	var xs: Array[float] = [24.0, maxf(float(_list.fixed_column_width) * 0.5, 24.0), 80.0]
	var y := 6.0
	while y < _list.size.y:
		for x in xs:
			var p := Vector2(x, y)
			var idx := _list.get_item_at_position(p, true)
			if idx < 0:
				continue
			var r := _list.get_item_rect(idx, true)
			var as_screen := r.has_point(p)
			r.position.y -= sv
			var as_content := r.has_point(p)
			if as_screen != as_content:
				_rect_includes_scroll = 1 if as_screen else 0
				return
		y += 10.0

func _current_zoom() -> float:
	return _zoom_list if _view_list else _zoom_grid

func _style_zoom_slider(_accent: Color) -> void:
	pass

func _name_matches(name_lc: String, tokens: PackedStringArray) -> bool:
	for t in tokens:
		if not name_lc.contains(t):
			return false
	return true


func _hidden_key(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		return path.trim_suffix("/") + "/"
	return path

func _is_hidden(path: String) -> bool:
	if _hidden.is_empty():
		return false
	var pd := path if path.ends_with("/") else path + "/"
	for h in _hidden:
		if h.ends_with("/"):
			if pd.begins_with(h):
				return true
		elif path == h:
			return true
	return false

func _pass_filter(path: String, filter_idx: int) -> bool:
	if filter_idx <= 0:
		return true
	var ext := path.get_extension().to_lower()
	match filter_idx:
		1: return ext in ["tscn", "scn"]
		2: return ext in ["gd", "cs", "cpp", "h"]
		3: return ext in ["obj", "fbx", "glb", "gltf", "blend"]
		4: return ext in ["png", "jpg", "jpeg", "svg", "webp", "bmp", "tga", "exr", "hdr"]
		5: return ext in ["wav", "ogg", "mp3"]
		6: return ext in ["gdshader", "shader", "gdshaderinc"]
	return true

func _update_status_bar(_unused: int = -1) -> void:
	if _list == null or _status == null:
		return
	var total := _list.item_count
	var sel_count := _list.get_selected_items().size()
	var where := current_dir if _active_set.is_empty() else L.t("Set : ") + _active_set
	var txt := L.t("%d élément%s") % [total, "s" if total > 1 else ""]
	if _truncated:
		txt += L.t(" (limité à %d)") % MAX_ITEMS
	if sel_count > 0:
		txt += L.t(" · %d sélectionné%s") % [sel_count, L.sel_s(sel_count > 1)]
	_status.text = txt + " · " + where

func _flash(msg: String, is_error: bool = false) -> void:
	if _status != null:
		_status.text = msg
	if is_inside_tree():
		get_tree().create_timer(2.5).timeout.connect(_update_status_bar)
	_show_toast(msg, is_error)

func _show_toast(msg: String, is_error: bool) -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast_lbl.text = msg
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var col: Color = COLOR_DANGER if is_error else accent
	_toast.add_theme_stylebox_override("panel", _make_stylebox(COLOR_POPUP_BG, Color(col.r, col.g, col.b, 0.85), 8, 1))
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(0.88, 0.88)
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.7)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2(0.94, 0.94), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _rel_time(mtime: int) -> String:
	var diff := int(Time.get_unix_time_from_system()) - mtime
	if diff < 60:
		return L.t("à l'instant")
	if diff < 3600:
		return L.t("il y a %d min") % (diff / 60)
	if diff < 86400:
		return L.t("il y a %d h") % (diff / 3600)
	if diff < 172800:
		return L.t("hier")
	var d := Time.get_date_dict_from_unix_time(mtime)
	if L.is_fr():
		return "%02d/%02d/%d" % [d.day, d.month, d.year]
	return "%d-%02d-%02d" % [d.year, d.month, d.day]

func _fmt_size(bytes: int) -> String:
	if bytes < 1024:
		return L.t("%d o") % bytes
	if bytes < 1024 * 1024:
		return L.t("%.1f Ko") % (bytes / 1024.0)
	return L.t("%.1f Mo") % (bytes / (1024.0 * 1024.0))

func _sort_label(mode: String) -> String:
	match mode:
		"date":
			return "Date"
		"size":
			return "Taille"
		"type":
			return "Type"
	return "Nom"

func _file_bytes(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

func _norm_dir(p: String) -> String:
	if p == "res://" or p == "res:/":
		return "res://"
	return p.trim_suffix("/")


func _valid_name(n: String) -> bool:
	if n.strip_edges().is_empty():
		return false
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		if n.contains(ch):
			_flash(L.t("Nom invalide : caractère « %s » interdit") % ch, true)
			return false
	return true

func _unique_path(dir: String, base_name: String, ext: String) -> String:
	var p := dir.path_join(base_name + ext)
	var i := 2
	while FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p):
		p = dir.path_join("%s_%d%s" % [base_name, i, ext])
		i += 1
	return p

func _script_template(ext: String, base_name: String) -> String:
	match ext:
		"gd":
			return "extends Node\n\n\nfunc _ready() -> void:\n\tpass\n"
		"cs":
			var cls := ""
			for ch in base_name.to_pascal_case():
				if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_":
					cls += ch
			if cls.is_empty() or (cls[0] >= "0" and cls[0] <= "9"):
				cls = "_" + cls
			return "using Godot;\n\npublic partial class %s : Node\n{\n\tpublic override void _Ready()\n\t{\n\t}\n}\n" % cls
		"gdshader":
			return "shader_type canvas_item;\n\nvoid fragment() {\n}\n"
		"json":
			return "{}\n"
		"xml":
			return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		"md":
			return "# %s\n" % base_name
	return ""

func _is_under(p: String, src: String) -> bool:
	var sp := p.trim_suffix("/")
	return sp == src or sp.begins_with(src + "/")

func _swap_prefix(p: String, src: String, dst: String) -> String:
	var sp := p.trim_suffix("/")
	var slash := "/" if p.ends_with("/") else ""
	if sp == src:
		return dst + slash
	if sp.begins_with(src + "/"):
		return dst + p.substr(src.length())
	return p
