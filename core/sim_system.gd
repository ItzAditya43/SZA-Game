extends RefCounted
## Base for every simulation system. A system is registered with TickLoop and gets
## tick() once per tick, in registration order. It reads and writes WorldState and
## reaches other systems only through EventBus, never by calling them.

var _handlers: Dictionary = {}  # event name -> Callable(payload: Dictionary)


## Called once per run, after every system is registered and before the first
## tick, in tick order. Builds this system's part of WorldState.
func setup() -> void:
	pass


func tick() -> void:
	pass


## Calls `handler(payload)` whenever `event_name` is emitted on the bus.
func listen(event_name: StringName, handler: Callable) -> void:
	if _handlers.is_empty():
		EventBus.event.connect(_dispatch)
	_handlers[event_name] = handler


func _dispatch(event_name: StringName, payload: Dictionary) -> void:
	var handler: Callable = _handlers.get(event_name, Callable())
	if handler.is_valid():
		handler.call(payload)
