shader_type canvas_item;

// Speed of the shimmer (in UV units per second)
uniform float speed : hint_range(0.0, 2.0) = 0.25;

// Width of the shimmer band (0–0.2 UV space)
uniform float width : hint_range(0.0, 0.2) = 0.5;

// Brightness of the shimmer (0 = invisible, 1 = full white)
uniform float intensity : hint_range(0.0, 1.0) = 0.7;

// Color of the shimmer line (alpha is ignored)
uniform vec4 line_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Get UV coords
    vec2 uv = UV;

    // Compute a looping position [0..1)
    float pos = fract(TIME * speed);

    // Project UV onto the 45° diagonal and remap [0,2]→[0,1]
    float proj = (uv.x + uv.y) * 0.5;

    // Distance from the moving diagonal line
    float d = abs(proj - pos);

    // Soft‑edge band: 1 at center, 0 at 'width'
    float band = smoothstep(width, 0.0, d);

    // Apply overall intensity
    float a = band * intensity;

    // Mix black background with the shimmer
    vec3 color = mix(vec3(0.0), line_color.rgb, a);

    COLOR = vec4(color, 1.0);
}
