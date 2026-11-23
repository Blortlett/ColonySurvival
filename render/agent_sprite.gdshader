shader_type canvas_item;
// Agent sprites (AgentLayer): one unit quad per layer, INSTANCE_CUSTOM = atlas UV rect
// (u, v, w, h) of the current frame. The instance colour (tint, flash, fade) is applied by
// the default fragment.

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
