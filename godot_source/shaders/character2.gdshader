shader_type canvas_item;

// Metallic effect controls
uniform vec4 metallic_tint : source_color = vec4(0.8, 0.8, 0.7, 1.0);
uniform float metallic_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float shimmer_speed : hint_range(0.1, 5.0) = 1.0;
uniform float shimmer_scale : hint_range(1.0, 20.0) = 10.0;
uniform float shimmer_intensity : hint_range(0.0, 1.0) = 0.5;

// Dynamic wave pattern
float wave_pattern(vec2 uv, float time) {
    // Create multiple waves for a more complex effect
    float wave1 = sin(uv.x * shimmer_scale + time * shimmer_speed);
    float wave2 = sin(uv.y * shimmer_scale * 0.7 + time * shimmer_speed * 0.8);
    float wave3 = sin((uv.x + uv.y) * shimmer_scale * 0.5 + time * shimmer_speed * 1.2);

    // Combine waves
    return (wave1 + wave2 + wave3) / 3.0;
}

void fragment() {
    // Sample the original texture - using built-in TEXTURE uniform
    vec4 original_color = texture(TEXTURE, UV);

    // Calculate the shimmer effect
    float time = TIME;
    float shimmer = wave_pattern(UV, time) * shimmer_intensity;

    // Apply metallic tint while preserving original alpha
    vec3 tinted_color = mix(original_color.rgb, metallic_tint.rgb, metallic_intensity);

    // Add shimmer highlight
    vec3 final_color = tinted_color + shimmer * metallic_tint.rgb;

    // Preserve original transparency
    COLOR = vec4(final_color, original_color.a);
}