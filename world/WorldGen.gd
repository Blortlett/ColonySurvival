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
			if roll < p_tree:
				World.add_node(ResourceNode.Type.TREE, c)
			elif roll < p_tree + p_rock:
				World.add_node(ResourceNode.Type.ROCK, c)
			elif roll < p_tree + p_rock + Cfg.DENSITY_HEMP:
				World.add_node(ResourceNode.Type.HEMP, c)
			elif roll < p_tree + p_rock + Cfg.DENSITY_HEMP + Cfg.DENSITY_BUSH:
				World.add_node(ResourceNode.Type.BUSH, c)
