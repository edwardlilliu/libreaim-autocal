extends RefCounted
# export csv cheat sheet for deadzone calibration to type into game controller settings

static func build_csv(profile: Dictionary) -> String:
	var rows: Array[String] = ["input,inner_deadzone_pct,outer_deadzone_pct,offset_x_pct,offset_y_pct,deadzone_if_offset_ignored_pct"]
	for side: String in ["left", "right"]:
		var s: Dictionary = profile[side + "_stick"]
		var off: Vector2 = s.offset
		var inner := float(s.inner)
		rows.append("%s stick,%d,%d,%+d,%+d,%d" % [
			side, ceili(inner * 100.0), roundi(float(s.outer) * 100.0),
			roundi(off.x * 100.0), roundi(off.y * 100.0),
			mini(ceili((off.length() + inner) * 100.0), 100)])
	for side: String in ["left", "right"]:
		var t: Dictionary = profile[side + "_trigger"]
		if t.get("detected", false):
			rows.append("%s trigger,%d,%d,,," % [side, ceili(maxf(float(t.inner), 0.0) * 100.0), roundi(float(t.outer) * 100.0)])
		else:
			rows.append("%s trigger,,,,," % side)
	return "\n".join(rows) + "\n"
