class_name SpatialHash
extends RefCounted
## Bucket grid for fast "agents near X" queries. Rebuilt every sim step.

const BUCKET := 8

var buckets := {} # Vector2i -> Array[Agent]


func rebuild(agents: Array) -> void:
	buckets.clear()
	for a in agents:
		var key := Vector2i(int(a.pos.x) / BUCKET, int(a.pos.y) / BUCKET)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(a)


func query(p: Vector2, radius: float) -> Array:
	var out := []
	var r2 := radius * radius
	var lo := Vector2i(int(p.x - radius) / BUCKET, int(p.y - radius) / BUCKET)
	var hi := Vector2i(int(p.x + radius) / BUCKET, int(p.y + radius) / BUCKET)
	for bx in range(lo.x, hi.x + 1):
		for by in range(lo.y, hi.y + 1):
			var b = buckets.get(Vector2i(bx, by))
			if b == null:
				continue
			for a in b:
				if a.alive and a.pos.distance_squared_to(p) <= r2:
					out.append(a)
	return out
