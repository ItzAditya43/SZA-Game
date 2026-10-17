extends RefCounted
## What the player has selected on screen. Shared by the UI panels only; the
## simulation never sees it.

signal building_selected(id: String)

var selected_building: String = ""


func select_building(id: String) -> void:
	selected_building = id
	building_selected.emit(id)
