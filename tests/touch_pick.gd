extends SceneTree
## A finger picks what is under it (docs/MOBILE_UI.md): real touch events
## (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, as a phone
## sends them) tap buttons, tiles with their own gui_input, lists, a scrolled tall window,
## the cards of the hand, of the field, of the choices and of the list of cards, and check that
## exactly that one reacted, exactly once.
##   godot --path . --resolution 2400x1080 -s res://tests/touch_pick.gd -- [zoom] [inset]
## zoom: «Масштаб» 0.85, 1.0 or 1.15 (default 1.0); inset: «inset» fakes a camera cutout at the left.
## Exit code 1 when a check fails.

const MainScene := preload("res://scenes/main.tscn")
const Phone = preload("res://scripts/ui/phone.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")

var main
var fails := 0
var checks := 0
var zoom := 1.0
var tag := ""                     # the table being tried, in front of each failure


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		zoom = float(args[0])
	if args.size() > 1 and args[1] == "inset":
		var w := DisplayServer.window_get_size()
		Phone.fake_insets = Vector4(roundf(w.x * 0.035), 0.0, 0.0, roundf(w.y * 0.03))
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	main.phone_layout = true
	root.add_child(main)
	_run()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", tag, what)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## On a phone the mouse position (get_global_mouse_position) is the last point a finger
## touched (Input's, the Android display server has no mouse of its own); on a PC it is the
## system's cursor: it is moved along with the finger.
func _mouse_to(px: Vector2) -> void:
	Input.warp_mouse(px)


## A finger on the screen (window pixels): down at `from`, moved to `to` in `steps`, up there.
func _finger(from: Vector2, to: Vector2, steps := 0, hold := 0.0) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = from
	t.pressed = true
	_mouse_to(from)
	Input.parse_input_event(t)
	await process_frame
	for i in range(1, steps + 1):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, float(i) / steps)
		d.relative = (to - from) / steps
		_mouse_to(d.position)
		Input.parse_input_event(d)
		await process_frame
	if hold > 0.0:
		await _wait(hold)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = to
	u.pressed = false
	Input.parse_input_event(u)
	await process_frame
	await process_frame


func _tap(px: Vector2, wobble := Vector2.ZERO) -> void:
	await _finger(px, px + wobble, 2 if wobble != Vector2.ZERO else 0)


## A control's rect in window pixels.
func _px(c: Control) -> Rect2:
	var k := root.get_final_transform() * c.get_global_transform_with_canvas()
	return Rect2(k * Vector2.ZERO, (k * c.size) - (k * Vector2.ZERO))


## A card of the table: a canvas point of it to window pixels.
func _view_px(v: Node2D, local: Vector2) -> Vector2:
	return root.get_final_transform() * (v.get_global_transform_with_canvas() * local)


