extends PanelContainer
## The alerts list (from the top bar): every current warning, most urgent first,
## each with a tier word and a button to show it. A switch per type decides
## whether that kind of alert pauses the game when it appears.

signal show_requested(alert: Dictionary)

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Alerts := preload("res://ui/alerts.gd")
const Settings := preload("res://ui/settings.gd")

var _column: VBoxContainer
var alerts: Array = []


func _ready() -> void:
	theme_type_variation = "Floating"
	visible = false
	custom_minimum_size = Vector2(460, 0)
	_column = Kit.vbox(Tokens.SPACE_XS)
	add_child(_column)


func toggle() -> void:
	visible = not visible
	if visible:
		rebuild()


func rebuild() -> void:
	Kit.clear(_column)
	var head: HBoxContainer = Kit.hbox()
	_column.add_child(head)
	var title: Label = Kit.label("Alerts", "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Kit.button("Close", func() -> void: visible = false, "GhostButton"))
	if alerts.is_empty():
		_column.add_child(Kit.label("Nothing needs you right now.", "MutedLabel"))
	for alert: Dictionary in alerts:
		var row: HBoxContainer = Kit.hbox()
		_column.add_child(row)
		row.add_child(Kit.chip(String(alert["tier"]), Alerts.tier_state(String(alert["tier"]))))
		var text: Label = Kit.label(String(alert["text"]), "", true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(260, 0)
		row.add_child(text)
		row.add_child(Kit.button("Show", func() -> void: show_requested.emit(alert), "GhostButton"))
	_column.add_child(HSeparator.new())
	_column.add_child(Kit.label("Pause the game when one of these appears:", "MutedLabel"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_column.add_child(grid)
	for type: String in Alerts.TYPES:
		var box: CheckBox = CheckBox.new()
		box.focus_mode = Control.FOCUS_NONE
		box.text = Alerts.TYPES[type]
		box.button_pressed = Settings.autopause(type)
		box.toggled.connect(func(on: bool) -> void: Settings.set_autopause(type, on))
		grid.add_child(box)
