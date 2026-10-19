extends ScrollContainer
## The People tab: the job board (drag names between jobs) and a compact card per
## survivor. Cards expand on click for the full picture.

signal plan_trip_requested(survivor_id: String)
signal survivor_focused(survivor_id: String)

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Card := preload("res://ui/survivor_card.gd")
const Board := preload("res://ui/job_board.gd")

var _column: VBoxContainer
var _summary: Label
var _board: Board
var _cards: VBoxContainer
var _roster_key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = Kit.vbox(Tokens.SPACE_S)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)
	var head: HBoxContainer = Kit.hbox()
	_column.add_child(head)
	_summary = Kit.label("", "HeadingLabel")
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_summary)
	var toggle: Button = Kit.button("Hide job board", func() -> void: pass, "GhostButton", "Show or hide who does what")
	toggle.pressed.connect(func() -> void:
		_board.visible = not _board.visible
		toggle.text = "Hide job board" if _board.visible else "Show job board")
	head.add_child(toggle)
	_board = Board.new()
	_column.add_child(_board)
	_cards = Kit.vbox(Tokens.SPACE_S)
	_column.add_child(_cards)
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"noise":
		refresh()


func refresh() -> void:
	var key: String = ",".join(WorldState.survivors.map(func(s: Dictionary) -> String: return "%s:%s" % [s["id"], s["status"]]))
	if key != _roster_key:
		_roster_key = key
		Kit.clear(_cards)
		var ordered: Array = WorldState.survivors.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["status"] == &"ok" and b["status"] != &"ok")
		for s: Dictionary in ordered:
			var card: Card = Card.new()
			card.survivor_id = s["id"]
			card.plan_trip_requested.connect(func(id: String) -> void: plan_trip_requested.emit(id))
			card.focus_requested.connect(func(id: String) -> void: survivor_focused.emit(id))
			_cards.add_child(card)
	var alive: int = WorldState.group().size()
	_summary.text = "Your group: %d of %d" % [alive, WorldState.survivors.size()]
	_board.refresh()
	for card: Node in _cards.get_children():
		(card as Card).refresh()