func _run() -> void:
	await _wait(1.0)
	main.ui_zoom = zoom
	main.apply_zoom()
	await _wait(0.5)
	print("zoom %.2f, insets %s, window %s" % [zoom, Phone.fake_insets, DisplayServer.window_get_size()])
	await _gui_probe()
	await _board_probe(["magic_man", "jake"], true)
	await _board_probe(["finn", "jake", "bmo", "marceline"], false)
	await _board_probe(["finn", "jake", "bmo"], false)
	print("touch_pick: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ windows and lists

## A window of the menus: buttons, a toggle, tiles with their own gui_input, in a plain box, in a
## list that scrolls and in a window taller than the screen (scrolled down).
func _gui_probe() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	var counts := {}
	var row := HBoxContainer.new()
	box.add_child(row)
	var items: Array[Control] = []
	for i in 4:
		var b := Button.new()
		b.text = "B%d" % i
		b.custom_minimum_size = Vector2(120, 70)
		b.pressed.connect(func(): counts[b.name] = counts.get(b.name, 0) + 1)
		b.name = "button%d" % i
		row.add_child(b)
		items.append(b)
	var tog := CheckButton.new()
	tog.name = "toggle"
	tog.custom_minimum_size = Vector2(120, 70)
	tog.toggled.connect(func(_on): counts["toggle"] = counts.get("toggle", 0) + 1)
	row.add_child(tog)
	items.append(tog)
	for i in 3:
		var t := Panel.new()
		t.name = "tile%d" % i
		t.custom_minimum_size = Vector2(120, 70)
		t.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				counts[t.name] = counts.get(t.name, 0) + 1)
		row.add_child(t)
		items.append(t)
	# A list that scrolls, of tiles and buttons.
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(900, 200)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	sc.add_child(grid)
	var list_items: Array[Control] = []
	for i in 36:
		var c: Control
		if i % 2 == 0:
			var b := Button.new()
			b.text = "L%d" % i
			b.pressed.connect(func(): counts[b.name] = counts.get(b.name, 0) + 1)
			c = b
		else:
			var t := Panel.new()
			t.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
					counts[t.name] = counts.get(t.name, 0) + 1)
			c = t
		c.name = "list%d" % i
		c.custom_minimum_size = Vector2(140, 70)
		grid.add_child(c)
		list_items.append(c)
	# Below: enough to make the window taller than the screen, with buttons at its end.
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(10, 500)
	box.add_child(filler)
	var low := HBoxContainer.new()
	box.add_child(low)
	for i in 3:
		var b := Button.new()
		b.name = "low%d" % i
		b.text = "D%d" % i
		b.custom_minimum_size = Vector2(160, 70)
		b.pressed.connect(func(): counts[b.name] = counts.get(b.name, 0) + 1)
		low.add_child(b)
	await _frames(4)
	ok(center.can_scroll(), "gui: the probe window is taller than the screen")

	# Every button, toggle and tile of the plain row: one tap, one press of exactly it.
	for c in items:
		counts.clear()
		await _tap(_px(c).get_center())
		await _frames(2)
		ok(counts.get(c.name, 0) == 1 and counts.size() == 1, "gui: a tap on %s gave %s" % [c.name, counts])
		# A finger that wandered a little (within the slop) is still a tap of the same one.
		counts.clear()
		await _tap(_px(c).get_center(), Vector2(13, -11))
		await _frames(2)
		ok(counts.get(c.name, 0) == 1 and counts.size() == 1, "gui: a tap that wandered on %s gave %s" % [c.name, counts])
	# The list: its items under the finger, scrolled and not.
	for scroll in [0, 60]:
		sc.scroll_vertical = scroll
		await _frames(2)
		for c in list_items:
			var r := _px(c).intersection(_px(sc))
			if r.size.y < 30.0:
				continue
			counts.clear()
			await _tap(r.get_center())
			await _frames(2)
			ok(counts.get(c.name, 0) == 1 and counts.size() == 1, "gui: list scrolled %d, a tap on %s gave %s" % [scroll, c.name, counts])
	# A finger dragged over the list scrolls it and presses nothing.
	sc.scroll_vertical = 0
	await _frames(2)
	counts.clear()
	var mid := _px(sc).get_center()
	await _finger(mid, mid - Vector2(0, 120), 6)
	await _frames(2)
	ok(sc.scroll_vertical > 0 and counts.is_empty(), "gui: a drag over the list scrolled %d, pressed %s" % [sc.scroll_vertical, counts])
	# The window scrolled to its end: the buttons there under the finger.
	center.scroll_y = center._overflow
	center.queue_sort()
	await _frames(3)
	for b in low.get_children():
		counts.clear()
		await _tap(_px(b).get_center())
		await _frames(2)
		ok(counts.get(b.name, 0) == 1 and counts.size() == 1, "gui: window scrolled, a tap on %s gave %s" % [b.name, counts])
	layer.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ the table

