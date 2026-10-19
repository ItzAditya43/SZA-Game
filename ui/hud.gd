extends Control
## The game screen. Top bar; the town map in the middle (overlays, the selected
## building's card, hints); a collapsible side panel with People, Stores, Base,
## Log and Stats; the last three events along the bottom. Pop-ups (decisions, the
## scavenge planner, confirmations, alerts, shortcuts, start/end/pause screens)
## sit above. Every panel reads WorldState (through core/insight.gd for
## explanations) and listens to EventBus; orders leave as command_* events.

const UiState := preload("res://ui/ui_state.gd")
const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Settings := preload("res://ui/settings.gd")
const Alerts := preload("res://ui/alerts.gd")
const Stores := preload("res://core/stores.gd")
const Traits := preload("res://core/traits.gd")
const Geo := preload("res://core/geo.gd")
const Controls := preload("res://ui/controls.gd")
const MapGrid := preload("res://ui/map_grid.gd")
const BuildingPanel := preload("res://ui/building_panel.gd")
const PeoplePanel := preload("res://ui/people_panel.gd")
const StoresPanel := preload("res://ui/stores_panel.gd")
const BasePanel := preload("res://ui/base_panel.gd")
const EventLog := preload("res://ui/event_log.gd")
const StatsPanel := preload("res://ui/stats_panel.gd")
const Ticker := preload("res://ui/ticker.gd")
const Hints := preload("res://ui/hints.gd")
const AlertsPanel := preload("res://ui/alerts_panel.gd")
const DecisionModal := preload("res://ui/decision_modal.gd")
const Planner := preload("res://ui/scavenge_planner.gd")
const ConfirmDialog := preload("res://ui/confirm_dialog.gd")
const Shortcuts := preload("res://ui/shortcuts.gd")
const EndScreen := preload("res://ui/end_screen.gd")
const StartScreen := preload("res://ui/start_screen.gd")
const SaveMenu := preload("res://ui/save_menu.gd")

const SIDE_WIDTH: float = 500.0
enum Tab { PEOPLE, STORES, BASE, LOG, STATS }

var ui_state: UiState = UiState.new()
var top_bar: Controls
var map: MapGrid
var tabs: TabContainer
var side: PanelContainer
var building_panel: BuildingPanel
var people: PeoplePanel
var hints: Hints
var alerts_panel: AlertsPanel
var decision_modal: DecisionModal
var planner: Planner
var confirm: ConfirmDialog
var shortcuts: Shortcuts
var end_screen: EndScreen
var start_screen: StartScreen
var save_menu: SaveMenu
var _backdrop: ColorRect
var _overlay_buttons: Dictionary = {}
var _alert_ids: Dictionary = {}
var _cues: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.apply_ui_scale(get_tree())
	var background: PanelContainer = Kit.panel("AppBackground")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column: VBoxContainer = Kit.vbox(0)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	top_bar = Controls.new()
	column.add_child(top_bar)
	var middle: HBoxContainer = Kit.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)
	middle.add_child(_build_map_area())
	side = Kit.panel("Sidebar")
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	middle.add_child(side)
	tabs = TabContainer.new()
	side.add_child(tabs)
	people = PeoplePanel.new()
	people.name = "People"
	tabs.add_child(people)
	var stores: StoresPanel = StoresPanel.new()
	stores.name = "Stores"
	tabs.add_child(stores)
	var base: BasePanel = BasePanel.new()
	base.name = "Base"
	tabs.add_child(base)
	var log_panel: EventLog = EventLog.new()
	log_panel.name = "Log"
	tabs.add_child(log_panel)
	var stats: StatsPanel = StatsPanel.new()
	stats.name = "Stats"
	tabs.add_child(stats)
	var ticker: Ticker = Ticker.new()
	column.add_child(ticker)
	_build_popups()

	top_bar.panel_toggled.connect(func() -> void: side.visible = not side.visible)
	top_bar.alerts_pressed.connect(func() -> void:
		alerts_panel.alerts = _current_alerts()
		alerts_panel.toggle())
	top_bar.shortcuts_pressed.connect(func() -> void: shortcuts.toggle())
	top_bar.menu_pressed.connect(func() -> void:
		TickLoop.set_speed(TickLoop.Speed.PAUSED)
		save_menu.open_pause())
	people.plan_trip_requested.connect(func(id: String) -> void: planner.open(ui_state.selected_building, id))
	building_panel.plan_requested.connect(func(id: String) -> void: planner.open(id))
	building_panel.move_requested.connect(_confirm_move)
	log_panel.locate_requested.connect(locate)
	ticker.locate_requested.connect(locate)
	alerts_panel.show_requested.connect(_show_alert)
	EventBus.event.connect(_on_bus_event)


