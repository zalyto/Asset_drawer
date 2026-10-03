@tool
extends PanelContainer

const HEIGHT_RATIO := 0.15      # drawer height (share of the editor window)
const MIN_HEIGHT := 60.0       # the content imposes a minimum anyway (top / bottom bars)
const CFG_VERSION := 4          # v3: more compact drawer by default (reduced height)
const SIDE_GAP := 40.0          # gap left on each side
const BOTTOM_GAP := 40.0        # gap below the drawer (keeps the Output / Debugger / Audio bar visible...)
const MAX_WIDTH := 2200.0
const DETAILS_MIN_WIDTH := 140.0       # minimum width of the details panel (resizable beyond it)
const ANIM_TIME := 0.2
const SHOW_HINT := true         # "Asset Drawer  Ctrl+Space" pill at the bottom of the editor
const HINT_BOTTOM := 44.0
const MAX_ITEMS := 3000         # cap on displayed items (performance)
const SEARCH_DELAY := 0.18      # search debounce
const FOCUS_SEARCH_ON_OPEN := true   # focus the search bar when the drawer opens: just start typing
const SAVE_DELAY := 0.6         # config save debounce
const PREVIEW_DELAY := 0.08     # thumbnail loading debounce
const STICKY_MAX := 3           # max number of parent folders pinned at the top of the tree
# _sticky_row_h() = height reserved per pinned row (always equal to one full row).
const ICON_BUCKETS := [24, 64, 96, 160]
const HIDDEN_ALPHA := 0.45      # opacity of hidden items when they are shown
const CFG_PATH := "res://.godot/asset_drawer.cfg"
const L := preload("res://addons/asset_drawer/lang.gd")   # FR / EN translations
const Sc := preload("res://addons/asset_drawer/shortcuts.gd")   # customizable shortcuts (Project Settings)

# --- Palette --------------------------------------------------------------
# The background / border / text colors below are VARIABLES: the values written here
# are only a fallback. They are recomputed at startup by _update_palette() from the
# editor theme (Editor Settings > Interface > Theme > Base Color + Contrast).
# Principle: few hues, a clear elevation hierarchy (from the darkest "foundation"
# to the lightest "under the fingers"), an accent used sparingly (drawer border,
# selection, focus) rather than spread everywhere, and a single gray scale for text.
var COLOR_BG_MAIN := Color(0.045, 0.05, 0.067, 1.0)      # foundation (the drawer itself)
var COLOR_HEADER := Color(0.083, 0.097, 0.14, 1.0)       # top bar (nav + search + filters)
var COLOR_LEFT_PANEL := Color(0.083, 0.097, 0.14, 1.0)   # folder tree
var COLOR_CENTER_PANEL := Color(0.083, 0.097, 0.14, 1.0) # asset grid/list, slightly raised
var COLOR_RIGHT_PANEL := Color(0.083, 0.097, 0.14, 1.0)  # details panel
var COLOR_FOOTER := Color(0.084, 0.091, 0.114)        # status bar, the darkest (bottom anchor)
var COLOR_BORDER := Color(0.26, 0.30, 0.37, 0.65)    # thin edge between panels, not a hard line
var COLOR_PATH_BG := Color(0.062, 0.068, 0.086)      # shared background of the top bar containers
const BAR_H := 26.0                                    # shared height of the top bar containers

# Text hierarchy: a single gray scale (never pure white, easier on the eyes).
var TEXT_PRIMARY := Color(0.93, 0.94, 0.97)          # titles, name of the selected file
var TEXT_SECONDARY := Color(0.93, 0.94, 0.97, 0.62)  # paths, meta info, status text
var TEXT_MUTED := Color(0.93, 0.94, 0.97, 0.38)      # subtle text (placeholders, separators)
var COLOR_POPUP_BG := Color(0.09, 0.10, 0.13, 0.97)    # notification background
var COLOR_CARD_BG := Color(0.10, 0.12, 0.15, 0.96)     # background of small cards (drag preview, drop target)
var COLOR_TRACK := Color(0.42, 0.46, 0.54)             # track of the zoom slider
var _font_color := Color(0.93, 0.94, 0.97)             # editor text color (base of the _ov overlays)
var _palette_sig := ""                                 # signature of the theme used to build the UI

# Semantic colors: each one has a single meaning across the whole UI.
const COLOR_FAV := Color(0.98, 0.78, 0.32)                        # favorites (gold)
const COLOR_RES_ACTION := Color(0.34, 0.76, 0.48)                 # copy/paste a resource (green)
const COLOR_DANGER := Color(0.90, 0.36, 0.40)                     # deletion, errors (red)

# Color names = the ones stored by Godot's FileSystem dock
const FOLDER_COLORS := {
	"red": Color(0.95, 0.35, 0.35), "orange": Color(0.98, 0.58, 0.25),
	"yellow": Color(0.96, 0.80, 0.25), "green": Color(0.35, 0.78, 0.45),
	"teal": Color(0.25, 0.78, 0.75), "cyan": Color(0.35, 0.75, 0.95),
	"blue": Color(0.35, 0.65, 0.98), "purple": Color(0.68, 0.45, 0.95),
	"pink": Color(0.95, 0.45, 0.72), "gray": Color(0.60, 0.62, 0.68)
}
const DEFAULT_FOLDER_COLOR := Color(0.35, 0.65, 0.98)

# Color strip under each thumbnail (in list view: bar on the left), one color per asset type,
# like in Unreal's Content Browser. Set SHOW_TYPE_BAR to false to disable it.
const SHOW_TYPE_BAR := true
const TYPE_COLORS := {
	"scene": Color(0.30, 0.58, 0.98),      # .tscn / .scn scenes — blue
	"script": Color(0.35, 0.78, 0.45),     # scripts — green
	"model": Color(0.68, 0.45, 0.95),      # 3D models and meshes — purple
	"image": Color(0.98, 0.50, 0.16),      # textures / images — bright orange
	"audio": Color(0.95, 0.80, 0.18),      # sounds — yellow/gold, clearly distinct from the orange above
	"shader": Color(0.95, 0.45, 0.72),     # shaders — pink
	"material": Color(0.20, 0.80, 0.55),   # materials — teal
	"animation": Color(0.35, 0.68, 0.98),  # animations — sky blue, distinct from the teal above
	"font": Color(0.85, 0.72, 0.55),       # fonts — beige
	"resource": Color(0.60, 0.62, 0.68),   # any other resource / file — gray
}

var is_open := false
var pinned := false
var current_dir := "res://"
var _history: PackedStringArray = PackedStringArray(["res://"])
var _history_i := 0
var _favorites: PackedStringArray = PackedStringArray()
var _fav_migrated := false          # old local favorites already merged into Godot's
var _recents: PackedStringArray = PackedStringArray()
var _sets: Dictionary = {}          # set name -> Array of paths
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
var _ctx_sel_override: PackedStringArray = PackedStringArray()   # right-click on a tree item: not part of the list selection
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
var _hidden: PackedStringArray = PackedStringArray()   # hidden items (folder = path ending with "/")
var _show_hidden := false
var _search_all := true         # search the whole project (otherwise: current folder)
var _last_script_ext := "gd"
var _index: Array = []          # flat index of file/folder names (global search)
var _index_dirty := true
var _btn_scope: Button
var _active_left_tab := 0
var _syncing_tree := false
var _zoom_grid := 80.0             # remembered grid-mode zoom (thumbnail size)
var _zoom_list := 22.0             # remembered list-mode zoom (icon size)

var _split: HSplitContainer
var _left_vbox: VBoxContainer
var _tree: Tree
var _tree_tools: HBoxContainer
var _tree_tools_box: PanelContainer   # rounded container around the tree buttons
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
var _btn_labels: Dictionary = {}     # button -> [label, tooltip]
var _details_compact := false        # true: buttons on a single row of icon-only buttons
var _btn_grid: Button
var _btn_list: Button
var _btn_details: Button
var _btn_pin: Button
var _filter_buttons: Array[Button] = []
var _left_tab_buttons: Array[Button] = []
var _ctx_popup: PanelContainer
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
var _card_images := {}
var _preview_cache := {}       # path -> Godot thumbnail (null = failure)
var _preview_pending := {}     # paths already sent to the previewer
var _svg_queue: Array = []     # [path, target size]: SVGs we rasterize ourselves (sharp at any size)
var _svg_px := {}              # path -> size (px) of the last successful rasterization
var _svg_fail := {}            # SVGs Godot could not rasterize: we fall back to its thumbnail
var _path_index := {}          # path -> index in _list
var _item_colors := PackedColorArray()   # color of each _list item's strip (transparent = none)
var _bar_style: StyleBoxFlat
var _dir_paths := {}           # paths of the displayed folders
var _drop_list_idx := -1        # list folder highlighted during a drag and drop
var _drop_tree_item: TreeItem   # tree folder highlighted during a drag and drop
var _drop_whole := false        # drop into the current folder (empty area): frame around the list
var _mq_active := false         # rectangle selection ("lasso") in progress
var _mq_moved := false
var _mq_start := Vector2.ZERO   # start in "content" coordinates (scroll included)
var _mq_cur := Vector2.ZERO     # current mouse position (list coordinates)
var _mq_base: PackedInt32Array = PackedInt32Array()   # starting selection (Ctrl / Shift)
var _tree_items := {}          # normalized path -> TreeItem
var _dirty := true
var _tree_dirty := true
var _save_dirty := false
var _truncated := false
var _icon_bucket := 0
var _search_timer: Timer
var _opened_msec := 0
var _create_menu_open := false   # the context popup currently shows the Shift+A create menu
var _save_timer: Timer
var _preview_timer: Timer


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 128
	z_as_relative = false
	clip_contents = false
	_search_timer = _make_timer(SEARCH_DELAY, _refresh)
	_save_timer = _make_timer(SAVE_DELAY, _flush_cfg)
	_preview_timer = _make_timer(PREVIEW_DELAY, _request_visible_previews)
	_load_cfg()
	_update_palette()
	_setup_style()
	_build_ui()
	_apply_saved_state()

	var base := EditorInterface.get_base_control()
	if not base.resized.is_connected(_on_editor_resized):
		base.resized.connect(_on_editor_resized)
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_fs_changed):
		fs.filesystem_changed.connect(_on_fs_changed)
	if not fs.resources_reimported.is_connected(_on_reimported):
		fs.resources_reimported.connect(_on_reimported)
	if SHOW_HINT:
		_build_hint(base)


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


