extends CanvasLayer
## Social state over the characters (Player Social Plan §5), drawn in screen space so it
## stays crisp at any zoom:
##   - hover card over the character under the mouse: name and group in their colour, a
##     very slim health bar under the name, then mood, their opinion of you and a tag
##     (your group / kingdom / servant / master, at war)
##   - mood icons over NPCs near the player (happy and angry; neutral shows nothing)
##   - a "!" over the NPC whose prompt is on screen (ui/OfferPrompt.gd)
## Reads sim state only and draws nothing beyond the player's nearby set.

const ICON_R := 5.0 # px
const HEAD := 0.8 # cells above the body centre where icons sit
const HAPPY_COL := Color(0.4, 0.85, 0.4)
const ANGRY_COL := Color(0.92, 0.32, 0.26)
const NEUTRAL_COL := Color(0.72, 0.72, 0.72)
const GOLD := Color(1.0, 0.82, 0.3)
const HP_COL := Color(0.85, 0.2, 0.2)

var player: PlayerController
var prompt: CanvasLayer # ui/OfferPrompt.gd: whose offer is on screen

var _canvas: Control
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)


func _process(_dt: float) -> void:
	_canvas.queue_redraw()


## Mood as a word: Happy / Neutral / Angry.
static func mood_word(a: Agent) -> String:
	return "Happy" if a.is_happy() else ("Angry" if a.is_angry() else "Neutral")


## How this character feels about you, from their opinion of you (start thresholds).
static func opinion_word(v: float) -> String:
	if v <= Cfg.GRUDGE:
		return "Hostile"
	if v < -10.0:
		return "Wary"
	if v >= 30.0:
		return "Friendly"
	return "Indifferent"


static func opinion_color(v: float) -> Color:
	if v <= Cfg.GRUDGE:
		return ANGRY_COL
	if v < -10.0:
		return Color(0.95, 0.6, 0.3)
	if v >= 30.0:
		return HAPPY_COL
	return NEUTRAL_COL


## The relationship tag shown on the hover card ("" if none).
static func tag_of(me: Agent, o: Agent) -> String:
	var tags: Array[String] = []
	if o.master_id == me.id:
		tags.append("your servant")
	elif me.master_id == o.id:
		tags.append("your master")
	elif me.faction and o.faction == me.faction and not me.faction.solo:
		tags.append("your group")
	elif me.faction and me.faction.kingdom and o.faction and o.faction.kingdom == me.faction.kingdom:
		tags.append("your kingdom")
	if me.faction and o.faction and o.faction != me.faction \
			and (KingdomWars.enemies(me, o) or Wars.at_war(me.faction, o.faction)):
		tags.append("at war")
	return ", ".join(tags)


func _screen(world_cells: Vector2) -> Vector2:
	return _canvas.get_viewport().get_canvas_transform() * (world_cells * Cfg.CELL)


func _draw_all() -> void:
	if player == null or not player.alive() or player.watching:
		return
	var me := player.body
	var hov := player.hover_agent()
	var asking := -1
	if prompt:
		var o: Dictionary = prompt.shown()
		if not o.is_empty():
			asking = o.from_id
	for a in World.agents_near(me.pos, Cfg.MOOD_ICON_RANGE):
		if a == me or a == hov or not a.alive or a.id == asking:
			continue
		if a.is_happy() or a.is_angry():
			_mood_icon(_screen(a.pos - Vector2(0, HEAD)), a, ICON_R)
	if asking != -1:
		var npc: Agent = World.agents.get(asking)
		if npc and npc.alive and npc != hov:
			_ask_marker(_screen(npc.pos - Vector2(0, HEAD)))
	if hov:
		_card(me, hov)


