extends MeshInstance3D

var _bus

func _ready() -> void:
	# Try to get the ElixirBus singleton
	_bus = Engine.get_singleton("ElixirBus")
	print("ElixirBus singleton: ", _bus)

	if _bus:
		# Add the singleton to the scene tree so it can process
		if not _bus.is_inside_tree():
			get_tree().root.add_child(_bus)
			print("Added ElixirBus to scene tree")

		_bus.connect("new_message", Callable(self, "_on_new_message"))
		_bus.send_event("status", "godot_ready")
	else:
		print("ElixirBus singleton not found!")


func _on_new_message(_queued: int) -> void:
	print("Received new_message signal, queued: ", _queued)
	if _bus:
		var messages = _bus.drain()
		print("Drained messages: ", messages)
		for msg in messages:
			print("Processing message: ", msg)
			# Request pattern: "__request__:<id>:<payload>"
			if typeof(msg) == TYPE_STRING and msg.begins_with("__request__:"):
				print("Found request message: ", msg)
				var rest = msg.substr("__request__:".length())
				var idx = rest.find(":")
				if idx > 0:
					var id_str = rest.substr(0, idx)
					var payload = rest.substr(idx + 1)
					var req_id := int(id_str)
					print("Parsed request - id: ", req_id, ", payload: ", payload)
					# Example: echo back.
					var response = "echo:" + payload
					print("Sending response: ", response)
					_bus.respond(req_id, response)
					_bus.send_event("request_handled", id_str)
					continue

			print("Elixir message: ", msg)

func _check_stdin():
	if _bus:
		print("Calling check_stdin...")
		_bus.call("check_stdin")

func _process(delta):
	rotate_x(delta)
	# Messages are handled via the signal callback.
