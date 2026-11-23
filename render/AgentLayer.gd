extends Node2D
## Agents as layered top-down sprites (Summer Roadmap §3), or the old discs.
##
## Sprites: legs turn to the movement direction (idle / walk / run by speed); the torso turns
## to the facing (see facing_of) and plays idle, walk, run, attack, use, pain and death. All
## sprites are one MultiMesh over a packed atlas (SpriteAtlas, mapped in BodySets), so 120+
## agents cost one draw call. Under each agent a disc shows faction colour (grey if solo)
## with a mood rim; servant / leader pips, raider pennants, selection, path and labels draw
## on top. Zoomed far out the discs read better, so mode AUTO switches to them.
##
## Read-only on the sim (roadmap §2 rule 1): animation state (timers, last position, facing)
## lives here, keyed by agent id. Swings, hits and deaths are inferred by watching
## attack_cd, hp and agents disappearing.

const Disc := preload("res://render/Disc.gd")
const Atlas := preload("res://render/SpriteAtlas.gd")
const SpriteShader := preload("res://render/agent_sprite.gdshader")

const MOOD_COLORS := {"happy": Color(0.3, 1.0, 0.4), "neutral": Color(0.75, 0.8, 0.9), "angry": Color(1.0, 0.2, 0.2)}

enum Mode { AUTO, SPRITES, DISCS }
const MODE_NAMES := ["auto", "sprites", "discs"]
const AUTO_DISC_ZOOM := 0.3 # AUTO draws discs below this camera zoom
const IDLE_SPEED := 0.3 # cells/s; slower counts as standing
const RUN_SPEED := 3.3 # cells/s; faster counts as running (base walking speed is 3)
const HURRY_JOBS := [Job.Kind.FIGHT, Job.Kind.FLEE, Job.Kind.RAID, Job.Kind.DEFEND]
const USE_JOBS := [Job.Kind.GATHER, Job.Kind.TASK, Job.Kind.CRAFT, Job.Kind.CHEST, Job.Kind.LOOT]
const TURN_RATE := 14.0 # 1/s, how fast sprites swing round to a new angle
const FLASH_SECS := 0.2
const CORPSE_SECS := 30.0 # sim seconds a body stays, fading over the last FADE
const CORPSE_FADE := 6.0
const MAX_CORPSES := 60
const FLOATS := 16 # per instance: 2D transform 8, colour 4, custom 4

var selected_id := -1
var show_labels := false
var mode := Mode.AUTO
var _font: Font

var _states := {} # agent id -> AnimState
var _corpses: Array[Corpse] = []
var _last_sim := 0.0
var _frame := 0
var _discs := false # resolved mode this frame
var _view := Rect2() # visible world rect plus a margin, this frame
var _has_facing := -1 # Agent.facing exists (1) or not (0); checked once
var _has_delta := false # World.delta exists (roadmap §2 rule 2)

var _mm: MultiMesh
var _mm_node: MultiMeshInstance2D
var _buf := PackedFloat32Array()
var _overlay: Node2D


class AnimState:
	var body: Dictionary
	var tint: Color
	var last_pos: Vector2
	var speed := 0.0 # smoothed, cells per sim second
	var move_ang := 0.0
	var legs_ang := 0.0
	var torso_ang := 0.0
	var legs_anim := "idle"
	var legs_t := 0.0
	var torso_anim := "idle"
	var torso_t := 0.0
	var oneshot := "" # "attack" / "pain" while playing
	var alt := false # alternate punch arm
	var last_hp := 0.0
	var last_cd := 0.0
	var flash := 0.0
	var stamp := 0


class Corpse:
	var body: Dictionary
	var tint: Color
	var pos: Vector2
	var ang: float
	var t := 0.0 # animation time
	var age := 0.0 # sim seconds


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = ThemeDB.fallback_font
	Atlas.ensure()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _unit_quad()
	_mm.custom_aabb = AABB(Vector3(-1e6, -1e6, -1), Vector3(2e6, 2e6, 2))
	_mm_node = MultiMeshInstance2D.new()
	_mm_node.multimesh = _mm
	_mm_node.texture = Atlas.texture
	# Nearest within a mip: crisp pixels at zoom >= 1, smaller mips instead of shimmer below.
	_mm_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	mat.shader = SpriteShader
	_mm_node.material = mat
	add_child(_mm_node)
	_overlay = Node2D.new()
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_last_sim = SimClock.time
	_has_delta = World.has_method("delta")


func mode_name() -> String:
	return MODE_NAMES[mode]


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	EventBus.log_event("Agent drawing: %s" % MODE_NAMES[mode])


