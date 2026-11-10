extends RefCounted
## Controller calibration math: how both sticks and both triggers are
## measured, the saved profile format, and the response curves the player uses.
##
## Drift is measured two ways. A hands-off sample gives each stick's resting
## position and jitter. Then the player flicks each stick in eight directions
## and lets it snap back: a worn stick comes to rest in a slightly different
## spot every time, usually displaced toward the direction it came from. The
## deadzone is the smallest circle that holds every one of those resting
## spots, so wherever the stick settles, it reads as centered.

const VERSION := 2

const STICKS: Array[String] = ["left", "right"]
const TRIGGERS: Array[String] = ["lt", "rt"]

# Hands-off sample
const SETTLE_SECONDS := 1.0
const REST_SECONDS := 3.0
const MIN_REST_SAMPLES := 60
const REST_MAX_OFFSET := 0.4 ## A stick resting farther out than this is being touched
const REST_MAX_NOISE := 0.3
const TRIGGER_REST_MAX := 0.5

# Stick range: roll around the rim
const SECTORS := 16
const MIN_SECTORS_COVERED := 13
const MIN_SAMPLES_PER_SECTOR := 3
const RIM_THRESHOLD := 0.6
const RANGE_GRACE_SECONDS := 12.0 ## After this, MIN_SECTORS_COVERED is enough

# Stick return-to-center: flick and let go
const RELEASE_DIRECTIONS := 8
const RELEASE_PUSH := 0.7 ## Distance from rest that counts as a flick
const RELEASE_RETURN := 0.45 ## Back inside this, the stick is on its way home
const RELEASE_SETTLE_SECONDS := 0.3 ## Must hold still this long to count as settled
const RELEASE_MIN_TOLERANCE := 0.015
const RELEASE_GRACE_SECONDS := 25.0 ## After this, MIN_RELEASES is enough
const MIN_RELEASES := 5
## A release that stops much farther out than the others (more than
## OUTLIER_FACTOR times the typical distance and OUTLIER_MARGIN beyond it)
## probably had a thumb still on the stick, so that direction is asked again
const OUTLIER_FACTOR := 3.0
const OUTLIER_MARGIN := 0.1

# Stick curve
const MIN_INNER := 0.05
const MAX_INNER := 0.40
const DRIFT_MARGIN := 1.15 ## Multiplies the measured drift zone
const DRIFT_PAD := 0.015 ## Added on top, for resting spots not seen during the test
const HEAVY_DRIFT := 0.2 ## Deadzones above this get a warning
const MIN_OUTER := 0.70
const MAX_OUTER := 1.0
const MIN_GAP := 0.25

# Triggers
const TRIGGER_PULLS := 3
const TRIGGER_PULL_HIGH := 0.5 ## A pull counts once the trigger passes this...
const TRIGGER_PULL_LOW := 0.1 ## ...and then returns within this of its rest value
const TRIGGER_MIN_GAP := 0.2
const DIGITAL_BINS := 10 ## A pull that skips the middle of its range is on/off only
const DIGITAL_MAX_MIDDLE_BINS := 1

const DEFAULT_STICK := {"inner": 0.2, "outer": 1.0, "offset": Vector2.ZERO}
const DEFAULT_TRIGGER := {"inner": 0.05, "outer": 1.0}

## Current state of every input calibrated here
static func read_inputs(device: int) -> Dictionary:
	return {
		"left": Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)),
		"right": Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)),
		"lt": Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT),
		"rt": Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT),
	}

## Right stick, which aims
static func read_stick(device: int) -> Vector2:
	return Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))

## Left stick, which moves
static func read_left_stick(device: int) -> Vector2:
	return Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))

static func _percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(floor((sorted.size() - 1) * p)), 0, sorted.size() - 1)])

#region Hands-off sample

