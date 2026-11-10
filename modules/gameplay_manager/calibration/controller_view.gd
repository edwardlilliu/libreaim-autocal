extends Control
## Live drawing of both sticks and both triggers for the controller
## calibration: where each input is right now, what the current step is
## measuring, and the deadzones that came out of it.
##
## The calibration sets [member inputs] every frame and fills in the overlay
## dictionaries as it measures. Stick positions are in raw controller units
## (the well's rim is 1.0), drawn with the middle magnified: distance from the
## center is shown as its square root, so drift of a few hundredths is still
## visible while the rim stays the rim.

const SECTORS := 16
const DIRECTIONS := 8
const TRAIL_LENGTH := 28

const COLOR_WELL := Color(0.066, 0.11, 0.161)
const COLOR_RIM := Color(0.36, 0.46, 0.56)
const COLOR_GRID := Color(1, 1, 1, 0.07)
const COLOR_PENDING := Color(1, 1, 1, 0.13)
const COLOR_DONE := Color(0.659, 0.902, 0.812) ## Same mint as the buttons
const COLOR_DEADZONE := Color(1.0, 0.55, 0.5)
const COLOR_REST := Color(1.0, 0.8, 0.42)
const COLOR_RAW := Color(1, 1, 1)
const COLOR_LABEL := Color(0.72, 0.78, 0.84)
const COLOR_VALUE := Color(0.95, 0.97, 0.99)

## Raw state: {"left": Vector2, "right": Vector2, "lt": float, "rt": float}
var inputs := {"left": Vector2.ZERO, "right": Vector2.ZERO, "lt": 0.0, "rt": 0.0}
## Calibrated output to show next to the raw position (same keys as inputs)
var outputs := {}
## Inputs drawn at full strength; the rest are dimmed. Empty: all of them.
var focus: Array[String] = []
## Per stick, any of: "sectors" (Array[bool], rim coverage), "directions"
## (Array[bool], flicks recorded), "rest_points" (Array[Vector2]), "offset"
## (Vector2, drift center), "inner" and "outer" (float, deadzone radii)
var sticks := {"left": {}, "right": {}}
## Per trigger, any of: "inner", "outer" (float), "peak" (float, deepest pull
## so far), "pulls" and "pulls_needed" (int), "digital" (bool), "skipped" (bool)
var triggers := {"lt": {}, "rt": {}}

var _trails := {"left": [], "right": []}

func _ready() -> void:
	resized.connect(queue_redraw)

func set_inputs(new_inputs: Dictionary) -> void:
	inputs = new_inputs
	for stick: String in ["left", "right"]:
		var trail: Array = _trails[stick]
		trail.append(new_inputs.get(stick, Vector2.ZERO))
		while trail.size() > TRAIL_LENGTH:
			trail.pop_front()
	queue_redraw()

## Clears everything measured, for a new session
func reset() -> void:
	outputs = {}
	focus = []
	sticks = {"left": {}, "right": {}}
	triggers = {"lt": {}, "rt": {}}
	_trails = {"left": [], "right": []}
	queue_redraw()

func _draw() -> void:
	var label_height := 64.0
	var ring_room := 40.0 # coverage ring and flick markers outside the rim
	var radius := minf((size.y - label_height) / 2.0 - ring_room, size.x * 0.13)
	if radius <= 8.0:
		return
	var y := ring_room + radius
	_draw_trigger("lt", Vector2(size.x * 0.06, y), radius, "LT")
	_draw_stick("left", Vector2(size.x * 0.3, y), radius, "LEFT STICK")
	_draw_stick("right", Vector2(size.x * 0.7, y), radius, "RIGHT STICK")
	_draw_trigger("rt", Vector2(size.x * 0.94, y), radius, "RT")

func _is_focused(id: String) -> bool:
	return focus.is_empty() or focus.has(id)

