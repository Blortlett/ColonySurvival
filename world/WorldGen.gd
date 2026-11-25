class_name WorldGen
## Scatters resource nodes: noise-clustered forests and quarries, uniform hemp and bushes.

static func generate(rng: RandomNumberGenerator) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.03
	var quarry := FastNoiseLite.new()
	quarry.seed = rng.randi()
	quarry.frequency = 0.04

	for x in Cfg.MAP_W:
		for y in Cfg.MAP_H:
			var c := Vector2i(x, y)
			var f := forest.get_noise_2d(x, y) # roughly -1..1
			var q := quarry.get_noise_2d(x, y)
			# Dense inside clusters, sparse outside; averages near the configured density.
			var p_tree: float = Cfg.DENSITY_TREE * (5.0 if f > 0.2 else 0.25)
			var p_rock: float = Cfg.DENSITY_ROCK * (6.0 if q > 0.35 else 0.3)
			var roll := rng.randf()
			# Trees and rocks are 2x2-cell sprites, spaced so they don't overlap; a rejected
			# one leaves the cell empty.
			if roll < p_tree:
				if not World.big_node_too_close(c):
					World.add_node(ResourceNode.Type.TREE, c)
			elif roll < p_tree + p_rock:
				if not World.big_node_too_close(c):
					World.add_node(ResourceNode.Type.ROCK, c)
			elif roll < p_tree + p_rock + Cfg.DENSITY_HEMP:
				World.add_node(ResourceNode.Type.HEMP, c)
			elif roll < p_tree + p_rock + Cfg.DENSITY_HEMP + Cfg.DENSITY_BUSH:
				World.add_node(ResourceNode.Type.BUSH, c)
	_scatter_metal(rng)


## Metal rock (v3, agreed: dispersed and rare): single nodes spread over the map, never in
## clusters, at about 1/6 of the rock density.
static func _scatter_metal(rng: RandomNumberGenerator) -> void:
	var mr := RandomNumberGenerator.new()
	mr.seed = rng.randi()
	var want := int(Cfg.MAP_W * Cfg.MAP_H * Cfg.DENSITY_METAL)
	var placed: Array[Vector2i] = []
	for i in want * 20:
		if placed.size() >= want:
			break
		var c := Vector2i(mr.randi_range(1, Cfg.MAP_W - 2), mr.randi_range(1, Cfg.MAP_H - 2))
		if not World.is_walkable(c) or World.big_node_too_close(c):
			continue
		if placed.any(func(p): return World.cheb(p, c) < Cfg.METAL_MIN_GAP):
			continue
		World.add_node(ResourceNode.Type.METAL, c)
		placed.append(c)
