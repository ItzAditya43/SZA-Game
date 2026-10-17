extends RefCounted
## Helpers for an item store: a Dictionary of item id -> Array of lots, each lot
## {"qty": float, "age_days": float}. Used for the group's stores and for anything
## a survivor carries. Plain functions on plain data, so any system may use them.
## Quantities are in each item's real unit (litres, kcal, kg, count; see items.json).

const EPSILON: float = 0.0001
## Spoilage doubles for every 10 °C above this, and halves for every 10 °C below.
const SPOILAGE_REFERENCE_C: float = 30.0
const SPOILAGE_Q10: float = 2.0


static func total(stores: Dictionary, item: String) -> float:
	var sum: float = 0.0
	for lot: Dictionary in stores.get(item, []):
		sum += float(lot["qty"])
	return sum


## Totals of every item present, item id -> quantity.
static func snapshot(stores: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for item: String in stores:
		var qty: float = total(stores, item)
		if qty > EPSILON:
			out[item] = qty
	return out


static func add(stores: Dictionary, item: String, qty: float, age_days: float = 0.0) -> void:
	if qty <= EPSILON:
		return
	if not stores.has(item):
		stores[item] = []
	var lots: Array = stores[item]
	for lot: Dictionary in lots:
		if absf(float(lot["age_days"]) - age_days) < 0.01:
			lot["qty"] = float(lot["qty"]) + qty
			return
	lots.append({"qty": qty, "age_days": age_days})


## Takes up to `qty`, oldest lots first. Returns how much was actually taken.
static func take(stores: Dictionary, item: String, qty: float) -> float:
	return float(take_lots(stores, item, qty).reduce(func(sum: float, lot: Dictionary) -> float: return sum + float(lot["qty"]), 0.0))


## Like take(), but returns the lots taken so their age can travel with them.
static func take_lots(stores: Dictionary, item: String, qty: float) -> Array:
	var taken: Array = []
	if qty <= EPSILON or not stores.has(item):
		return taken
	var lots: Array = stores[item]
	lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["age_days"]) > float(b["age_days"]))
	var wanted: float = qty
	while wanted > EPSILON and not lots.is_empty():
		var lot: Dictionary = lots[0]
		var amount: float = minf(float(lot["qty"]), wanted)
		taken.append({"qty": amount, "age_days": lot["age_days"]})
		lot["qty"] = float(lot["qty"]) - amount
		wanted -= amount
		if float(lot["qty"]) <= EPSILON:
			lots.pop_front()
	if lots.is_empty():
		stores.erase(item)
	return taken


static func add_lots(stores: Dictionary, item: String, lots: Array) -> void:
	for lot: Dictionary in lots:
		add(stores, item, float(lot["qty"]), float(lot["age_days"]))


## Moves everything from one store into another, keeping lot ages.
static func merge_into(target: Dictionary, source: Dictionary) -> void:
	for item: String in source:
		add_lots(target, item, source[item])
	source.clear()


static func weight_kg(item: String, qty: float) -> float:
	var row: Dictionary = Data.entry("items", item)
	if row.has("kcal_per_kg"):
		return qty / float(row["kcal_per_kg"])
	return qty * float(row.get("kg_per_unit", 1.0))


## How much of `item` fits in `kg` of carrying capacity.
static func qty_for_weight(item: String, kg: float) -> float:
	var per_unit: float = weight_kg(item, 1.0)
	return kg / per_unit if per_unit > 0.0 else 0.0


## Ages every perishable lot by `days` at `temp_c` and removes what has spoiled.
## Returns item id -> quantity spoiled.
static func age_and_spoil(stores: Dictionary, days: float, temp_c: float) -> Dictionary:
	var spoiled: Dictionary = {}
	var rate: float = pow(SPOILAGE_Q10, (temp_c - SPOILAGE_REFERENCE_C) / 10.0)
	for item: String in stores.keys():
		var shelf_life: float = float(Data.entry("items", item).get("shelf_life_days", 0.0))
		if shelf_life <= 0.0:
			continue
		var lots: Array = stores[item]
		for lot: Dictionary in lots:
			lot["age_days"] = float(lot["age_days"]) + days * rate
		var kept: Array = lots.filter(func(lot: Dictionary) -> bool: return float(lot["age_days"]) < shelf_life)
		if kept.size() != lots.size():
			var lost: float = 0.0
			for lot: Dictionary in lots:
				if float(lot["age_days"]) >= shelf_life:
					lost += float(lot["qty"])
			spoiled[item] = lost
			if kept.is_empty():
				stores.erase(item)
			else:
				stores[item] = kept
	return spoiled


## Total food energy in a store, in kcal.
static func food_kcal(stores: Dictionary) -> float:
	var sum: float = 0.0
	for item: String in stores:
		if Data.entry("items", item).get("category", "") == "food":
			sum += total(stores, item)
	return sum
