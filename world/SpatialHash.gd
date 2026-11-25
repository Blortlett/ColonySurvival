class_name SpatialHash
extends RefCounted
## Bucket grid for fast "agents near X" queries. Rebuilt every sim step.
## Wrap-aware: a query near the seam also reads the buckets on the far side.

const BUCKET := 8 # divides MAP_W and MAP_H

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
	var lo := Vector2i(floori((p.x - radius) / BUCKET), floori((p.y - radius) / BUCKET))
	var hi := Vector2i(floori((p.x + radius) / BUCKET), floori((p.y + radius) / BUCKET))
	if Cfg.WRAP:
		var nx := Cfg.MAP_W / BUCKET
		var ny := Cfg.MAP_H / BUCKET
		# A radius as wide as the map would visit a bucket twice: clamp the span to one lap.
		hi.x = mini(hi.x, lo.x + nx - 1)
		hi.y = mini(hi.y, lo.y + ny - 1)
		for bx in range(lo.x, hi.x + 1):
			for by in range(lo.y, hi.y + 1):
				var b = buckets.get(Vector2i(posmod(bx, nx), posmod(by, ny)))
				if b == null:
					continue
				for a in b:
					if a.alive and World.dist_sq(a.pos, p) <= r2:
						out.append(a)
		return out
	for bx in range(lo.x, hi.x + 1):
		for by in range(lo.y, hi.y + 1):
			var b = buckets.get(Vector2i(bx, by))
			if b == null:
				continue
			for a in b:
				if a.alive and a.pos.distance_squared_to(p) <= r2:
					out.append(a)
	return out
