extends PanelContainer
## A decision that needs the player, one at a time: the situation, each option
## with what the group knows will follow, what nobody can know yet, and a clear
## mark on options that can't be undone. Nothing has default focus, so a stray
## key never picks an irreversible option. "Decide later" leaves it waiting.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Alerts := preload("res://ui/alerts.gd")

const TITLES: Dictionary = {&"bite": "A bite", &"antibiotics": "Antibiotics", &"event": "Someone at the gate"}

var _column: VBoxContainer
var _showing: int = -1
var _later: Array = []


func _ready() -> void:
	theme_type_variation = "Modal"
	visible = false
	_column = Kit.vbox(Tokens.SPACE_M)
	_column.custom_minimum_size = Vector2(620, 0)
	add_child(_column)
	EventBus.event.connect(_on_bus_event)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	# Losing someone can make a waiting question about them moot.
	if event_name in [&"decision_needed", &"decision_made", &"run_started", &"game_loaded",
			&"survivor_died", &"survivor_turned", &"survivor_left", &"survivor_exiled"]:
		if event_name in [&"run_started", &"game_loaded"]:
			_later.clear()
		refresh()


## Shows the oldest waiting decision not put off with "Decide later" (or any, if forced).
func refresh(force: bool = false) -> void:
	if force:
		_later.clear()
	var waiting: Array = WorldState.pending_decisions.filter(func(d: Dictionary) -> bool:
		return not _later.has(int(d["id"])) and Alerts.is_live(d))
	if waiting.is_empty():
		visible = false
		_showing = -1
		return
	var decision: Dictionary = waiting[0]
	if int(decision["id"]) == _showing and visible:
		return
	_showing = int(decision["id"])
	Kit.clear(_column)
	_column.add_child(Kit.label(TITLES.get(decision["kind"], "A decision"), "TitleLabel"))
	_column.add_child(Kit.label(String(decision["text"]), "", true))
	for option: Dictionary in decision["options"]:
		var card: PanelContainer = Kit.panel("Card")
		_column.add_child(card)
		var row: VBoxContainer = Kit.vbox(Tokens.SPACE_XS)
		card.add_child(row)
		var head: HBoxContainer = Kit.hbox()
		row.add_child(head)
		var id: int = int(decision["id"])
		var choice: StringName = option["id"]
		var button: Button = Kit.button(option["label"], func() -> void:
			EventBus.emit_event(&"decision_made", {"id": id, "option": choice}),
			"DangerButton" if option.get("irreversible", false) else "Button")
		head.add_child(button)
		if option.get("irreversible", false):
			head.add_child(Kit.chip("can't be undone", "danger"))
		if String(option.get("consequence", "")) != "":
			row.add_child(Kit.label(String(option["consequence"]), "MutedLabel", true))
	var unknowns: Array = decision.get("unknowns", [])
	if not unknowns.is_empty():
		_column.add_child(Kit.label("Unknown: " + " ".join(unknowns), "InfoLabel", true))
	var footer: HBoxContainer = Kit.hbox()
	footer.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(footer)
	if waiting.size() > 1:
		footer.add_child(Kit.label("%d more waiting" % (waiting.size() - 1), "MutedLabel"))
	footer.add_child(Kit.button("Decide later", func() -> void:
		_later.append(_showing)
		refresh(), "GhostButton", "It stays in Alerts; the game stays paused until you resume."))
	visible = true
	_center.call_deferred()


func _center() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()
