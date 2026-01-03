extends Node

var message_queue = []
var initialized = false

signal new_message(queued_count)

func _ready():
	# Set up stdin reading (this is a simplified version)
	# In a real implementation, we'd need to read from stdin properly
	print("ElixirBus GDScript ready")

func send_message(message):
	# Send message to Elixir via stdout
	var msg_data = {"type": "message", "data": message}
	var json_str = JSON.stringify(msg_data)
	print("MSG:" + json_str)

func send_event(event_name, data = null):
	# Send event to Elixir via stdout
	var event_data = {"type": "event", "event": event_name, "data": data}
	var json_str = JSON.stringify(event_data)
	print("EVENT:" + json_str)

func respond(request_id, response):
	# Send response to Elixir via stdout
	var json_str = JSON.stringify(response)
	print("RESP:" + str(request_id) + ":" + json_str)

func drain():
	var result = message_queue.duplicate()
	message_queue.clear()
	return result

func size():
	return message_queue.size()

func is_empty():
	return message_queue.is_empty()

func clear():
	message_queue.clear()

# For this demo, we'll simulate receiving messages
# In a real implementation, this would read from stdin
func _process(delta):
	if not initialized:
		initialized = true
		# Simulate receiving a message after 2 seconds
		var timer = Timer.new()
		timer.wait_time = 2.0
		timer.one_shot = true
		timer.connect("timeout", Callable(self, "_simulate_message"))
		add_child(timer)
		timer.start()

func _simulate_message():
	# Simulate receiving a request message
	var request_msg = "__request__:123:test_message"
	message_queue.append(request_msg)
	emit_signal("new_message", message_queue.size())
	print("Simulated receiving message: ", request_msg)
