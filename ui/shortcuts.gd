extends PanelContainer
## The keyboard shortcuts card (?).

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")

const KEYS: Array = [
	["Space", "Pause / resume"], ["1  2  3", "Speed 1× (a day in 72 s), 3×, 10×"], ["Tab", "Show or hide the side panel"],
	["Esc", "Menu: save, load, settings, new run"], ["Ctrl+S", "Quick save"], ["Ctrl+L", "Load a save"],
	["?", "This card"], ["Click a building", "See what's inside; plan a trip or move in"],
	["Hover a number", "See what makes it up"], ["Drag a name", "Move someone to another job (job board)"],
]


func _ready() -> void:
	theme_type_variation = "Modal"
	visible = false
	var column: VBoxContainer = Kit.vbox(Tokens.SPACE_S)
	add_child(column)
	column.add_child(Kit.label("Keys and mouse", "TitleLabel"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_XL)
	column.add_child(grid)
	for row: Array in KEYS:
		grid.add_child(Kit.label(row[0], "HeadingLabel"))
		grid.add_child(Kit.label(row[1]))
	column.add_child(Kit.button("Close", func() -> void: visible = false, "PrimaryButton"))


func toggle() -> void:
	visible = not visible
	if visible:
		set_anchors_preset(Control.PRESET_CENTER)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BOTH
		offset_left = 0.0
		offset_right = 0.0
		offset_top = 0.0
		offset_bottom = 0.0
		reset_size()
