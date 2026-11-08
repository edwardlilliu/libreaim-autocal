class_name SensitivityBenchmark
extends RefCounted
## Small, transparent candidate search; thresholds are prototype defaults.
## A completed equal-target block is faster only if accuracy is maintained.

const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 720.0
## Independent controller default: a half turn in one second at full stick.
const DEFAULT_SPEED: float = 180.0
## Keep sensitivity trials readable without changing the original precision test.
const TARGET_RADIUS_RATIO: float = 0.035
const MIN_IMPROVEMENT: float = 0.05
const ACCURACY_TOLERANCE: float = 0.02
const HITS_PER_STAGE: int = 3
const TARGET_COUNT: int = HITS_PER_STAGE * 3
const ROUND_TIMEOUT: float = 75.0
const VERSION: int = 2

static func resolve_speed(value: Variant) -> float:
	if not (value is float or value is int) or not is_finite(float(value)) or float(value) <= 0.0:
		return DEFAULT_SPEED
	return clampf(float(value), MIN_SPEED, MAX_SPEED)

static func candidates(baseline: float) -> Array[float]:
	var values: Array[float] = []
	baseline = resolve_speed(baseline)
	# A legacy mouse-derived speed can be only 22 degrees/second. A narrow
	# search around that value never reaches usable controller speeds.
	var search_center := DEFAULT_SPEED if baseline < DEFAULT_SPEED * 0.5 else baseline
	for candidate in [baseline, search_center * 0.8, search_center * 1.2]:
		var speed := clampf(candidate, MIN_SPEED, MAX_SPEED)
		if not values.has(speed):
			values.append(speed)
	return values

static func result(speed: float, elapsed: float, shots: int, hits: int, times: Array[float]) -> Dictionary:
	return {
		"speed": speed, "seconds": elapsed, "shots": shots, "hits": hits,
		"accuracy": float(hits) / shots if shots > 0 else 0.0,
		"target_seconds": times.duplicate(),
		"valid": hits == TARGET_COUNT and shots >= hits and elapsed > 0.0 and elapsed <= ROUND_TIMEOUT,
	}

static func improves(candidate: Dictionary, baseline: Dictionary) -> bool:
	if not candidate.get("valid", false) or not baseline.get("valid", false):
		return false
	return float(candidate.accuracy) + ACCURACY_TOLERANCE >= float(baseline.accuracy) \
		and float(candidate.seconds) <= float(baseline.seconds) * (1.0 - MIN_IMPROVEMENT)

static func choose(results: Array[Dictionary], baseline_speed: float) -> Dictionary:
	var baseline: Dictionary = {}
	for entry in results:
		if is_equal_approx(float(entry.speed), baseline_speed):
			baseline = entry
	if not baseline.get("valid", false):
		return {}
	var best := baseline
	for entry in results:
		if improves(entry, baseline) and float(entry.seconds) < float(best.seconds):
			best = entry
	return best
