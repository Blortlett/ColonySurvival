shader_type canvas_item;
// Grass ground as one quad. Each TILE_PX tile picks a variant from the atlas (weighted)
// and one of 8 rotations/flips from a hash of its tile index, so it needs no stored state
// and stays seamless when the map wraps (Summer Roadmap §4.1). A soft, large-scale
// brightness patch on top hides the tiling.

uniform sampler2D atlas : filter_nearest_mipmap, repeat_disable;
uniform int variants = 5;
uniform float tile_px = 80.0;
// Cumulative variant weights, 0..1 (last must be 1).
uniform float cum[8];
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform float patch_px = 1400.0;
uniform float patch_dark = 0.86;
uniform float patch_light = 1.06;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 t = world / tile_px;
	vec2 cell = floor(t);
	vec2 f = t - cell;
	float h = hash(cell);
	int idx = variants - 1;
	for (int i = 0; i < 8; i++) {
		if (i < variants && h < cum[i]) {
			idx = i;
			break;
		}
	}
	int orient = int(hash(cell + 71.7) * 8.0);
	if ((orient & 1) != 0) f.x = 1.0 - f.x;
	if ((orient & 2) != 0) f.y = 1.0 - f.y;
	if ((orient & 4) != 0) f = f.yx;
	vec2 uv = vec2((float(idx) + f.x) / float(variants), f.y);
	// Gradients from the continuous coordinate, so mip selection doesn't jump at tile edges.
	vec2 g = vec2(1.0 / float(variants), 1.0);
	vec4 col = textureGrad(atlas, uv, dFdx(t) * g, dFdy(t) * g);
	float n = texture(patch_noise, world / patch_px).r;
	col.rgb *= mix(patch_dark, patch_light, smoothstep(0.25, 0.75, n));
	COLOR = col;
}
