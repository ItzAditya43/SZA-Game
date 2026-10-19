extends "res://tests/checks_base.gd"
## Milestone 6: events, win/lose and balance.

const AutoPlayer := preload("res://tools/auto_player.gd")
const EndScreen := preload("res://ui/end_screen.gd")
const Geo := preload("res://core/geo.gd")
const DecisionPanel := preload("res://ui/decision_panel.gd")
const Decisions := preload("res://core/decisions.gd")

## Enough games for the survival rate to mean something, few enough to run in a few minutes.
const BATCH_GAMES: int = 40

var _player: AutoPlayer


func run_checks() -> void:
	_check_event_data()
	_check_event_effects()
	_check_stranger()
	_check_decision_panel()
	_check_full_run()
	_check_replay()
	_check_lose_conditions()
	_check_batch()


func _check_event_data() -> void:
	var events: Array = Data.table("events")
	expect("about a dozen hand-written events load from data/events.json", events.size() >= 12, "%d events" % events.size())
	var fired: Dictionary = {}
	for run_seed: int in 12:
		_play(3000 + run_seed, &"balanced")
		for id: String in WorldState.flags["events_fired"]:
			fired[id] = int(fired.get(id, 0)) + 1
	var never: Array = events.map(func(e: Dictionary) -> String: return e["id"]).filter(func(id: String) -> bool: return not fired.has(id))
	expect("every event fires in at least one of 12 runs", never.is_empty(), "never fired: %s; counts %s" % [never, fired])


func _check_event_effects() -> void:
	start(3100)
	var school: Dictionary = WorldState.building("school_01")
	var rice: float = Stores.total(school["loot"], "rice")
	TickLoop.run_headless(int(ceil((3.0 * 1440.0 + 10.0 * 60.0 - 360.0) / 10.0)) + 1)  # past day 3, 10:00
	expect("the relief camp stocks the school with rice, water and medicine", Stores.total(school["loot"], "rice") > rice + 50000.0
		and Stores.total(school["loot"], "antibiotics") >= 4.0)
	var system: Object = load("res://systems/events.gd").new()
	system.call("setup")
	var tower: Dictionary = WorldState.building("water_tower_01")
	tower["tank_l"] = 0.0
	captured.clear()
	system.call("_apply", [{"type": "rain", "mm": 25}])
	expect("25 mm of rain refills roof tanks by roof area (1 mm on 1 m² is 1 L)", float(tower["tank_l"]) > 3000.0
		and not events_named(&"rain_caught").is_empty(), "water tower: %.0f L" % float(tower["tank_l"]))
	system.call("_apply", [{"type": "destroy_loot", "landmark": "Market", "count": 3}])
	var burned: Array = WorldState.buildings.filter(func(b: Dictionary) -> bool: return b.get("burned", false))
	expect("a market fire burns out the three shops nearest the market", burned.size() == 3
		and burned.all(func(b: Dictionary) -> bool: return Stores.snapshot(b["loot"]).is_empty()))
	var zone: Dictionary = WorldState.zones[Geo.zone_index_at(Geo.building_center_m(WorldState.building("school_01")))]
	var before: float = float(zone["infected"])
	system.call("_apply", [{"type": "add_infected", "building": "school_01", "count": 400}])
	expect("an overrun camp adds infected to its zone", is_equal_approx(float(zone["infected"]), before + 400.0))


func _check_stranger() -> void:
	start(3200)
	var system: Object = load("res://systems/events.gd").new()
	system.call("setup")
	for event: Dictionary in Data.table("events"):
		if event["id"] == "stranger":
			system.call("_fire", event)
	var decision: Dictionary = WorldState.pending_decisions.back()
	expect("the stranger at the gate is a decision", decision["kind"] == &"event" and decision["options"].size() == 2)
	var stranger: String = decision["fill"]["id"]
	expect("the stranger is someone from the survivor pool who isn't in the group",
		not Data.entry("survivors", stranger).is_empty() and WorldState.survivor(stranger).is_empty()
		and String(decision["text"]).contains(String(decision["fill"]["name"])), decision["text"])
	EventBus.emit_event(&"decision_made", {"id": decision["id"], "option": &"accept"})
	expect("letting them in adds them to the group", not WorldState.survivor(stranger).is_empty()
		and WorldState.group().size() == 6)