func _make_timer(delay: float, cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	t.timeout.connect(cb)
	add_child(t)
	return t


func _on_fs_changed() -> void:
	# Nothing to rebuild while the drawer is closed: we just mark it "dirty".
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


## Drawer palette = the editor's. Backgrounds come from "Base Color" and "Contrast"
## (Godot derives dark_color_1/2/3 from them with base.lerp(black, contrast), contrast * 1.5, contrast * 2).
## We read those colors from the editor theme (they also follow the presets), and fall back to
## computing them from the settings if they are missing.
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
	# Panels use d1 (the least dark): with a high contrast, d2 / d3 become
	# almost black. The drawer background and the inset fields use d2, always darker than the panels.
	COLOR_BG_MAIN = d2            # foundation (the drawer itself)
	COLOR_HEADER = d1             # top bar
	COLOR_LEFT_PANEL = d1         # folder tree
	COLOR_CENTER_PANEL = d1       # asset grid / list
	COLOR_RIGHT_PANEL = d1        # details panel
	COLOR_FOOTER = d1             # status bar
	COLOR_PATH_BG = d2            # inset containers of the top bar
	COLOR_BORDER = _with_a(base_c.lerp(font, 0.22), 0.65)
	COLOR_POPUP_BG = _with_a(d1, 0.97)
	COLOR_CARD_BG = _with_a(d1, 0.96)
	COLOR_TRACK = base_c.lerp(font, 0.35)
	TEXT_PRIMARY = font
	TEXT_SECONDARY = _with_a(font, 0.62)
	TEXT_MUTED = _with_a(font, 0.38)
	_palette_sig = _palette_signature()


## Fingerprint of the current theme: lets the plugin know whether the drawer must be rebuilt.
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


## Translucent overlay in the editor's text color (hovers, separators...).
## Replaces the old Color(1, 1, 1, a), invisible on a light theme.
func _ov(a: float) -> Color:
	return Color(_font_color.r, _font_color.g, _font_color.b, a)


func _make_stylebox(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 6, border_w: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if border != Color.TRANSPARENT:
		style.border_color = border
		style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	return style


## Lightens a color for a hovered state — a single setting used everywhere (chips,
## list rows, floating buttons) so the hover "feel" is identical
## across the whole drawer rather than slightly different depending on where you look.
func _hover_c(c: Color) -> Color:
	return c.lightened(0.09)


## Darkens a color for a pressed/active state — counterpart of _hover_c() above.
func _press_c(c: Color) -> Color:
	return c.darkened(0.16)


func _setup_style() -> void:
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_MAIN
	# Thin, discreet outline (not a saturated solid line): the drawer must read as a
	# raised card above the editor, not as a neon-framed window.
	style.set_border_width_all(1)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_corner_radius_all(12)
	# Soft, wide shadow rather than tight: that is what gives the "floating card" feel
	# of depth in pro UIs, as opposed to a hard edge that reads as a "game window".
	style.shadow_color = Color(0, 0, 0, 0.30)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, -12)   # shifted upward: nothing sticks out below the drawer
	add_theme_stylebox_override("panel", style)
	_panel_style = style


func _pad(margin: int, top_bottom: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	var tb := margin if top_bottom < 0 else top_bottom
	m.add_theme_constant_override("margin_left", margin)
	m.add_theme_constant_override("margin_right", margin)
	m.add_theme_constant_override("margin_top", tb)
	m.add_theme_constant_override("margin_bottom", tb)
	return m


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
	main_vbox.add_theme_constant_override("separation", 3)
	pad.add_child(main_vbox)

	# --- HEADER ---
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _make_stylebox(COLOR_HEADER, COLOR_BORDER, 6, 1))
	var header_pad := _pad(5, 2)
	header.add_child(header_pad)
	header_pad.add_child(_build_toolbar())
	main_vbox.add_child(header)

	# --- SPLIT ---
	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.split_offset = 0
	main_vbox.add_child(_split)

	# --- LEFT PANEL ---
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(180, 0)
	left_panel.add_theme_constant_override("separation", 4)

	# Tabs (Folders / Favorites / Recents / Sets) in their own container
	var tabs_panel := PanelContainer.new()
	tabs_panel.add_theme_stylebox_override("panel", _make_stylebox(COLOR_HEADER, COLOR_BORDER, 6, 1))
	var tabs_pad := _pad(3)
	tabs_panel.add_child(tabs_pad)
	var left_tabs := HBoxContainer.new()
	left_tabs.add_theme_constant_override("separation", 2)
	tabs_pad.add_child(left_tabs)
	left_panel.add_child(tabs_panel)

	# Tab content: same background for the tree and the lists
	var left_content := PanelContainer.new()
	left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.add_theme_stylebox_override("panel", _make_stylebox(COLOR_LEFT_PANEL, COLOR_BORDER, 6, 1))
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
		_style_ghost_button(btn, 4, 3, Color(accent.r, accent.g, accent.b, 0.45))
		btn.button_pressed = (i == 0)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		var tab_idx := i
		btn.pressed.connect(func() -> void: _switch_left_tab(tab_idx))
		left_tabs.add_child(btn)
		_left_tab_buttons.append(btn)

	# Tools row (always visible): tree buttons on the left (Folders tab only), then the
	# "create" container (new folder / scene / script) pushed to the right.
	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 4)
	_left_vbox.add_child(tools_row)
	# Same rounded container as the "create" box on the right
	_tree_tools_box = PanelContainer.new()
	_tree_tools_box.add_theme_stylebox_override("panel", _topbar_stylebox())
	tools_row.add_child(_tree_tools_box)
	var tools_pad := _pad(2, 1)
	_tree_tools_box.add_child(tools_pad)
	_tree_tools = HBoxContainer.new()
	_tree_tools.add_theme_constant_override("separation", 0)
	tools_pad.add_child(_tree_tools)
	_add_tree_tool_button("CollapseTree", "⇤", L.t("Tout replier"), _collapse_all_folders)
	_add_tree_tool_button("ExpandTree", "◎", L.t("Localiser le dossier courant"), _sync_tree_selection)
	var tools_spacer := Control.new()
	tools_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_row.add_child(tools_spacer)
	tools_row.add_child(_build_create_box())

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

	# --- CENTER AREA ---
	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.add_theme_stylebox_override("panel", _make_stylebox(COLOR_CENTER_PANEL, COLOR_BORDER, 6, 1))
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
	# Keyboard focus keeps working (arrows, activation...), but without the accent frame
	# that Godot draws by default around the focused control — it looked like an unintended
	# selection of the whole panel when the drawer opened.
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
	var reset_n := _pill_style(accent)
	var reset_h := _pill_style(accent.lightened(0.15))
	for st in [reset_n, reset_h]:
		(st as StyleBoxFlat).content_margin_left = 12
		(st as StyleBoxFlat).content_margin_right = 12
		(st as StyleBoxFlat).content_margin_top = 4
		(st as StyleBoxFlat).content_margin_bottom = 4
	_empty_reset.add_theme_stylebox_override("normal", reset_n)
	_empty_reset.add_theme_stylebox_override("hover", reset_h)
	_empty_reset.add_theme_stylebox_override("pressed", reset_n)
	_empty_reset.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_empty_reset.add_theme_color_override("font_color", Color.WHITE)
	_empty_reset.add_theme_color_override("font_hover_color", Color.WHITE)
	_empty_reset.pressed.connect(func() -> void: _set_filter(0))
	_empty_state.add_child(_empty_reset)
	center_pad.add_child(_empty_state)
	# Center + details: resizable HSplitContainer (2 children, compatible with Godot 4.2+).
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.dragged.connect(_on_details_split_dragged)
	right_split.add_child(center_panel)
	_details_panel = _build_details_panel()
	right_split.add_child(_details_panel)
	# offset=0 would give the panel (non-expand, second child) its minimum width;
	# a negative offset gives it back the remembered width (or the default width on first launch).
	right_split.split_offset = -int(maxf(_details_width - DETAILS_MIN_WIDTH, 0.0))
	_split.add_child(right_split)

	# --- FOOTER ---
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _make_stylebox(COLOR_FOOTER, COLOR_BORDER, 6, 1))
	var footer_pad := _pad(6, 1)
	footer.add_child(footer_pad)
	footer_pad.add_child(_build_footer())
	main_vbox.add_child(footer)

	# Context menu = a simple PanelContainer placed on the editor overlay (rather than a
	# PopupPanel window): no more square black corners behind the rounded edges.
	_ctx_popup = PanelContainer.new()
	_ctx_popup.visible = false
	_ctx_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_ctx_popup.z_index = 350
	var ctx_style := _make_stylebox(COLOR_HEADER, COLOR_BORDER, 8, 1)
	ctx_style.shadow_color = Color(0, 0, 0, 0.55)
	ctx_style.shadow_size = 10
	ctx_style.shadow_offset = Vector2(0, 3)
	_ctx_popup.add_theme_stylebox_override("panel", ctx_style)
	var ctx_margin := _pad(8)
	_ctx_popup.add_child(ctx_margin)
	_ctx_vbox = VBoxContainer.new()
	_ctx_vbox.add_theme_constant_override("separation", 2)
	ctx_margin.add_child(_ctx_vbox)

	_build_toast()
	_toast_overlay.add_child(_ctx_popup)
	_build_paste_pop()


## Small floating "Paste" button that appears near any resource field
## of the Inspector (compatible with the copied resource) when the mouse hovers it —
## like dragging and dropping assets in Unreal's Content Browser.
func _build_paste_pop() -> void:
	var base := EditorInterface.get_base_control()

	_paste_pop = Button.new()
	_paste_pop.text = ""
	_paste_pop.tooltip_text = L.t("Coller la ressource copiée ici")
	_paste_pop.custom_minimum_size = Vector2(22, 22)
	_paste_pop.expand_icon = true
	_paste_pop.visible = false
	_paste_pop.modulate.a = 0.0
	_paste_pop.focus_mode = Control.FOCUS_NONE
	_paste_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_paste_pop.z_index = 200  # above the drawer panel itself (z_index = 128)
	if base.has_theme_icon("ActionPaste", "EditorIcons"):
		_paste_pop.icon = base.get_theme_icon("ActionPaste", "EditorIcons")
	elif base.has_theme_icon("ActionCopy", "EditorIcons"):
		_paste_pop.icon = base.get_theme_icon("ActionCopy", "EditorIcons")
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


## Small floating "Copy" button (icon only, same green as "Paste") that appears when
## hovering a resource in the drawer's list — counterpart of the "Paste" button on the Inspector side.
func _build_copy_pop() -> void:
	var base := EditorInterface.get_base_control()
	_copy_pop = Button.new()
	_copy_pop.text = ""
	_copy_pop.tooltip_text = L.t("Copier la ressource")
	_copy_pop.custom_minimum_size = Vector2(22, 22)
	_copy_pop.expand_icon = true
	_copy_pop.visible = false
	_copy_pop.modulate.a = 0.0
	_copy_pop.focus_mode = Control.FOCUS_NONE
	_copy_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_copy_pop.z_index = 200  # above the drawer panel itself (z_index = 128)
	if base.has_theme_icon("ActionCopy", "EditorIcons"):
		_copy_pop.icon = base.get_theme_icon("ActionCopy", "EditorIcons")
	elif base.has_theme_icon("Duplicate", "EditorIcons"):
		_copy_pop.icon = base.get_theme_icon("Duplicate", "EditorIcons")
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
	# Added at the editor level (like the hint pill), not as a child of the drawer:
	# it must stay visible even when the drawer is closed (e.g. after an Alt+V paste).
	_toast_overlay = Control.new()
	_toast_overlay.name = "AssetDrawerToastOverlay"
	_toast_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.add_child(_toast_overlay)

	# Strip centered at the bottom of the editor that hosts the toast (auto-centered by the CenterContainer).
	var bottom_bar := CenterContainer.new()
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -58
	bottom_bar.offset_bottom = -14
	_toast_overlay.add_child(bottom_bar)

	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	# Must stay readable even above the "Ctrl+Space" pill (z_index = 200) and the
	# drawer panel (z_index = 128), since both occupy the same area at the bottom of the screen.
	_toast.z_index = 300
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	_toast.add_theme_stylebox_override("panel", _make_stylebox(COLOR_POPUP_BG, Color(accent.r, accent.g, accent.b, 0.85), 8, 1))
	var pad := _pad(14, 7)
	_toast.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pad.add_child(row)
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(_toast_lbl)
	bottom_bar.add_child(_toast)


