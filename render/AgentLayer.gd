extends Node2D
## Agents: fill = faction colour (grey if solo), outline = mood. Servants get a dark dot, leaders a gold one.

const Disc := preload("res://render/Disc.gd")

const MOOD_COLORS := {"happy": Color(0.3, 1.0, 0.4), "neutral": Color(0.75, 0.8, 0.9), "angry": Color(1.0, 0.2, 0.2)}

var selected_id := -1
var show_labels := false
var _font: Font


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_usec()
	_draw_body()
	World.prof_add("draw_agents", t)


func _draw_body() -> void:
	var s := float(Cfg.CELL)
	for a in World.agent_list:
		var p := a.pos * s
		var fill: Color = Color(0.55, 0.55, 0.55) if a.faction.solo else a.faction.color
		if a.is_armoured():
			Disc.draw(self, p, s * 0.54, Color(0.62, 0.63, 0.68)) # armoured: grey outer ring (v3)
		Disc.draw(self, p, s * 0.42, MOOD_COLORS[a.mood_label()])
		Disc.draw(self, p, s * 0.30, fill)
		if a.is_servant():
			Disc.draw(self, p, s * 0.12, Color(0.05, 0.05, 0.05))
		elif not a.faction.solo and a.faction.leader_id == a.id:
			Disc.draw(self, p, s * 0.12, Color(1.0, 0.85, 0.2))
		if a.raid_id != -1:
			# Raiders carry a small red pennant.
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.9), p + Vector2(s * 0.45, -s * 0.75), p + Vector2(0, -s * 0.6)]), Color(1, 0.15, 0.1))
			draw_line(p + Vector2(0, -s * 0.9), p + Vector2(0, -s * 0.4), Color(0.1, 0.1, 0.1), 1.0 * Cfg.PX)
		if a.job and a.job.kind == Job.Kind.FIGHT:
			var t: Agent = World.agents.get(a.job.target_id)
			if t:
				draw_line(p, t.pos * s, Color(1, 0.1, 0.1, 0.6), 1.0 * Cfg.PX)
		if show_labels:
			draw_string(_font, p + Vector2(-s, -s * 0.6), a.short(), HORIZONTAL_ALIGNMENT_CENTER, s * 2, int(8 * Cfg.PX))
	var sel: Agent = World.agents.get(selected_id)
	if sel:
		var p := sel.pos * s
		draw_arc(p, s * 0.7, 0, TAU, 24, Color(1, 1, 0), 2.0 * Cfg.PX)
		if sel.path.size() > 1:
			var pts := PackedVector2Array([p])
			for i in range(sel.path_i, sel.path.size()):
				pts.append(World.center(sel.path[i]) * s)
			if pts.size() > 1:
				draw_polyline(pts, Color(1, 1, 0, 0.5), 1.0 * Cfg.PX)
