extends RefCounted
const SimRun := preload("res://core/sim_run.gd")
const AutoPlayer := preload("res://tools/auto_player.gd")
const Body := preload("res://core/body.gd")
func go() -> void:
	SimRun.start(3)
	var p: AutoPlayer = AutoPlayer.new(StringName(SimRun.string_arg("strategy", "keep_moving")))
	p.begin()
	for day: int in 30:
		for i: int in 144:
			TickLoop.step()
		var parts: PackedStringArray = []
		for s: Dictionary in WorldState.survivors:
			if s["status"] == &"ok":
				parts.append("%s s%d w%.1f k%d f%d sd%.0f %s" % [s["name"].substr(0,3), roundi(float(s["stress"])), float(s["water_deficit_l"]), roundi(float(s["kcal_debt"])), roundi(float(s["fatigue"])), float(s["sleep_debt_h"]), ",".join(Body.conditions(s))])
		print(WorldState.clock_string(), " base=", WorldState.base["building"], " | ", " | ".join(parts))
		if not WorldState.is_running():
			print(WorldState.outcome["reason"]); break