func _draw_stick(id: String, c: Vector2, r: float, title: String) -> void:
	var a := 1.0 if _is_focused(id) else 0.3
	var info: Dictionary = sticks.get(id, {})
	var raw: Vector2 = inputs.get(id, Vector2.ZERO)

	draw_circle(c, r, COLOR_WELL, true, -1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), _fade(COLOR_GRID, a), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), _fade(COLOR_GRID, a), 1.0)
	draw_arc(c, r, 0, TAU, 96, _fade(COLOR_RIM, a), 2.0, true)

	# Rim coverage while rolling the stick
	if info.has("sectors"):
		var mask: Array = info.sectors
		var gap := 0.04
		for i in SECTORS:
			var start := TAU * i / SECTORS + gap
			var end := TAU * (i + 1) / SECTORS - gap
			var color := COLOR_DONE if i < mask.size() and mask[i] else COLOR_PENDING
			draw_arc(c, r + 12.0, start, end, 10, _fade(color, a), 7.0, true)

	# Flick-and-release directions
	if info.has("directions"):
		var done: Array = info.directions
		for i in DIRECTIONS:
			var dir := Vector2.from_angle(TAU * i / DIRECTIONS)
			var tip := c + dir * (r + 34.0)
			var base := c + dir * (r + 20.0)
			var side := dir.orthogonal() * 8.0
			var color := COLOR_DONE if i < done.size() and done[i] else COLOR_PENDING
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), _fade(color, a))

	# Deadzone: everything inside the coral circle reads as centered
	if info.has("inner"):
		var offset := Vector2(info.get("offset", Vector2.ZERO))
		var outline := _circle_points(c, r, offset, float(info.inner), 72)
		draw_colored_polygon(outline, _fade(Color(COLOR_DEADZONE, 0.2), a))
		outline.append(outline[0])
		draw_polyline(outline, _fade(COLOR_DEADZONE, a), 2.0, true)
		if info.has("outer"):
			var ring := _circle_points(c, r, offset, float(info.outer), 80)
			for i in range(0, ring.size(), 2):
				draw_line(ring[i], ring[(i + 1) % ring.size()], _fade(Color(COLOR_DONE, 0.7), a), 2.0, true)
	if info.has("offset"):
		var o: Vector2 = c + _to_well(info.offset) * r
		draw_line(o - Vector2(6, 0), o + Vector2(6, 0), _fade(COLOR_DEADZONE, a), 2.0)
		draw_line(o - Vector2(0, 6), o + Vector2(0, 6), _fade(COLOR_DEADZONE, a), 2.0)

	for p: Vector2 in info.get("rest_points", []):
		draw_circle(c + _to_well(p) * r, 4.0, _fade(COLOR_REST, a), true, -1.0, true)

	# Recent movement, then the stick itself
	var trail: Array = _trails.get(id, [])
	for k in range(1, trail.size()):
		var from: Vector2 = c + _to_well(trail[k - 1]) * r
		var to: Vector2 = c + _to_well(trail[k]) * r
		draw_line(from, to, _fade(Color(COLOR_RAW, 0.5 * k / trail.size()), a), 2.0, true)
	draw_circle(c + _to_well(raw) * r, 8.0, _fade(COLOR_RAW, a), true, -1.0, true)

	# Calibrated output: dead center whenever the stick is at rest
	if outputs.has(id):
		var out: Vector2 = outputs[id]
		draw_arc(c + _to_well(out) * r, 13.0, 0, TAU, 32, _fade(COLOR_DONE, a), 3.0, true)

	var font := get_theme_default_font()
	var text_y := c.y + r + 40.0 + 18.0
	draw_string(font, Vector2(c.x - r * 1.5, text_y), title, HORIZONTAL_ALIGNMENT_CENTER, r * 3.0, 17, _fade(COLOR_LABEL, a))
	var values := "x %+.2f   y %+.2f" % [raw.x, raw.y]
	if outputs.has(id):
		var out: Vector2 = outputs[id]
		values = "raw %+.2f %+.2f   →   %+.2f %+.2f" % [raw.x, raw.y, out.x, out.y]
	draw_string(font, Vector2(c.x - r * 1.5, text_y + 24.0), values, HORIZONTAL_ALIGNMENT_CENTER, r * 3.0, 16, _fade(COLOR_VALUE, a))

