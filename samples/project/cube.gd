extends MeshInstance3D

var _bus

func _ready() -> void:
	_bus = Engine.get_singleton("ElixirBus")
	if _bus:
		_bus.connect("new_message", Callable(self, "_on_new_message"))
		_bus.send_event("status", "godot_ready")


func _on_new_message(_queued: int) -> void:
	if _bus:
		for msg in _bus.drain():
			# Request pattern: "__request__:<id>:<payload>"
			if typeof(msg) == TYPE_STRING and msg.begins_with("__request__:"):
				var rest = msg.substr("__request__:".length())
				var idx = rest.find(":")
				if idx > 0:
					var id_str = rest.substr(0, idx)
					var payload = rest.substr(idx + 1)
					var req_id := int(id_str)
					# Example: echo back.
					_bus.respond(req_id, "echo:" + payload)
					_bus.send_event("request_handled", id_str)
					continue

			print("Elixir message: ", msg)

func _process(delta):
	rotate_x(delta)
	# Messages are handled via the signal callback.
