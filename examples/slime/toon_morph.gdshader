shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D target_colors : filter_nearest, repeat_disable;
uniform float morph_weight : hint_range(0.0, 1.0) = 0.0;
uniform bool has_target = false;

vec3 to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
    vec3 color = COLOR.rgb;
    if (has_target) {
        color = mix(color, to_linear(texture(target_colors, UV).rgb), morph_weight);
    }
    if (OUTPUT_IS_SRGB) {
        color = mix(12.92 * color, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0/2.4)) - 0.055, step(vec3(0.0031308), color));
    }
    ALBEDO = color;
}