## A point of the card `v` that no card drawn over it covers (window pixels), or INF.
func _visible_point(b, v) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	var sz: Vector2 = v._size
	for iy in range(1, 10):
		for ix in range(1, 10):
			var local := Vector2(-sz.x * 0.5 + sz.x * ix / 10.0, -sz.y * 0.5 + sz.y * iy / 10.0)
			var canvas: Vector2 = v.get_global_transform_with_canvas() * local
			var covered := false
			for o in b.views.values():
				if o == v or not o.visible or o.z_index <= v.z_index:
					continue
				for off in [Vector2.ZERO, Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
					if o.contains_point(canvas + off):
						covered = true
				if covered:
					break
			var px := root.get_final_transform() * canvas
			if covered or not Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size())).grow(-12).has_point(px):
				continue
			if _hud_at(b, px):
				continue
			var d := local.length()
			if d < best_d:
				best_d = d
				best = px
	return best


## A control of the table's HUD (the column, its buttons) takes the point.
func _hud_at(b, px: Vector2) -> bool:
	for c: Control in b.hud.find_children("*", "Control", true, false):
		if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP and _px(c).has_point(px):
			return true
	return false


## The cards settle where they go.
func _settle() -> void:
	await _wait(0.6)


## A picture of the window to the folder of the test's shots (CW_SHOTS), when it is set.
func _shot(name: String) -> void:
	var dir := OS.get_environment("CW_SHOTS")
	if dir != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("%s_%.2f.png" % [name, zoom]))


