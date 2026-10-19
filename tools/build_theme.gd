extends SceneTree
## Builds ui/theme/main_theme.tres from ui/theme/tokens.gd. Run after changing a token:
## godot --headless --script res://tools/build_theme.gd
## The project uses the theme for every Control (Project Settings > GUI > Theme > Custom),
## so panels never set their own colours; they pick a theme type variation instead
## (e.g. Label "MutedLabel", PanelContainer "Card", Button "PrimaryButton").

const OUT: String = "res://ui/theme/main_theme.tres"


func _initialize() -> void:
	var t: Variant = load("res://ui/theme/tokens.gd")
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = t.FONT_NAMES
	var bold: SystemFont = SystemFont.new()
	bold.font_names = t.FONT_NAMES
	bold.font_weight = 700
	theme.default_font = font
	theme.default_font_size = t.FONT_BODY

	# Text.
	for type: String in ["Label", "RichTextLabel", "Button", "CheckBox", "OptionButton", "LineEdit", "TabContainer", "PopupMenu", "TooltipLabel"]:
		theme.set_color("font_color", type, t.TEXT)
	theme.set_color("default_color", "RichTextLabel", t.TEXT)
	theme.set_font("bold_font", "RichTextLabel", bold)
	_label(theme, "MutedLabel", t.TEXT_MUTED, t.FONT_SMALL, font)
	_label(theme, "FaintLabel", t.TEXT_FAINT, t.FONT_SMALL, font)
	_label(theme, "HeadingLabel", t.TEXT, t.FONT_H3, bold)
	_label(theme, "TitleLabel", t.TEXT, t.FONT_H1, bold)
	_label(theme, "SubtitleLabel", t.TEXT, t.FONT_H2, bold)
	_label(theme, "OkLabel", t.OK, t.FONT_BODY, font)
	_label(theme, "WarnLabel", t.WARN, t.FONT_BODY, font)
	_label(theme, "DangerLabel", t.DANGER, t.FONT_BODY, font)
	_label(theme, "InfoLabel", t.INFO, t.FONT_BODY, font)
	_label(theme, "ClockLabel", t.TEXT, t.FONT_H1, bold)
	for state: String in ["ok", "warn", "danger", "info", "muted"]:
		var chip: String = "Chip" + state.capitalize()
		_label(theme, chip + "Label", t.TEXT_ON_ACCENT if state != "muted" else t.TEXT, t.FONT_SMALL, bold)
		theme.set_stylebox("normal", chip + "Label", _box(t.state_color(state) if state != "muted" else t.BG_HOVER, 4, 6, 2))

	# Panels.
	theme.set_stylebox("panel", "PanelContainer", _box(t.BG_PANEL, 0, 0, 0))
	theme.set_stylebox("panel", "Panel", _box(t.BG_PANEL, 0, 0, 0))
	_panel(theme, "AppBackground", _box(t.BG_APP, 0, 0, 0))
	_panel(theme, "Card", _box(t.BG_CARD, t.RADIUS, t.SPACE_M, t.SPACE_S))
	_panel(theme, "CardSelected", _box(t.BG_RAISED, t.RADIUS, t.SPACE_M, t.SPACE_S, t.ACCENT, 2))
	_panel(theme, "CardWarn", _box(t.BG_CARD, t.RADIUS, t.SPACE_M, t.SPACE_S, t.WARN, 2))
	_panel(theme, "CardDanger", _box(t.BG_CARD, t.RADIUS, t.SPACE_M, t.SPACE_S, t.DANGER, 2))
	_panel(theme, "Sidebar", _box(t.BG_PANEL, 0, t.SPACE_S, t.SPACE_S))
	_panel(theme, "TopBar", _box(t.BG_PANEL, 0, t.SPACE_M, t.SPACE_S, t.BORDER, 0, 1))
	_panel(theme, "Modal", _box(t.BG_PANEL, 10, t.SPACE_XL, t.SPACE_L, t.BORDER, 1))
	_panel(theme, "Inset", _box(t.BG_APP, t.RADIUS, t.SPACE_S, t.SPACE_S))
	_panel(theme, "Ticker", _box(t.BG_PANEL, 0, t.SPACE_M, t.SPACE_XS, t.BORDER, 0, 0, 1))
	_panel(theme, "Floating", _box(Color(t.BG_PANEL, 0.96), t.RADIUS, t.SPACE_M, t.SPACE_S, t.BORDER, 1))
	theme.set_stylebox("panel", "TooltipPanel", _box(t.BG_RAISED, t.RADIUS, t.SPACE_M, t.SPACE_S, t.BORDER, 1))
	theme.set_color("font_color", "TooltipLabel", t.TEXT)

	# Buttons.
	_button(theme, "Button", t.BG_RAISED, t.BG_HOVER, t.ACCENT.darkened(0.55), t.TEXT, t.TEXT, t)
	_button(theme, "PrimaryButton", t.ACCENT, t.ACCENT.lightened(0.15), t.ACCENT.darkened(0.2), t.TEXT_ON_ACCENT, t.TEXT_ON_ACCENT, t)
	_button(theme, "GhostButton", Color(0, 0, 0, 0), t.BG_HOVER, t.BG_RAISED, t.TEXT_MUTED, t.TEXT, t)
	_button(theme, "DangerButton", t.DANGER.darkened(0.45), t.DANGER.darkened(0.3), t.DANGER.darkened(0.6), t.TEXT, t.TEXT, t)
	_button(theme, "SpeedButton", Color(0, 0, 0, 0), t.BG_HOVER, t.ACCENT, t.TEXT_MUTED, t.TEXT_ON_ACCENT, t)
	for type: String in ["Button", "PrimaryButton", "GhostButton", "DangerButton", "SpeedButton"]:
		theme.set_color("font_disabled_color", type, t.TEXT_FAINT)
	for type: String in ["CheckBox", "OptionButton"]:
		theme.set_color("font_hover_color", type, t.TEXT)
		theme.set_color("font_pressed_color", type, t.TEXT)
	theme.set_stylebox("normal", "OptionButton", _box(t.BG_RAISED, 4, t.SPACE_S, t.SPACE_XS))
	theme.set_stylebox("hover", "OptionButton", _box(t.BG_HOVER, 4, t.SPACE_S, t.SPACE_XS))
	theme.set_stylebox("pressed", "OptionButton", _box(t.BG_HOVER, 4, t.SPACE_S, t.SPACE_XS))
	theme.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PopupMenu", _box(t.BG_RAISED, 4, t.SPACE_XS, t.SPACE_XS, t.BORDER, 1))
	theme.set_stylebox("hover", "PopupMenu", _box(t.BG_HOVER, 3, t.SPACE_XS, t.SPACE_XS))
	theme.set_stylebox("normal", "LineEdit", _box(t.BG_APP, 4, t.SPACE_S, t.SPACE_XS, t.BORDER, 1))
	theme.set_stylebox("focus", "LineEdit", _box(t.BG_APP, 4, t.SPACE_S, t.SPACE_XS, t.ACCENT, 1))
	theme.set_color("font_placeholder_color", "LineEdit", t.TEXT_FAINT)

	# Tabs.
	theme.set_stylebox("panel", "TabContainer", _box(t.BG_PANEL, 0, t.SPACE_S, t.SPACE_S))
	theme.set_stylebox("tab_selected", "TabContainer", _box(t.BG_PANEL, 4, t.SPACE_M, t.SPACE_XS, t.ACCENT, 0, 0, 0, 2))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(t.BG_APP, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("tab_hovered", "TabContainer", _box(t.BG_RAISED, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_color("font_selected_color", "TabContainer", t.TEXT)
	theme.set_color("font_unselected_color", "TabContainer", t.TEXT_MUTED)
	theme.set_color("font_hovered_color", "TabContainer", t.TEXT)
	theme.set_font_size("font_size", "TabContainer", t.FONT_BODY)

	# Scroll bars.
	theme.set_stylebox("scroll", "VScrollBar", _box(t.BG_PANEL, 4, 2, 2))
	theme.set_stylebox("grabber", "VScrollBar", _box(t.BG_HOVER, 4, 2, 2))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(t.BORDER.lightened(0.2), 4, 2, 2))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(t.ACCENT.darkened(0.3), 4, 2, 2))
	theme.set_constant("separation", "VBoxContainer", t.SPACE_S)
	theme.set_constant("separation", "HBoxContainer", t.SPACE_S)

	var error: Error = ResourceSaver.save(theme, OUT)
	print("Saved %s (%s)" % [OUT, error_string(error)])
	quit(0 if error == OK else 1)


func _label(theme: Theme, type: String, color: Color, size: int, font: Font) -> void:
	theme.set_type_variation(type, "Label")
	theme.set_color("font_color", type, color)
	theme.set_font_size("font_size", type, size)
	theme.set_font("font", type, font)


func _panel(theme: Theme, type: String, box: StyleBox) -> void:
	theme.set_type_variation(type, "PanelContainer")
	theme.set_stylebox("panel", type, box)


func _button(theme: Theme, type: String, normal: Color, hover: Color, pressed: Color, text: Color, pressed_text: Color, t: Variant) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	theme.set_stylebox("normal", type, _box(normal, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("hover", type, _box(hover, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("pressed", type, _box(pressed, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("hover_pressed", type, _box(pressed.lightened(0.1), 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("disabled", type, _box(normal.darkened(0.3) if normal.a > 0.0 else normal, 4, t.SPACE_M, t.SPACE_XS))
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_color("font_color", type, text)
	theme.set_color("font_hover_color", type, text if type != "GhostButton" else t.TEXT)
	theme.set_color("font_pressed_color", type, pressed_text)
	theme.set_color("font_hover_pressed_color", type, pressed_text)
	theme.set_color("font_focus_color", type, text)


## A flat box: background, corner radius, horizontal/vertical padding and an
## optional border (all sides, or just the bottom/top/left with the last args).
func _box(bg: Color, radius: int, pad_x: int, pad_y: int, border: Color = Color(0, 0, 0, 0), width: int = 0,
		bottom: int = 0, top: int = 0, left: int = 0) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	box.border_color = border
	if width > 0:
		box.set_border_width_all(width)
	if bottom > 0:
		box.border_width_bottom = bottom
	if top > 0:
		box.border_width_top = top
	if left > 0:
		box.border_width_left = left
	return box
