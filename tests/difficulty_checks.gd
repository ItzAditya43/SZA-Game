extends "res://tests/checks_base.gd"
## Difficulty presets: Easy, Normal and Hard from data/difficulty.json.

const Difficulty := preload("res://core/difficulty.gd")
const InfectedSystem := preload("res://systems/infected.gd")
const AutoPlayer := preload("res://tools/auto_player.gd")
const StartScreen := preload("res://ui/start_screen.gd")

const LEVELS: Array[String] = ["easy", "normal", "hard"]
const BATCH_GAMES: int = 20

var _player: AutoPlayer


func run_checks() -> void:
	_check_presets()
	_check_world_scales()
	_check_encounters_scale()
	_check_start_screen()
	_check_batch_order()


func _check_presets() -> void:
	var ids: Array = Difficulty.ids()
	expect("three presets load: easy, normal, hard", ids == ["easy", "normal", "hard"], str(ids))
	var normal: Dictionary = Difficulty.preset("normal")["multipliers"]
	expect("normal is the tuned baseline (every multiplier 1.0)", normal.values().all(func(v: float) -> bool: return is_equal_approx(v, 1.0)))
	expect("each preset explains itself to the player", Data.table("difficulty").all(
		func(p: Dictionary) -> bool: return String(p.get("description", "")).length() > 40))


func _check_world_scales() -> void:
	var infected: Array[float] = []
	var stores: Array[float] = []
	var loot: Array[float] = []
	for level: String in LEVELS:
		_start(100, level)
		infected.append(InfectedSystem.total())
		stores.append(Stores.food_kcal(WorldState.stores))
		var food: float = 0.0
		for b: Dictionary in WorldState.buildings:
			food += Stores.food_kcal(b["loot"])
		loot.append(food)
	expect("the outbreak is smaller on easy and bigger on hard", infected[0] < infected[1] and infected[1] < infected[2],
		"%d / %d / %d infected at the start" % [infected[0], infected[1], infected[2]])
	expect("the group starts with more on easy, less on hard", stores[0] > stores[1] and stores[1] > stores[2],
		"%d / %d / %d kcal" % [stores[0], stores[1], stores[2]])
	expect("there is more left on the shelves on easy, less on hard", loot[0] > loot[1] and loot[1] > loot[2])
	_start(100, "hard")
	expect("the rules don't change: power still fails between day 3 and 6", WorldState.day_at(int(WorldState.infrastructure["power_fail_tick"])) in [3, 4, 5, 6])


func _check_encounters_scale() -> void:
	var counts: Array[int] = []
	for level: String in LEVELS:
		_start(101, level)
		var system: Object = InfectedSystem.new()
		WorldState.tick = 90
		var s: Dictionary = WorldState.survivor("farhan")
		var met: int = 0
		for i: int in 3000:
			s["health"] = 100.0
			s["injuries"] = []
			s["exposure"] = {"outdoors": true, "building": "", "noise_m": 15.0, "zone": 10}
			captured.clear()
			system.call("_roll_encounter", s)
			if not events_named(&"encounter").is_empty():
				met += 1
		counts.append(met)
	expect("the same walk meets infected less often on easy and more often on hard", counts[0] < counts[1] and counts[1] < counts[2],
		"%d / %d / %d encounters per 3,000 ticks" % [counts[0], counts[1], counts[2]])


func _check_start_screen() -> void:
	var screen: StartScreen = StartScreen.new()
	tree.root.add_child(screen)
	if not screen.is_node_ready():
		screen._ready()
	var chosen: Array = []
	screen.start_requested.connect(func(level: String, run_seed: int) -> void: chosen.append([level, run_seed]))
	for button: Button in screen.find_children("*", "Button", true, false):
		if button.text == "Hard":
			button.pressed.emit()
	(screen.find_children("*", "LineEdit", true, false)[0] as LineEdit).text = "77"
	for button: Button in screen.find_children("*", "Button", true, false):
		if button.text == "Start":
			button.pressed.emit()
	expect("the start screen starts a Hard run with the seed typed in", chosen == [["hard", 77]], str(chosen))
	screen.queue_free()


func _check_batch_order() -> void:
	var won: Array[int] = []
	for level: String in LEVELS:
		var wins: int = 0
		for game: int in BATCH_GAMES:
			_start(7000 + game, level)
			WorldState.flags["sandbox"] = false
			_player = AutoPlayer.new(&"balanced")
			_player.begin()
			while WorldState.is_running() and WorldState.tick <= 30 * WorldState.TICKS_PER_DAY:
				TickLoop.step()
			if WorldState.outcome["state"] == &"won":
				wins += 1
		won.append(wins)
	expect("the same strategy wins most on easy, less on normal, least on hard (%d games each)" % BATCH_GAMES,
		won[0] > won[1] and won[1] > won[2] and won[0] - won[2] >= BATCH_GAMES / 3,
		"%d / %d / %d won" % [won[0], won[1], won[2]])


func _start(run_seed: int, level: String) -> void:
	_player = null
	SimRun.start(run_seed, level)
	WorldState.flags["sandbox"] = true
	captured.clear()
