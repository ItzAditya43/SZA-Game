extends PanelContainer
## The "Getting started" list on the map: five first-day steps, ticked off as the
## player does them (steps and wording in data/tutorial.json). It disappears once
## all are done, or when hidden; progress is remembered in settings and
## "Show the tips again" resets it. UI-only.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Settings := preload("res://ui/settings.gd")
const Tutorial := preload("res://ui/tutorial.gd")

const HIDDEN_KEY: String = "steps_hidden"

var _column: VBoxContainer


func _ready() -> void:
	theme_type_variation = "Floating"
	custom_minimum_size = Vector2(330, 0)
	_column = Kit.vbox(Tokens.SPACE_XS)
	add_child(_column)
	EventBus.event.connect(_on_bus_event)
	Settings.listen(rebuild)
	rebuild()


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	if event_name == &"run_started":
		rebuild()
	for trigger: String in Tutorial.triggers(event_name, payload):
		notify(trigger)


## Ticks every step this trigger completes.
func notify(trigger: String) -> void:
	var changed: bool = false
	for step: Dictionary in Tutorial.steps():
		if step["done_on"] == trigger and not is_done(String(step["id"])):
			Settings.store("hints", "step_" + String(step["id"]), true)
			changed = true
	if changed:
		rebuild()


static func is_done(id: String) -> bool:
	return bool(Settings.value("hints", "step_" + id, false))


static func all_done() -> bool:
	return Tutorial.steps().all(func(step: Dictionary) -> bool: return is_done(String(step["id"])))


func rebuild() -> void:
	Kit.clear(_column)
	var hidden: bool = bool(Settings.value("hints", HIDDEN_KEY, false))
	visible = not hidden and not all_done()
	if not visible:
		return
	var head: HBoxContainer = Kit.hbox()
	_column.add_child(head)
	var title: Label = Kit.label("Getting started", "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Kit.button("Hide", func() -> void:
		Settings.store("hints", HIDDEN_KEY, true)
		rebuild(), "GhostButton", "Hide this list. Menu, Settings, Show the tips again brings it back."))
	var next_shown: bool = false
	for step: Dictionary in Tutorial.steps():
		var done: bool = is_done(String(step["id"]))
		var line: Label = Kit.label("%s  %s" % ["[x]" if done else "[ ]", step["text"]], "MutedLabel" if done else "", true)
		line.tooltip_text = String(step["why"])
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		_column.add_child(line)
		if not done and not next_shown:
			next_shown = true
			_column.add_child(Kit.label(String(step["why"]), "FaintLabel", true))
