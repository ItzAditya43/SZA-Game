extends Node
## Autoload `Rng`. The only source of randomness in the simulation, with one seed
## per run, so any run can be replayed exactly. Never call the global randi() or
## randf() anywhere else.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0


func set_seed(new_seed: int) -> void:
	_seed = new_seed
	_rng.seed = new_seed
	print("Rng seed: %d" % new_seed)


func get_seed() -> int:
	return _seed


## Uniform float in [0, 1).
func randf() -> float:
	return _rng.randf()


## Uniform int in [a, b], both ends included.
func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


## True with probability p. p <= 0 is never true, p >= 1 is always true.
func chance(p: float) -> bool:
	return _rng.randf() < p


## The generator's exact position in its sequence, for saving and loading.
func get_state() -> int:
	return _rng.state


func set_state(state: int) -> void:
	_rng.state = state


## A separate generator for things that must never shift the simulation's own
## sequence, such as names: the same seed gives the same names, and rolling them
## doesn't change a single outcome. `salt` keeps different uses apart.
static func stream(run_seed: int, salt: String) -> RandomNumberGenerator:
	var out: RandomNumberGenerator = RandomNumberGenerator.new()
	out.seed = hash("%d:%s" % [run_seed, salt])
	return out