## A table of the sandbox with these heroes; `full`: the hold, the play, the lists and the log too.
func _board_probe(heroes: Array, full: bool) -> void:
	main.show_title()
	await _wait(0.3)
	main.sandbox_start.start(heroes)
	tag = "%d seats: " % heroes.size()
	await _wait(2.0)
	var b = main.board
	var g = main.game
	for i in 300:
		await process_frame
		if not b._busy and b._choice == null:
			break
	b.sb_panel.visible = false
	var sb = b.sandbox
	var p: int = b.viewer
	var ids := ["cool_dog", "corn_lord", "big_foot", "archer_dan"]
	var foe := -1
	for side in g.sides():
		if g.is_foe(p, side) and foe < 0:
			foe = side
	for lane in 4:
		if lane != 3:
			await sb.add_card(p, ids[lane], "creature", lane)
		await sb.add_card(foe, ids[(lane + 1) % 4], "creature", lane)
	b.sync()
	await _wait(1.2)
	ok(not b._hand_crowded(), "hand: %d cards are not crowded" % g.players[p].hand.size())
	print("%d seats: viewer %d, turn %d, phase %s, hand %d, can act %s" % [g.players.size(), p, g.turn_player, g.phase, g.players[p].hand.size(), b._can_act()])

	# The hand: each card, tapped where it shows, is the one picked; a tap picks another even
	# while one is up; a second tap on the picked one puts it down, and then no card stays up.
	var hand: Array = g.players[p].hand.duplicate()
	for round in 2:
		b._clear_selection()
		await _settle()
		for i in hand.size():
			var c = hand[i] if round == 0 else hand[hand.size() - 1 - i]
			var v = b.views[c.uid]
			var at := _visible_point(b, v)
			if at == Vector2.INF:
				# All of it under the picked one, which stands up over the hand: no tap for it now.
				ok(b._selected_uid != -1, "hand: card %d has a visible part" % i)
				if b._selected_uid == -1:
					await _shot("hidden_%d" % heroes.size())
				continue
			await _tap(at, Vector2(13, 11) if i % 2 == 1 else Vector2.ZERO)
			await _settle()
			ok(b._selected_uid == c.uid, "hand: a tap on card %d (%s at %s) picked %s" % [i, c.id, at, _name(b, b._selected_uid)])
			if round == 0 and i == 4:
				await _shot("hand_picked")
	var sel: int = b._selected_uid
	if sel != -1:
		var at := _visible_point(b, b.views[sel])
		await _tap(at)
		await _settle()
		ok(b._selected_uid == -1, "hand: a second tap on the picked card puts it down")
		var up := []
		for c in hand:
			var v = b.views[c.uid]
			if v.target_scale > (0.38 if b.teams else b.P_S_HAND) + 0.01 or v.z_index >= 100:
				up.append(c.id)
		ok(up.is_empty(), "hand: no card stays up after it was put down: %s" % [up])
	# Every card of the hand again from nothing picked, by the middle of what shows of it.
	for i in hand.size():
		var c = hand[i]
		b._clear_selection()
		await _settle()
		var at := _visible_point(b, b.views[c.uid])
		ok(at != Vector2.INF, "hand: from none, card %d has a visible part" % i)
		await _tap(at)
		await _settle()
		ok(b._selected_uid == c.uid, "hand: from none, a tap on card %d picked %s" % [i, _name(b, b._selected_uid)])
		# The tapped card is shown on the left too, as the mouse over it shows it on a PC.
		ok(b._peek_view == b.views[c.uid] and b.preview_rect.texture != null and b.preview_rect.is_visible_in_tree(),
			"preview: a tap on card %d shows it on the left" % i)
	b._clear_selection()
	await _settle()
	# A creature of the other side, tapped: shown on the left, its numbers under it.
	for lane in 4:
		var fc = g.players[foe].creatures[lane]
		if fc == null:
			continue
		var at := _visible_point(b, b.views[fc.uid])
		if at == Vector2.INF:
			continue
		await _tap(at)
		await _settle()
		ok(b._peek_view == b.views[fc.uid] and b.preview_rect.texture != null and b.preview_info.text.begins_with("АТК"),
			"preview: a tap on the other's creature in lane %d shows it (%s)" % [lane + 1, b.preview_info.text])
		b._clear_selection()
		await _settle()
		if b.teams or g.players.size() > 2:
			break

	# A long hand (its cards over each other): a tap on it opens the whole hand big; a tap on a
	# card there picks it and closes the hand.
	for id in ["cool_dog", "corn_lord", "big_foot", "archer_dan", "cool_dog", "corn_lord", "big_foot"]:
		await sb.add_card(p, id, "hand")
	b.sync()
	await _wait(1.2)
	hand = g.players[p].hand.duplicate()
	ok(b._hand_crowded(), "long hand: %d cards are crowded" % hand.size())
	for i in [0, hand.size() / 2, hand.size() - 1]:
		b._clear_selection()
		await _settle()
		await _pick_from_hand(b, hand[i], i)
	await _shot("hand_open_%d" % heroes.size())
	b._clear_selection()
	await _settle()
	if not full:
		await _field_choices(b, g, p, foe)
		main._end_game()
		await _wait(0.4)
		return

	# A finger held on a card of the hand: the card big to read, nothing picked or played.
	var held = hand[2]
	await _finger(_visible_point(b, b.views[held.uid]), _visible_point(b, b.views[held.uid]), 0, 0.7)
	await _settle()
	ok(b.inspect_layer.visible and b._selected_uid == -1, "hold: a held finger shows the card (%s), picks %s" % [b.inspect_layer.visible, _name(b, b._selected_uid)])
	await _tap(Vector2(DisplayServer.window_get_size()) * Vector2(0.3, 0.4))
	await _settle()
	ok(not b.inspect_layer.visible, "hold: a tap closes the big card")

	# A creature of the hand tapped, then its empty lane tapped by a shaky finger: it is played there.
	var cre = null
	for c in g.players[p].hand:
		if c.kind() == "creature" and g.can_play(p, c.uid):
			cre = c
			break
	ok(cre != null, "play: a creature to play")
	if cre != null:
		await _pick_from_hand(b, cre, g.players[p].hand.find(cre))
		ok(b._selected_uid == cre.uid, "play: the creature is picked")
		var target = null
		for t in b._drop_targets:
			if t["lane"] == 3:
				target = t
		ok(target != null, "play: lane 4 is a target")
		if target != null:
			var at: Vector2 = root.get_final_transform() * (b.world.get_global_transform_with_canvas() * target["shape"]["c"])
			await _tap(at, Vector2(14, 12))
			await _wait(1.5)
			ok(g.players[p].creatures[3] != null and g.players[p].creatures[3].uid == cre.uid,
				"play: a shaky tap on lane 4 played it there (%s)" % [_name(b, g.players[p].creatures[3].uid if g.players[p].creatures[3] else -1)])
		# The creature's own question when it enters (Фиалис asks to show spells) is answered,
		# or the test's own choices below would share its answer.
		for i in 600:
			await process_frame
			if b._choice != null and not b._choice["options"].is_empty():
				b._resolve_choice(b._choice["options"][-1])
			elif not b._busy:
				break

	await _field_choices(b, g, p, foe)
	# A choice of a card of the hand.
	await _hand_choices(b, p, g.players[p].hand.duplicate())
	await _picker_choices(b, p, sb, ids)
	await _log_taps(b)
	main._end_game()
	await _wait(0.4)