## Resting position and jitter of every input, from samples taken while
## nothing is touched. Each sample is a read_inputs() Dictionary.
static func analyze_rest(samples: Array[Dictionary]) -> Dictionary:
	if samples.size() < MIN_REST_SAMPLES:
		return {"valid": false, "reason": "Not enough samples were collected. Try again."}
	var result := {"valid": true, "samples": samples.size()}
	for stick: String in STICKS:
		var mean := Vector2.ZERO
		for s: Dictionary in samples:
			mean += s[stick]
		mean /= samples.size()
		if not mean.is_finite() or mean.length() > REST_MAX_OFFSET:
			return {"valid": false, "reason": "The %s stick did not look released. Let go of both sticks completely and try again." % stick}
		var distances: Array = []
		for s: Dictionary in samples:
			distances.append((s[stick] - mean).length())
		distances.sort()
		var noise := _percentile(distances, 0.99)
		if noise > REST_MAX_NOISE:
			return {"valid": false, "reason": "The %s stick moved during the measurement. Set the controller down and try again." % stick}
		result[stick] = {"center": mean, "noise": noise}
	for trigger: String in TRIGGERS:
		var mean := 0.0
		for s: Dictionary in samples:
			mean += float(s[trigger])
		mean /= samples.size()
		if not is_finite(mean) or mean > TRIGGER_REST_MAX:
			return {"valid": false, "reason": "The %s trigger looked pressed. Let go of both triggers and try again." % ("left" if trigger == "lt" else "right")}
		var distances: Array = []
		for s: Dictionary in samples:
			distances.append(absf(float(s[trigger]) - mean))
		distances.sort()
		result[trigger] = {"rest": mean, "noise": _percentile(distances, 0.99)}
	return result

#endregion

#region Sticks

## Which of the SECTORS slices of the rim a stick position points in
static func sector_of(v: Vector2) -> int:
	return RangeTracker.sector(v)

## Which of the eight flick directions a stick position points in.
## 0 is right, 2 is down, 4 is left, 6 is up (screen coordinates).
static func direction_of(v: Vector2) -> int:
	return ReleaseTracker.direction(v)

## How far the stick reaches, measured from its drift center so the full
## output is reachable in every direction once the offset is removed
static func analyze_range(samples: Array[Vector2], center := Vector2.ZERO) -> Dictionary:
	var buckets: Array = []
	for i in SECTORS:
		buckets.append([])
	for s: Vector2 in samples:
		var v := s - center
		var m := v.length()
		if m >= RIM_THRESHOLD:
			buckets[sector_of(v)].append(m)
	var reaches: Array = []
	for b: Array in buckets:
		if b.size() >= MIN_SAMPLES_PER_SECTOR:
			b.sort()
			reaches.append(_percentile(b, 0.9))
	if reaches.size() < MIN_SECTORS_COVERED:
		return {"valid": false, "covered": reaches.size(),
			"reason": "Roll the stick around the full rim. Only %d of %d directions were covered." % [reaches.size(), SECTORS]}
	reaches.sort()
	return {"valid": true, "covered": reaches.size(), "reach": _percentile(reaches, 0.2), "weakest": float(reaches[0])}

## Smallest circle holding every point (Welzl's algorithm, iterative form)
static func enclosing_circle(points: Array[Vector2]) -> Dictionary:
	const EPSILON := 1e-6
	var center := Vector2.ZERO
	var radius := -1.0
	for i in points.size():
		var p := points[i]
		if radius >= 0.0 and center.distance_to(p) <= radius + EPSILON:
			continue
		center = p
		radius = 0.0
		for j in i:
			var q := points[j]
			if center.distance_to(q) <= radius + EPSILON:
				continue
			center = (p + q) / 2.0
			radius = p.distance_to(q) / 2.0
			for k in j:
				var r := points[k]
				if center.distance_to(r) <= radius + EPSILON:
					continue
				var circle := _circle_through(p, q, r)
				center = circle.center
				radius = circle.radius
	return {"center": center, "radius": maxf(radius, 0.0)}

static func _circle_through(a: Vector2, b: Vector2, c: Vector2) -> Dictionary:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-9:
		# In a line: the two farthest points span the circle
		var pairs := [[a, b], [a, c], [b, c]]
		var best: Array = pairs[0]
		for pair: Array in pairs:
			if pair[0].distance_to(pair[1]) > best[0].distance_to(best[1]):
				best = pair
		return {"center": (best[0] + best[1]) / 2.0, "radius": best[0].distance_to(best[1]) / 2.0}
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	var center := Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
	return {"center": center, "radius": center.distance_to(a)}