func _process(delta: float) -> void:
	var t := Time.get_ticks_usec()
	var ct := get_viewport().get_canvas_transform()
	var zoom := ct.get_scale().x
	_view = (ct.affine_inverse() * get_viewport_rect()).grow(96.0)
	_discs = mode == Mode.DISCS or (mode == Mode.AUTO and zoom < AUTO_DISC_ZOOM)
	if _discs:
		# Nothing to animate; start fresh (bodies and tints come from the id) on the way back.
		_states.clear()
		_corpses.clear()
		_last_sim = SimClock.time
	else:
		_update(delta)
	_mm_node.visible = not _discs
	queue_redraw()
	_overlay.queue_redraw()
	World.prof_add("draw_agents", t)


func _draw() -> void:
	var t := Time.get_ticks_usec()
	if _discs:
		_draw_discs()
	else:
		_draw_under()
	World.prof_add("draw_agents", t)


## Where an agent's torso points, in radians. Prefers the sim's own facing once the player
## work adds it (Agent.facing, a Vector2 or an angle); otherwise toward the fight target,
## else the way it last moved.
func facing_of(a: Agent, st: AnimState) -> float:
	if _has_facing == -1:
		_has_facing = 1 if "facing" in a else 0
	if _has_facing == 1:
		var f = a.get("facing")
		if f is Vector2 and f != Vector2.ZERO:
			return f.angle()
		if f is float:
			return f
	if a.job and a.job.kind == Job.Kind.FIGHT:
		var tg: Agent = World.agents.get(a.job.target_id)
		if tg and tg != a:
			var d := _delta(a.pos, tg.pos)
			if d != Vector2.ZERO:
				return d.angle()
	return st.move_ang


## Wrap-aware once World.delta exists (roadmap §2 rule 2).
func _delta(from: Vector2, to: Vector2) -> Vector2:
	if _has_delta:
		return World.call("delta", from, to)
	return to - from


# --- animation state ------------------------------------------------------------------------

