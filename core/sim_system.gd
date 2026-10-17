extends RefCounted
## Base for every simulation system. A system is registered with TickLoop and gets
## tick() once per tick, in registration order. It reads and writes WorldState and
## reaches other systems only through EventBus, never by calling them.


func tick() -> void:
	pass
