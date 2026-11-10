extends RefCounted
## A worn controller for tests. Each stick rests off center, and every time it
## is let go it settles a little further toward the direction it was pushed
## (hysteresis), plus a little jitter: the kind of drift that makes aim creep.
## Triggers rest slightly pressed and stop short of full.

## Where each stick rests on average, and how far a release can leave it from there
var sticks := {
	"left": {"offset": Vector2(0.02, -0.01), "hysteresis": 0.02, "reach": 0.98},
	"right": {"offset": Vector2(0.07, 0.06), "hysteresis": 0.07, "reach": 0.97},
}
var triggers := {
	"lt": {"rest": 0.01, "max": 0.96, "digital": false},
	"rt": {"rest": 0.0, "max": 0.99, "digital": false},
}
var noise := 0.004
var rng := RandomNumberGenerator.new()

var _thumb := {"left": null, "right": null} ## Where a thumb holds each stick
var _last_push := {"left": Vector2.ZERO, "right": Vector2.ZERO}
var _position := {"left": Vector2.ZERO, "right": Vector2.ZERO}
var _rest := {"left": Vector2.ZERO, "right": Vector2.ZERO}
var _pull := {"lt": 0.0, "rt": 0.0}

func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value
	for stick: String in ["left", "right"]:
		_rest[stick] = sticks[stick].offset
		_position[stick] = _rest[stick]

## Holds a stick at [param direction] (length 1 is the rim)
func hold(stick: String, direction: Vector2) -> void:
	var limited := direction.limit_length(1.0) * float(sticks[stick].reach)
	_thumb[stick] = limited
	if limited.length() > 0.3:
		_last_push[stick] = limited

## Lets go: the stick springs back and settles near its offset, displaced
## toward where it was last pushed
func release(stick: String) -> void:
	_thumb[stick] = null
	var push: Vector2 = _last_push[stick]
	var shift := push.normalized() * float(sticks[stick].hysteresis) * rng.randf_range(0.5, 1.0) if push != Vector2.ZERO else Vector2.ZERO
	_rest[stick] = Vector2(sticks[stick].offset) + shift

## Where the stick will settle after the last release
func resting_position(stick: String) -> Vector2:
	return _rest[stick]

func squeeze(trigger: String, amount: float) -> void:
	_pull[trigger] = clampf(amount, 0.0, 1.0)

## Advances the springs by one frame
func step(delta: float) -> void:
	for stick: String in ["left", "right"]:
		var target: Vector2 = _thumb[stick] if _thumb[stick] != null else _rest[stick]
		_position[stick] = Vector2(_position[stick]).lerp(target, minf(1.0, delta * 30.0))

## What the controller reports right now
func read() -> Dictionary:
	var state := {}
	for stick: String in ["left", "right"]:
		var p: Vector2 = _position[stick] + Vector2(rng.randfn(0, noise), rng.randfn(0, noise))
		state[stick] = Vector2(clampf(p.x, -1, 1), clampf(p.y, -1, 1))
	for trigger: String in ["lt", "rt"]:
		var t: Dictionary = triggers[trigger]
		var pull: float = _pull[trigger]
		if t.digital:
			pull = 1.0 if pull > 0.5 else 0.0
		state[trigger] = clampf(lerpf(t.rest, t.max, pull) + rng.randfn(0, noise * 0.5), 0.0, 1.0)
	return state
