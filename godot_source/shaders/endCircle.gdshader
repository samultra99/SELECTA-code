shader_type canvas_item;

uniform float time; // Time uniform for animation
uniform vec2 circle_center = vec2(0.5, 0.5); // Center of the circle in UV space
uniform float radius : hint_range(0.0, 1.0) = 0.3; // Circle radius
uniform float edge_smooth : hint_range(0.01, 0.1) = 0.05; // Soft edge for the circle
uniform float opacity : hint_range(0.0, 1.0) = 1.0; // New uniform to control overall opacity

void fragment() {
	vec2 uv = UV;

	// Animate circle movement with sine waves
	vec2 moving_center = circle_center + vec2(sin(time) * 0.05, cos(time * 1.0) * 0.0);

	// Distance from the moving center
	float dist = length(uv - moving_center);

	// Circle mask with soft edge
	float circle_mask = smoothstep(radius + edge_smooth, radius - edge_smooth, dist);

	// Animate red-black gradient
	float gradient = 0.5 + 0.5 * sin(uv.y * 10.0 + time * 2.0);

	// Final color with reduced opacity
	vec4 color = vec4(gradient, 0.0, 0.0, circle_mask * gradient * opacity);

	COLOR = color;
}