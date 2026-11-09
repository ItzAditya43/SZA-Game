extends Node
## Entry point for an interactive run. Opens on the start screen (difficulty, seed,
## survivors, Continue/Load) over a paused world; `-- --difficulty=easy [--seed=N]
## [--roster=random]` on the command line skips it. The clock stops by itself when
## a decision is waiting, when the run ends, and while a menu is open.
## Keys: Esc pause menu, Ctrl+S quick save, Ctrl+L load list. Autosaves each dawn.

const SimRun := preload("res://core/sim_run.gd")
const SaveGame := preload("res://core/save_game.gd")

@onready var hud: Control = $HUD
## Off for tools that fast-forward the game (screenshots), so they leave no saves behind.
var autosave_enabled: bool = true


func _ready() -> void:
	TickLoop.auto_pause_on(&"decision_needed")
	TickLoop.auto_pause_on(&"run_won")
	TickLoop.auto_pause_on(&"run_lost")
	hud.end_screen.new_run_requested.connect(hud.start_screen.open)
	hud.start_screen.start_requested.connect(_start)
	hud.start_screen.continue_requested.connect(func() -> void: _load(SaveGame.latest()))
	hud.start_screen.load_list_requested.connect(hud.save_menu.open_load)
	hud.save_menu.new_run_requested.connect(hud.start_screen.open)
	hud.save_menu.load_requested.connect(_load)
	EventBus.event.connect(_on_bus_event)
	var run_seed: int = SimRun.int_arg("seed", int(Time.get_unix_time_from_system()))
	var difficulty: String = SimRun.string_arg("difficulty", "")
	if difficulty != "":
		_start(difficulty, run_seed, SimRun.roster_arg())
	else:
		# A paused world to look at behind the start screen.
		SimRun.start(run_seed)
		hud.start_screen.open()


func _start(difficulty: String, run_seed: int, roster: Array) -> void:
	SimRun.start(run_seed, difficulty, roster)
	TickLoop.set_speed(TickLoop.Speed.X1)


func _load(path: String) -> void:
	var problem: String = SaveGame.load_game(path) if path != "" else "There is no save to continue."
	if problem != "":
		hud.save_menu.open_load()
		hud.save_menu.show_message(problem)
		return
	hud.save_menu.close()
	hud.start_screen.visible = false
	TickLoop.set_speed(TickLoop.Speed.PAUSED)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if autosave_enabled and event_name == &"tick" and WorldState.is_dawn() and WorldState.is_running() and not WorldState.flags.get("sandbox", false):
		SaveGame.autosave()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		if hud.guide.visible:
			hud.guide.close()
		elif hud.save_menu.visible:
			hud.save_menu.close()
		elif not hud.modal_open():
			TickLoop.set_speed(TickLoop.Speed.PAUSED)
			hud.save_menu.open_pause()
	elif key.keycode == KEY_S and key.ctrl_pressed and not hud.start_screen.visible:
		SaveGame.save("quicksave")
	elif key.keycode == KEY_L and key.ctrl_pressed:
		TickLoop.set_speed(TickLoop.Speed.PAUSED)
		hud.save_menu.open_load()
	else:
		return
	get_viewport().set_input_as_handled()
