extends PanelContainer
## First-days hints: one short card at a time, each shown once and never again
## after "Got it" (remembered in settings). "No more hints" turns them all off.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Settings := preload("res://ui/settings.gd")

const HINTS: Dictionary = {
	"start": "Your five survivors are in the house with the blue outline. The clock is paused: press Space (or 1) to let time run. Click any building to see what's inside and plan a scavenging trip. The People tab shows how everyone is; hover any number to see why it is what it is.",
	"first_trip": "Trips take hours. People on the move can meet infected: the planner shows the risk before you send them. Midday heat keeps infected sluggish; night is the most dangerous.",
	"first_night": "Night has fallen. Infected are most active now. Put someone on Guard for the night shift (People tab, job board) and keep noise down: hammering and generators draw them.",
	"first_water": "Water is the first thing to run out in this heat. Before the taps fail, put someone on Collect water to fill every container. Afterwards, water must be fetched and boiled.",
	"first_decision": "A decision is waiting. The game pauses for these. Each option says what will follow; options marked 'can't be undone' are final.",
}

var _showing: String = ""
var _text: Label


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
	var row: HBoxContainer = Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	row.add_child(Kit.button("No more hints", func() -> void:
		for id: String in HINTS:
			Settings.dismiss_hint(id)
		visible = false, "GhostButton"))
	row.add_child(Kit.button("Got it", func() -> void:
		Settings.dismiss_hint(_showing)
		visible = false, "PrimaryButton"))
	EventBus.event.connect(_on_bus_event)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	match event_name:
		&"run_started", &"game_loaded":
			if WorldState.day() == 0:
				show_hint("start")
		&"scavenge_started":
			show_hint("first_trip")
		&"phase_changed":
			if WorldState.phase() == WorldState.PHASE_NIGHT:
				show_hint("first_night")
		&"mains_warning", &"mains_failed":
			show_hint("first_water")
		&"decision_needed":
			show_hint("first_decision")


func show_hint(id: String) -> void:
	if Settings.hint_dismissed(id) or WorldState.day() > 2 and id != "first_decision":
		return
	_showing = id
	_text.text = HINTS[id]
	visible = true
