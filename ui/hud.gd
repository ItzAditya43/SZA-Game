extends Control
## The game screen: top bar, town map on the left, tabbed panels on the right and
## the event log along the bottom. Every panel only reads WorldState and listens
## to EventBus; player orders leave as command_* events on the bus.

const Controls := preload("res://ui/controls.gd")
const EventLog := preload("res://ui/event_log.gd")
const SurvivorPanel := preload("res://ui/survivor_panel.gd")
const MapGrid := preload("res://ui/map_grid.gd")
const BuildingPanel := preload("res://ui/building_panel.gd")
const DecisionPanel := preload("res://ui/decision_panel.gd")
const BasePanel := preload("res://ui/base_panel.gd")
const UiState := preload("res://ui/ui_state.gd")

const LOG_HEIGHT: float = 140.0

var ui_state: UiState = UiState.new()
var tabs: TabContainer
var left: VBoxContainer
var map: MapGrid
var building_panel: BuildingPanel
var decision_panel: DecisionPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.11, 0.115, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	column.add_child(Controls.new())

	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	column.add_child(middle)

	left = VBoxContainer.new()
	middle.add_child(left)
	_add_map()

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(tabs)
	var survivors: SurvivorPanel = SurvivorPanel.new()
	survivors.ui_state = ui_state
	survivors.name = "Group"
	tabs.add_child(survivors)
	building_panel = BuildingPanel.new()
	building_panel.ui_state = ui_state
	building_panel.name = "Building"
	tabs.add_child(building_panel)
	ui_state.building_selected.connect(func(id: String) -> void:
		if id != "":
			tabs.current_tab = building_panel.get_index())
	var base_panel: BasePanel = BasePanel.new()
	base_panel.name = "Base"
	tabs.add_child(base_panel)
	decision_panel = DecisionPanel.new()
	decision_panel.name = "Decisions"
	tabs.add_child(decision_panel)
	decision_panel.pending_changed.connect(func(count: int) -> void:
		tabs.set_tab_title(decision_panel.get_index(), "Decisions (%d)" % count if count > 0 else "Decisions")
		if count > 0:
			tabs.current_tab = decision_panel.get_index())

	var log_panel: EventLog = EventLog.new()
	log_panel.custom_minimum_size = Vector2(0, LOG_HEIGHT)
	column.add_child(log_panel)


func _add_map() -> void:
	map = MapGrid.new()
	map.ui_state = ui_state
	left.add_child(map)
	var toggle: CheckBox = CheckBox.new()
	toggle.text = "Show infected per zone"
	toggle.button_pressed = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(func(on: bool) -> void:
		map.show_infected = on
		map.queue_redraw())
	left.add_child(toggle)
	var legend: Label = Label.new()
	legend.add_theme_font_size_override("font_size", 12)
	legend.modulate = Color(1, 1, 1, 0.7)
	legend.text = "Green outline: base · yellow: selected · blue dots: survivors out · red tint: infected per zone"
	left.add_child(legend)
