extends RefCounted
## Warnings for the player, worked out from the world each time it changes.
## Tiers: "info", "caution", "urgent". Each alert only states what the group could
## know: the taps failing is announced after the pressure drops, never from the
## hidden timer. Alert: {"id", "type", "tier", "text", "survivor"?, "building"?}.

const Body := preload("res://core/body.gd")
const Insight := preload("res://core/insight.gd")
const Stores := preload("res://core/stores.gd")

const TYPES: Dictionary = {
	"decision": "A decision is waiting", "bleeding": "Someone is bleeding", "bite": "A bite or its fever",
	"infection": "Infected wounds", "water": "Water running low", "food": "Food running low", "mains": "Taps about to fail",
	"power": "Power about to fail", "heat": "Heat exhaustion", "thirst": "Thirst and dehydration", "hunger": "Hunger",
	"shaken": "Too shaken to work", "attention": "Base drawing infected", "generator": "Generator fuel", "cook": "Food needs cooking",
	"night": "Night with no guard",
}
const TIER_ORDER: Array[String] = ["urgent", "caution", "info"]


## Every alert right now, most urgent first.
static func current(cues: Dictionary) -> Array:
	var out: Array = []
	for decision: Dictionary in WorldState.pending_decisions.filter(is_live):
		out.append(_alert("decision:%d" % int(decision["id"]), "decision", "urgent", String(decision["text"])))
	var water: Dictionary = Insight.water_forecast()
	var taps: bool = WorldState.infrastructure.get("mains_on", false)
	if not taps:
		var days: float = float(water["days"])
		if days < 1.5:
			out.append(_alert("water", "water", "urgent", "Water lasts about %.1f days. Collect, ration or move." % days))
		elif days < 3.0:
			out.append(_alert("water", "water", "caution", "Water lasts about %.1f days." % days))
	elif cues.get("mains_warning", false):
		out.append(_alert("mains", "mains", "caution", "The taps are failing. Put someone on Collect water to fill every container now."))
	if WorldState.infrastructure.get("power_on", false) and cues.get("power_warning", false):
		out.append(_alert("power", "power", "info", "The grid keeps browning out. Fridges and lights will go soon."))
	var food: Dictionary = Insight.food_forecast()
	if float(food["days"]) < 2.0:
		out.append(_alert("food", "food", "urgent", "Food lasts about %.1f days." % float(food["days"])))
	elif float(food["days"]) < 4.0:
		out.append(_alert("food", "food", "caution", "Food lasts about %.1f days." % float(food["days"])))
	if String(food["forecast"]).contains("nobody is on the cook job"):
		out.append(_alert("cook", "cook", "caution", "Most food is raw rice and dal: put someone on the Cook job."))
	for s: Dictionary in WorldState.group():
		_survivor_alerts(s, out)
	match WorldState.base.get("attention_level", &"low"):
		&"high":
			out.append(_alert("attention", "attention", "caution", "The base is drawing infected (attention high). Expect attacks, or move."))
		&"rising":
			out.append(_alert("attention", "attention", "info", "Attention at the base is rising."))
	if WorldState.policies.get(&"generator", &"off") != &"off" and Stores.total(WorldState.stores, "generator") >= 1.0:
		var hours: float = float(Insight.fuel_forecast()["generator_hours"])
		if hours < 9.0:
			out.append(_alert("generator", "generator", "caution", "Generator fuel for about %.0f hours." % hours))
	var minute: int = WorldState.minute_of_day()
	if minute >= 16 * 60 and minute < 18 * 60 and not WorldState.group().any(func(s: Dictionary) -> bool: return s["jobs"][&"night"] == &"guard"):
		out.append(_alert("night", "night", "caution", "Night falls at 18:00 and nobody is on guard."))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return TIER_ORDER.find(a["tier"]) < TIER_ORDER.find(b["tier"]))
	return out


static func _survivor_alerts(s: Dictionary, out: Array) -> void:
	var name: String = s["name"]
	var id: String = s["id"]
	if Body.is_bleeding(s):
		out.append(_alert("bleeding:" + id, "bleeding", "urgent", "%s is bleeding." % name, id))
	var pathogen: Dictionary = s["pathogen"]
	if not pathogen.is_empty() and (pathogen["known"] or pathogen["stage"] == &"prodrome"):
		out.append(_alert("bite:" + id, "bite", "urgent", "%s %s." % [name, "has a fever and will turn within hours" if pathogen["stage"] == &"prodrome" else "is bitten"], id))
	match Body.worst_infection(s):
		&"sepsis":
			out.append(_alert("infection:" + id, "infection", "urgent", "%s has sepsis." % name, id))
		&"fever":
			out.append(_alert("infection:" + id, "infection", "urgent", "%s's wound is infected and feverish." % name, id))
		&"local":
			out.append(_alert("infection:" + id, "infection", "caution", "%s's wound is reddening." % name, id))
	var deficit: float = float(s["water_deficit_l"])
	if deficit >= Body.DEHYDRATED_L:
		out.append(_alert("thirst:" + id, "thirst", "urgent", "%s is dehydrated and confused." % name, id))
	elif deficit >= Body.THIRSTY_L:
		out.append(_alert("thirst:" + id, "thirst", "caution", "%s is thirsty." % name, id))
	if float(s["core_temp_c"]) >= Body.HEAT_EXHAUSTION_C and Body.worst_infection(s) == &"none":
		out.append(_alert("heat:" + id, "heat", "caution", "%s has heat exhaustion. Rest in shade, water, work at dawn or dusk." % name, id))
	if float(s["kcal_debt"]) >= Body.WEAK_KCAL:
		out.append(_alert("hunger:" + id, "hunger", "caution", "%s is weak from hunger." % name, id))
	var stress: float = float(s["stress"])
	if stress >= Body.MAY_LEAVE_STRESS:
		out.append(_alert("shaken:" + id, "shaken", "urgent", "%s may leave the group tonight." % name, id))
	elif stress >= Body.REFUSES_JOBS_STRESS:
		out.append(_alert("shaken:" + id, "shaken", "caution", "%s is too shaken to work." % name, id))


static func _alert(id: String, type: String, tier: String, text: String, survivor: String = "") -> Dictionary:
	return {"id": id, "type": type, "tier": tier, "text": text, "survivor": survivor}


static func tier_state(tier: String) -> String:
	return {"urgent": "danger", "caution": "warn", "info": "info"}.get(tier, "muted")


## A waiting decision about someone who has since died, turned or left is moot:
## nobody is asked about it any more.
static func is_live(decision: Dictionary) -> bool:
	if not decision.has("survivor"):
		return true
	var id: String = String(decision["survivor"])
	return WorldState.group().any(func(s: Dictionary) -> bool: return s["id"] == id)
