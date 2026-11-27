shader_type canvas_item;
render_mode unshaded;

uniform vec3 palette[48];
uniform int palette_size = 40;
uniform float dither_amount : hint_range(0.0, 0.15) = 0.04;

// A 4x4 ordered threshold made from interleaved two-bit coordinates.
// Evaluate in source pixels, so enlarging the window does not change the pattern.
float ordered_threshold(ivec2 p) {
    int x = p.x & 3;
    int y = p.y & 3;
    int low = ((x & 1) ^ (y & 1)) * 2 + (y & 1);
    int high = (((x >> 1) & 1) ^ ((y >> 1) & 1)) * 2 + ((y >> 1) & 1);
    return (float(low * 4 + high) + 0.5) / 16.0 - 0.5;
}

void fragment() {
    ivec2 pixel = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
    vec4 sample_color = texture(TEXTURE, (vec2(pixel) + vec2(0.5)) * TEXTURE_PIXEL_SIZE);
    vec3 wanted = clamp(sample_color.rgb + vec3(ordered_threshold(pixel) * dither_amount), vec3(0.0), vec3(1.0));
    vec3 chosen = palette[0];
    float closest = 10.0;
    for (int i = 0; i < 48; i++) {
        if (i >= palette_size) { break; }
        vec3 difference = wanted - palette[i];
        float distance_squared = dot(difference * difference, vec3(0.30, 0.59, 0.11));
        if (distance_squared < closest) {
            closest = distance_squared;
            chosen = palette[i];
        }
    }
    COLOR = vec4(chosen, sample_color.a);
}
