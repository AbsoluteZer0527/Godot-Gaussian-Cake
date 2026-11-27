@tool
extends RefCounted
## Shared JSON graph. Endpoints remain in the existing form library.

static func validate(graph: Variant, names: PackedStringArray) -> String:
	if not graph is Dictionary: return "Invalid form state machine."
	if graph.is_empty(): return ""
	if graph.get("version") != 1: return "Unsupported form state machine version."
	if not graph.get("initial") is String or not names.has(graph.initial): return "Unknown initial form."
	if not graph.get("allow_any", false) is bool: return "Invalid state transition policy."
	var positions: Variant = graph.get("positions")
	if not positions is Array or (not positions.is_empty() and positions.size() != names.size()):
		return "State layout must contain every form."
	for point in positions:
		if not point is Array or point.size() != 2: return "Invalid state position."
		for coordinate in point:
			if not (coordinate is float or coordinate is int) or not is_finite(coordinate) or absf(coordinate) > 100000:
				return "Invalid state position."
	var edges: Variant = graph.get("transitions")
	if not edges is Array or edges.size() > names.size() * (names.size() - 1): return "Invalid transition list."
	var pairs := {}
	for edge in edges:
		if not edge is Dictionary: return "Invalid transition."
		if not edge.get("from") is String or not edge.get("to") is String: return "Invalid transition endpoints."
		var source: int = names.find(edge.from)
		var target: int = names.find(edge.to)
		var key := "%d:%d" % [source, target]
		if source < 0 or target < 0 or source == target or pairs.has(key): return "Unknown, repeated or identical transition endpoints."
		pairs[key] = true
		var seconds: Variant = edge.get("duration")
		if not (seconds is float or seconds is int) or not is_finite(seconds) or seconds < 0.01 or seconds > 3600:
			return "Transition duration must be between 0.01 and 3600 seconds."
	return ""

static func transition_duration(graph: Dictionary, source: String, target: String, fallback: float) -> float:
	if graph.is_empty(): return fallback
	for edge in graph.transitions:
		if edge.from == source and edge.to == target: return float(edge.duration)
	return fallback if graph.get("allow_any", false) or source == target else -1.0

static func default_graph(names: PackedStringArray) -> Dictionary:
	var positions: Array = []
	for i in range(names.size()): positions.append([20 + (i % 3) * 220, 20 + (i / 3) * 140])
	return {"version": 1, "initial": names[0], "allow_any": true, "positions": positions, "transitions": []}
