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


## Called when the run ends or a new one starts: stop listening to the bus, so a
## finished run's systems can never act on the next one.
func shutdown() -> void:
	if EventBus.event.is_connected(_dispatch):
		EventBus.event.disconnect(_dispatch)
	_handlers.clear()


## Calls `handler(payload)` whenever `event_name` is emitted on the bus. Pass a
## method, not an inline lambda: a lambda that uses the system keeps it alive.
func listen(event_name: StringName, handler: Callable) -> void:
	if _handlers.is_empty():
		EventBus.event.connect(_dispatch)
	_handlers[event_name] = handler


func _dispatch(event_name: StringName, payload: Dictionary) -> void:
	var handler: Callable = _handlers.get(event_name, Callable())
	if handler.is_valid():
		handler.call(payload)