## A small face: green smile (happy), red frown (angry), grey flat (neutral).
func _mood_icon(c: Vector2, a: Agent, r: float) -> void:
	var col := HAPPY_COL if a.is_happy() else (ANGRY_COL if a.is_angry() else NEUTRAL_COL)
	_canvas.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.75))
	_canvas.draw_circle(c, r, col)
	var ink := Color(0.08, 0.08, 0.08)
	_canvas.draw_circle(c + Vector2(-r * 0.38, -r * 0.25), r * 0.14, ink)
	_canvas.draw_circle(c + Vector2(r * 0.38, -r * 0.25), r * 0.14, ink)
	if a.is_happy():
		_canvas.draw_arc(c + Vector2(0, r * 0.05), r * 0.5, 0.15 * PI, 0.85 * PI, 8, ink, 1.2)
	elif a.is_angry():
		_canvas.draw_arc(c + Vector2(0, r * 0.75), r * 0.45, 1.2 * PI, 1.8 * PI, 8, ink, 1.2)
	else:
		_canvas.draw_line(c + Vector2(-r * 0.35, r * 0.35), c + Vector2(r * 0.35, r * 0.35), ink, 1.2)


func _ask_marker(c: Vector2) -> void:
	var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 150.0)
	var r := 7.0 * pulse
	_canvas.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.8))
	_canvas.draw_circle(c, r, GOLD)
	_canvas.draw_string(_font, c + Vector2(-2.5, 4.5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.1, 0.08, 0.02))


## The hover card above a character: name (and group), a slim health bar, then mood,
## opinion of you and a tag.
func _card(me: Agent, o: Agent) -> void:
	var head := _screen(o.pos - Vector2(0, HEAD))
	var f := o.faction
	var name := o.short()
	if f and not f.solo:
		name += "  ·  %s" % f.display_name()
		if f.kingdom:
			name += " (%s)" % f.kingdom.name
	var name_col: Color = f.color.lightened(0.35) if f and not f.solo else Color.WHITE
	var op := o.opinion_of(me.id)
	var line2 := "%s  ·  %s" % [mood_word(o), opinion_word(op)]
	var tag := tag_of(me, o)
	if tag != "":
		line2 += "  ·  " + tag
	var fs1 := 13
	var fs2 := 11
	var w1 := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs1).x
	var w2 := _font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + ICON_R * 2.0 + 4.0
	var w := maxf(maxf(w1, w2), 48.0)
	var pad := 5.0
	var h := 15.0 + 3.0 + 2.0 + 3.0 + 13.0
	var box := Rect2(head.x - w * 0.5 - pad, head.y - h - pad * 2.0 - 4.0, w + pad * 2.0, h + pad * 2.0)
	_canvas.draw_rect(box, Color(0.05, 0.05, 0.08, 0.72))
	var x := box.position.x + pad
	var y := box.position.y + pad
	# Name, centred.
	_canvas.draw_string(_font, Vector2(head.x - w1 * 0.5, y + 12.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs1, name_col)
	# The slim health bar right under the name (agreed: very slim).
	var by := y + 15.0 + 3.0
	var bar := Rect2(x, by, w, 2.0)
	_canvas.draw_rect(bar, Color(0.2, 0.2, 0.2, 0.9))
	_canvas.draw_rect(Rect2(bar.position, Vector2(w * clampf(o.hp / Cfg.MAX_HP, 0.0, 1.0), 2.0)), HP_COL)
	# Mood face, then "Mood · Opinion · tag".
	var ly := by + 2.0 + 3.0
	var lx := head.x - w2 * 0.5
	_mood_icon(Vector2(lx + ICON_R, ly + 6.0), o, ICON_R)
	var tx := lx + ICON_R * 2.0 + 4.0
	var mw := mood_word(o) + "  ·  "
	_canvas.draw_string(_font, Vector2(tx, ly + 10.0), mw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.85, 0.85, 0.85))
	tx += _font.get_string_size(mw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var ow := opinion_word(op)
	_canvas.draw_string(_font, Vector2(tx, ly + 10.0), ow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, opinion_color(op))
	if tag != "":
		tx += _font.get_string_size(ow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		_canvas.draw_string(_font, Vector2(tx, ly + 10.0), "  ·  " + tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2,
			ANGRY_COL if "at war" in tag else GOLD)
