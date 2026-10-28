class_name SensitivityBenchmark
extends RefCounted
## Small, transparent candidate search; thresholds are prototype defaults.
## A completed equal-target block is faster only if accuracy is maintained.

const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 720.0
const MIN_IMPROVEMENT: float = 0.05
const ACCURACY_TOLERANCE: float = 0.02
const HITS_PER_STAGE: int = 3
const TARGET_COUNT: int = HITS_PER_STAGE * 3
const ROUND_TIMEOUT: float = 75.0
const VERSION: int = 1

static func candidates(baseline: float) -> Array[float]:
	var values: Array[float] = []
	for factor in [1.0, 0.8, 1.2]:
		var speed := clampf(baseline * factor, MIN_SPEED, MAX_SPEED)
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
