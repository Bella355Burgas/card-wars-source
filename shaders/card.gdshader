shader_type canvas_item;
// Fake 3D card: perspective tilt, moving specular sheen, rainbow foil,
// dimming and hit flash. The quad is enlarged in the vertex stage so the
// tilted card never gets clipped.

uniform float fov : hint_range(1.0, 120.0) = 50.0;
uniform float x_rot : hint_range(-80.0, 80.0) = 0.0;
uniform float y_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float foil : hint_range(0.0, 1.0) = 0.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float sheen : hint_range(0.0, 2.0) = 1.0;

varying flat vec2 o;
varying vec3 p;
varying vec4 v_color;

void vertex() {
	// COLOR in fragment() already holds texture(UV); keep the plain vertex colour.
	v_color = COLOR;
	float sin_b = sin(radians(y_rot));
	float cos_b = cos(radians(y_rot));
	float sin_c = sin(radians(x_rot));
	float cos_c = cos(radians(x_rot));
	mat3 inv_rot;
	inv_rot[0][0] = cos_b;
	inv_rot[0][1] = 0.0;
	inv_rot[0][2] = -sin_b;
	inv_rot[1][0] = sin_b * sin_c;
	inv_rot[1][1] = cos_c;
	inv_rot[1][2] = cos_b * sin_c;
	inv_rot[2][0] = sin_b * cos_c;
	inv_rot[2][1] = -sin_c;
	inv_rot[2][2] = cos_b * cos_c;
	float t = tan(radians(fov) * 0.5);
	p = inv_rot * vec3(UV - 0.5, 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot[2].z;
	o = v * inv_rot[2].xy;
	VERTEX += (UV - 0.5) / TEXTURE_PIXEL_SIZE * t;
}

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	if (p.z <= 0.0) discard;
	vec2 uv = (p.xy / p.z) - o;
	vec2 st = uv + 0.5;
	// Half a mip level finer: the levels are Lanczos-shrunk (tools/make_sharp.gd), so this sharpens without shimmer.
	vec4 col = texture(TEXTURE, st, -0.5);
	col.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);

	// A soft light band that slides across the card as it tilts.
	float band_pos = y_rot / 40.0 - x_rot / 60.0;
	float d = (st.x * 0.8 + st.y * 0.6) - 0.7 - band_pos;
	float band = exp(-d * d * 60.0) * 0.22 + exp(-d * d * 900.0) * 0.18;
	col.rgb += vec3(band) * sheen;

	if (foil > 0.0) {
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		vec3 rainbow = hue(fract(st.x * 0.9 + st.y * 0.6 + y_rot / 90.0 + x_rot / 120.0 + TIME * 0.05));
		float mask = smoothstep(0.35, 0.95, lum) * 0.35 + 0.08;
		col.rgb = mix(col.rgb, col.rgb * 0.6 + rainbow * 0.7, foil * mask);
	}

	float grey = dot(col.rgb, vec3(0.3, 0.59, 0.11));
	col.rgb = mix(col.rgb, vec3(grey) * 0.72, dim * 0.6);
	col.rgb = mix(col.rgb, flash_color.rgb, flash_color.a);
	COLOR = col * v_color;
}
