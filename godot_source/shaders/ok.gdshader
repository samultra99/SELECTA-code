shader_type canvas_item;

uniform float speed : hint_range(0.0, 10.0) = 2; // Controls animation speed
uniform float thickness : hint_range(0.0, 5.0) = 1.5; // Controls how bold the text appears

void fragment() {
    vec2 pos = UV;

    // Animate a brown-orange gradient
    float t = sin(pos.x * 10.0 + TIME * speed) * 0.5 + 0.5;
    vec3 gradient_color = vec3(0.6 + 0.4 * t, 0.3 + 0.2 * t, 0.1 + 0.1 * (1.0 - t));

    // Sample surrounding pixels to make text look thicker
    float alpha = 0.0;
    float pixel_size = 1.0 / float(textureSize(TEXTURE, 0).x); // assumes square texels

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 offset = vec2(float(i), float(j)) * pixel_size * thickness;
            alpha += texture(TEXTURE, UV + offset).a;
        }
    }

    alpha = clamp(alpha / 9.0, 0.0, 1.0); // average and clamp

    COLOR = vec4(gradient_color, alpha);
}