func _update(real_dt: float) -> void:
	_frame += 1
	var sim_dt := maxf(SimClock.time - _last_sim, 0.0)
	_last_sim = SimClock.time
	var anim_dt := minf(sim_dt, real_dt * 3.0) # cap so 16x doesn't strobe
	var turn := 1.0 - exp(-TURN_RATE * maxf(real_dt, anim_dt))
	var n := World.agent_list.size()
	var count := 0
	_reserve((n + _corpses.size()) * 2)
	# Only agents on screen (plus a frame of margin) animate and draw; the rest just track
	# position, hp and swings so nothing jumps when they come into view.
	var view := _view
	# Bodies first, so the living draw over them.
	var i := 0
	while i < _corpses.size():
		var c := _corpses[i]
		c.t += anim_dt
		c.age += sim_dt
		if c.age > CORPSE_SECS:
			_corpses.remove_at(i)
			continue
		if not view.has_point(c.pos * Cfg.CELL):
			i += 1
			continue
		var col := c.tint
		col.a = clampf((CORPSE_SECS - c.age) / CORPSE_FADE, 0.0, 1.0)
		var death: Dictionary = c.body.torso.death
		count = _put(count, c.pos, c.ang + c.body.angle, death.px, col, Atlas.frame(death, c.t))
		i += 1
	for a in World.agent_list:
		var st: AnimState = _states.get(a.id)
		if st == null:
			st = _new_state(a)
			_states[a.id] = st
		st.stamp = _frame
		if not view.has_point(a.pos * Cfg.CELL):
			if sim_dt > 0.0 and a.pos != st.last_pos:
				st.move_ang = _delta(st.last_pos, a.pos).angle()
			st.last_pos = a.pos
			st.last_cd = a.attack_cd
			st.last_hp = a.hp
			continue
		# Movement.
		if sim_dt > 0.0:
			var d := _delta(st.last_pos, a.pos)
			var v := d.length() / sim_dt
			if v > 30.0:
				v = st.speed # teleport (respawn, scatter): ignore
			st.speed = lerpf(st.speed, v, 1.0 - exp(-12.0 * sim_dt))
			if d.length_squared() > 1e-8:
				st.move_ang = d.angle()
		st.last_pos = a.pos
		var moving := st.speed > IDLE_SPEED
		var hurry := a.job != null and HURRY_JOBS.has(a.job.kind)
		# Swings and hits (attack_cd jumps up when a swing lands, hp drops on a hit).
		if a.attack_cd > st.last_cd + 0.01:
			st.oneshot = "attack"
			st.torso_t = 0.0
			st.alt = not st.alt
		if a.hp < st.last_hp - 0.001:
			st.flash = FLASH_SECS
			if st.oneshot != "attack" and st.body.torso.has("pain"):
				st.oneshot = "pain"
				st.torso_t = 0.0
		st.last_cd = a.attack_cd
		st.last_hp = a.hp
		st.flash = maxf(st.flash - real_dt, 0.0)
		# Angles.
		var face := facing_of(a, st)
		st.torso_ang = lerp_angle(st.torso_ang, face, turn)
		st.legs_ang = lerp_angle(st.legs_ang, st.move_ang if moving else face, turn)
		# Legs.
		var legs := "idle"
		if moving:
			legs = "run" if hurry or st.speed > RUN_SPEED else "walk"
		if legs != st.legs_anim:
			st.legs_anim = legs
			st.legs_t = 0.0
		var la: Dictionary = st.body.legs[legs]
		st.legs_t += anim_dt * (st.speed / la.stride if la.stride > 0.0 else 1.0)
		# Torso.
		var torso := st.oneshot
		if torso != "" and Atlas.finished(st.body.torso[torso], st.torso_t + anim_dt):
			st.oneshot = ""
			torso = ""
		if torso == "":
			if moving:
				torso = legs
			elif a.job and USE_JOBS.has(a.job.kind):
				torso = "use"
			else:
				torso = "idle"
			if torso != st.torso_anim:
				st.torso_t = 0.0
		st.torso_anim = torso
		st.torso_t += anim_dt
		# Instances: legs, then torso.
		var col := st.tint
		if st.flash > 0.0:
			col = col.lerp(Color(1.0, 0.25, 0.2), st.flash / FLASH_SECS)
		var ta: Dictionary = st.body.torso[torso]
		count = _put(count, a.pos, st.legs_ang + st.body.angle, la.px, col, Atlas.frame(la, st.legs_t))
		count = _put(count, a.pos, st.torso_ang + st.body.angle, ta.px, col,
			Atlas.frame(ta, st.torso_t, torso == "attack" and st.alt))
	# Agents gone since last frame died (or left): leave a body.
	if _states.size() > n:
		for id in _states.keys():
			var st: AnimState = _states[id]
			if st.stamp != _frame:
				_states.erase(id)
				var c := Corpse.new()
				c.body = st.body
				c.tint = st.tint
				c.pos = st.last_pos
				c.ang = st.torso_ang
				_corpses.append(c)
		while _corpses.size() > MAX_CORPSES:
			_corpses.remove_at(0)
	_mm.buffer = _buf
	_mm.visible_instance_count = count


func _new_state(a: Agent) -> AnimState:
	var st := AnimState.new()
	st.body = Atlas.set_for(a.id)
	st.tint = Atlas.tint_for(a.id, st.body)
	st.last_pos = a.pos
	st.last_hp = a.hp
	st.last_cd = a.attack_cd
	st.move_ang = float(a.id % 8) * TAU / 8.0
	st.legs_ang = st.move_ang
	st.torso_ang = st.move_ang
	return st


func _reserve(instances: int) -> void:
	if instances <= _mm.instance_count:
		return
	_mm.instance_count = maxi(instances + 64, _mm.instance_count * 2)
	_buf.resize(_mm.instance_count * FLOATS)
	_buf.fill(0.0)


## Writes one sprite instance at agent position pos (cells) and returns the next index.
func _put(i: int, pos: Vector2, ang: float, px: float, col: Color, uv: Vector4) -> int:
	var o := i * FLOATS
	var c := cos(ang) * px
	var s := sin(ang) * px
	var p := pos * Cfg.CELL
	_buf[o] = c; _buf[o + 1] = -s; _buf[o + 2] = 0.0; _buf[o + 3] = p.x
	_buf[o + 4] = s; _buf[o + 5] = c; _buf[o + 6] = 0.0; _buf[o + 7] = p.y
	_buf[o + 8] = col.r; _buf[o + 9] = col.g; _buf[o + 10] = col.b; _buf[o + 11] = col.a
	_buf[o + 12] = uv.x; _buf[o + 13] = uv.y; _buf[o + 14] = uv.z; _buf[o + 15] = uv.w
	return i + 1


static func _unit_quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- drawing --------------------------------------------------------------------------------

func _faction_fill(a: Agent) -> Color:
	return Color(0.55, 0.55, 0.55) if a.faction.solo else a.faction.color