func _build_toolbar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	wrap.add_child(row)

	# Top bar: each group in a dark container of the same height, same outline, same corners
	var accent_bar: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")

	# 1) Navigation
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
	_btn_up.tooltip_text = Sc.with_hint(L.t("Dossier parent"), "parent_folder")
	_btn_up.pressed.connect(_go_up)
	nav_row.add_child(_btn_up)

	# 2) Breadcrumb
	_breadcrumbs = HBoxContainer.new()
	_breadcrumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breadcrumbs.clip_contents = true
	row.add_child(_bar_panel(_breadcrumbs, true))

	# 3) Search: same background / outline as the containers
	_search = LineEdit.new()
	_search.placeholder_text = Sc.with_hint(L.t("Rechercher..."), "focus_search")
	_search.clear_button_enabled = true
	_search.right_icon = EditorInterface.get_base_control().get_theme_icon("Search", "EditorIcons")
	_search.custom_minimum_size = Vector2(170, BAR_H)
	var search_box := _topbar_stylebox()
	search_box.content_margin_left = 8
	search_box.content_margin_right = 6
	search_box.content_margin_top = 2
	search_box.content_margin_bottom = 2
	var search_focus := search_box.duplicate() as StyleBoxFlat
	search_focus.border_color = Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.9)
	_search.add_theme_stylebox_override("normal", search_box)
	_search.add_theme_stylebox_override("focus", search_focus)
	_search.add_theme_stylebox_override("read_only", search_box)
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	_search.gui_input.connect(_on_search_gui_input)
	row.add_child(_search)

	# Search scope: whole project / current folder
	_btn_scope = _icon_btn("Filesystem,Folder", L.t("Projet"))
	_btn_scope.toggle_mode = true
	_btn_scope.button_pressed = _search_all
	_btn_scope.toggled.connect(_on_scope_toggled)
	_style_ghost_button(_btn_scope, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.45))
	row.add_child(_bar_panel(_btn_scope))
	_update_search_ui()

	# 4) Display mode (grid / list)
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
	_style_ghost_button(_btn_grid, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.45))
	_style_ghost_button(_btn_list, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.45))

	# 5) Zoom
	_zoom = HSlider.new()
	_zoom.min_value = 48
	_zoom.max_value = 160
	_zoom.step = 8
	_zoom.value = 80
	_zoom.tooltip_text = L.t("Taille des miniatures (Ctrl+molette)")
	_zoom.custom_minimum_size.x = 80
	_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom.value_changed.connect(_on_zoom_changed)
	_style_zoom_slider(accent_bar)
	row.add_child(_bar_panel(_zoom, false, 8))

	# 6) Actions: details, pin, dock, close
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	row.add_child(_bar_panel(actions))

	_btn_details = _icon_btn("ControlLayout", L.t("Détails"))
	_btn_details.tooltip_text = L.t("Panneau de détails")
	_btn_details.toggle_mode = true
	_btn_details.toggled.connect(func(on: bool) -> void:
		_details_visible = on
		_details_panel.visible = on
		_save_cfg()
	)
	_style_ghost_button(_btn_details, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.45))
	actions.add_child(_btn_details)

	_btn_pin = _icon_btn("Pin", L.t("Épingler"))
	_btn_pin.tooltip_text = L.t("Épingler (reste ouvert)")
	_btn_pin.toggle_mode = true
	_btn_pin.toggled.connect(func(on: bool) -> void:
		pinned = on
		_save_cfg()
	)
	_style_ghost_button(_btn_pin, 5, 2, Color(accent_bar.r, accent_bar.g, accent_bar.b, 0.45))
	actions.add_child(_btn_pin)

	var dock_btn := Button.new()
	dock_btn.text = "DOCK"
	dock_btn.tooltip_text = L.t("Afficher ce dossier dans le dock Fichiers")
	dock_btn.focus_mode = Control.FOCUS_NONE
	dock_btn.add_theme_font_size_override("font_size", 10)
	_style_ghost_button(dock_btn, 6, 2)
	dock_btn.pressed.connect(func() -> void: _show_in_dock(current_dir))
	actions.add_child(dock_btn)

	var close_btn := _icon_btn("Close", "X")
	close_btn.tooltip_text = Sc.with_hint(L.t("Fermer"), "close_drawer")
	close_btn.pressed.connect(close)
	actions.add_child(close_btn)

	# Row 2: filters
	var filters_box := HBoxContainer.new()
	filters_box.add_theme_constant_override("separation", 3)
	var filters := [L.t("Tout"), L.t("Scènes"), "Scripts", L.t("Modèles"), "Images", "Audio", "Shaders"]
	for i in range(filters.size()):
		var btn := Button.new()
		btn.text = filters[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		var idx := i
		btn.pressed.connect(func() -> void: _set_filter(idx))
		_add_press_bounce(btn, 1.06, 0.92)
		_filter_buttons.append(btn)
		filters_box.add_child(btn)
	wrap.add_child(filters_box)
	_update_filter_pills()
	return wrap


func _build_details_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAILS_MIN_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _make_stylebox(COLOR_RIGHT_PANEL, COLOR_BORDER, 6, 1))

	# Everything is in a ScrollContainer: the panel can be very short, so it scrolls.
	# When there is no more room, the buttons switch to a single row of icon-only buttons.
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

	# --- Header: framed thumbnail on the left; on the right the name then chips (type, size, date) ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	dv.add_child(head)

	# Frameless thumbnail: a small drop shadow is drawn behind the image itself
	# (slightly enlarged black silhouettes that get more and more transparent = soft shadow).
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
	_details_name.add_theme_font_size_override("font_size", 12)
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

	# --- Separator + inset info card: path, UID (hidden if there is nothing to show) ---
	_details_sep_info = _detail_sep()
	dv.add_child(_details_sep_info)

	_details_card = PanelContainer.new()
	_details_card.add_theme_stylebox_override("panel", _make_stylebox(COLOR_PATH_BG, COLOR_BORDER.darkened(0.25), 6, 1))
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

	# --- Separator before the actions area ---
	dv.add_child(_detail_sep())

	# --- Buttons: column with text + icon, or a row of icon-only buttons when space is short ---
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
		L.t("Puis survolez un champ ressource de l'Inspecteur (ex. Mesh d'un MeshInstance3D) : un bouton « Coller » apparaît (ou %s au clavier)") % Sc.label("paste_resource", "–"))
	# Same green as the "Paste resource" button (COLOR_RES_ACTION): the two actions
	# form a visual pair (copy here → paste over there).
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


## Rounded chip (type, size, date) around a Label.
func _make_chip(lbl: Label, tint: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _make_stylebox(tint, Color.TRANSPARENT, 4))
	var pad := _pad(2, 0)
	# Negative vertical margins: removes the line spacing the Label adds around the text
	pad.add_theme_constant_override("margin_top", -2)
	pad.add_theme_constant_override("margin_bottom", -2)
	chip.add_child(pad)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_constant_override("line_spacing", 0)
	lbl.add_theme_constant_override("outline_size", 0)
	pad.add_child(lbl)
	return chip


## "Discreet title above, value below" field: readable even for long values.
func _make_field(title: String, val: Label) -> VBoxContainer:
	var f := VBoxContainer.new()
	f.add_theme_constant_override("separation", 1)
	var t := Label.new()
	t.text = title
	t.modulate = TEXT_MUTED
	t.add_theme_font_size_override("font_size", 9)
	f.add_child(t)
	val.add_theme_font_size_override("font_size", 10)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_child(val)
	return f


## Adds invisible break points (zero-width space) after _ . / -
## so that long names wrap cleanly instead of in the middle of a word.
func _soft_wrap(t: String) -> String:
	var zw := char(0x200B)
	return t.replace("_", "_" + zw).replace(".", "." + zw).replace("/", "/" + zw).replace("-", "-" + zw)


## Thin separator line between the zones of the details panel.
func _detail_sep() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COLOR_BORDER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Details panel button: icon (first name found in the list) + label + tooltip.
func _detail_btn(icon_names: String, label: String, tip: String = "") -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.expand_icon = false
	b.add_theme_font_size_override("font_size", 11)
	b.icon = _icon_from(icon_names)
	_btn_labels[b] = [label, tip]
	_apply_btn_mode(b)
	return b


func _icon_from(names: String) -> Texture2D:
	var base := EditorInterface.get_base_control()
	for n in names.split(","):
		if base.has_theme_icon(n, "EditorIcons"):
			return base.get_theme_icon(n, "EditorIcons")
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


## Text + icon on the left (normal mode) or centered icon only, text as tooltip (compact mode).
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


func _set_fav_state(path: String) -> void:
	var fav := _is_fav(path)
	_set_btn_label(_btn_fav, L.t("Retirer des favoris") if fav else L.t("Ajouter aux favoris"))
	_btn_fav.icon = _icon_from("Favorites") if fav else _icon_from("NonFavorite,Favorites")
	if fav:
		_tint_btn_icon(_btn_fav, COLOR_FAV)
	else:
		_untint_btn_icon(_btn_fav)


## Hides empty info (« - ») to keep only what is useful.
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


## Switches between buttons in a column (text + icon) and a row of icons depending on the available room.
## The height needed for normal mode is recomputed every time (no remembered value):
## current content height, minus the current button area, plus the stacked buttons.
func _update_details_layout() -> void:
	if _details_scroll == null or _details_dv == null:
		return
	var avail := _details_scroll.size.y
	if avail <= 0.0 or _details_scroll.size.x < 60.0:
		return   # not laid out yet
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


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	_status = Label.new()
	_status.modulate = TEXT_SECONDARY
	_status.add_theme_font_size_override("font_size", 12)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	footer.add_child(_status)

	return footer


## Small rounded container with the most common operations: new folder / scene / script.
## Lives at the top of the left panel so they are always one click away.
func _build_create_box() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _topbar_stylebox())
	var pad := _pad(2, 1)
	box.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	pad.add_child(row)

	var btn_f := _icon_btn("Folder", "+" + L.t("Dossier"))
	btn_f.tooltip_text = L.t("Nouveau dossier")
	btn_f.pressed.connect(func() -> void: _create_folder())
	row.add_child(btn_f)
	var btn_sc := _icon_btn("PackedScene,Node", L.t("+Scène"))
	btn_sc.tooltip_text = L.t("Nouvelle scène")
	btn_sc.pressed.connect(func() -> void: _create_scene())
	row.add_child(btn_sc)
	var btn_st := _icon_btn("ScriptCreate,Script", "+Script")
	btn_st.tooltip_text = L.t("Nouveau script")
	btn_st.pressed.connect(func() -> void: _create_script())
	row.add_child(btn_st)
	return box


func _topbar_stylebox() -> StyleBoxFlat:
	return _make_stylebox(COLOR_PATH_BG, COLOR_BORDER.darkened(0.25), 6, 1)


# Uniform dark container of the top bar (same height, outline and corners)
func _bar_panel(inner: Control, expand: bool = false, pad_h: int = 3) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, BAR_H)
	p.add_theme_stylebox_override("panel", _topbar_stylebox())
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := _pad(pad_h, 2)
	p.add_child(pad)
	pad.add_child(inner)
	return p


func _icon_btn(icon_name: String, fallback: String) -> Button:
	# icon_name can contain several names separated by commas: the first existing one is used
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	_style_ghost_button(b, 5, 2)
	var base := EditorInterface.get_base_control()
	var found := false
	for n in icon_name.split(","):
		if base.has_theme_icon(n, "EditorIcons"):
			b.icon = base.get_theme_icon(n, "EditorIcons")
			found = true
			break
	if not found:
		b.text = fallback
	return b


func _ghost_box(bg: Color, h: int, v: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(5)
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	return s


func _style_ghost_button(b: Button, h: int = 6, v: int = 3, active_bg: Color = Color.TRANSPARENT) -> void:
	if active_bg.a <= 0.0:
		active_bg = _ov(0.18)
	# Transparent at rest, "panel" on hover; active state (toggle button) more pronounced.
	# flat must stay false, otherwise Godot draws no background.
	b.flat = false
	b.add_theme_stylebox_override("normal", _ghost_box(Color(1, 1, 1, 0.0), h, v))
	b.add_theme_stylebox_override("hover", _ghost_box(_ov(0.10), h, v))
	b.add_theme_stylebox_override("pressed", _ghost_box(active_bg, h, v))
	b.add_theme_stylebox_override("hover_pressed", _ghost_box(active_bg.lightened(0.1), h, v))
	b.add_theme_stylebox_override("disabled", _ghost_box(Color(1, 1, 1, 0.0), h, v))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_add_press_bounce(b)


## Micro-interaction shared by all "ghost" buttons: slight zoom on hover,
## small "squash" on click. Gives the drawer a livelier, more responsive feel.
func _add_press_bounce(b: Button, hover_scale: float = 1.08, press_scale: float = 0.9) -> void:
	b.pivot_offset = b.size * 0.5
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _bounce_to(b, Vector2.ONE * hover_scale, 0.12))
	b.mouse_exited.connect(func() -> void: _bounce_to(b, Vector2.ONE, 0.16))
	b.button_down.connect(func() -> void: _bounce_to(b, Vector2.ONE * press_scale, 0.06))
	b.button_up.connect(func() -> void:
		var target := Vector2.ONE * hover_scale if b.is_hovered() else Vector2.ONE
		_bounce_to(b, target, 0.14)
	)