## Curve for one stick. [param rest_points] are every resting position seen
## (the hands-off one plus each settled release), [param noise] the jitter
## from the hands-off sample, [param range_samples] the rim roll.
static func build_stick(rest_points: Array[Vector2], noise: float, range_samples: Array[Vector2]) -> Dictionary:
	if rest_points.is_empty():
		return {"valid": false, "reason": "No resting positions were measured."}
	var circle := enclosing_circle(rest_points)
	var center: Vector2 = circle.center
	if center.length() > REST_MAX_OFFSET:
		return {"valid": false, "reason": "The stick rests too far from the middle to calibrate."}
	var needed := (float(circle.radius) + noise) * DRIFT_MARGIN + DRIFT_PAD
	var inner := clampf(needed, MIN_INNER, MAX_INNER)
	var rng := analyze_range(range_samples, center)
	if not rng.valid:
		return {"valid": false, "reason": rng.reason}
	var outer := clampf(float(rng.reach) * 0.97, MIN_OUTER, MAX_OUTER)
	outer = minf(maxf(outer, inner + MIN_GAP), MAX_OUTER)
	return {
		"valid": true,
		"offset": center,
		"inner": inner,
		"outer": outer,
		"spread": circle.radius, ## How far apart the resting spots were
		"noise": noise,
		"rest_points": rest_points.size(),
		"drift_exceeds_limit": needed > MAX_INNER,
		"reach": rng.reach,
		"covered": rng.covered,
	}

## Watches one stick while the player rolls it around the rim
class RangeTracker:
	var center := Vector2.ZERO
	var samples: Array[Vector2] = []
	var _counts: Array[int] = []

	func _init(drift_center: Vector2) -> void:
		center = drift_center
		_counts.resize(SECTORS)
		_counts.fill(0)

	static func sector(v: Vector2) -> int:
		return clampi(int(fposmod(v.angle(), TAU) / TAU * SECTORS), 0, SECTORS - 1)

	func add(raw: Vector2) -> void:
		if not raw.is_finite():
			return
		samples.append(raw)
		var v := raw - center
		if v.length() >= RIM_THRESHOLD:
			_counts[sector(v)] += 1

	func covered() -> int:
		return covered_mask().count(true)

	func covered_mask() -> Array[bool]:
		var mask: Array[bool] = []
		for c: int in _counts:
			mask.append(c >= MIN_SAMPLES_PER_SECTOR)
		return mask