## Sprite mode, under the sprites: a faction disc with a mood rim at the feet, fight lines.
func _draw_under() -> void:
	var s := float(Cfg.CELL)
	for a in World.agent_list:
		var p := a.pos * s
		if not _view.has_point(p):
			continue
		if a.is_armoured():
			Disc.draw(self, p, s * 0.56, Color(0.62, 0.63, 0.68)) # armoured: grey outer ring (v3)
		Disc.draw(self, p, s * 0.48, MOOD_COLORS[a.mood_label()])
		var fill := _faction_fill(a)
		fill.a = 0.9
		Disc.draw(self, p, s * 0.41, fill)
		if a.job and a.job.kind == Job.Kind.FIGHT:
			var t: Agent = World.agents.get(a.job.target_id)
			if t:
				draw_line(p, t.pos * s, Color(1, 0.1, 0.1, 0.6), 1.0 * Cfg.PX)


## Sprite mode, over the sprites: servant / leader pips, raider pennants, labels, selection.
func _draw_overlay() -> void:
	if _discs:
		return
	var t0 := Time.get_ticks_usec()
	_overlay_body()
	World.prof_add("draw_agents", t0)


func _overlay_body() -> void:
	var ci := _overlay
	var s := float(Cfg.CELL)
	for a in World.agent_list:
		var p := a.pos * s
		if not _view.has_point(p):
			continue
		var pip := p + Vector2(s * 0.36, -s * 0.36)
		if a.is_servant():
			Disc.draw(ci, pip, s * 0.15, Color(0.95, 0.95, 0.95))
			Disc.draw(ci, pip, s * 0.11, Color(0.05, 0.05, 0.05))
		elif not a.faction.solo and a.faction.leader_id == a.id:
			Disc.draw(ci, pip, s * 0.15, Color(0.1, 0.07, 0.0))
			Disc.draw(ci, pip, s * 0.11, Color(1.0, 0.85, 0.2))
		if a.raid_id != -1:
			_pennant(ci, p, s)
		if show_labels:
			ci.draw_string(_font, p + Vector2(-s, -s * 0.6), a.short(), HORIZONTAL_ALIGNMENT_CENTER, s * 2, int(8 * Cfg.PX))
	_draw_selection(ci)


## Disc mode (far zoom or the K toggle): the pre-sprite look.
func _draw_discs() -> void:
	var s := float(Cfg.CELL)
	for a in World.agent_list:
		var p := a.pos * s
		if a.is_armoured():
			Disc.draw(self, p, s * 0.54, Color(0.62, 0.63, 0.68)) # armoured: grey outer ring (v3)
		Disc.draw(self, p, s * 0.42, MOOD_COLORS[a.mood_label()])
		Disc.draw(self, p, s * 0.30, _faction_fill(a))
		if a.is_servant():
			Disc.draw(self, p, s * 0.12, Color(0.05, 0.05, 0.05))
		elif not a.faction.solo and a.faction.leader_id == a.id:
			Disc.draw(self, p, s * 0.12, Color(1.0, 0.85, 0.2))
		if a.raid_id != -1:
			_pennant(self, p, s)
		if a.job and a.job.kind == Job.Kind.FIGHT:
			var t: Agent = World.agents.get(a.job.target_id)
			if t:
				draw_line(p, t.pos * s, Color(1, 0.1, 0.1, 0.6), 1.0 * Cfg.PX)
		if show_labels:
			draw_string(_font, p + Vector2(-s, -s * 0.6), a.short(), HORIZONTAL_ALIGNMENT_CENTER, s * 2, int(8 * Cfg.PX))
	_draw_selection(self)


## Raiders carry a small red pennant.
func _pennant(ci: CanvasItem, p: Vector2, s: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.9), p + Vector2(s * 0.45, -s * 0.75), p + Vector2(0, -s * 0.6)]), Color(1, 0.15, 0.1))
	ci.draw_line(p + Vector2(0, -s * 0.9), p + Vector2(0, -s * 0.4), Color(0.1, 0.1, 0.1), 1.0 * Cfg.PX)


func _draw_selection(ci: CanvasItem) -> void:
	var sel: Agent = World.agents.get(selected_id)
	if sel == null:
		return
	var s := float(Cfg.CELL)
	var p := sel.pos * s
	ci.draw_arc(p, s * 0.7, 0, TAU, 24, Color(1, 1, 0), 2.0 * Cfg.PX)
	if sel.path.size() > 1:
		var pts := PackedVector2Array([p])
		for i in range(sel.path_i, sel.path.size()):
			pts.append(World.center(sel.path[i]) * s)
		if pts.size() > 1:
			ci.draw_polyline(pts, Color(1, 1, 0, 0.5), 1.0 * Cfg.PX)
