extends CanvasLayer
# Biscuit's shop window. Opens when you talk to the cat: a list of what's for
# sale, one purchase at a time, navigated with the arrow keys OR the mouse.
#
# Built entirely in code (no .tscn) so it rides along with the cat in any scene.
# Each row is a real Button, which is what gives us mouse hover, clicking, and
# up/down focus movement for free instead of hand-rolling a selection cursor.

signal bought(id: String)
signal closed()

const ROW_HEIGHT := 54

var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _coins: Label
var _blurb: Label
var _rows: Array[Button] = []      # focusable item buttons
var _spawned: Array[Node] = []     # everything added to the list, for teardown
var _open: bool = false

func _ready() -> void:
	# Below the pause menu (layer 10) on purpose: if both are ever up, the pause
	# menu must be on top and clickable, not buried under this window's dim.
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 0)
	centre.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_title = Label.new()
	_title.text = "BISCUIT"
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_blurb = Label.new()
	_blurb.text = "Mrrow? *taps the counter*"
	_blurb.add_theme_font_size_override("font_size", 17)
	_blurb.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_blurb)

	_coins = Label.new()
	_coins.add_theme_font_size_override("font_size", 22)
	_coins.add_theme_color_override("font_color", Color(1, 0.88, 0.32))
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_coins)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)

	var hint := Label.new()
	hint.text = "↑ ↓ choose  ·  Enter / click to buy  ·  Esc to leave"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

# `items` is an array of {id, name, note, price, enabled}. Rebuilt on every
# purchase so prices, affordability and "owned" states stay honest.
func show_items(items: Array, blurb: String = "", title: String = "") -> void:
	if title != "":
		_title.text = title
	if blurb != "":
		_blurb.text = blurb
	_coins.text = "%d coins" % Game.coins
	for n in _spawned:
		n.queue_free()
	_spawned.clear()
	_rows.clear()

	for item in items:
		var b := Button.new()
		var price: int = item.get("price", 0)
		var label: String = item["name"]
		if price > 0:
			label += "        %d coins" % price
		b.text = label
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		b.add_theme_font_size_override("font_size", 21)
		b.disabled = not bool(item.get("enabled", true))
		b.tooltip_text = item.get("note", "")
		var id: String = item["id"]
		b.pressed.connect(func() -> void: _buy(id))
		Sfx.wire_button(b)
		_list.add_child(b)
		_rows.append(b)
		_spawned.append(b)
		# The note sits under its row so it reads without hovering.
		if str(item.get("note", "")) != "":
			var note := Label.new()
			note.text = str(item["note"])
			note.add_theme_font_size_override("font_size", 15)
			note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.75))
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_list.add_child(note)
			_spawned.append(note)

	_link_focus_wrap()
	_focus_first()

# Up at the top jumps to the bottom, and vice versa. Godot doesn't wrap focus by
# default, so the neighbours are chained explicitly — over the ENABLED rows only,
# since a disabled button can't take focus and would break the loop.
func _link_focus_wrap() -> void:
	var live: Array[Button] = []
	for r in _rows:
		if is_instance_valid(r) and not r.disabled:
			live.append(r)
	var n := live.size()
	if n == 0:
		return
	for i in n:
		var above := live[(i - 1 + n) % n]
		var below := live[(i + 1) % n]
		live[i].focus_neighbor_top = above.get_path()
		live[i].focus_neighbor_bottom = below.get_path()
		live[i].focus_previous = above.get_path()
		live[i].focus_next = below.get_path()

func _focus_first() -> void:
	for r in _rows:
		if is_instance_valid(r) and not r.disabled:
			r.grab_focus()
			return

func open(items: Array, blurb: String = "", title: String = "") -> void:
	_open = true
	Game.shop_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_items(items, blurb, title)

func close() -> void:
	if not _open:
		return
	_open = false
	Game.shop_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

func is_open() -> bool:
	return _open

func _buy(id: String) -> void:
	bought.emit(id)

# _input, not _unhandled_input: pause_menu also listens for ui_cancel in _input,
# and without consuming it here Esc would pause the game behind this window.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
