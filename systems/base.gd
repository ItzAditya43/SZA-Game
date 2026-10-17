extends "res://core/sim_system.gd"
## Base. Where the group lives and keeps its stores. Milestone 3: the start
## building from scenario.json.
# LATER (Milestone 5): moving base, barricades, defense, night attacks.


func setup() -> void:
	WorldState.base = {"building": String(Data.table("scenario")["start_building"]), "alert": 0.0}