func _draw_trigger(id: String, c: Vector2, r: float, title: String) -> void:
	var a := 1.0 if _is_focused(id) else 0.3
	var info: Dictionary = triggers.get(id, {})
	var width := 34.0
	var bar := Rect2(c.x - width / 2.0, c.y - r, width, r * 2.0)
	var value := clampf(float(inputs.get(id, 0.0)), 0.0, 1.0)

	draw_rect(bar, _fade(COLOR_WELL, a))
	var fill_height := bar.size.y * value
	var fill_color := COLOR_RAW
	if outputs.has(id):
		fill_height = bar.size.y * clampf(float(outputs[id]), 0.0, 1.0)
		fill_color = COLOR_DONE
	draw_rect(Rect2(bar.position.x, bar.end.y - fill_height, width, fill_height), _fade(Color(fill_color, 0.85), a))
	draw_rect(bar, _fade(COLOR_RIM, a), false, 2.0)

	# Deepest pull so far, and the calibrated start and end points
	if info.has("peak"):
		var py := bar.end.y - bar.size.y * clampf(float(info.peak), 0.0, 1.0)
		draw_line(Vector2(bar.position.x - 8, py), Vector2(bar.position.x, py), _fade(COLOR_RAW, a), 2.0)
	if info.has("inner"):
		var iy := bar.end.y - bar.size.y * clampf(float(info.inner), 0.0, 1.0)
		draw_line(Vector2(bar.position.x - 6, iy), Vector2(bar.end.x + 6, iy), _fade(COLOR_DEADZONE, a), 2.0)
	if info.has("outer"):
		var oy := bar.end.y - bar.size.y * clampf(float(info.outer), 0.0, 1.0)
		draw_line(Vector2(bar.position.x - 6, oy), Vector2(bar.end.x + 6, oy), _fade(COLOR_DONE, a), 2.0)

	# One pip per required pull
	var needed: int = info.get("pulls_needed", 0)
	for i in needed:
		var pip := Vector2(c.x + (i - (needed - 1) / 2.0) * 16.0, bar.position.y - 18.0)
		if i < int(info.get("pulls", 0)):
			draw_circle(pip, 5.0, _fade(COLOR_DONE, a), true, -1.0, true)
		else:
			draw_arc(pip, 5.0, 0, TAU, 16, _fade(Color(1, 1, 1, 0.4), a), 1.5, true)

	var font := get_theme_default_font()
	var text_y := c.y + r + 40.0 + 18.0
	draw_string(font, Vector2(c.x - 60, text_y), title, HORIZONTAL_ALIGNMENT_CENTER, 120, 17, _fade(COLOR_LABEL, a))
	var shown := "%d%%" % roundi(value * 100.0)
	if info.get("skipped", false):
		shown = "skipped"
	elif info.get("digital", false):
		shown = "on/off"
	elif outputs.has(id):
		shown = "%d%%" % roundi(clampf(float(outputs[id]), 0.0, 1.0) * 100.0)
	draw_string(font, Vector2(c.x - 60, text_y + 24.0), shown, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, _fade(COLOR_VALUE, a))

## Points of a circle given in stick units, mapped into the well
func _circle_points(c: Vector2, r: float, center: Vector2, radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		points.append(c + _to_well(center + Vector2.from_angle(TAU * i / count) * radius) * r)
	return points

## Stick units to well units, magnifying the middle
func _to_well(v: Vector2) -> Vector2:
	if not v.is_finite():
		return Vector2.ZERO
	var m := v.length()
	if m < 0.000001:
		return Vector2.ZERO
	return v / m * sqrt(minf(m, 1.08))

func _fade(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)