func _bounce_to(node: Control, target: Vector2, dur: float) -> void:
	if not is_instance_valid(node):
		return
	# has_meta() first: get_meta(key, null) still logs an error on a missing key, because
	# null is indistinguishable from "no default given" on the engine side.
	if node.has_meta("_bounce_tween"):
		var tw: Tween = node.get_meta("_bounce_tween")
		if tw != null and is_instance_valid(tw) and tw.is_valid():
			tw.kill()
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", target, dur)
	node.set_meta("_bounce_tween", t)


## Softer selection/hover highlight (rounded corners + slight accent glow)
## than the default square rectangle of the ItemList.
func _style_item_list(list: ItemList) -> void:
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	# Selection: tinted background + crisp 2 px outline + slight glow (the ✓ badge is drawn on top).
	var sel := _make_stylebox(Color(accent.r, accent.g, accent.b, 0.20), Color(accent.r, accent.g, accent.b, 0.95), 8, 2)
	sel.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	sel.shadow_size = 5
	list.add_theme_stylebox_override("selected", sel)
	list.add_theme_stylebox_override("selected_focus", sel)
	list.add_theme_stylebox_override("cursor", _make_stylebox(Color.TRANSPARENT, Color(accent.r, accent.g, accent.b, 0.45), 8, 1))
	list.add_theme_stylebox_override("cursor_unfocused", StyleBoxEmpty.new())
	# "hovered" only exists from Godot 4.3; silently ignored on earlier versions.
	list.add_theme_stylebox_override("hovered", _make_stylebox(_ov(0.07), _ov(0.14), 8, 1))
	# Selected AND hovered: without these two, Godot 4.3+ falls back to its default grey style,
	# so the accent selection turned grey under the mouse. Same look, slightly stronger fill.
	var sel_hover := _make_stylebox(Color(accent.r, accent.g, accent.b, 0.30), Color(accent.r, accent.g, accent.b, 1.0), 8, 2)
	sel_hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	sel_hover.shadow_size = 6
	list.add_theme_stylebox_override("hovered_selected", sel_hover)
	list.add_theme_stylebox_override("hovered_selected_focus", sel_hover)


func _update_nav_buttons() -> void:
	if _btn_back == null:
		return
	_btn_back.disabled = _history_i <= 0
	_btn_fwd.disabled = _history_i >= _history.size() - 1
	_btn_up.disabled = _active_set.is_empty() and current_dir == "res://"


# ---------- Filters & tabs ----------

func _set_filter(idx: int) -> void:
	_selected_filter = idx
	_update_filter_pills()
	_refresh()


func _update_filter_pills() -> void:
	var accent: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	for i in range(_filter_buttons.size()):
		var b := _filter_buttons[i]
		var active := (i == _selected_filter)
		b.add_theme_stylebox_override("normal", _pill_style(accent if active else _ov(0.05)))
		b.add_theme_stylebox_override("hover", _pill_style(accent.lightened(0.15) if active else _ov(0.12)))
		b.add_theme_stylebox_override("pressed", _pill_style(accent))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if active:
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		else:
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")


func _pill_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(9)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


func _switch_left_tab(idx: int) -> void:
	_active_left_tab = idx
	_tree.visible = (idx == 0)
	_tree_tools_box.visible = (idx == 0)
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
			var idx := _tab_list.add_item("%s (%d)" % [n, (_sets[n] as Array).size()], base.get_theme_icon("Groups", "EditorIcons"))
			_tab_list.set_item_metadata(idx, str(n))
			_tab_list.set_item_tooltip(idx, L.t("Clic droit : supprimer le set"))
		return
	if _active_left_tab == 1:
		_sync_favorites()
	var src: PackedStringArray = _favorites if _active_left_tab == 1 else _recents
	var colors: Dictionary = ProjectSettings.get_setting("file_customization/folder_colors", {})
	for path in src:
		var is_dir := DirAccess.dir_exists_absolute(path)
		var idx := _tab_list.add_item(path.get_file() if path != "res://" else "res://", base.get_theme_icon("Folder" if is_dir else "File", "EditorIcons"))
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



# ---------- Anti-blur HD rendering ----------

