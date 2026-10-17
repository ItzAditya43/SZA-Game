extends ScrollContainer
## Decisions waiting for the player, each with its options as buttons. Choosing
## one sends `decision_made` {"id", "option"} on the bus; the system that asked
## applies it. The game pauses itself whenever a new decision arrives.

signal pending_changed(count: int)

var _list: VBoxContainer
var _shown_key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)
	EventBus.event.connect(_on_bus_event)
	_refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"noise":
		_refresh()


func _refresh() -> void:
	var key: String = ",".join(WorldState.pending_decisions.map(func(d: Dictionary) -> String: return str(d["id"])))
	if key == _shown_key:
		return
	_shown_key = key
	for child: Node in _list.get_children():
		child.queue_free()
	if WorldState.pending_decisions.is_empty():
		var none: Label = Label.new()
		none.text = "Nothing waiting on you."
		none.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(none)
	for decision: Dictionary in WorldState.pending_decisions:
		var panel: PanelContainer = PanelContainer.new()
		var column: VBoxContainer = VBoxContainer.new()
		panel.add_child(column)
		var text: Label = Label.new()
		text.text = "%s\n(%s)" % [decision["text"], WorldState.clock_string_at(int(decision["tick"]))]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 16)
		column.add_child(text)
		var row: HBoxContainer = HBoxContainer.new()
		column.add_child(row)
		for option: Dictionary in decision["options"]:
			var button: Button = Button.new()
			button.text = option["label"]
			button.focus_mode = Control.FOCUS_NONE
			var id: int = int(decision["id"])
			var choice: StringName = option["id"]
			button.pressed.connect(func() -> void: EventBus.emit_event(&"decision_made", {"id": id, "option": choice}))
			row.add_child(button)
		_list.add_child(panel)
	pending_changed.emit(WorldState.pending_decisions.size())
