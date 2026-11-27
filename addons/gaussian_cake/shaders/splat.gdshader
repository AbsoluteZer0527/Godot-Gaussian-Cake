shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D frame_a : filter_nearest, repeat_disable;
uniform sampler2D frame_b : filter_nearest, repeat_disable;
uniform sampler2D splat_order : filter_nearest, repeat_disable;
uniform float frame_blend = 0.0;
uniform float camera_near = 0.05;
varying vec2 pixel_delta;
varying vec3 conic;
varying vec4 splat_color;

vec2 record(sampler2D tex, int id, int field) {
	return texelFetch(tex, ivec2((id % 256) * 7 + field, id / 256), 0).rg;
}
vec4 slerp_short(vec4 a, vec4 b, float t) {
	float d = dot(a,b);
	if (d < 0.0) { b = -b; d = -d; }
	if (d > 0.9995) { return normalize(mix(a,b,t)); }
	float angle = acos(clamp(d,-1.0,1.0));
	return (sin((1.0-t)*angle)*a + sin(t*angle)*b)/sin(angle);
}
mat3 rotation(vec4 q) {
	vec3 x = q.xyz;
	return mat3(
		vec3(1.0-2.0*(x.y*x.y+x.z*x.z), 2.0*(x.x*x.y+q.w*x.z), 2.0*(x.x*x.z-q.w*x.y)),
		vec3(2.0*(x.x*x.y-q.w*x.z), 1.0-2.0*(x.x*x.x+x.z*x.z), 2.0*(x.y*x.z+q.w*x.x)),
		vec3(2.0*(x.x*x.z+q.w*x.y), 2.0*(x.y*x.z-q.w*x.x), 1.0-2.0*(x.x*x.x+x.y*x.y)));
}
void vertex() {
	int slot = int(INSTANCE_CUSTOM.x+0.5) + 256*int(INSTANCE_CUSTOM.y+0.5);
	int id = int(texelFetch(splat_order, ivec2(slot % 256, slot / 256), 0).r + 0.5);
	vec2 a0=record(frame_a,id,0), a1=record(frame_a,id,1), a2=record(frame_a,id,2), a3=record(frame_a,id,3);
	vec2 b0=record(frame_b,id,0), b1=record(frame_b,id,1), b2=record(frame_b,id,2), b3=record(frame_b,id,3);
	vec3 center=mix(vec3(a0,a1.x),vec3(b0,b1.x),frame_blend);
	vec4 q=slerp_short(vec4(a1.y,a2,a3.x),vec4(b1.y,b2,b3.x),frame_blend);
	vec3 size=exp(mix(vec3(a3.y,record(frame_a,id,4)),vec3(b3.y,record(frame_b,id,4)),frame_blend));
	splat_color=mix(vec4(record(frame_a,id,5),record(frame_a,id,6)),vec4(record(frame_b,id,5),record(frame_b,id,6)),frame_blend);
	vec4 view_center=MODELVIEW_MATRIX*vec4(center,1.0);
	mat3 basis=mat3(MODELVIEW_MATRIX)*rotation(q)*mat3(vec3(size.x,0,0),vec3(0,size.y,0),vec3(0,0,size.z));
	mat3 covariance=basis*transpose(basis);
	vec4 clip=PROJECTION_MATRIX*view_center;
	// Derivative of clip.xy/clip.w works for both perspective and orthographic projections.
	float w=max(abs(clip.w),0.00001);
	vec3 row_w=vec3(PROJECTION_MATRIX[0][3],PROJECTION_MATRIX[1][3],PROJECTION_MATRIX[2][3]);
	vec3 jx=(vec3(PROJECTION_MATRIX[0][0],PROJECTION_MATRIX[1][0],PROJECTION_MATRIX[2][0])*w-clip.x*row_w)/(w*w)*VIEWPORT_SIZE.x*0.5;
	vec3 jy=(vec3(PROJECTION_MATRIX[0][1],PROJECTION_MATRIX[1][1],PROJECTION_MATRIX[2][1])*w-clip.y*row_w)/(w*w)*VIEWPORT_SIZE.y*0.5;
	float xx=dot(jx,covariance*jx)+0.3;
	float xy=dot(jx,covariance*jy);
	float yy=dot(jy,covariance*jy)+0.3;
	float determinant=max(xx*yy-xy*xy,0.000001);
	conic=vec3(yy,-xy,xx)/determinant;
	float middle=0.5*(xx+yy);
	float radius=3.0*sqrt(max(middle+sqrt(max(middle*middle-determinant,0.0)),0.1));
	pixel_delta=VERTEX.xy*radius;
	clip.xy+=pixel_delta*2.0/VIEWPORT_SIZE*clip.w;
	POSITION=clip;
	if (-view_center.z <= camera_near) { POSITION=vec4(2.0,2.0,2.0,1.0); splat_color.a=0.0; }
}
void fragment() {
	float power=-0.5*(conic.x*pixel_delta.x*pixel_delta.x+2.0*conic.y*pixel_delta.x*pixel_delta.y+conic.z*pixel_delta.y*pixel_delta.y);
	float alpha=min(0.99,splat_color.a*exp(power));
	if (power>0.0 || alpha<1.0/255.0) { discard; }
	vec3 color=splat_color.rgb;
	// Cache stores linear RGB. Compatibility's output buffer uses display/sRGB values.
	if (OUTPUT_IS_SRGB) { color=mix(12.92*color,1.055*pow(max(color,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),color)); }
	ALBEDO=color;
	ALPHA=alpha;
}
