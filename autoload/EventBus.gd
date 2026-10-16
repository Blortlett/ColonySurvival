extends Node
## Global event log feeding the HUD.

signal logged(text: String)

const MAX_LINES := 200
var lines: Array[String] = []


func log_event(text: String) -> void:
	var line := "[%s] %s" % [SimClock.time_string(), text]
	lines.append(line)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	logged.emit(line)