func _build_map_area() -> Control:
	var area: Control = Control.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	map = MapGrid.new()
	map.ui_state = ui_state
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.offset_top = 52.0
	area.add_child(map)
	var bar: PanelContainer = Kit.panel("Floating")
	bar.position = Vector2(Tokens.SPACE_S, Tokens.SPACE_S)
	area.add_child(bar)
	var row: HBoxContainer = Kit.hbox(Tokens.SPACE_XS)
	bar.add_child(row)
	row.add_child(Kit.label("Show:", "MutedLabel"))
	for overlay: String in MapGrid.OVERLAYS:
		var button: Button = Kit.button(MapGrid.OVERLAY_NAMES[overlay], set_overlay.bind(overlay), "SpeedButton")
		button.toggle_mode = true
		button.button_pressed = overlay == map.overlay
		row.add_child(button)
		_overlay_buttons[overlay] = button
	building_panel = BuildingPanel.new()
	building_panel.ui_state = ui_state
	building_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	building_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	building_panel.position = Vector2(-Tokens.SPACE_S, 56)
	area.add_child(building_panel)
	building_panel.anchor_left = 1.0
	building_panel.anchor_right = 1.0
	building_panel.offset_right = -Tokens.SPACE_S
	building_panel.offset_top = 56
	# Bottom right of the map area, clear of the base, the legend and the building card.
	hints = Hints.new()
	hints.anchor_left = 1.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_right = -Tokens.SPACE_S
	hints.offset_bottom = -Tokens.SPACE_S
	area.add_child(hints)
	return area


func _build_popups() -> void:
	alerts_panel = AlertsPanel.new()
	alerts_panel.anchor_left = 1.0
	alerts_panel.anchor_right = 1.0
	alerts_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	alerts_panel.offset_right = -Tokens.SPACE_S
	alerts_panel.offset_top = 56
	alerts_panel.z_index = 5
	add_child(alerts_panel)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.6)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_backdrop.z_index = 10
	add_child(_backdrop)
	decision_modal = DecisionModal.new()
	planner = Planner.new()
	confirm = ConfirmDialog.new()
	shortcuts = Shortcuts.new()
	end_screen = EndScreen.new()
	start_screen = StartScreen.new()
	start_screen.visible = false
	save_menu = SaveMenu.new()
	for modal: Control in [decision_modal, planner, confirm, shortcuts, end_screen, start_screen, save_menu]:
		modal.add_to_group(&"modal")
		modal.z_index = 11
		add_child(modal)
		modal.visibility_changed.connect(_update_backdrop)
	save_menu.z_index = 12
	confirm.z_index = 12


func _update_backdrop() -> void:
	_backdrop.visible = modal_open()


## True while any pop-up that blocks the game screen is open.
func modal_open() -> bool:
	for modal: Node in get_tree().get_nodes_in_group(&"modal"):
		if (modal as Control).visible and is_ancestor_of(modal):
			return true
	return false


func set_overlay(name: String) -> void:
	map.set_overlay(name)
	for key: String in _overlay_buttons:
		(_overlay_buttons[key] as Button).set_pressed_no_signal(key == name)


## Jumps to whatever an event or alert is about: its building, or the spot on the map.
func locate(payload: Dictionary) -> void:
	if payload.has("building") and not WorldState.building(String(payload["building"])).is_empty():
		ui_state.select_building(String(payload["building"]))
		map.pulse_at(Geo.building_center_m(WorldState.building(String(payload["building"]))))
	elif payload.has("x_m"):
		map.pulse_at(Vector2(float(payload["x_m"]), float(payload["y_m"])))
	if payload.has("survivor"):
		side.visible = true
		tabs.current_tab = Tab.PEOPLE
		var s: Dictionary = WorldState.survivor(String(payload["survivor"]))
		if not s.is_empty() and s["location"] == &"away":
			map.pulse_at(Vector2(float(s["x_m"]), float(s["y_m"])))


