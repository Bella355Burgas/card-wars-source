shader_type canvas_item;
// Card pictures in menus and previews: read half a mip level finer, as the cards on the table
// do (card.gdshader). The levels are Lanczos-shrunk (tools/make_sharp.gd), so it does not shimmer.

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	COLOR = texture(TEXTURE, UV, -0.5) * v_color;
}