## Watches one stick while the player flicks it and lets it snap back, and
## records where it comes to rest each time
class ReleaseTracker:
	var rest_center := Vector2.ZERO
	var tolerance := RELEASE_MIN_TOLERANCE
	var points: Array[Vector2] = [] ## Settled resting positions
	var directions: Array[int] = [] ## Flick direction for each point
	var rejected: int = 0 ## Settled too far out (probably held by a thumb)
	var _done: Array[bool] = []
	var _rechecked: Array[bool] = [] ## Directions already asked again once
	var _suspects := {} ## direction -> resting spot set aside by review()
	var _time := 0.0
	var _pushed := false
	var _push_direction := -1
	var _returned_at := -1.0
	var _window: Array[Array] = []

	func _init(center: Vector2, noise: float) -> void:
		rest_center = center
		tolerance = maxf(RELEASE_MIN_TOLERANCE, noise * 3.0)
		_done.resize(RELEASE_DIRECTIONS)
		_done.fill(false)
		_rechecked.resize(RELEASE_DIRECTIONS)
		_rechecked.fill(false)

	static func direction(v: Vector2) -> int:
		return posmod(roundi(v.angle() / (TAU / RELEASE_DIRECTIONS)), RELEASE_DIRECTIONS)

	## Returns true when a new resting position was recorded
	func add(raw: Vector2, delta: float) -> bool:
		_time += delta
		if not raw.is_finite():
			return false
		var v := raw - rest_center
		var m := v.length()
		if m >= RELEASE_PUSH:
			# The direction it springs back from is where it was let go
			_push_direction = direction(v)
			_pushed = true
			_window.clear()
			return false
		if not _pushed or m > RELEASE_RETURN:
			_window.clear()
			return false
		# On its way home: wait until it stops moving
		if _window.is_empty():
			_returned_at = _time
		_window.append([_time, raw])
		while _window.size() > 1 and _time - float(_window[0][0]) > RELEASE_SETTLE_SECONDS:
			_window.pop_front()
		if _time - _returned_at < RELEASE_SETTLE_SECONDS:
			return false
		var mean := Vector2.ZERO
		for entry: Array in _window:
			mean += entry[1]
		mean /= _window.size()
		for entry: Array in _window:
			if (entry[1] as Vector2).distance_to(mean) > tolerance:
				return false
		_pushed = false
		_window.clear()
		if mean.distance_to(rest_center) > MAX_INNER:
			rejected += 1
			return false
		_record(mean, _push_direction)
		return true

	func _record(point: Vector2, dir: int) -> void:
		points.append(point)
		directions.append(dir)
		_done[dir] = true
		if _suspects.has(dir):
			# Asked again: if it stops far out again, the first one was real
			var suspect: Vector2 = _suspects[dir]
			if point.distance_to(rest_center) >= suspect.distance_to(rest_center) * 0.5:
				points.append(suspect)
				directions.append(dir)
			_suspects.erase(dir)
			_rechecked[dir] = true

	## Sets aside resting spots far beyond the others and un-marks their
	## directions (unless another release covered them), so they get flicked
	## again. Each direction is only asked again once. Returns how many
	## directions need another flick.
	func review() -> int:
		if points.size() < MIN_RELEASES:
			return 0
		var distances: Array = []
		for p: Vector2 in points:
			distances.append(p.distance_to(rest_center))
		distances.sort()
		var typical := float(distances[int(distances.size() / 2.0)])
		var limit := maxf(typical * OUTLIER_FACTOR, typical + OUTLIER_MARGIN)
		var flagged := 0
		for i in range(points.size() - 1, -1, -1):
			var dir := directions[i]
			if _rechecked[dir] or points[i].distance_to(rest_center) <= limit:
				continue
			_suspects[dir] = points[i]
			points.remove_at(i)
			directions.remove_at(i)
			if not directions.has(dir):
				_done[dir] = false
				flagged += 1
			else:
				_suspects.erase(dir)
				_rechecked[dir] = true
		return flagged

	func done_mask() -> Array[bool]:
		return _done.duplicate()

	func done_count() -> int:
		return _done.count(true)

#endregion

#region Triggers

## Watches one trigger while the player squeezes it all the way and lets go
class PullTracker:
	var rest := 0.0
	var peaks: Array[float] = []
	var max_seen := 0.0
	var _moving: Array[float] = [] ## Values seen while the trigger was off rest
	var _pulling := false
	var _peak := 0.0

	func _init(rest_value: float) -> void:
		rest = rest_value
		max_seen = rest_value

	## Returns true when a full pull and release finished
	func add(value: float) -> bool:
		if not is_finite(value):
			return false
		max_seen = maxf(max_seen, value)
		if value > rest + TRIGGER_PULL_LOW * 0.5:
			_moving.append(value)
		if not _pulling:
			if value >= TRIGGER_PULL_HIGH:
				_pulling = true
				_peak = value
			return false
		_peak = maxf(_peak, value)
		if value <= rest + TRIGGER_PULL_LOW:
			_pulling = false
			peaks.append(_peak)
			return true
		return false

	func pulls() -> int:
		return peaks.size()

	## Analog triggers pass through the middle of their range on the way in;
	## on/off triggers jump straight from rest to full
	func is_digital() -> bool:
		if peaks.is_empty():
			return false
		var full := float(peaks.min())
		var span := full - rest
		if span <= 0.0:
			return false
		var middle := {}
		for v: float in _moving:
			var bin := int((v - rest) / span * DIGITAL_BINS)
			if bin > 0 and bin < DIGITAL_BINS - 1:
				middle[bin] = true
		return middle.size() <= DIGITAL_MAX_MIDDLE_BINS

## Curve for one trigger. [param tracker] is null when the player skipped it.
static func build_trigger(rest: float, noise: float, tracker: PullTracker) -> Dictionary:
	if tracker == null or tracker.pulls() == 0:
		return {"valid": true, "detected": false, "rest": rest}
	var peaks := tracker.peaks.duplicate()
	peaks.sort()
	var full := float(peaks[int(peaks.size() / 2.0)]) # median
	var inner := clampf(rest + maxf(noise * 3.0, 0.01) + 0.02, -1.0, 0.5)
	var outer := clampf(full * 0.98, inner + TRIGGER_MIN_GAP, 1.0)
	return {
		"valid": true,
		"detected": true,
		"digital": tracker.is_digital(),
		"rest": rest,
		"noise": noise,
		"inner": inner, ## Output starts above this raw value
		"outer": outer, ## Output is full at this raw value
		"full": full,
		"pulls": peaks.size(),
	}

