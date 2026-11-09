extends PanelContainer
## Contextual tips: one short card at a time, each shown once and never again after
## "Got it" (remembered in settings). Tips wait in a queue while another is open.
## The text and what raises each tip live in data/tutorial.json; "No more tips"
## turns them all off. Raised by bus events and by notify() from the HUD.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Settings := preload("res://ui/settings.gd")
const Tutorial := preload("res://ui/tutorial.gd")

var _showing: String = ""
var _queue: Array[String] = []
var _text: Label
var _more: Label


func _ready() -> void:
	theme_type_variation = "Floating"
	custom_minimum_size = Vector2(380, 0)
	visible = false
	var column: VBoxContainer = Kit.vbox(Tokens.SPACE_S)
	add_child(column)
	column.add_child(Kit.label("Tip", "HeadingLabel"))
	_text = Kit.label("", "", true)
	_text.custom_minimum_size = Vector2(360, 0)
	column.add_child(_text)
	_more = Kit.label("", "FaintLabel")
	column.add_child(_more)
	var row: HBoxContainer = Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	row.add_child(Kit.button("No more tips", turn_off, "GhostButton"))
	row.add_child(Kit.button("Got it", dismiss, "PrimaryButton"))
	EventBus.event.connect(_on_bus_event)


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	if event_name in [&"run_started", &"game_loaded"]:
		_queue.clear()
		_showing = ""
		visible = false
	for trigger: String in Tutorial.triggers(event_name, payload):
		notify(trigger)


## Queues every tip raised by this trigger that is still unseen and applies now.
func notify(trigger: String) -> void:
	if trigger == "game_loaded":
		return
	var all: Dictionary = Tutorial.hints()
	for id: String in all:
		var hint: Dictionary = all[id]
		if hint["on"] == trigger and Tutorial.applies(hint):
			show_hint(id)


func show_hint(id: String) -> void:
	if Settings.hint_dismissed(id) or id == _showing or _queue.has(id):
		return
	if _showing != "":
		_queue.append(id)
		_refresh_more()
		return
	_open(id)


func _open(id: String) -> void:
	_showing = id
	_text.text = String(Tutorial.hints()[id]["text"])
	visible = true
	_refresh_more()


func _refresh_more() -> void:
	_more.text = "" if _queue.is_empty() else "%d more tip%s waiting" % [_queue.size(), "" if _queue.size() == 1 else "s"]


## Closes the card for good and moves on to the next waiting tip.
func dismiss() -> void:
	if _showing != "":
		Settings.dismiss_hint(_showing)
	_showing = ""
	visible = false
	while not _queue.is_empty():
		var next: String = _queue.pop_front()
		if not Settings.hint_dismissed(next) and Tutorial.applies(Tutorial.hints()[next]):
			_open(next)
			return
	_refresh_more()


func turn_off() -> void:
	for id: String in Tutorial.hints():
		Settings.dismiss_hint(id)
	_queue.clear()
	dismiss()
