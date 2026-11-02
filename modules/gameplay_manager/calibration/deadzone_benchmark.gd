extends RefCounted
## deadzone calibration: sampling analysis, profile building, and the response curve the player uses

const VERSION := 1
const AXIS_X := JOY_AXIS_RIGHT_X
const AXIS_Y := JOY_AXIS_RIGHT_Y

const SETTLE_SECONDS := 1.0
const REST_SECONDS := 3.0
const RANGE_SECONDS := 6.0

const SECTORS := 16
const MIN_SECTORS_COVERED := 13
const MIN_SAMPLES_PER_SECTOR := 3
const RIM_THRESHOLD := 0.6    
const REST_MAX_OFFSET := 0.4  
const MIN_REST_SAMPLES := 60

const MIN_INNER := 0.05
const MAX_INNER := 0.35
const MIN_OUTER := 0.70
const MAX_OUTER := 1.0
const MIN_GAP := 0.25  

const DEFAULT_PROFILE := {"inner": 0.2, "outer": 1.0, "offset": Vector2.ZERO}

static func read_stick(device: int) -> Vector2:
	return Vector2(Input.get_joy_axis(device, AXIS_X), Input.get_joy_axis(device, AXIS_Y))

static func _percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(floor((sorted.size() - 1) * p)), 0, sorted.size() - 1)])

static func analyze_rest(samples: Array[Vector2]) -> Dictionary:
	if samples.size() < MIN_REST_SAMPLES:
		return {"valid": false, "reason": "Not enough samples were collected. Try again."}
	var mean := Vector2.ZERO
	for s in samples:
		mean += s
	mean /= samples.size()
	if mean.length() > REST_MAX_OFFSET:
		return {"valid": false, "reason": "The stick did not look released. Let go completely and try again."}
	var mags: Array = []
	for s in samples:
		mags.append((s - mean).length())
	mags.sort()
	var noise := _percentile(mags, 0.99)
	if noise > 0.3:
		return {"valid": false, "reason": "The stick moved too much during rest. Set the controller down and try again."}
	return {"valid": true, "offset": mean, "noise_radius": noise, "samples": samples.size()}

static func _sector_of(v: Vector2) -> int:
	var a := fposmod(v.angle(), TAU)
	return clampi(int(a / TAU * SECTORS), 0, SECTORS - 1)

static func analyze_range(samples: Array[Vector2]) -> Dictionary:
	var buckets: Array = []
	for i in SECTORS:
		buckets.append([])
	for s in samples:
		var m := s.length()
		if m >= RIM_THRESHOLD:
			buckets[_sector_of(s)].append(m)
	var reaches: Array = []
	for b in buckets:
		if b.size() >= MIN_SAMPLES_PER_SECTOR:
			b.sort()
			reaches.append(_percentile(b, 0.9))
	if reaches.size() < MIN_SECTORS_COVERED:
		return {"valid": false, "covered": reaches.size(),
			"reason": "Roll the stick around the full rim. Only %d of %d directions were covered." % [reaches.size(), SECTORS]}
	reaches.sort()
	return {"valid": true, "covered": reaches.size(), "reach": _percentile(reaches, 0.2), "weakest": float(reaches[0])}

static func build_profile(rest: Dictionary, rng: Dictionary, device_name: String, device_guid: String) -> Dictionary:
	if not rest.get("valid", false) or not rng.get("valid", false):
		return {}
	var inner := clampf(float(rest.noise_radius) * 1.3 + 0.02, MIN_INNER, MAX_INNER)
	var outer := clampf(float(rng.reach) * 0.97, MIN_OUTER, MAX_OUTER)
	outer = maxf(outer, inner + MIN_GAP)
	return {
		"version": VERSION,
		"created_at": Time.get_datetime_string_from_system(true),
		"controller_name": device_name,
		"controller_guid": device_guid,
		"inner": inner,
		"outer": outer,
		"offset": rest.offset,
		"rest": {"noise_radius": rest.noise_radius, "samples": rest.samples},
		"range": {"reach": rng.reach, "weakest": rng.weakest, "covered": rng.covered},
	}

## Response curve used by the player. 
static func apply(raw: Vector2, profile: Dictionary) -> Vector2:
	var p := profile if not profile.is_empty() else DEFAULT_PROFILE
	var v := raw - Vector2(p.get("offset", Vector2.ZERO))
	var inner := float(p.inner)
	var outer := float(p.outer)
	var m := v.length()
	if m <= inner:
		return Vector2.ZERO
	return v.normalized() * clampf((m - inner) / maxf(outer - inner, 0.001), 0.0, 1.0)

static func is_compatible(profile: Dictionary, device_guid: String) -> bool:
	return not profile.is_empty() and int(profile.get("version", 0)) == VERSION \
		and str(profile.get("controller_guid", "")) == device_guid

## Verification is "no worse than default".
static func verified(with_profile: Dictionary, with_default: Dictionary) -> bool:
	if not with_profile.get("valid", false) or not with_default.get("valid", false):
		return false
	return float(with_profile.accuracy) >= float(with_default.accuracy) - 0.02 \
		and float(with_profile.seconds) <= float(with_default.seconds) * 1.05