func _sd_rounded_box(p: Vector2, b: Vector2, r: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - b + Vector2(r, r)
	return minf(maxf(q.x, q.y), 0.0) + Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() - r


func _bucket(size: int) -> int:
	for b in ICON_BUCKETS:
		if size <= int(b):
			return int(b)
	return int(ICON_BUCKETS[ICON_BUCKETS.size() - 1])


func _get_hd_folder_icon(size: int) -> Texture2D:
	# Grayscale icon: the folder color is applied by modulation
	# (a single texture per size instead of one per color).
	var cache_key := "folder_%d" % size
	if _hd_icon_cache.has(cache_key):
		return _hd_icon_cache[cache_key]

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var S := float(size)
	var tab_center := Vector2(S * 0.32, S * 0.26)
	var tab_size := Vector2(S * 0.22, S * 0.09)
	var tab_radius := S * 0.05
	var body_center := Vector2(S * 0.50, S * 0.58)
	var body_size := Vector2(S * 0.42, S * 0.28)
	var body_radius := S * 0.07

	var tab_color := Color(0.78, 0.78, 0.78)   # = darkened(0.22) once tinted
	var body_color := Color.WHITE

	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var d_tab := _sd_rounded_box(p - tab_center, tab_size, tab_radius)
			var d_body := _sd_rounded_box(p - body_center, body_size, body_radius)
			var a_tab := clampf(0.5 - d_tab, 0.0, 1.0)
			var a_body := clampf(0.5 - d_body, 0.0, 1.0)
			var c := Color(0, 0, 0, 0)
			if a_tab > 0.0:
				c = Color(tab_color.r, tab_color.g, tab_color.b, a_tab)
			if a_body > 0.0:
				c = c.blend(Color(body_color.r, body_color.g, body_color.b, a_body))
			img.set_pixel(x, y, c)

	var tex := ImageTexture.create_from_image(img)
	_hd_icon_cache[cache_key] = tex
	return tex


func _get_card_image(size: int) -> Image:
	# Common "card" background for all file types, computed only once per size
	if _card_images.has(size):
		return _card_images[size]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var S := float(size)
	var card_center := Vector2(S * 0.50, S * 0.52)
	var card_size := Vector2(S * 0.36, S * 0.40)
	var card_radius := S * 0.08
	var card_color := Color(0.16, 0.20, 0.26, 0.95)
	var border_color := Color(0.35, 0.45, 0.60, 0.8)
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _sd_rounded_box(p - card_center, card_size, card_radius)
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				var col := border_color if (d > -1.5) else card_color
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	_card_images[size] = img
	return img


func _raw_file_icon(base: Control, type: String) -> Texture2D:
	var icon_name := type if base.has_theme_icon(type, "EditorIcons") else "File"
	return base.get_theme_icon(icon_name, "EditorIcons")


func _get_hd_file_icon(base: Control, type: String, size: int, with_card: bool = true) -> Texture2D:
	var icon_name := type if base.has_theme_icon(type, "EditorIcons") else "File"
	if base.has_theme_icon(icon_name + "Big", "EditorIcons"):
		icon_name += "Big"
	var cache_key := "file_%s_%d_%s" % [icon_name, size, "card" if with_card else "flat"]
	if _hd_icon_cache.has(cache_key):
		return _hd_icon_cache[cache_key]

	var raw_tex := base.get_theme_icon(icon_name, "EditorIcons")
	var raw_img := raw_tex.get_image()
	if raw_img == null:
		return raw_tex
	if raw_img.is_compressed():
		raw_img.decompress()
	raw_img.convert(Image.FORMAT_RGBA8)

	var img: Image
	var inner_size: int
	if with_card:
		# Decorative "card" thumbnail (grid): icon at 52 % for a consistent look across types.
		img = _get_card_image(size).duplicate() as Image
		inner_size = int(size * 0.52)
	else:
		# No card: the container that displays this texture already has its own frame
		# (details panel), so the icon fills the thumbnail instead of floating in the middle
		# of a large transparent area.
		img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		inner_size = int(size * 0.82)
	raw_img.resize(inner_size, inner_size, Image.INTERPOLATE_LANCZOS)
	var offset := int((size - inner_size) / 2.0)
	img.blend_rect(raw_img, Rect2i(0, 0, inner_size, inner_size), Vector2i(offset, offset))

	var tex := ImageTexture.create_from_image(img)
	_hd_icon_cache[cache_key] = tex
	return tex




# ---------- Folder colors (inherited, like in the FileSystem dock) ----------

func _colors() -> Dictionary:
	return ProjectSettings.get_setting("file_customization/folder_colors", {})


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


func _set_folder_color(path: String, color_key: String) -> void:
	var colors: Dictionary = _colors().duplicate()
	var p := path.trim_suffix("/")
	colors.erase(p)
	colors.erase(p + "/")
	if not color_key.is_empty():
		colors[p + "/"] = color_key
	ProjectSettings.set_setting("file_customization/folder_colors", colors)
	ProjectSettings.save()
	_tree_dirty = true
	_refresh()


# ---------- Refresh ----------

func _refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	_sync_favorites()
	var fs := EditorInterface.get_resource_filesystem()
	# While the editor rescans (e.g. right after a rename), get_filesystem_path() returns null
	# even for folders that exist: that used to make the code below think the current folder was
	# gone and send us back to res://. We wait for filesystem_changed, which refreshes us when done.
	if _active_set.is_empty() and current_dir != "res://" and DirAccess.dir_exists_absolute(current_dir) \
			and fs.get_filesystem_path(current_dir) == null:
		_dirty = true
		return
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
	# If the current folder is gone, go up
	# Folder existence is checked on disk (reliable), not through the editor's file tree
	while _active_set.is_empty() and current_dir != "res://" and (not DirAccess.dir_exists_absolute(current_dir) or (not _show_hidden and _is_hidden(current_dir))):
		current_dir = current_dir.trim_suffix("/").get_base_dir()
		if current_dir == "res:":
			current_dir = "res://"
	_refresh_breadcrumbs()
	_update_nav_buttons()
	_refresh_left_tab_content()

	# entry = [path, type, is_folder, name]
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

	entries.sort_custom(func(a: Array, b: Array) -> bool:
		# entry = [path, type, is_folder, name, rank]  (rank: 0 exact name, 1 starts with, 2 contains)
		var ra: int = a[4] if a.size() > 4 else 0
		var rb: int = b[4] if b.size() > 4 else 0
		if ra != rb:
			return ra < rb
		if a[2] != b[2]:
			return a[2]
		return str(a[3]).naturalnocasecmp_to(str(b[3])) < 0
	)
	_truncated = entries.size() > MAX_ITEMS
	if _truncated:
		entries.resize(MAX_ITEMS)

	var custom_colors := _colors()
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
			# Results coming from several folders: show where they come from
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
			var tex: Texture2D = _preview_cache.get(path, null)
			if tex == null:
				tex = _raw_file_icon(base, type) if (_view_list and _icon_bucket <= 24) else _get_hd_file_icon(base, type, _icon_bucket)
			idx = _list.add_item(label, tex)
			if is_hid:
				_list.set_item_icon_modulate(idx, Color(1, 1, 1, HIDDEN_ALPHA))
		_list.set_item_metadata(idx, path)
		_list.set_item_tooltip(idx, path + (("\n" + L.t("Masqué dans le tiroir")) if is_hid else ""))
		_path_index[path] = idx
		_item_colors.append(Color(0, 0, 0, 0) if is_dir else _type_color(path, type))
		if _is_fav(path):
			_list.set_item_custom_fg_color(idx, COLOR_FAV)
		if is_hid:
			_list.set_item_custom_fg_color(idx, Color(1, 1, 1, HIDDEN_ALPHA))
	var shown := _list.item_count

	# Restore the selection (or select the newly created item)
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


## Strip color of an asset according to its type (resource class, otherwise extension).
func _type_color(path: String, type: String) -> Color:
	var ext := path.get_extension().to_lower()
	var known := type != "" and ClassDB.class_exists(type)
	var kind := "resource"
	if ext in ["obj", "fbx", "glb", "gltf", "blend", "dae"] or (known and ClassDB.is_parent_class(type, "Mesh")):
		kind = "model"
	elif ext in ["tscn", "scn"] or type == "PackedScene":
		kind = "scene"
	elif ext in ["gd", "cs", "cpp", "h"] or (known and ClassDB.is_parent_class(type, "Script")):
		kind = "script"
	elif ext in ["png", "jpg", "jpeg", "svg", "webp", "bmp", "tga", "exr", "hdr", "dds", "ktx"] or (known and ClassDB.is_parent_class(type, "Texture")):
		kind = "image"
	elif ext in ["wav", "ogg", "mp3"] or (known and ClassDB.is_parent_class(type, "AudioStream")):
		kind = "audio"
	elif ext in ["gdshader", "shader", "gdshaderinc"] or (known and ClassDB.is_parent_class(type, "Shader")):
		kind = "shader"
	elif known and ClassDB.is_parent_class(type, "Material"):
		kind = "material"
	elif type.begins_with("Animation") or (known and ClassDB.is_parent_class(type, "Animation")):
		kind = "animation"
	elif ext in ["ttf", "otf", "woff", "woff2", "fnt"] or (known and ClassDB.is_parent_class(type, "Font")):
		kind = "font"
	return TYPE_COLORS[kind]


# ItemList.get_item_rect() does not account for scrolling in every Godot version
# (rectangle in content coordinates instead of screen coordinates): the type strips, the
# badges and the "Copy" button then stayed fixed while the list was scrolled.
# We detect it once with a hover test (which is always correct), then correct for it.
var _rect_includes_scroll := -1   # -1 unknown, 0: rect without scroll, 1: rect already on screen


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
			if as_screen != as_content:   # unambiguous result
				_rect_includes_scroll = 1 if as_screen else 0
				return
		y += 10.0


## Draws, on top of the list, the colored indicator of each visible item:
## grid = bar inset at the bottom of the thumbnail; list = vertical bar on the left.
func _draw_type_bars() -> void:
	if not SHOW_TYPE_BAR or _list == null:
		return
	var n := mini(_list.item_count, _item_colors.size())
	if n == 0:
		return
	if _bar_style == null:
		_bar_style = StyleBoxFlat.new()
		_bar_style.set_corner_radius_all(2)
		# Thin dark outline: the bar stays readable even on a thumbnail of a color
		# close to its own (without it, a blue thumbnail with a blue "scene" bar
		# would almost completely blend into it).
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
			break   # items are laid out top to bottom: the rest is off screen
		_bar_style.bg_color = Color(c.r, c.g, c.b, 0.95)
		if _view_list:
			_list.draw_style_box(_bar_style, Rect2(r.position.x + 1.0, r.position.y + 3.0, 3.0, maxf(r.size.y - 6.0, 4.0)))
		else:
			var x := r.position.x + floorf((r.size.x - icon_w) * 0.5)
			# Inset in the last pixels of the thumbnail (not in the margin before the
			# text): so it can never overlap the file name, even on 2 lines.
			var y := r.position.y + margin + icon_w - thick - 1.0
			_list.draw_style_box(_bar_style, Rect2(x, y, icon_w, thick))


## On top of the list: ✓ badges of selected items, drop target (highlighted folder with
## "Move here" pill, or frame around the list) and the selection rectangle.
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


## Tree folder targeted during a drag and drop: rounded accent frame.
func _draw_tree_drop() -> void:
	if _drop_tree_item == null or not is_instance_valid(_drop_tree_item):
		return
	var acc: Color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	var r := _tree.get_item_area_rect(_drop_tree_item, 0).grow(-1.0)
	var st := _make_stylebox(Color(acc.r, acc.g, acc.b, 0.25), acc, 6, 2)
	st.shadow_color = Color(acc.r, acc.g, acc.b, 0.4)
	st.shadow_size = 5
	_tree.draw_style_box(st, r)


func _current_zoom() -> float:
	return _zoom_list if _view_list else _zoom_grid


# Adapts the slider range to the current mode and restores the remembered zoom of THIS mode
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


## Called when the user releases the separator between the list and the details panel.
## `offset` is already clamped by the SplitContainer (respects the minimums of both sides).
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
	# Zoom only affects the layout; the list is rebuilt only if the
	# generated icon size changes tier.
	_apply_list_layout()
	if _bucket(int(v)) != _icon_bucket:
		_refresh()
	else:
		_schedule_previews()


# Zoom slider readable on a dark background: light track, filled part in accent, round handle
func _style_zoom_slider(accent: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = COLOR_TRACK
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = accent
	var fill_hi := track.duplicate() as StyleBoxFlat
	fill_hi.bg_color = accent.lightened(0.2)
	_zoom.add_theme_stylebox_override("slider", track)
	_zoom.add_theme_stylebox_override("grabber_area", fill)
	_zoom.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	_zoom.add_theme_icon_override("grabber", _make_dot(12, TEXT_PRIMARY))
	_zoom.add_theme_icon_override("grabber_highlight", _make_dot(12, Color.WHITE))
	_zoom.add_theme_icon_override("grabber_disabled", _make_dot(12, COLOR_TRACK))


func _make_dot(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	var r := d * 0.5 - 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(r + 0.5 - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ---------- Lazy thumbnails ----------

func _schedule_previews() -> void:
	if _preview_timer != null and is_open:
		_preview_timer.start()


func _request_visible_previews() -> void:
	# Only requests thumbnails of visible items (+ one page of margin on each side)
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
		if path.get_extension().to_lower() == "svg" and not _svg_fail.has(path):
			# Godot's thumbnail is small (≈ 64 px) then enlarged: blurry. We rasterize the
			# SVG at display size, in small batches so the interface doesn't stutter.
			var target := _svg_target()
			if _preview_cache.has(path) and int(_svg_px.get(path, 0)) >= target:
				continue
			_preview_pending[path] = true
			_svg_queue.append([path, target])
			continue
		if _preview_cache.has(path):
			continue
		_preview_pending[path] = true
		previewer.queue_resource_preview(path, self, "_on_preview", path)


## All the search words must appear in the name (already lowercase).
func _name_matches(name_lc: String, tokens: PackedStringArray) -> bool:
	for t in tokens:
		if not name_lc.contains(t):
			return false
	return true


## Flat index (path, type, folder?, name, lowercase name) of the whole project.
## Rebuilt only when the file system changes: a search no longer walks
## the editor's tree, just this array.
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


## Search across the whole project (or under the current folder). Results ranked:
## exact name, then name starting with the 1st word, then name containing it.
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


func _on_scope_toggled(on: bool) -> void:
	_search_all = on
	_update_search_ui()
	_save_cfg()
	if not _search.text.strip_edges().is_empty():
		_refresh()


func _update_search_ui() -> void:
	if _search != null:
		_search.placeholder_text = Sc.with_hint(L.t("Rechercher dans tout le projet..."), "focus_search") if _search_all else Sc.with_hint(L.t("Rechercher dans ce dossier..."), "focus_search")
	if _btn_scope != null:
		_btn_scope.tooltip_text = L.t("Recherche : tout le projet (cliquer pour limiter au dossier courant)") if _search_all else L.t("Recherche : dossier courant (cliquer pour chercher dans tout le projet)")


# ---------- Hidden items ----------

## Stored key: a folder ends with "/", a file keeps its exact path.
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


func _update_status_bar(_unused: int = -1) -> void:
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
	_status.text = msg
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
		_preview.self_modulate = _folder_color(_colors(), path)
	else:
		var t := EditorInterface.get_resource_filesystem().get_file_type(path)
		_preview.self_modulate = Color.WHITE
		_lbl_type.text = t if t != "" else path.get_extension().to_upper()
		_lbl_size.text = "-"
		_lbl_modified.text = "-"
		_lbl_uid.text = "-"
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var bytes := f.get_length()
				f.close()
				if bytes < 1024:
					_lbl_size.text = L.t("%d o") % bytes
				elif bytes < 1024 * 1024:
					_lbl_size.text = L.t("%.1f Ko") % (bytes / 1024.0)
				else:
					_lbl_size.text = L.t("%.1f Mo") % (bytes / (1024.0 * 1024.0))
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
				_set_preview_tex(_get_hd_file_icon(EditorInterface.get_base_control(), t, 96, false))
				if not _preview_pending.has(path):
					_preview_pending[path] = true
					EditorInterface.get_resource_previewer().queue_resource_preview(path, self, "_on_preview", path)
	_set_fav_state(path)
	if is_instance_valid(_btn_copy_res):
		_btn_copy_res.visible = not is_dir
	_sync_details_meta()
	_update_details_layout.call_deferred()


func _refresh_breadcrumbs() -> void:
	for c in _breadcrumbs.get_children():
		_breadcrumbs.remove_child(c)
		c.queue_free()
	var bold := EditorInterface.get_base_control().get_theme_font("bold", "EditorFonts")
	var parts: Array = []   # [text, path or ""]
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
		btn.add_theme_font_size_override("font_size", 12)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", bold)
		var target: String = parts[i][1]
		if target != "":
			btn.pressed.connect(func() -> void: _navigate(target))
		else:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE   # non-clickable segment: no hover
		_breadcrumbs.add_child(btn)
		if i < parts.size() - 1:
			var sep := Label.new()
			sep.text = "›"
			sep.modulate = TEXT_MUTED
			_breadcrumbs.add_child(sep)


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
	var icon := EditorInterface.get_base_control().get_theme_icon("Folder", "EditorIcons")
	var root := _tree.create_item()
	root.set_text(0, "res://")
	root.set_metadata(0, "res://")
	root.set_icon(0, icon)
	_tree_items["res:/"] = root
	_fill_tree(root, fs, _colors(), icon)
	_syncing_tree = false
	_sync_tree_selection()


func _sync_tree_selection() -> void:
	# Selects the current folder without rebuilding the tree
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
		# Collapsed by default (large projects); the current folder is expanded on selection
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


# ---------- Tree: pinned (sticky) items, single click, tools ----------

func _add_tree_tool_button(icon_name: String, fallback: String, tip: String, cb: Callable) -> void:
	# Ghost button (same as the others): a rounded background appears on hover / press
	var b := _icon_btn(icon_name, fallback)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	_tree_tools.add_child(b)


func _setup_sticky() -> void:
	# Overlay placed on the tree: shows the parent folders "stuck" at the top.
	# Home-made implementation (works from Godot 4.2, without relying on 4.8's sticky Tree).
	_sticky_box = Control.new()
	_sticky_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Safety net: whatever happens (late signature, shaky row measurement on the
	# first display, etc.), the overlay must NEVER be able to draw outside the tree's
	# rectangle — neither above nor below.
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
	# Safeguard: the "Ctrl+Space" pill must always be invisible while the drawer
	# is open. Reasserted every frame rather than relying only on open()/close(),
	# in case a side path (theme reload, deferred call...) missed it.
	if SHOW_HINT and is_instance_valid(_hint) and _hint.visible == is_open:
		_hint.visible = not is_open


# Height of a tree row, measured by finding two consecutive row changes.
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


# List (root -> deep) of the folders to pin at the top of the tree.
func _compute_sticky_chain() -> Array:
	var chain: Array = []
	if _tree.get_root() == null or _tree.get_scroll().y < 1.0:
		return chain
	var pitch := _get_row_pitch()
	if pitch <= 0.0:
		return chain
	var slot := _sticky_row_h(pitch)  # = pitch: we probe at multiples of a WHOLE row
	var k := 0
	for _i in range(STICKY_MAX + 1):
		# Row located just below the rows already pinned
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
	# Immediate, priority hiding: as soon as the tree is at the very top, there is no parent folder
	# to show. We never depend on the signature cache for this specific case, to avoid
	# a leftover of the overlay staying visible for a moment above "res://". (The handling of
	# _pending_reveal above must stay BEFORE this test: it is what can move the
	# scroll and therefore change this result on the next call.)
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


## RESERVED height per pinned row: always one whole tree row.
## Never reduce this value: it is what guarantees that the pinned-folders overlay
## covers exactly a whole number of real rows,
## otherwise a real row appears half under the overlay (overlap).
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
	var slot := _sticky_row_h(pitch)  # = pitch: one reserved row = one whole tree row
	# Explicit placement, one WHOLE row after the other: the overlay then covers exactly
	# the same number of pixels as the real rows it hides, no row can
	# end up half visible under the overlay (overlap).
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
	var slot := _sticky_row_h(pitch)  # RESERVED height = one whole row (alignment)
	var is_cur := path.trim_suffix("/") == current_dir.trim_suffix("/")
	var bg := _hover_c(COLOR_LEFT_PANEL)
	if is_cur:
		bg = bg.lerp(accent, 0.30)
	bg.a = 1.0  # always opaque: this row must fully hide the real tree behind it
	var hover_bg := _hover_c(bg)
	hover_bg.a = 1.0
	var sb_normal := _sticky_row_style(bg)
	var sb_hover := _sticky_row_style(hover_bg)

	# PanelContainer: its "panel" style paints the whole rectangle ALONE (the full
	# reserved height, without the slightest transparent gap), and it automatically centers its
	# content — no more manual anchoring math, so no possible offset.
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, slot)
	row.clip_contents = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS   # the mouse wheel keeps going to the tree
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = path
	row.add_theme_stylebox_override("panel", sb_normal)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", sb_hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", sb_normal))

	# Inner margins: shift the content without ever letting the background show through
	# (they stay INSIDE the opaque panel above).
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
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# EXPLICIT centering: the Label receives the whole row height (SIZE_FILL) and centers
	# its text inside it (vertical_alignment), rather than depending on the "minimum size"
	# computed by Godot (unreliable depending on font/DPI).
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


# Click on a pinned folder: opens the folder and brings it just under its pinned parents
func _on_sticky_clicked(path: String) -> void:
	if path.trim_suffix("/") != current_dir.trim_suffix("/"):
		_navigate.call_deferred(path)
	var it := _sticky_item(path)
	if it != null:
		_reveal_tree_item.call_deferred(it)


# Click on the arrow of a pinned folder: collapses it
func _on_sticky_arrow(path: String) -> void:
	var it := _sticky_item(path)
	if it == null:
		return
	it.collapsed = true
	_reveal_tree_item.call_deferred(it)


# Makes the item visible, taking into account the pinned rows that would cover it
func _reveal_tree_item(item: TreeItem) -> void:
	if item == null or not is_instance_valid(item) or _tree == null:
		return
	_tree.scroll_to_item(item)
	if _tree_vscroll == null:
		return
	var pitch := _get_row_pitch()
	if pitch <= 0.0:
		_pending_reveal = item      # tree not measurable yet: we try again later
		return
	var idx := _row_index(item)
	if idx < 0:
		return
	var need := mini(_item_depth(item), STICKY_MAX) * _sticky_row_h(pitch)
	var y_top := idx * pitch - _tree.get_scroll().y
	if y_top < need - 0.5:
		_tree_vscroll.value = maxf(0.0, _tree_vscroll.value - (need - y_top))


# Single click on a tree folder: navigation (through the selection) + expansion.
# Right click: context menu on that folder, without touching the current tree selection
# (so right-clicking a different folder doesn't navigate you away from where you are).
func _on_tree_gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		var ritem := _tree.get_item_at_position(mb.position)
		if ritem == null:
			return
		var rpath := str(ritem.get_metadata(0))
		if rpath.is_empty():
			return
		_context_path = rpath
		_ctx_sel_override = PackedStringArray([rpath])
		_show_context()
		_tree.accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.double_click:
		return
	var item := _tree.get_item_at_position(mb.position)
	if item == null:
		return
	var path := str(item.get_metadata(0))
	var was_current := path.trim_suffix("/") == current_dir.trim_suffix("/")
	_after_tree_click.call_deferred(item, item.collapsed, was_current)


func _after_tree_click(item: TreeItem, was_collapsed: bool, was_current: bool) -> void:
	if not is_instance_valid(item) or item.collapsed != was_collapsed:
		return      # click on the arrow: already handled by Godot
	var path := str(item.get_metadata(0))
	if item.get_first_child() != null:
		if was_current:
			item.collapsed = not was_collapsed     # re-click on the current folder: toggle
		elif was_collapsed:
			item.collapsed = false                 # new folder: we expand it
	_center_tree_item_soon(path)


# Waits for the tree to finish its layout (expansion, selection) then centers the clicked folder
func _center_tree_item_soon(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_center_tree_item(_sticky_item(path))


# Scrolls the tree (smoothly) so that the item is in the middle of the visible area
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
	# Space reserved for the pinned parent folders of THIS item (same rule as the
	# sticky overlay: always a whole number of rows). If we ignore it here, scrolling can bring
	# the item just under the overlay with a fraction-of-a-row offset, which makes
	# a real row appear half visible UNDER the overlay (the overlap bug).
	var reserved := mini(_item_depth(item), STICKY_MAX) * _sticky_row_h(pitch)
	var available := maxf(_tree.size.y - reserved, pitch)
	# Number of context rows to leave visible above the item, in half of the
	# space available under the overlay — always a WHOLE number of rows to stay aligned.
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


func _set_preview_tex(tex: Texture2D) -> void:
	_preview.texture = tex
	for sh in _preview_shadows:
		sh.texture = tex


## Size (px) at which to rasterize SVGs, depending on zoom and editor scale
## (≈ 2× the displayed size: the ItemList then downscales without aliasing).
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
			_schedule_previews()   # falls back to Godot's thumbnail


func _render_svg(path: String, target: int) -> Texture2D:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var img := Image.new()
	if img.load_svg_from_string(text, 1.0) != OK or img.get_width() <= 0 or img.get_height() <= 0:
		return null
	var longest := maxi(img.get_width(), img.get_height())
	if absf(float(longest) - float(target)) > 2.0:
		# Direct rendering at the right scale (vector: no loss, unlike an enlargement)
		var img2 := Image.new()
		if img2.load_svg_from_string(text, float(target) / float(longest)) == OK and img2.get_width() > 0:
			img = img2
	return ImageTexture.create_from_image(img)


func _on_preview(path: String, preview: Texture2D, _thumb: Texture2D, _user) -> void:
	_preview_pending.erase(path)
	if str(_user) != "svg" and _svg_px.has(path) and _preview_cache.get(path, null) != null:
		return   # we keep our own rasterization, which is sharper
	if _preview_cache.size() > 4000:
		_preview_cache.clear()
	_preview_cache[path] = preview    # null = failure, avoids asking again in a loop
	if preview == null or _list == null:
		return
	if _path_index.has(path):
		var i: int = _path_index[path]
		if i < _list.item_count and str(_list.get_item_metadata(i)) == path:
			_list.set_item_icon(i, preview)
	if _context_path == path and _list.get_selected_items().size() <= 1:
		_set_preview_tex(preview)


# ---------- Animated opening / closing ----------

func toggle() -> void:
	if is_open:
		close()
	elif Time.get_ticks_msec() - _outside_close_msec > 250:
		# Avoids reopening right away when the click that just closed the drawer
		# (outside click) lands on the toolbar button.
		open()


func open() -> void:
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
	_opened_msec = Time.get_ticks_msec()
	if FOCUS_SEARCH_ON_OPEN:
		# Deferred: the key press that opened the drawer is fully consumed first
		_focus_search.call_deferred()
	else:
		_list.grab_focus()


## Puts the keyboard focus in the search bar and selects its text, so typing starts a new search.
func _focus_search() -> void:
	if not is_open or _search == null:
		return
	_search.grab_focus()
	_search.select_all()


## Keyboard flow from the search bar to the results: Down / Enter moves to the list.
func _on_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	# Ctrl+Space held down while opening: its auto-repeat must not type spaces in the field
	if k.keycode == KEY_SPACE and k.echo and Time.get_ticks_msec() - _opened_msec < 800:
		_search.accept_event()
		return
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_DOWN or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		if not _search_timer.is_stopped():
			_search_timer.stop()
			_refresh()
		if _list.item_count > 0:
			_list.grab_focus()
			if _list.get_selected_items().is_empty():
				_list.select(0)
				_list.ensure_current_is_visible()
				_on_selection_changed()
			_search.accept_event()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_flush_cfg()
	_ctx_popup.hide()
	var base := EditorInterface.get_base_control()
	_animate_close(base)
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
	_layout_hint()
	if is_inside_tree() and is_open:
		_layout(EditorInterface.get_base_control())


# ---------- Hint pill (shortcut) ----------

func _build_hint(base: Control) -> void:
	var accent: Color = base.get_theme_color("accent_color", "Editor")
	_hint = PanelContainer.new()
	_hint.name = "AssetDrawerHint"
	_hint.z_index = 200  # above the drawer panel itself (z_index = 128)
	_hint.z_as_relative = false
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
	title.add_theme_font_size_override("font_size", 12)
	row.add_child(title)
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", _make_stylebox(_ov(0.06), _ov(0.25), 4, 1))
	var key_pad := _pad(6, 1)
	key.add_child(key_pad)
	var key_lbl := Label.new()
	key_lbl.text = Sc.label("open_drawer")
	key_lbl.modulate = Color(1, 1, 1, 0.8)
	key_lbl.add_theme_font_size_override("font_size", 11)
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


## Slow, discreet breathing of the hint pill's outline, looping,
## to gently signal that it is clickable without being loud.
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


## Opening with a slight bounce ("overshoot"): livelier than a plain linear slide.
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


## Shorter, crisper closing, with a slight fold-back to accompany the exit.
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


## Pulse of the accent outline/shadow right after opening: a discreet luminous "pop".
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


# ---------- Navigation ----------

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


const MODEL_EXTS := ["glb", "gltf", "fbx", "blend", "dae", "obj"]
const MODEL_SCENE_EXTS := ["glb", "gltf", "fbx", "blend", "dae"]   # imported as scenes (obj = Mesh)


func _is_model(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_EXTS


func _is_model_scene(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_SCENE_EXTS


## Selects the file (the Import dock updates) then brings the Import tab to the front.
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


## Opens Godot's "Advanced Import" window: selects the file, waits for the Import dock
## to show that file, then triggers its "Advanced..." button.
func _open_advanced_import(path: String) -> void:
	if not _is_model_scene(path):
		_show_import_settings(path)   # e.g. .obj: no advanced import, we show the Import dock
		return
	EditorInterface.select_file(path)
	if not pinned:
		close()
	_try_advanced_import(path, 0)


func _try_advanced_import(path: String, attempt: int) -> void:
	await get_tree().create_timer(0.15).timeout
	# 1) Main method: reproduce exactly the double-click in the FileSystem dock, which itself
	#    calls Godot's advanced import for 3D models.
	if _activate_in_filesystem_dock(path):
		return
	# 2) Fallback: the "Advanced..." button of the Import dock.
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


## Simulates a double-click on the file in the FileSystem dock (file list or tree).
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
	# Unknown language: the "Advanced..." button is the only plain button whose text ends with "..."
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


## Opens the model as a scene: Godot then offers to create a new inherited scene.
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
		# Opens the model's "Advanced Import" window (creating an inherited scene
		# is in the right-click menu).
		_open_advanced_import(path)
	elif ResourceLoader.exists(path):
		var res := load(path)
		if res is Script:
			EditorInterface.edit_script(res)
		elif res is PackedScene:
			EditorInterface.open_scene_from_path(path)   # .glb / .gltf / .fbx imported as scenes
		else:
			EditorInterface.edit_resource(res)
	else:
		OS.shell_open(ProjectSettings.globalize_path(path))
		return
	if not pinned:
		close()


# ---------- Keyboard & mouse ----------

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
		elif _create_menu_open and event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
			var ck := (event as InputEventKey).keycode
			var picked := 0
			if ck == KEY_1 or ck == KEY_KP_1:
				picked = 1
			elif ck == KEY_2 or ck == KEY_KP_2:
				picked = 2
			elif ck == KEY_3 or ck == KEY_KP_3:
				picked = 3
			if picked > 0:
				_ctx_popup.hide()
				get_viewport().set_input_as_handled()
				match picked:
					1: _create_folder()
					2: _create_scene()
					3: _create_script()
				return
	# Mouse side buttons: back / forward (only over the drawer)
	if is_open and event is InputEventMouseButton and event.pressed:
		var xb := event as InputEventMouseButton
		if xb.button_index == MOUSE_BUTTON_XBUTTON1 or xb.button_index == MOUSE_BUTTON_XBUTTON2:
			if get_global_rect().has_point(xb.global_position):
				_hist_go(-1 if xb.button_index == MOUSE_BUTTON_XBUTTON1 else 1)
				get_viewport().set_input_as_handled()
			return
	# Click outside the drawer -> closes it (like Unreal's Content Drawer), unless pinned.
	# The event is not consumed: the click keeps its effect on whatever was clicked.
	if is_open and not pinned and event is InputEventMouseButton and event.pressed:
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
	if Sc.matches(k, "focus_search"):
		_focus_search()
		get_viewport().set_input_as_handled()
		return
	# Shift+A: create menu (like Blender's Add menu). While typing in a text field it only
	# triggers when the search bar is focused AND empty (an uppercase "A" as the very first
	# letter of a search is rare), so it still works right after the drawer opens.
	if Sc.matches(k, "create_menu"):
		var typing := focus is LineEdit or focus is TextEdit
		if not typing or (focus == _search and _search.text.is_empty()):
			_show_create_menu()
			get_viewport().set_input_as_handled()
			return
	if focus is LineEdit or focus is TextEdit:
		return
	# Actions on items: only if the list has focus (not the tree nor a button)
	if focus != null and focus != _list and not Sc.matches(k, "parent_folder"):
		return
	var sel := _selected_paths()
	var handled := true
	if Sc.matches(k, "rename"):
		if sel.size() == 1:
			_rename(sel[0])
	elif Sc.matches(k, "delete"):
		if not sel.is_empty():
			_confirm_delete(sel)
	elif Sc.matches(k, "duplicate"):
		if not sel.is_empty():
			_duplicate(sel)
	elif Sc.matches(k, "parent_folder"):
		_go_up()
	elif Sc.matches(k, "open_item"):
		if sel.size() == 1:
			_open_path(sel[0])
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_list_gui_input(event: InputEvent) -> void:
	# --- Rectangle selection (left click held in an empty area) ---
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
	# Auto-scroll near the top / bottom edges
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

	# Small floating card (icon + name, slightly tilted) rather than a bare Label.
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
	icon.texture = base.get_theme_icon("Folder" if is_dir else "File", "EditorIcons")
	if is_dir:
		icon.modulate = _folder_color(_colors(), first)
	row.add_child(icon)
	var lbl := Label.new()
	lbl.text = first.trim_suffix("/").get_file() + (" (+%d)" % (files.size() - 1) if files.size() > 1 else "")
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	wrap.add_child(card)
	set_drag_preview(wrap)
	return {"type": "files", "files": files}


# ---------- Drag and drop: move files / folders into a folder ----------

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_hl()


# Paths contained in a drag (drawer or Godot's FileSystem dock), without trailing "/"
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


func _norm_dir(p: String) -> String:
	if p == "res://" or p == "res:/":
		return "res://"
	return p.trim_suffix("/")


func _can_move_one(src: String, dst_dir: String) -> bool:
	if src.is_empty() or src == "res://":
		return false
	if src.get_base_dir() == dst_dir or src == dst_dir:
		return false
	if _is_under(dst_dir, src):
		return false      # a folder cannot go into itself / one of its subfolders
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


# Target of a drop in the list: hovered folder, otherwise the current folder (empty area)
func _list_drop_target(at: Vector2) -> Dictionary:
	var idx := _list.get_item_at_position(at, true)
	if idx >= 0:
		var p := str(_list.get_item_metadata(idx))
		if _dir_paths.has(p):
			return {"dir": _norm_dir(p), "idx": idx}
	# Empty area (or file): we drop into the current folder, except in search / set,
	# where the list mixes several folders.
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


# You can also grab a folder in the tree to move it into another folder
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
	EditorInterface.save_all_scenes()          # <-- ADDED: avoids losing changes on reload
	var moved := 0
	var moves: Array = []                       # <-- ADDED
	for p in files:
		var src := p.trim_suffix("/")
		if not _can_move_one(src, dst_dir):
			continue
		var dst := dst_dir.path_join(src.get_file())
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			_flash(L.t("« %s » existe déjà") % src.get_file(), true)
			continue
		var is_dir := DirAccess.dir_exists_absolute(src)   # <-- ADDED (before the rename)
		if DirAccess.rename_absolute(src, dst) != OK:
			_flash(L.t("Échec du déplacement"), true)
			continue
		moves.append([src, dst, is_dir])                    # <-- ADDED
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
	_update_references(moves)                               # <-- ADDED
	_scan()
	_flash(L.t("%d élément(s) déplacé(s)") % moved if moved > 1 else L.t("Élément déplacé"))


# ---------- Context menu ----------

func _ctx_btn(title: String, callback: Callable, color: Color = Color.TRANSPARENT, icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_ghost_button(b, 8, 3)
	if color != Color.TRANSPARENT:
		b.add_theme_color_override("font_color", color)
	if not icon_name.is_empty():
		var base := EditorInterface.get_base_control()
		if base.has_theme_icon(icon_name, "EditorIcons"):
			b.icon = base.get_theme_icon(icon_name, "EditorIcons")
			b.add_theme_constant_override("h_separation", 8)
	b.pressed.connect(func() -> void:
		_ctx_popup.hide()
		callback.call()
	)
	_ctx_vbox.add_child(b)
	return b


func _ctx_sep() -> void:
	_ctx_vbox.add_child(HSeparator.new())


## Checkbox menu entry.
func _ctx_check(title: String, checked: bool, on_toggle: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = title
	cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = checked
	_style_ghost_button(cb, 8, 3)
	# The theme colors the text of a checked button: we keep the normal color
	var fc: Color = EditorInterface.get_base_control().get_theme_color("font_color", "Button")
	for n in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(n, fc)
	cb.toggled.connect(func(on: bool) -> void:
		_ctx_popup.hide()
		on_toggle.call(on)
	)
	_ctx_vbox.add_child(cb)
	return cb


## Loads the resource in memory and keeps it as the drawer's "clipboard".
## A "Paste" button then appears when hovering any compatible resource field
## of the Inspector (or Alt+V as a keyboard shortcut).
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


## True if `res` matches at least one of the types allowed by an EditorResourcePicker
## (native types via is_class, and custom script classes via their global class_name).
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


## Walks up the parent chain from the hovered control to find an
## EditorResourcePicker (the widget of a resource field in the Inspector).
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


## Looks for an EditorResourcePicker (Inspector resource field) under the mouse
## and assigns the copied resource to it if the type matches. Alt+V keyboard shortcut (plugin.gd);
## the floating "Paste" button that appears on hover does the same on click.
func try_paste_resource_at_mouse() -> bool:
	if _clip_resource == null or not is_instance_valid(_clip_resource):
		_flash(L.t("Aucune ressource copiée : clic droit sur un fichier → « Copier la ressource »"), true)
		return false
	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null
	var picker := _picker_under(hovered)
	if picker == null:
		_flash(L.t("Survolez un champ ressource de l'Inspecteur puis %s") % Sc.label("paste_resource", "–"), true)
		return false
	if not picker.editable:
		_flash(L.t("Ce champ n'est pas modifiable"), true)
		return false
	var allowed := picker.get_allowed_types()
	if not _resource_type_matches(_clip_resource, allowed):
		var attendu := ", ".join(allowed) if not allowed.is_empty() else "?"
		_flash(L.t("Type incompatible : ce champ attend « %s »") % attendu, true)
		return false
	# set_edited_resource() only refreshes the field's display: without emitting
	# resource_changed, the Inspector never propagates the value to the object's real property
	# (e.g. MeshInstance3D.mesh), which then overwrites the display on the next refresh.
	picker.set_edited_resource(_clip_resource)
	picker.emit_signal("resource_changed", _clip_resource)
	_flash(L.t("« %s » collée dans l'Inspecteur") % _clip_resource_name)
	return true


## Lightweight loop that makes the floating "Paste" button appear/follow above
## any compatible hovered resource field (only when a resource is copied).
func _update_paste_pop_hover() -> void:
	if _clip_resource == null or not is_instance_valid(_clip_resource):
		if _paste_pop.visible:
			_hide_paste_pop()
		return

	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null

	# Do not hide while heading to the button to click it.
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
	var rect := picker.get_global_rect()
	var origin: Vector2 = _toast_overlay.global_position
	var btn_size := _paste_pop.size

	# Left side of the field, vertically centered: the right stays free for Godot's native
	# quick menu and dropdown arrow. Always clamped inside the field.
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


## Lightweight loop that makes the floating "Copy" button appear/follow above
## the drawer's list resource currently hovered by the mouse.
func _update_copy_pop_hover() -> void:
	var vp := EditorInterface.get_base_control().get_viewport()
	var hovered: Control = vp.gui_get_hovered_control() if vp else null

	# Do not hide while heading to the button to click it.
	if hovered != null and (hovered == _copy_pop or _copy_pop.is_ancestor_of(hovered)):
		return
	if hovered == null or not (hovered == _list or _list.is_ancestor_of(hovered)):
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
		# item (almost) entirely out of the visible area: no button
		if _copy_pop.visible:
			_hide_copy_pop()
		return
	var is_new := path != _copy_target_path or not _copy_pop.visible
	_copy_target_path = path
	if is_new:
		_show_copy_pop()


func _position_copy_pop(idx: int) -> bool:
	# The button lives in an unclipped layer: we explicitly keep it inside the
	# VISIBLE part of the list (a file half out at the top must not make it overflow onto
	# the search bar / the path). Returns false if there is no visible room.
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

	# Top-right corner of the visible part of the item
	var x: float = vis.end.x - btn_size.x - 3.0
	x = maxf(x, vis.position.x + 1.0)
	var y: float = vis.position.y + 3.0
	y = minf(y, vis.position.y + maxf(vis.size.y - btn_size.y - 1.0, 1.0))
	# Final safeguard: never outside the list
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
	# Already fading out: above all, do not restart the tween (the hover loop
	# recreated it every frame, which froze the fade and made it very slow).
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


func _add_color_row(target: String) -> void:
	var color_lbl := Label.new()
	color_lbl.text = L.t("COULEUR DU DOSSIER")
	color_lbl.modulate = TEXT_MUTED
	color_lbl.add_theme_font_size_override("font_size", 10)
	_ctx_vbox.add_child(color_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for key in FOLDER_COLORS.keys():
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(16, 16)
		cb.flat = false
		cb.tooltip_text = str(key)
		cb.add_theme_stylebox_override("normal", _make_stylebox(FOLDER_COLORS[key], Color.TRANSPARENT, 8))
		cb.add_theme_stylebox_override("hover", _make_stylebox(FOLDER_COLORS[key], Color.WHITE, 8, 2))
		_add_press_bounce(cb, 1.25, 0.85)
		var ck: String = key
		cb.pressed.connect(func() -> void:
			_ctx_popup.hide()
			_set_folder_color(target, ck)
		)
		row.add_child(cb)
	var rb := Button.new()
	rb.custom_minimum_size = Vector2(16, 16)
	rb.flat = false
	rb.tooltip_text = L.t("Couleur par défaut")
	rb.add_theme_stylebox_override("normal", _make_stylebox(Color(0.2, 0.2, 0.2), Color.GRAY, 8, 1))
	_add_press_bounce(rb, 1.25, 0.85)
	rb.pressed.connect(func() -> void:
		_ctx_popup.hide()
		_set_folder_color(target, "")
	)
	row.add_child(rb)
	_ctx_vbox.add_child(row)


## Small "Create" menu (Shift+A): new folder / scene / script, also reachable with keys 1 / 2 / 3.
## Opens at the mouse, or in the middle of the drawer when the mouse is elsewhere.
func _show_create_menu() -> void:
	for c in _ctx_vbox.get_children():
		_ctx_vbox.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = L.t("Créer").to_upper()
	title.modulate = TEXT_SECONDARY
	title.add_theme_font_size_override("font_size", 10)
	_ctx_vbox.add_child(title)
	_ctx_btn(L.t("Nouveau dossier") + "   (1)", func() -> void: _create_folder(), Color.TRANSPARENT, "Folder")
	_ctx_btn(L.t("Nouvelle scène") + "   (2)", func() -> void: _create_scene(), Color.TRANSPARENT, "PackedScene")
	_ctx_btn(L.t("Nouveau script") + "   (3)", func() -> void: _create_script(), Color.TRANSPARENT, "ScriptCreate")
	_place_ctx_popup()
	_create_menu_open = true   # after _place_ctx_popup()
	if not get_global_rect().has_point(get_global_mouse_position()):
		_ctx_popup.position = get_global_rect().get_center() - _ctx_popup.size * 0.5


func _show_context() -> void:
	_create_menu_open = false
	for c in _ctx_vbox.get_children():
		_ctx_vbox.remove_child(c)
		c.queue_free()
	var sel := _ctx_sel_override if not _ctx_sel_override.is_empty() else _selected_paths()
	_ctx_sel_override = PackedStringArray()
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
		_ctx_sep()

	# If the menu was opened on a single folder (list or tree), new items go inside it;
	# otherwise they go in the current folder, exactly like before.
	var new_item_dir := target if (on_item and single and is_dir) else current_dir
	_ctx_btn(L.t("Nouveau dossier"), func() -> void: _create_folder(new_item_dir), Color.TRANSPARENT, "Folder")
	_ctx_btn(L.t("Nouvelle scène"), func() -> void: _create_scene(new_item_dir), Color.TRANSPARENT, "PackedScene")
	_ctx_btn(L.t("Nouveau script"), func() -> void: _create_script(new_item_dir), Color.TRANSPARENT, "Script")

	if not on_item and _active_set.is_empty() and current_dir != "res://":
		_ctx_sep()
		_add_color_row(current_dir)

	if on_item:
		_ctx_sep()
		if single:
			_ctx_btn(Sc.with_hint(L.t("Renommer"), "rename"), func() -> void: _rename(target), Color.TRANSPARENT, "Rename")
		_ctx_btn(Sc.with_hint(L.t("Dupliquer"), "duplicate"), func() -> void: _duplicate(sel), Color.TRANSPARENT, "Duplicate")
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
		if is_dir and single:
			_ctx_sep()
			_add_color_row(target)
		_ctx_sep()
		_ctx_btn(Sc.with_hint(L.t("Supprimer"), "delete"), func() -> void: _confirm_delete(sel), COLOR_DANGER, "Remove")

	_place_ctx_popup()
	# PopupPanel is a Window (no "scale"/"modulate"): we animate its content instead.
	_ctx_vbox.modulate.a = 0.0
	create_tween().tween_property(_ctx_vbox, "modulate:a", 1.0, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---------- Creation / renaming / deletion ----------

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


func _scan() -> void:
	EditorInterface.get_resource_filesystem().scan()


func _target_dir() -> String:
	return current_dir


func _create_folder(in_dir: String = "") -> void:
	var dir := in_dir if not in_dir.is_empty() else _target_dir()
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


func _create_scene(in_dir: String = "") -> void:
	var dir := in_dir if not in_dir.is_empty() else _target_dir()
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


## True only if the project already has a C# solution (a .csproj file at the root).
## Without it, Godot does not index .cs scripts in its EditorFileSystem: the file
## would exist on disk but stay invisible everywhere in the editor, not only
## in the drawer (that is why we block creation rather than let a "ghost"
## file be created that would later make people think it already exists).
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


## Languages offered in the dropdown: only those THIS Godot build knows
## about (ScriptServer only lists "C#" on the .NET edition, for example), exactly
## like Godot's native "Create Script" dialog does. We add "Shader" (not a
## ScriptLanguage in its own right) and "Custom..." (free extension) at the end.
## Languages offered in the dropdown: only those THIS Godot build knows
## about. `ScriptServer` (used internally by the native "Create Script" dialog) is not
## exposed to GDScript, so we detect differently: GDScript is always there, and C# only
## if this build has the "mono" feature tag (the .NET editions of Godot define it).
## Each entry is either {"sep": "Category name"} (a non-selectable separator in
## the menu), or {"name": ..., "ext": ...} (a real option).
func _script_languages() -> Array:
	var out: Array = []
	out.append({"sep": L.t("Scripts")})
	out.append({"name": "GDScript", "ext": "gd"})
	if OS.has_feature("mono"):
		out.append({"name": "C#", "ext": "cs"})
	out.append({"name": L.t("Shader"), "ext": "gdshader"})
	# Common text file types, not tied to a particular script language
	# (creating a simple .txt or .json next to the assets is a frequent need).
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


func _create_script(in_dir: String = "") -> void:
	var dir := in_dir if not in_dir.is_empty() else _target_dir()
	var langs := _script_languages()

	var d := ConfirmationDialog.new()
	d.title = L.t("Nouveau script")
	d.ok_button_text = L.t("Créer")
	d.cancel_button_text = L.t("Annuler")

	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = 340
	vb.add_theme_constant_override("separation", 8)
	d.add_child(vb)

	# Name field FIRST: it holds the full file name with its extension ("player.gd", "rules.lua"...).
	# Everything can be done from the keyboard; the dropdown below is only a shortcut.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vb.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = L.t("Nom")
	name_lbl.custom_minimum_size.x = 70
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.tooltip_text = L.t("Tapez le nom complet avec son extension (ex. : player.lua)")
	name_row.add_child(name_edit)
	d.register_text_enter(name_edit)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vb.add_child(lang_row)
	var lang_lbl := Label.new()
	lang_lbl.text = L.t("Langage")
	lang_lbl.custom_minimum_size.x = 70
	lang_row.add_child(lang_lbl)
	var lang_opt := OptionButton.new()
	lang_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Mapping between the menu index (category separators count as one
	# slot, even though they cannot be selected) and the real index in "langs": -1 for
	# a separator, otherwise the index of the matching entry in "langs".
	var entry_of_index: Array = []
	var custom_index := -1
	var first_selectable := -1
	for i in langs.size():
		var entry: Dictionary = langs[i]
		if entry.has("sep"):
			lang_opt.add_separator(entry.sep)
			entry_of_index.append(-1)
		else:
			lang_opt.add_item(entry.name)
			entry_of_index.append(i)
			if first_selectable < 0:
				first_selectable = entry_of_index.size() - 1
			if str(entry.ext).is_empty():
				custom_index = entry_of_index.size() - 1
	lang_row.add_child(lang_opt)

	# "player.gd" -> ["player", "gd"]; no extension (or a trailing dot) -> [name, ""]
	var split_name := func(full: String) -> Array:
		var dot := full.rfind(".")
		if dot <= 0 or dot == full.length() - 1:
			return [full.trim_suffix("."), ""]
		return [full.substr(0, dot), full.substr(dot + 1)]

	# Preselects the last extension used (a preset language, or the custom extension typed last time).
	var start_idx := -1
	var initial_ext := _last_script_ext
	for oi in entry_of_index.size():
		var li: int = entry_of_index[oi]
		if li >= 0 and not _last_script_ext.is_empty() and langs[li].ext == _last_script_ext:
			start_idx = oi
			break
	if start_idx < 0:
		if _last_script_ext.is_empty() or custom_index < 0:
			start_idx = first_selectable
			initial_ext = str(langs[entry_of_index[first_selectable]].ext)
		else:
			start_idx = custom_index   # custom extension remembered from last time
	lang_opt.select(start_idx)
	name_edit.text = _unique_path(dir, L.t("nouveau_script"), "." + initial_ext).get_file()

	# Dropdown changed: the typed base name is NEVER touched, only the extension changes, and the
	# keyboard focus goes back to the name field so typing can continue right away.
	lang_opt.item_selected.connect(func(_i: int) -> void:
		var entry: Dictionary = langs[entry_of_index[lang_opt.selected]]
		var parts: Array = split_name.call(name_edit.text.strip_edges())
		var base: String = str(parts[0])
		var cur_ext: String = str(parts[1]).to_lower()
		var ext: String = str(entry.ext)
		if ext.is_empty():
			# "Custom...": the user types the extension. We keep one that is already custom,
			# otherwise we leave "name." with the caret at the end, ready for the extension.
			var cur_is_preset := cur_ext.is_empty()
			for l in langs:
				if l.has("ext") and str(l.ext) == cur_ext:
					cur_is_preset = true
					break
			if cur_is_preset:
				name_edit.text = base + "."
		else:
			name_edit.text = base + "." + ext
		name_edit.grab_focus()
		name_edit.deselect()
		name_edit.caret_column = name_edit.text.length()
	)
	# Extension typed by hand: the dropdown follows (preset language, otherwise "Custom...").
	name_edit.text_changed.connect(func(t: String) -> void:
		var ext: String = str((split_name.call(t.strip_edges()) as Array)[1]).to_lower()
		if ext.is_empty():
			return
		var target := custom_index
		for oi in entry_of_index.size():
			var li: int = entry_of_index[oi]
			if li >= 0 and langs[li].ext == ext:
				target = oi
				break
		if target >= 0 and lang_opt.selected != target:
			lang_opt.select(target)
	)

	d.confirmed.connect(func() -> void:
		var entry: Dictionary = langs[entry_of_index[lang_opt.selected]]
		var parts: Array = split_name.call(name_edit.text.strip_edges())
		var base_name: String = str(parts[0])
		# Extension typed in the field wins; otherwise the dropdown's one.
		var ext: String = str(parts[1]).to_lower()
		if ext.is_empty():
			ext = str(entry.ext)
		if base_name.is_empty() or ext.is_empty():
			_flash(L.t("Indiquez un nom et une extension (ex. : player.gd)"), true)
			return
		if not _valid_name(base_name + "." + ext):
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
		_last_script_ext = ext   # remembered for next time, preset or custom
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
	EditorInterface.get_base_control().add_child(d)
	d.popup_centered(Vector2i(380, 140))
	name_edit.grab_focus()
	# Select only the base name: typing replaces it and keeps ".ext"; End / arrows reach the extension
	name_edit.select(0, name_edit.text.rfind("."))


## Initial content depending on the extension: GDScript, C# and shader have a template, the rest is empty.
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
		EditorInterface.save_all_scenes()                      # here rather than before the dialog
		var is_dir := DirAccess.dir_exists_absolute(src)       # BEFORE the rename
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
		_update_references([[src, dst, is_dir]])               # ADDED
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
	# A .tscn/.tres embeds its UID in the header: we remove it from the copy to
	# avoid a duplicate UID (Godot assigns a new one).
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


func _is_under(p: String, src: String) -> bool:
	var sp := p.trim_suffix("/")
	return sp == src or sp.begins_with(src + "/")

const REF_EXTS := ["tscn", "tres", "gd", "gdshader", "gdshaderinc", "godot", "cfg"]

func _collect_text_files(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		_collect_text_files(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in REF_EXTS:
			out.append(dir.path_join(f))


# moves: Array of [src, dst, is_dir]
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
			# Exact path in quotes (avoids touching "x.tres2", etc.)
			new_text = new_text.replace('"' + src + '"', '"' + dst + '"')
			if m[2]:  # folder: everything that starts with src + "/"
				new_text = new_text.replace('"' + src + "/", '"' + dst + "/")
		if new_text != text:
			var w := FileAccess.open(path, FileAccess.WRITE)
			if w:
				w.store_string(new_text)
				w.close()
				changed_files += 1
	if changed_files > 0:
		# Reload the open scenes, otherwise the editor may rewrite the old paths
		for scene in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(scene)

func _swap_prefix(p: String, src: String, dst: String) -> String:
	var sp := p.trim_suffix("/")
	var slash := "/" if p.ends_with("/") else ""
	if sp == src:
		return dst + slash
	if sp.begins_with(src + "/"):
		return dst + p.substr(src.length())
	return p


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
	_save_cfg()


# ---------- Dialogs ----------

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
	EditorInterface.get_base_control().add_child(d)
	d.popup_centered()


# ---------- Favorites / recents / config ----------

# Godot's FileSystem dock favorites are authoritative (EditorSettings.get_favorites / set_favorites).
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
		# Once only: favorites created before this version are added to Godot's
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
	if c.load(CFG_PATH) == OK:
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
	_history = PackedStringArray([current_dir])


func _save_cfg() -> void:
	# Deferred write: avoids writing the file at every zoom step / navigation
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
	c.save(CFG_PATH)
