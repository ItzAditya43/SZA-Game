extends "res://core/sim_system.gd"
## Jobs. Each survivor has one job for the day shift (06:00-18:00) and one for the
## night shift (18:00-06:00). Every tick this system turns the job and the hour
## into an activity (sleeping, working, travelling...) that Survivors uses for the
## body and other systems use for output (Base: fortify, Resources: cook...).
## Player orders arrive as `command_set_job` on the bus.

const Body := preload("res://core/body.gd")

const JOBS: Array[StringName] = [&"rest", &"scavenge", &"guard", &"fortify", &"collect_water", &"cook", &"treat"]
## Activity while doing each job at base during working hours.
const JOB_ACTIVITY: Dictionary = {
	&"guard": &"guarding",
	&"fortify": &"heavy_work",
	&"collect_water": &"heavy_work",
	&"cook": &"light_work",
	&"treat": &"light_work",
}
## Jobs done out in the sun (heat load) rather than indoors.
const OUTDOOR_JOBS: Array[StringName] = [&"fortify", &"collect_water", &"guard"]
## Working hours: start an hour into the shift and work 9 hours (07:00-16:00 by day,
## 19:00-04:00 by night). Guards watch the whole shift.
const WORK_START_OFFSET_MIN: int = 60
const WORK_MINUTES: int = 9 * 60
## Resting on the night shift: free time until 21:00, then sleep until 06:00.
const NIGHT_SLEEP_START_MINUTE: int = 21 * 60
## Resting on the day shift: nap when this tired or short of sleep, wake when rested.
const NAP_FATIGUE: float = 35.0
const NAP_SLEEP_DEBT_H: float = 2.0
const WAKE_FATIGUE: float = 5.0


func setup() -> void:
	listen(&"command_set_job", _on_set_job)
	for s: Dictionary in WorldState.survivors:
		_schedule(s)


func tick() -> void:
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok":
			s["activity"] = &"none"
			continue
		_schedule(s)


## Sets job_now, activity, outdoors and asleep for a survivor at base.
func _schedule(s: Dictionary) -> void:
	var shift: StringName = current_shift()
	var job: StringName = s["jobs"][shift]
	if s["quarantined"] or Body.is_incapacitated(s):
		job = &"rest"
	elif float(s["stress"]) >= Body.REFUSES_JOBS_STRESS and job != &"rest":
		var shift_id: int = shift_index()
		if int(s.get("refused_shift", -1)) != shift_id:
			s["refused_shift"] = shift_id
			EventBus.emit_event(&"job_refused", {"survivor": s["id"],
				"text": "%s is too shaken to %s and stays in." % [s["name"], String(s["jobs"][shift]).replace("_", " ")]})
		job = &"rest"
	s["job_now"] = job
	s["outdoors"] = false
	if job == &"rest":
		_rest(s, shift)
		return
	s["asleep"] = false
	if job == &"guard":
		s["activity"] = &"guarding"
		s["outdoors"] = true
	elif in_work_hours() and JOB_ACTIVITY.has(job):
		s["activity"] = JOB_ACTIVITY[job]
		s["outdoors"] = OUTDOOR_JOBS.has(job)
	else:
		# LATER (Milestone 3): scavenge trips.
		s["activity"] = &"idle"


func _rest(s: Dictionary, shift: StringName) -> void:
	var minute: int = WorldState.minute_of_day()
	if shift == &"night":
		s["asleep"] = minute >= NIGHT_SLEEP_START_MINUTE or minute < WorldState.DAYTIME_START_MINUTE
	elif s["asleep"]:
		s["asleep"] = float(s["fatigue"]) > WAKE_FATIGUE
	else:
		s["asleep"] = float(s["fatigue"]) >= NAP_FATIGUE or float(s["sleep_debt_h"]) >= NAP_SLEEP_DEBT_H
	s["activity"] = &"sleeping" if s["asleep"] else &"resting"


func _on_set_job(payload: Dictionary) -> void:
	var s: Dictionary = WorldState.survivor(String(payload["survivor"]))
	var shift: StringName = StringName(payload["shift"])
	var job: StringName = StringName(payload["job"])
	if s.is_empty() or not JOBS.has(job) or not shift in [&"day", &"night"]:
		push_error("Jobs: bad command_set_job %s" % payload)
		return
	s["jobs"][shift] = job
	if payload.has("target"):
		s["targets"][shift] = String(payload["target"])


static func current_shift() -> StringName:
	return &"day" if WorldState.phase() == WorldState.PHASE_DAY else &"night"


## Minutes since the current shift began.
static func minutes_into_shift() -> int:
	var start: int = WorldState.DAYTIME_START_MINUTE if current_shift() == &"day" else WorldState.NIGHT_START_MINUTE
	return posmod(WorldState.minute_of_day() - start, WorldState.MINUTES_PER_DAY)


static func in_work_hours() -> bool:
	var into: int = minutes_into_shift()
	return into >= WORK_START_OFFSET_MIN and into < WORK_START_OFFSET_MIN + WORK_MINUTES


## A number that changes every shift, for "once per shift" bookkeeping.
@warning_ignore("integer_division")
static func shift_index() -> int:
	return WorldState.tick / (WorldState.TICKS_PER_DAY / 2)
