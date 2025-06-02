shader_type canvas_item;

// Speed of the shimmer (in UV units per second)
uniform float speed : hint_range(0.0, 2.0) = 1.0;
// Width of the shimmer band (0–0.2 UV space)
uniform float width : hint_range(0.0, 0.2) = 0.1;
// Brightness of the shimmer (0 = invisible, 1 = full white)
uniform float intensity : hint_range(0.0, 1.0) = 0.9;
// Base color of the object
uniform vec4 base_color : source_color = vec4(0.7, 0.1, 0.1, 1.0);
// Color of the shimmer line (alpha is ignored)
uniform vec4 line_color : source_color = vec4(1.0, 0.3, 0.3, 1.0);

void fragment() {
    // Get UV coords
    vec2 uv = UV;
    // Compute a looping position [0..1)
    float pos = fract(TIME * speed);
    // Use only the x coordinate for horizontal movement
    float proj = uv.x;
    // Distance from the moving vertical line
    float d = abs(proj - pos);
    // Soft‑edge band: 1 at center, 0 at 'width'
    float band = smoothstep(0.25, 0.0, d);
    // Apply overall intensity
    float a = band * intensity;
    // Mix base color with the shimmer line color
    vec3 color = mix(base_color.rgb, line_color.rgb, a);
    // Preserve the original texture's alpha
    vec4 texture_color = texture(TEXTURE, UV);
    COLOR = vec4(color, texture_color.a);
}