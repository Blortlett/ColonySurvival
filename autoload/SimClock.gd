extends Node
## Sim time. Every gameplay timer runs on sim time so speed changes scale everything.

signal speed_changed(speed: float)

const SPEEDS := [1.0, 2.0, 4.0, 8.0, 16.0]

var time := 0.0
var speed := 1.0
var paused := false


func set_speed(s: float) -> void:
	speed = s
	paused = false
	speed_changed.emit(speed)


func toggle_pause() -> void:
	paused = not paused
	speed_changed.emit(speed)


func scaled(real_delta: float) -> float:
	return 0.0 if paused else real_delta * speed


func time_string() -> String:
	var t := int(time)
	return "%02d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