## A choice of a creature on the field: each option, tapped, is the one chosen.
func _field_choices(b, g, p: int, foe: int) -> void:
	var opts := []
	for lane in 4:
		if g.players[foe].creatures[lane] != null:
			opts.append({"p": foe, "lane": lane})
		if g.players[p].creatures[lane] != null:
			opts.append({"p": p, "lane": lane})
	for opt in opts:
		var req := {"kind": "creature", "player": p, "optional": true, "prompt": "Выбери существо", "options": opts}
		var res := [null, false]
		_choose(b, req, res)
		await _settle()
		var c = g.slot(opt["p"], "creature", opt["lane"])
		var at := _visible_point(b, b.views[c.uid])
		var moving := opts.find(opt) % 3 == 1
		if moving:
			# The field moves (a zoom going on) while the finger is down: the card it went down on counts.
			b._zoom_home()
			await _finger(at, at, 0, 0.2)
		else:
			await _tap(at, Vector2(12, -12))
		await _settle()
		ok(res[1] and res[0] is Dictionary and res[0]["p"] == opt["p"] and res[0]["lane"] == opt["lane"],
			"field: a tap on %s%s chose %s" % [opt, " while the field moved" if moving else "", res[0]])
		if not res[1]:
			b._resolve_choice(null)
			await _settle()



func _hand_choices(b, p: int, hand: Array) -> void:
	for c in hand.slice(0, 4):
		var uids := hand.map(func(x): return x.uid)
		var req := {"kind": "hand_card", "player": p, "optional": true, "prompt": "Выбери карту", "options": uids}
		var res := [null, false]
		_choose(b, req, res)
		await _settle()
		if b._hand_crowded():
			ok(b.picker_layer.visible, "choice: a long hand is shown big for a choice of its card")
			await _tap_picker(b, hand.find(c))
		else:
			await _tap(_visible_point(b, b.views[c.uid]))
		await _settle()
		ok(res[1] and res[0] == c.uid, "choice: a tap on hand card %s chose %s" % [c.id, _name(b, res[0] if res[0] is int else -1)])
		if not res[1]:
			b._resolve_choice(null)
			await _settle()



