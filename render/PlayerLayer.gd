extends Node2D
## Player-only visuals over the agents: the controlled body's ring and facing marker, the
## build ghost, harvest progress, and swing arcs (everyone's, so directional melee reads).
## Reads sim state only (Summer Roadmap §2.1). Drawn until sprites replace the discs.

const SWING_SHOW := 0.15 # seconds a swing arc stays visible

var player: PlayerController


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := float(Cfg.CELL)
	_draw_swings(s)
	if player == null or not player.alive():
		return
	var a := player.body
	var p := a.pos * s
	var col := Color(1, 1, 1, 0.9) if not player.watching else Color(0.6, 0.8, 1.0, 0.8)
	draw_arc(p, s * 0.58, 0, TAU, 32, col, 1.5 * Cfg.PX)
	# Facing marker: a small wedge just outside the body.
	var f := a.facing
	var side := f.orthogonal()
	draw_colored_polygon(PackedVector2Array([p + f * s * 0.85, p + f * s * 0.6 + side * s * 0.18, p + f * s * 0.6 - side * s * 0.18]), col)
	if player.watching:
		return
	_draw_harvest(s)
	_draw_build(s)


func _draw_swings(s: float) -> void:
	var now := SimClock.time
	var half := deg_to_rad(Cfg.SWING_ARC_DEG) * 0.5
	for a in World.agent_list:
		var age := now - a.last_swing
		if age < 0.0 or age > SWING_SHOW:
			continue
		var reach: float = Items.WEAPONS[a.melee_weapon()].reach * s
		var ang := a.facing.angle()
		var pts := PackedVector2Array([a.pos * s])
		for i in 9:
			pts.append(a.pos * s + Vector2.from_angle(ang - half + half * 2.0 * i / 8.0) * reach)
		var alpha := 0.35 * (1.0 - age / SWING_SHOW)
		var c := Color(1, 1, 1, alpha) if player and a == player.body else Color(1, 0.4, 0.3, alpha)
		draw_colored_polygon(pts, c)


func _draw_harvest(s: float) -> void:
	var n := player.harvest_node
	if n == null or player.harvest_secs <= 0.0:
		return
	var c := World.center(n.cell) * s
	var t := clampf(player.harvest_t / player.harvest_secs, 0.0, 1.0)
	draw_arc(c, s * 0.55, -PI / 2, -PI / 2 + TAU * t, 24, Color(1, 0.9, 0.3), 2.5 * Cfg.PX)


func _draw_build(s: float) -> void:
	if player.build_piece == "":
		return
	var a := player.body
	var c := player.hover_cell
	var why := Actions.can_place(a, player.build_piece, c, Cfg.PLAYER_BUILD_REACH)
	var col := Color(0.3, 1.0, 0.4, 0.45) if why == "" else Color(1.0, 0.25, 0.2, 0.45)
	draw_rect(Rect2(Vector2(c) * s, Vector2(s, s)), col)
	draw_rect(Rect2(Vector2(c) * s, Vector2(s, s)), Color(col, 0.9), false, 1.0 * Cfg.PX)
	draw_arc(a.pos * s, Cfg.PLAYER_BUILD_REACH * s, 0, TAU, 48, Color(1, 1, 1, 0.15), 1.0 * Cfg.PX)