func _check_decision_panel() -> void:
	start(3250)
	var panel: DecisionPanel = DecisionPanel.new()
	tree.root.add_child(panel)
	# Checks run before the first frame, when Godot has not yet readied new nodes.
	if not panel.is_node_ready():
		panel._ready()
	Decisions.create(&"test", "Test question?", [Decisions.option(&"yes", "Yes"), Decisions.option(&"no", "No")])
	var buttons: Array = panel.find_children("*", "Button", true, false)
	expect("a waiting decision shows in the Decisions tab with one button per option", buttons.size() == 2,
		"%d buttons" % buttons.size())
	captured.clear()
	if buttons.size() == 2:
		(buttons[1] as Button).pressed.emit()
	var made: Array[Dictionary] = events_named(&"decision_made")
	expect("pressing a button sends the choice on the bus", made.size() == 1 and made[0]["payload"]["option"] == &"no")
	panel.queue_free()


func _check_full_run() -> void:
	_play(3300, &"balanced")
	var outcome: Dictionary = WorldState.outcome
	expect("a full 30-day run is completable: it ends won or lost by day 30", outcome["state"] in [&"won", &"lost"]
		and int(outcome["day"]) <= 30, "%s on day %d: %s" % [outcome["state"], int(outcome["day"]), outcome["reason"]])
	expect("a won run reaches day 30 at 06:00 with someone alive", outcome["state"] != &"won"
		or int(outcome["tick"]) == 30 * WorldState.TICKS_PER_DAY and int(outcome["alive"]) > 0)
	var shown: String = EndScreen.describe(outcome)
	expect("the end screen shows the score and how it was made", shown.contains("Score") and shown.contains("alive × 100"))
	expect("after the end, time stops", _stays_still())


func _check_replay() -> void:
	_play(3400, &"fortress")
	var first: Dictionary = WorldState.outcome.duplicate(true)
	_play(3400, &"fortress")
	expect("the same seed and strategy replay exactly", first == WorldState.outcome, "%s vs %s" % [first["score"], WorldState.outcome["score"]])


func _check_lose_conditions() -> void:
	start(3500)
	for s: Dictionary in WorldState.survivors:
		s["health"] = -5.0
	TickLoop.step()
	expect("everyone dead loses the run", WorldState.outcome["state"] == &"lost" and not events_named(&"run_lost").is_empty())
	start(3501)
	for s: Dictionary in WorldState.survivors:
		s["stress"] = 100.0
	TickLoop.step()
	expect("everyone's morale below 5 scatters the group and loses", WorldState.outcome["state"] == &"lost"
		and String(WorldState.outcome["reason"]).contains("scattered"))


func _check_batch() -> void:
	var won: int = 0
	var alive: int = 0
	var people: int = 0
	for game: int in BATCH_GAMES:
		_play(5000 + game, &"balanced")
		if WorldState.outcome["state"] == &"won":
			won += 1
		alive += int(WorldState.outcome["alive"])
		people += int(WorldState.outcome["started"])
	var survival: float = 100.0 * alive / people
	expect("over %d games, survivor survival is neither near 0%% nor near 100%% (between 20%% and 90%%)" % BATCH_GAMES,
		survival >= 20.0 and survival <= 90.0, "%d%% of survivors alive at the end, %d%% of runs won" % [roundi(survival), roundi(100.0 * won / BATCH_GAMES)])
	expect("...and runs are lost as well as won (run win rate between 10% and 95%)",
		won > BATCH_GAMES / 10 and won < BATCH_GAMES * 95 / 100, "%d of %d won" % [won, BATCH_GAMES])


## A plain run with nobody playing (the auto-player from an earlier check is dropped).
func start(run_seed: int) -> void:
	_player = null
	super.start(run_seed)
	WorldState.flags["sandbox"] = false


func _play(run_seed: int, strategy: StringName) -> void:
	start(run_seed)
	_player = AutoPlayer.new(strategy)
	_player.begin()
	var end_tick: int = int(Data.table("scenario")["days_to_survive"]) * WorldState.TICKS_PER_DAY
	while WorldState.is_running() and WorldState.tick <= end_tick:
		TickLoop.step()


func _stays_still() -> bool:
	var at: int = WorldState.tick
	TickLoop.run_headless(10)
	return WorldState.tick == at