#endregion

#region Profile

static func build_profile(rest: Dictionary, sticks: Dictionary, triggers: Dictionary, device_name: String, device_guid: String) -> Dictionary:
	if not rest.get("valid", false):
		return {}
	for stick: String in STICKS:
		if not sticks.get(stick, {}).get("valid", false):
			return {}
	var profile := {
		"version": VERSION,
		"created_at": Time.get_datetime_string_from_system(true),
		"controller_name": device_name,
		"controller_guid": device_guid,
		"rest_samples": rest.samples,
	}
	for stick: String in STICKS:
		profile[stick + "_stick"] = _without_valid(sticks[stick])
	profile["left_trigger"] = _without_valid(triggers.get("lt", {"detected": false}))
	profile["right_trigger"] = _without_valid(triggers.get("rt", {"detected": false}))
	return profile

static func _without_valid(data: Dictionary) -> Dictionary:
	var copy := data.duplicate()
	copy.erase("valid")
	return copy

## Stick response curve: removes the drift offset, ignores everything inside
## the inner deadzone and reaches full output at the outer edge.
## [param stick] is a profile's "left_stick" or "right_stick" entry; anything
## invalid falls back to the default curve.
static func apply(raw: Vector2, stick: Variant) -> Vector2:
	if not raw.is_finite():
		return Vector2.ZERO
	var p: Dictionary = stick if has_valid_curve(stick) else DEFAULT_STICK
	var v := raw - Vector2(p.get("offset", Vector2.ZERO))
	var inner := float(p.inner)
	var outer := float(p.outer)
	var m := v.length()
	if m <= inner:
		return Vector2.ZERO
	return v.normalized() * clampf((m - inner) / maxf(outer - inner, 0.001), 0.0, 1.0)

## Trigger response curve: 0 until the inner value, 1 from the outer value
static func apply_trigger(raw: float, trigger: Variant) -> float:
	if not is_finite(raw):
		return 0.0
	var t: Dictionary = trigger if has_valid_trigger(trigger) else DEFAULT_TRIGGER
	var inner := float(t.inner)
	var outer := float(t.outer)
	return clampf((raw - inner) / maxf(outer - inner, 0.001), 0.0, 1.0)

static func has_valid_curve(stick: Variant) -> bool:
	if not stick is Dictionary:
		return false
	var inner: Variant = stick.get("inner")
	var outer: Variant = stick.get("outer")
	var offset: Variant = stick.get("offset")
	if not (inner is float or inner is int) or not (outer is float or outer is int) or not offset is Vector2:
		return false
	return is_finite(inner) and is_finite(outer) and offset.is_finite() \
		and inner >= MIN_INNER and inner <= MAX_INNER \
		and outer >= MIN_OUTER and outer <= MAX_OUTER \
		and outer - inner >= MIN_GAP and offset.length() <= REST_MAX_OFFSET

static func has_valid_trigger(trigger: Variant) -> bool:
	if not trigger is Dictionary or not trigger.get("detected", false):
		return false
	var inner: Variant = trigger.get("inner")
	var outer: Variant = trigger.get("outer")
	if not (inner is float or inner is int) or not (outer is float or outer is int):
		return false
	return is_finite(inner) and is_finite(outer) and inner >= -1.0 and inner <= 0.5 \
		and outer <= 1.0 and outer - inner >= TRIGGER_MIN_GAP

## True if [param profile] is a current profile for the controller with
## [param device_guid]. Profiles from before both sticks were calibrated
## (version 1) don't qualify: their drift measurement was too small.
static func is_compatible(profile: Variant, device_guid: String) -> bool:
	if not profile is Dictionary or device_guid.is_empty():
		return false
	return profile.get("version") is int and profile.version == VERSION \
		and profile.get("controller_guid") is String and profile.controller_guid == device_guid \
		and has_valid_curve(profile.get("left_stick")) and has_valid_curve(profile.get("right_stick"))

#endregion
