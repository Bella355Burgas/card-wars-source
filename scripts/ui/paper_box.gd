extends StyleBox
## A box drawn by hand, like the paper cards, tags and mats of Adventure Time: a rounded shape
## with a slightly uneven outline. The unevenness comes from `seed`, so a box keeps its shape
## from frame to frame. Margins are the StyleBox content margins.

var fill := Color.WHITE
var line := Color.BLACK
var line_width := 3.0
var radius := 14.0
var wobble := 1.4                   # how far the outline strays from the straight shape
var seed := 0
var shadow := Vector2.ZERO          # a dark copy of the shape under the box, this far off
var shadow_color := Color(0, 0, 0, 0.3)
var stitch := Color.TRANSPARENT     # a dashed seam inside the edge, as on a felt mat
var stitch_inset := 9.0
var tape := false                   # a strip of sticky tape across the top


func _draw(ci: RID, rect: Rect2) -> void:
	var pts := outline(rect, radius, wobble, seed)
	if shadow != Vector2.ZERO:
		var sp := PackedVector2Array()
		for p in pts:
			sp.append(p + shadow)
		RenderingServer.canvas_item_add_polygon(ci, sp, PackedColorArray([shadow_color]))
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([fill]))
	if stitch.a > 0.0:
		_dashes(ci, outline(rect.grow(-stitch_inset), maxf(radius - stitch_inset, 4.0), wobble * 0.6, seed + 7))
	if line_width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([line]), line_width, true)
	if tape:
		var w := minf(rect.size.x * 0.4, 110.0)
		var c := Vector2(rect.get_center().x, rect.position.y + 2.0)
		var t := Transform2D(-0.05, c)
		var strip := PackedVector2Array([t * Vector2(-w * 0.5, -12), t * Vector2(w * 0.5, -10),
			t * Vector2(w * 0.5 + 2, 11), t * Vector2(-w * 0.5 - 1, 12)])
		RenderingServer.canvas_item_add_polygon(ci, strip, PackedColorArray([Color(0.96, 0.93, 0.78, 0.62)]))


## The points round a rounded rect, each pushed out or in a little along the edge's normal.
static func outline(rect: Rect2, r: float, wob: float, s: int) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	var along := 0.0
	for i in 4:
		# The arc of the corner, then the straight edge to the next corner.
		var a0 := -PI * 0.5 + i * PI * 0.5
		for k in 6:
			var a := a0 + PI * 0.5 * k / 6.0
			var n := Vector2(cos(a), sin(a))
			pts.append(corners[i] + n * (r + _bump(along, wob, s)))
			along += r * PI * 0.5 / 6.0
		var a1 := a0 + PI * 0.5
		var n1 := Vector2(cos(a1), sin(a1))
		var from: Vector2 = corners[i] + n1 * r
		var to: Vector2 = corners[(i + 1) % 4] + n1 * r
		var steps := maxi(1, ceili(from.distance_to(to) / 22.0))
		for k in steps:
			pts.append(from.lerp(to, float(k) / steps) + n1 * _bump(along, wob, s))
			along += from.distance_to(to) / steps
	return pts


static func _bump(t: float, wob: float, s: int) -> float:
	var x := t / 37.0 + s * 1.618
	return wob * (sin(x) * 0.6 + sin(x * 2.37 + s) * 0.4)


func _dashes(ci: RID, pts: PackedVector2Array) -> void:
	var dash := 9.0
	var gap := 7.0
	var on := true
	var left := dash
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := a.distance_to(b)
		var pos := 0.0
		while pos < d:
			var take := minf(left, d - pos)
			if on:
				RenderingServer.canvas_item_add_line(ci, a.lerp(b, pos / d), a.lerp(b, (pos + take) / d), stitch, 2.0, true)
			pos += take
			left -= take
			if left <= 0.0:
				on = not on
				left = dash if on else gap