## A card of the hand picked by a finger: a tap on it, and when the hand is long, a tap on the
## hand opens it big and a tap there on the card.
func _pick_from_hand(b, c, i: int) -> void:
	var at := _visible_point(b, b.views[c.uid])
	ok(at != Vector2.INF, "hand: card %d has a visible part" % i)
	await _tap(at)
	await _settle()
	if b._hand_crowded():
		ok(b.picker_layer.visible and b.picker_title.text.begins_with("Рука"), "long hand: a tap on card %d opens the hand" % i)
		ok(b._selected_uid == -1, "long hand: the tap picks nothing yet (%s)" % _name(b, b._selected_uid))
		if not b.picker_layer.visible:
			return
		if i == 0:
			await _shot("hand_big_%d" % b.game.players.size())
			if b.picker_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				# One row on a small screen: a finger moved sideways scrolls it and picks nothing.
				var r := _px(b.picker_scroll)
				await _finger(r.get_center() + Vector2(r.size.x * 0.3, 0), r.get_center() - Vector2(r.size.x * 0.3, 0), 8)
				await _settle()
				ok(b.picker_scroll.scroll_horizontal > 100, "long hand: a swipe scrolls the row (%d)" % b.picker_scroll.scroll_horizontal)
				ok(b.picker_layer.visible and b._selected_uid == -1, "long hand: a swipe picks nothing")
				b.picker_scroll.scroll_horizontal = 0
				await _frames(2)
		await _tap_picker(b, i)
		await _settle()
		ok(not b.picker_layer.visible, "long hand: a pick closes the hand")
	ok(b._selected_uid == c.uid, "hand: card %d (%s) is picked: %s" % [i, c.id, _name(b, b._selected_uid)])


## A tap on the k-th card button of the picker window, scrolled to it.
func _tap_picker(b, k: int) -> void:
	var btn: Control = b.picker_grid.get_child(k)
	b.picker_scroll.ensure_control_visible(btn)
	await _frames(3)
	var r := _px(btn).intersection(_px(b.picker_scroll))
	ok(r.size.x > 40 and r.size.y > 40, "picker: card %d shows (%s)" % [k, r.size])
	await _tap(r.get_center(), Vector2(-12, 10))


## The list window of a choice (picker): each card button, tapped, is the one chosen.
func _picker_choices(b, p: int, sb, ids: Array) -> void:
	for n in [4, 16]:
		var cards := []
		for k in n:
			var ci = await sb.add_card(p, ids[k % 4], "discard")
			cards.append(ci.uid)
		for k in [0, 1, n - 1]:
			var req := {"kind": "card", "player": p, "optional": true, "prompt": "Выбери карту", "options": cards, "zone": "discard"}
			var res := [null, false]
			_choose(b, req, res)
			await _settle()
			ok(b.picker_layer.visible, "picker: shown for %d cards" % n)
			var btn: Control = b.picker_grid.get_child(k)
			b.picker_scroll.ensure_control_visible(btn)
			await _frames(3)
			var r := _px(btn).intersection(_px(b.picker_scroll))
			await _tap(r.get_center(), Vector2(-12, 10))
			await _settle()
			ok(res[1] and res[0] == cards[k], "picker %d: a tap on card %d chose %s" % [n, k, res[0]])
			if not res[1]:
				b._resolve_choice(null)
				await _settle()



## The strip of the log: a finger opens it big over the table, with its lines in it; another tap closes it.
func _log_taps(b) -> void:
	ok(b.log_box.get_parsed_text().strip_edges() != "", "log: the log has lines")
	await _tap(_px(b.log_panel).get_center())
	await _settle()
	ok(b._log_big, "log: a tap opens it")
	var lr := _px(b.log_panel)
	var text_r := _px(b.log_box)
	ok(lr.size.y > 300.0 and text_r.size.y > 200.0 and b.log_box.is_visible_in_tree() and b.log_box.get_parsed_text().strip_edges() != "",
		"log: open big with its text (panel %s, text %s)" % [lr, text_r])
	await _shot("log_open")
	await _tap(_px(b.log_panel).get_center())
	await _settle()
	ok(not b._log_big, "log: a second tap closes it (under the finger: %s)" % [root.gui_get_hovered_control()])


## A choice asked of the board as the game asks it; `res` gets [result, done].
func _choose(b, req: Dictionary, res: Array) -> void:
	var r = await b._local_choice(req)
	res[0] = r
	res[1] = true


func _name(b, uid) -> String:
	if uid == null or uid == -1:
		return "none"
	var c = b.game.card(uid)
	return "%s#%d" % [c.id if c != null else "?", uid]