func _show_alert(alert: Dictionary) -> void:
	alerts_panel.visible = false
	match String(alert["type"]):
		"decision":
			decision_modal.refresh(true)
		"water", "food", "generator":
			side.visible = true
			tabs.current_tab = Tab.STORES
		"attention":
			side.visible = true
			tabs.current_tab = Tab.BASE
			set_overlay("attention")
		"mains", "cook", "night":
			side.visible = true
			tabs.current_tab = Tab.PEOPLE
		_:
			if String(alert.get("survivor", "")) != "":
				locate({"survivor": alert["survivor"]})


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	match event_name:
		&"run_started":
			_cues.clear()
			_alert_ids.clear()
			ui_state.select_building("")
		&"game_loaded":
			_cues.clear()
			for entry: Dictionary in EventBus.event_log:
				if entry["name"] in [&"mains_warning", &"power_warning"]:
					_cues[String(entry["name"])] = true
			_alert_ids.clear()
		&"mains_warning", &"power_warning":
			_cues[String(event_name)] = true
	if event_name == &"tick" and WorldState.tick % 3 != 0:
		return
	if event_name == &"noise":
		return
	_refresh_alerts()


func _current_alerts() -> Array:
	return Alerts.current(_cues)


## Updates the alert counter, and pauses for new alerts the player wants paused on.
func _refresh_alerts() -> void:
	var alerts: Array = _current_alerts()
	var worst: String = alerts[0]["tier"] if not alerts.is_empty() else ""
	top_bar.set_alerts(alerts.size(), worst)
	var fresh: Dictionary = {}
	for alert: Dictionary in alerts:
		fresh[alert["id"]] = true
		if not _alert_ids.has(alert["id"]) and Settings.autopause(String(alert["type"])) and TickLoop.speed != TickLoop.Speed.PAUSED:
			TickLoop.set_speed(TickLoop.Speed.PAUSED)
	_alert_ids = fresh
	if alerts_panel.visible:
		alerts_panel.alerts = alerts
		alerts_panel.rebuild()


## Moving base, with what it will cost spelled out before the player commits.
func _confirm_move(building_id: String) -> void:
	var target: Dictionary = WorldState.building(building_id)
	var mobility: Dictionary = Data.table("mobility")
	var movers: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	var away: int = WorldState.group().size() - movers.size()
	var carry: float = 0.0
	for s: Dictionary in movers:
		carry += float(mobility["on_foot_kg"]) * Traits.mult(s, "carry_kg_mult")
	var carts: int = mini(roundi(Stores.total(WorldState.stores, "handcart")), movers.size())
	carry += carts * float(mobility["handcart"]["carry_kg"])
	var weight: float = 0.0
	for item: String in Stores.snapshot(WorldState.stores):
		weight += Stores.weight_kg(item, Stores.total(WorldState.stores, item))
	var distance: float = Geo.street_distance_m(Geo.base_center_m(), Geo.building_center_m(target))
	var type: Dictionary = Data.entry("buildings", String(target["type"]))
	var lines: Array = [
		"Everyone at base walks %.1f km to %s, exposed on the way, then clears it room by room (about an hour)." % [distance / 1000.0, target["name"]],
		"They can carry about %d kg%s. Stores weigh about %d kg: %s" % [roundi(carry), (" with %d handcart%s" % [carts, "" if carts == 1 else "s"]) if carts > 0 else "",
			roundi(weight), "everything fits." if weight <= carry else "the rest is hidden in a cache here."],
		"Barricades stay behind. The new base starts with defense %d and no barricades (Quick barricade helps)." % int(type["base_defense"]),
		"A new place draws less attention at first, but arriving is seen and heard. Uprooting is stressful for everyone.",
		"Whatever is still inside %s becomes yours." % target["name"],
	]
	if movers.is_empty():
		lines = ["Nobody is at base to move."]
	elif away > 0:
		lines.append("%d people are out and will come back to the new base." % away)
	confirm.ask("Move base to %s?" % target["name"], lines, "Move base", func() -> void:
		EventBus.emit_event(&"command_move_base", {"building": building_id})
		ui_state.select_building(""))
