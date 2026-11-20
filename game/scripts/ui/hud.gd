## In-game interface: friends and save status, emotes, context actions, the
## toy box catalog, placement tools, scrapbook, language and connection dialogs.
##
## All text is English source passed through Godot translation, so switching
## language updates the screen without touching the town or a placement draft.
extends Control

const Places := preload("res://scripts/core/places.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")
const ThousandPanel := preload("res://scripts/ui/thousand_panel.gd")
const ThousandInspect := preload("res://scripts/core/thousand_inspect.gd")

const UI := preload("res://scripts/ui/ui_kit.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const PadInput := preload("res://scripts/ui/pad_input.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const PlacementDock := preload("res://scripts/ui/placement_dock.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Wishes := preload("res://scripts/core/wishes.gd")
const PhotoIdeas := preload("res://scripts/core/photo_ideas.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const WearThumbs := preload("res://scripts/ui/wear_thumbs.gd")
const PhotoStore := preload("res://scripts/core/photo_store.gd")
const TagLayout := preload("res://scripts/ui/tag_layout.gd")
const ItemQuery := preload("res://scripts/ui/item_query.gd")
const ActivityGuide := preload("res://scripts/ui/activity_guide.gd")
const GuideArt := preload("res://scripts/ui/guide_art.gd")
const PetRules := preload("res://scripts/core/pets.gd")
const Cooking := preload("res://scripts/core/cooking.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")
const PlayRules := preload("res://scripts/core/play_rules.gd")
const Puzzles := preload("res://scripts/core/puzzles.gd")
const PictureBoard := preload("res://scripts/core/picture_board.gd")
const Echoes := preload("res://scripts/core/echoes.gd")
const FirstSteps := preload("res://scripts/core/first_steps.gd")
const Story := preload("res://scripts/core/story.gd")
const Invites := preload("res://scripts/core/invites.gd")
const Blueprints := preload("res://scripts/core/blueprints.gd")
const Wearables := preload("res://scripts/core/wearables.gd")
const SETTINGS_PATH := "user://settings.cfg"

## Width of the Decorate/Undo column; the catalog leaves room for it.
const SIDE_W := 236

signal reef_requested()   # unified r1: the Lantern Reef (main._open_reef), from the tram stop
signal leave_requested()
signal photo_requested()
## The child kept a three-panel story (F05): panels (Images), their order, the card id.
signal story_kept(panels: Array, order: Array, card_id: String)
signal reconnect_requested()

var controller: Node
var thumbs: Node

var _friends: HBoxContainer
var _location: Label
var _ride_home: Button
var _city_reset: Button
var _city_look: Button    # city r2: Look around / Stop looking
var _city_pause: Button   # city r2: Pause / Resume (only while looking)
var _city_weather: VBoxContainer   # city r3: sunny / rain / night, small glass buttons on the right
var _city_weather_btns: Array[Button] = []
## thousand-town: Thousand Town's time (Day, Dusk, Night, Auto; glass buttons on the right like the city's
## weather), its Look button (overview and back), and the inspect panel's data provider.
var _thousand_time: VBoxContainer
var _thousand_time_btns := {}          # mode -> Button
var _thousand_speed: Label             # the Auto button's speed badge (1x, 2x, 4x)
var _thousand_look: Button
var _thousand_clock: Label   # unified r4: "08:15 · Auto: time runs by itself (1x)" / "21:30 · Stays at Night. ..."
## thousand-town interactions (world/thousand_play.gd): the chip (following, the bus, the wheel, a show; with its
## buttons), the resident card (Follow, Close), both at the top right under the top bar, left of the camera and
## time buttons, and the two show buttons
## in the bottom right column. All hidden outside Thousand Town.
var _tt_box: VBoxContainer
var _tt_chip: PanelContainer
var _tt_chip_label: Label
var _tt_chip_btns: HBoxContainer
var _tt_card: PanelContainer
var _tt_card_name: Label
var _tt_card_who: Label
var _tt_card_now: Label
var _tt_card_heading: Label
var _tt_card_follow: Button
var _tt_shows := {}                    # "fireworks" | "fountain" -> Button
var _tt_t := 0.0
## The inspect panel's data: Callable(building_id: String) -> Dictionary (thousand_panel.gd header). The lead
## connects it to ThousandSim; until then a building shows its name and nobody in it.
var inspect_provider: Callable
## The Thousand Town credit (design/thousand-town.md section 0). The upstream title and author are written as
## escapes so the sources stay English (check.py); the sentence around them is translated.
const THOUSAND_TITLE := "\u5343\u4eba\u5c0f\u9547 \u00b7 Thousand Town"
const THOUSAND_AUTHOR := "\u4eea\u7ed8\u58eb / YiHuiShiBY"
const THOUSAND_CREDIT := "Thousand Town is adapted from “%s” by %s (github.com/YiHuiShiBY/thousand-town), CC BY 4.0. Changed for Lantern Lane: units, characters, controls, lighting, and the additions listed in design/thousand-town.md."
var _zoo_invite: Button
var _loc_t := 0.0
var _activity_chip: PanelContainer
var _activity_label: Label
var _warmth_dots: HBoxContainer
var _gift_btn: Button
var _tag_layer: Control
var _tags := {}                       # landmark id -> Button (tappable name tag)
var _heart_btn: Button
var _status: Label
var _status_icon: TextureRect
var _lantern_btn: Button
var _context_btn: Button
var _side_col: VBoxContainer   # the bottom right column (Decorate, and while decorating: display, blueprints, Undo, Done)
var _left_stack: VBoxContainer # the top left column (friends, Activities, Pets, Dress up, Story, Hello)
var _top_right: HBoxContainer  # the top bar's right part (saved status, lanterns, photo, sound, language, leave)
var _bottom_left: VBoxContainer # poses and emotes (bottom left)
var _menus_aside := {}         # side menu -> true while it steps aside for a held thing (_keep_menus_clear)
var _idea_lift := 0            # how far the idea line is raised above its usual place (see _keep_idea_clear)
var _idea_side := 0            # -1: left of the child, 1: right of it, 0: in the middle
var _tools_shift := 0.0        # how far the placement tools stand from the middle of the screen (see _fit_tools)
var _cam_margin: MarginContainer   # holds the camera buttons at the right edge
var _context_alt_btn: Button   # the context's second action (in a cart: Get off), beside the main one
var _workshop_btn: Button      # Workshop r4: the tram stop's Roller Coaster Workshop (Start/+ on a controller)
var _reef_btn: Button          # unified r1: the tram stop's Lantern Reef (main._open_reef)
var _station_row: HBoxContainer   # unified r1: the row holding those two, above the journeys
var _context_alt2_btn: Button  # city-web: a third action (the tram stop's Ride to the city (web), where offered)
var _context_alt3_btn: Button  # thousand-town: a fourth action (the tram stop's Ride to Thousand Town)
var _ctx_row: HBoxContainer     # the action buttons' row (bottom centre)
var _ctx_row2: HBoxContainer    # thousand-town: the third and fourth actions, above, when one row is too wide
var _echo_btn: Button          # Hello (friend echoes), in the menu column under Story
## First steps: one line at a time for a child who is new on this device (core/first_steps.gd).
## Test drivers for other things switch it off (main.gd), so their pictures and timing stay as they were.
var first_steps_enabled := true
var first_steps := FirstSteps.fresh()
var _first_chip: PanelContainer
var _first_icon: TextureRect
var _first_label: Label
var _first_from: Variant = null   # where the child stood when the walking step began
var pad_layer: Node = null        # the game controller layer, set by main.gd (null without one)
var _decorate_btn: Button
var _emotes: HBoxContainer
var _cam_tools: VBoxContainer
var _catalog: PanelContainer
var _tabs: HBoxContainer
var _cards: HBoxContainer
var _card_scroll: ScrollContainer
var _search: LineEdit
var _search_timer: Timer
var _count: Label
var _things_btn: Button
var _empty: HBoxContainer
var _empty_label: Label
var _empty_btn: Button
var _placement := ""                  # placement filter id, "" = all
var _query := ""
var _recent: Array = []               # kinds this device placed, newest first
var _last_kind := ""                  # the card taken last (outlined)
var _scroll_pos := {}                 # view key -> card row scroll
var _cards_key := ""                  # the view (space, tab, filter, search) the card row shows now
var _row_target := 0.0                # where the row is being put after a rebuild
var _row_settling := false            # a rebuilt row has not reached its place yet
var _row_gen := 0                     # the newest rebuild owns the row
var _tools_name: Label
var _guide_btn: Button                # "Activities": the how-to-play guide, always reachable
var _pets_btn: Button                 # "Pets": adopt, choose who follows, send home
var _adopt := {"family": "cat", "color": 0, "name": 0}   # the adoption choices on screen
var _tab_space := ""                  # the room the toy box tab was last chosen for
var _guide_body: Control              # the guide's current page (overview or one activity)
var _guide_scroll := 0                # where the overview was scrolled
## Tests set this to stand in for the on-screen keyboard (HUD units).
var debug_keyboard_height := 0.0
var _tools: PanelContainer
var _tools_row: HFlowContainer   # wraps into two rows when the buttons do not fit side by side (see _fit_tools)
var _swatches: HBoxContainer
var _place_btn: Button
var _remove_btn: Button
var _paint_btn: Button
var _undo_btn: Button
var _display_btn: Button               # decorate mode: put this place on display / take it off (F10)
var _display_badge: Control            # play mode: "On display" while it is
var _dress_btn: Button                 # F07: hats and clothes color in town
var _story_btn: Button                 # F05: start a three-panel story
var _poses: HBoxContainer              # F05: story poses, shown while a story is being made
var _play_chip: PanelContainer         # F05/F06: the story or trail in progress, with Stop
var _play_chip_label: Label
var _play_chip_stop: Button
## A story being made: {"card", "panels": [Image]}; {} when none.
var story := {}
## The trail the local child follows: {"found", "total"}; {} when not following.
var trail := {}
var _invites_box: VBoxContainer        # r11: invitation cards (one per inviter)
var _help_btn: Button                  # r11: "Ask friends to help" for my place on display
var _trail_btn: Button                 # r11: "Suggest a trail" (town with fewer than two signs)
var _bp_btn: Button                    # r11: open saved blueprints
var _bp_save_btn: Button               # r11: save the picked group as a blueprint
var _bp_tools: PanelContainer          # r11: Turn / Place / Cancel while a blueprint is previewed
var _bp_label: Label
var _hint: Label
var _hint_panel: PanelContainer
var _tools_hint: Label                 # what to do, or why not, inside the tools while a thing is held (r8)
var _tools_box: MarginContainer       # positions the placement tools (bottom or top)
var _tools_col: VBoxContainer
var _catalog_box: MarginContainer
## Where the placement tools are: "bottom" (above the toy box; only while nothing is held), and while a
## thing is held "low" (the bottom edge, toy box tucked away) or "top" (under the top bar).
var dock := "bottom"
var _dock_since := 0.0
var _dock_shift := {"low": 0.0, "top": 0.0}   # how far the tools stand from the middle at each place (_fit_tools)
var _pick_frames := 0                  # frames since a thing was picked in which the tools still take their place unseen
var _tools_inner: VBoxContainer        # everything inside the tools' panel (name, line, swatches, buttons): takes no press while unseen
var _top_chips: Array = []             # the holders of the first-steps line, the activity chip and the story/trail chip (top centre)
const FRAME_GAP := 24.0                  # between the tools' two places and the room the camera rests the thing in
const FRAME_MIN := 120.0                 # a lower room than this is no room: the camera rests the thing as before
const DOCK_DWELL := 0.3
const TOP_BAR_H := 104.0
const CAM_GAP := 8.0                     # between the camera buttons and what they keep clear of
const IDEA_GAP := 14.0                   # between the idea line and the child it must not cover
const LOW_MARGIN := 16                   # the tools' distance from the bottom edge in their "low" place
var _toast: PanelContainer
var _toast_label: Label
var _celebration: PanelContainer
var _overlay: Control
var _category := ""
var _ctx := {}
var _photos: Array = []
var _photo_thumbs := {}   # stored photo file name -> scrapbook picture (loaded when the scrapbook opens)
var _toast_tw: Tween
const TOAST_TOP := 196.0                 # the toast's usual distance from the top of the safe area
var _toast_until := 0.0               # while a message shows, name tags keep out of its way


func _ready() -> void:
	UI.fit_safe_area(self)
	get_viewport().size_changed.connect(func(): UI.fit_safe_area(self))
	get_viewport().size_changed.connect(func(): _fit_context_row.call_deferred())   # thousand-town
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	_build_top()
	_build_bottom()
	_build_catalog()
	_build_tools()
	_build_messages()
	_build_thousand_play()
	# Landmark name tags live just above the world and under every other HUD part,
	# so messages and controls are never drawn over by a tag (PT-AH-001).
	_tag_layer = Control.new()
	_tag_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag_layer)
	move_child(_tag_layer, 0)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	Session.players_changed.connect(_refresh_friends)
	Session.saved.connect(func(_ok): _refresh_status())
	Session.connection_changed.connect(_on_connection)
	Session.lantern_lit.connect(_on_lantern)
	Session.request_failed.connect(func(e): show_hint(e))
	Session.rejected.connect(_on_rejected)
	Session.evening_changed.connect(func(_on): _refresh_lanterns())
	I18n.locale_changed.connect(func(_c): _refresh_texts())


func bind(c: Node, t: Node) -> void:
	controller = c
	thumbs = t
	controller.context_changed.connect(_on_context)
	controller.mode_changed.connect(_on_mode)
	controller.ghost_changed.connect(_on_ghost)
	controller.journey.connect(_on_journey)
	controller.look_changed.connect(_on_look)
	controller.city_look_changed.connect(func(_on): _refresh_city_look())   # city r2
	controller.thousand_look_changed.connect(func(_on): _refresh_thousand())   # thousand-town
	if controller.get("thousand_play"):
		controller.thousand_play.changed.connect(_refresh_thousand_play)   # thousand-town interactions
	var thousand_node := get_node_or_null("/root/Thousand")
	if thousand_node and thousand_node.has_signal("updated"):
		thousand_node.updated.connect(func(_states): _refresh_thousand())   # a friend may change the time
	var city_node := get_node_or_null("/root/City")
	if city_node and city_node.has_signal("updated"):
		city_node.updated.connect(func(_states): _refresh_city_weather())   # city r3: a friend may change it
	controller.hint.connect(show_hint)
	controller.toast.connect(show_toast)
	controller.confirm_remove.connect(_confirm_remove)
	controller.item_placed.connect(_remember)
	controller.choose_item.connect(open_chooser)
	controller.space_changed.connect(func(s):
		_rebuild_catalog_tabs()
		_refresh_location()
		_offer_world_actions(s)   # dest-fix r1, unified r6: only this map's actions (back on return)
		for i in 2:
			_cam_tools.get_child(i).visible = Places.is_map(s))
	_offer_world_actions(controller.space)
	controller.undo_changed.connect(func(a): _undo_btn.disabled = not a)
	controller.open_panel.connect(_open_panel)
	controller.ask_display.connect(_ask_display)
	controller.blueprint_changed.connect(_on_blueprint)
	Session.invited.connect(_on_invited)
	Session.invite_joined.connect(func(nick, _kind):
		Sfx.play("place")
		show_toast(tr("%s joined you!") % tr(nick)))
	Session.leaves_jumped.connect(func(_id, peer, together):
		if peer == Session.my_id and together:
			show_toast("You jumped in together!"))
	Session.music_parts_changed.connect(func(id, _parts):
		if _overlay.get_node_or_null("Music") != null and _overlay.get_node("Music").get_meta("item_id", "") == id:
			_refresh_music_grid(id))
	controller.world.play_fx.track_hint.connect(show_hint)
	controller.world.ride_fx.ride_hint.connect(show_hint)
	controller.item_placed.connect(func(_kind): first_step_done("build"))
	_load_first_steps()
	Session.puzzle_changed.connect(_on_puzzle_changed)
	Session.lamplight.connect(func(_by): show_toast("Every lamp is lit. The fireflies have come!"))
	Session.trail_changed.connect(_on_trail)
	Session.item_changed.connect(func(item):
		if item.get("kind", "") == "music_box" and _overlay.get_node_or_null("Music") != null \
				and _overlay.get_node("Music").get_meta("item_id", "") == item["id"]:
			_refresh_music_grid(item["id"]))
	controller.space_changed.connect(func(_s): _refresh_display())
	controller.mode_changed.connect(func(_m): _refresh_display())
	controller.space_changed.connect(func(_s): _refresh_heart())
	Activities.message.connect(show_toast)
	Activities.hs_changed.connect(_refresh_activity)
	Activities.warmth_changed.connect(func(_l, _a): _refresh_activity())
	Activities.party_changed.connect(func(_on): _refresh_activity())
	Activities.hs_found.connect(func(nick): show_toast(tr("%s found the golden acorn!") % tr(nick)))
	Activities.hs_ended.connect(func(reason):
		if reason == "hider_left":
			show_toast("The hider went home. The acorn rolled back to the stump.")
		elif reason == "stopped":
			show_toast("Hide and seek is over. Play again any time!"))
	Activities.wish_done.connect(_on_wish_done)
	Session.gift_opened.connect(func(_id, from_nick, _peer): show_toast(tr("A present from %s!") % tr(from_nick)))
	Session.cooking_changed.connect(func(_stove, recipe, on):
		if on:
			show_toast(tr("Cooking: %s…") % tr(Cooking.RECIPES.get(recipe, {}).get("name", ""))))
	Session.cooked.connect(func(_stove, _dish, recipe, _nick, _peer):
		Sfx.play("place")
		show_toast(tr("%s is ready! Tap it to eat.") % tr(Cooking.RECIPES.get(recipe, {}).get("name", ""))))
	Session.ate.connect(func(peer, _kind):
		if peer == Session.my_id:
			Sfx.play("pop")
			show_toast("Yum! That was delicious."))
	Session.snack_shared.connect(func(peer, _kind, space, _at, nick):
		if controller.space == space:
			Sfx.play("place")
			show_toast("You shared a snack! Everyone close by cheered." if peer == Session.my_id else tr("%s shared a snack!") % tr(nick)))
	Session.pet_happy.connect(func(_owner, _pet, action, _nick):
		Sfx.play("pop" if action == "pat" else "place"))
	Session.town_data_changed.connect(func(key):
		if key == "pets" and _overlay.get_node_or_null("Pets") != null:
			open_pets())
	Session.town_data_changed.connect(func(key):
		if key == "hearts":
			_refresh_heart()
		if key == "display":
			_refresh_display()
		if key == "wishes":
			_rebuild_catalog_tabs())
	if not thumbs.is_done:
		thumbs.finished.connect(_rebuild_cards)
	_on_mode("play")
	_set_dock("bottom")
	Session.joined.connect(func(_id):
		_refresh_heart()
		_refresh_activity())
	Session.joined.connect(func(_id): _zoo_intro_line())
	_refresh_texts()


func _corner(preset: int, margin := 16) -> MarginContainer:
	var m := MarginContainer.new()
	UI.pin(m, preset)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	return m


# ------------------------------------------------------------- top bar

func _build_top() -> void:
	var left := _corner(Control.PRESET_TOP_LEFT)
	var left_stack := VBoxContainer.new()
	left_stack.add_theme_constant_override("separation", 10)
	left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_stack.name = "LeftMenu"   # named for the tours' logs (side menus, r10)
	left.add_child(left_stack)
	_left_stack = left_stack
	var p := UI.panel(24)
	left_stack.add_child(p)
	# How to play: just under the friends, on every screen and in both modes.
	_guide_btn = UI.button("Activities", "guide", false, 0)
	_guide_btn.custom_minimum_size.y = 64
	_guide_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_guide_btn.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 32, 2, UI.SOFT.darkened(0.08), 0.12))
	_guide_btn.pressed.connect(func():
		Sfx.play("tap")
		open_guide())
	left_stack.add_child(_guide_btn)
	_pets_btn = UI.button("Pets", "paw", false, 0)
	_pets_btn.custom_minimum_size.y = 64
	_pets_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pets_btn.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 32, 2, UI.SOFT.darkened(0.08), 0.12))
	_pets_btn.pressed.connect(func():
		Sfx.play("tap")
		open_pets())
	left_stack.add_child(_pets_btn)
	_dress_btn = UI.button("Dress up", "friends", false, 0)
	_dress_btn.custom_minimum_size.y = 64
	_dress_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_dress_btn.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 32, 2, UI.SOFT.darkened(0.08), 0.12))
	_dress_btn.pressed.connect(func():
		Sfx.play("tap")
		open_dress_up())
	left_stack.add_child(_dress_btn)
	_story_btn = UI.button("Story", "book", false, 0)
	_story_btn.custom_minimum_size.y = 64
	_story_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_story_btn.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 32, 2, UI.SOFT.darkened(0.08), 0.12))
	_story_btn.pressed.connect(func():
		Sfx.play("tap")
		open_story_cards())
	left_stack.add_child(_story_btn)
	# A hello for friends who are not here now (friend echoes): in the menu column, under Story.
	_echo_btn = UI.button("Hello", "wave", false, 0)
	_echo_btn.name = "LeaveHello"
	_echo_btn.custom_minimum_size.y = 64
	_echo_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_echo_btn.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 32, 2, UI.SOFT.darkened(0.08), 0.12))
	_echo_btn.pressed.connect(func():
		Sfx.play("tap")
		if Session.model.echoes.has(Session.my_pid):
			_open_echo(Session.my_pid)
		else:
			_open_echo_recorder())
	left_stack.add_child(_echo_btn)
	var row := HBoxContainer.new()
	p.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UI.icon("friends", 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var left_col := VBoxContainer.new()
	row.add_child(left_col)
	_friends = HBoxContainer.new()
	left_col.add_child(_friends)
	# Which floor and room of a cottage the child is in.
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 10)
	left_col.add_child(loc_row)
	_location = UI.label("", 22, UI.ACCENT)
	_location.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_location.visible = false
	loc_row.add_child(_location)
	# unified r4 (Apple TV feedback): Thousand Town's clock and what its time buttons do, in words. The four time
	# buttons are icons whose names show only as tooltips, which a TV never shows; the clock itself was nowhere.
	_thousand_clock = UI.label("", 18, UI.TEXT)
	_thousand_clock.name = "ThousandClock"
	_thousand_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_thousand_clock.visible = false
	left_col.add_child(_thousand_clock)
	# Always available in the zoo: the way back (design 9.2, 11.3).
	_ride_home = UI.button("Ride home", "tram", false, 0)
	_ride_home.custom_minimum_size.y = 52
	UI.style_destination(_ride_home, false)   # unified r6: the way home looks like the stop's destinations
	_ride_home.visible = false
	_ride_home.pressed.connect(func():
		Sfx.play("tap")
		controller.ride(Places.TOWN))
	loc_row.add_child(_ride_home)
	_zoo_invite = UI.button("Invite friends", "friends", false, 0)
	_zoo_invite.custom_minimum_size.y = 52
	_zoo_invite.visible = false
	_zoo_invite.set_meta("invite", "zoo")
	_zoo_invite.pressed.connect(func():
		Sfx.play("tap")
		_send_invite("zoo", ""))
	loc_row.add_child(_zoo_invite)

	var right := _corner(Control.PRESET_TOP_RIGHT)
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_END
	rrow.name = "TopBar"
	right.add_child(rrow)
	_top_right = rrow
	var sp := UI.panel(24)
	rrow.add_child(sp)
	var srow := HBoxContainer.new()
	sp.add_child(srow)
	_status_icon = TextureRect.new()
	_status_icon.texture = UI.icon("saved", 36)
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	srow.add_child(_status_icon)
	_status = UI.label("", 20, UI.MUTED)
	srow.add_child(_status)
	_lantern_btn = UI.button("", "lantern")
	_lantern_btn.tooltip_text = "Scrapbook"
	_lantern_btn.pressed.connect(open_scrapbook)
	rrow.add_child(_lantern_btn)
	var photo := UI.icon_button("camera", "Take a photo")
	photo.pressed.connect(func(): photo_requested.emit())
	rrow.add_child(photo)
	var sound := UI.icon_button("music", "Sound and music")
	sound.pressed.connect(open_sound)
	rrow.add_child(sound)
	var lang := UI.icon_button("globe", "Language")
	lang.pressed.connect(open_language)
	rrow.add_child(lang)
	var leave := UI.icon_button("leave", "Leave town")
	leave.name = "LeaveTown"
	leave.pressed.connect(func(): leave_requested.emit())
	rrow.add_child(leave)

	# Camera controls on the right edge, where a thumb rests while holding an iPad.
	var mid := MarginContainer.new()
	UI.pin(mid, Control.PRESET_CENTER_RIGHT)
	mid.add_theme_constant_override("margin_right", 16)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)
	_cam_tools = VBoxContainer.new()
	_cam_tools.name = "CameraButtons"
	mid.add_child(_cam_tools)
	_cam_margin = mid
	# city r3: the city's weather, three small glass buttons just inside the camera column (shared weather).
	var wmid := MarginContainer.new()
	UI.pin(wmid, Control.PRESET_CENTER_RIGHT)
	wmid.add_theme_constant_override("margin_right", 16 + 68 + 12)
	wmid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wmid)
	_city_weather = VBoxContainer.new()
	_city_weather.name = "CityWeather"
	_city_weather.add_theme_constant_override("separation", 8)
	_city_weather.visible = false
	wmid.add_child(_city_weather)
	for i in CityMap.WEATHERS.size():
		var wname: String = CityMap.WEATHERS[i]
		var b := UI.icon_button({"sunny": "sun", "rain": "rain", "night": "moon"}[wname], {"sunny": "Sunny", "rain": "Rain", "night": "Night"}[wname], 52)
		b.name = "Weather_" + wname
		for st in ["normal", "hover", "pressed"]:
			var glass := UI.box(Color(1, 1, 1, 0.34 if st == "normal" else 0.5), 26, 2, Color(1, 1, 1, 0.75))
			glass.content_margin_left = 6
			glass.content_margin_right = 6
			glass.content_margin_top = 6
			glass.content_margin_bottom = 6
			b.add_theme_stylebox_override(st, glass)
		var wi := i
		b.pressed.connect(func():
			Sfx.play("tap")
			var city := get_node_or_null("/root/City")
			if city and city.has_method("set_weather"):
				city.set_weather(wi))
		_city_weather.add_child(b)
		_city_weather_btns.append(b)
	# thousand-town: the town's time, four glass buttons in the same place (design/thousand-town.md section 4).
	var tmid := MarginContainer.new()
	UI.pin(tmid, Control.PRESET_CENTER_RIGHT)
	tmid.add_theme_constant_override("margin_right", 16 + 68 + 12)
	tmid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tmid)
	_thousand_time = VBoxContainer.new()
	_thousand_time.name = "ThousandTime"
	_thousand_time.add_theme_constant_override("separation", 8)
	_thousand_time.visible = false
	tmid.add_child(_thousand_time)
	for spec in [["day", "sun", "Day"], ["dusk", "sunset", "Dusk"], ["night", "moon", "Night"], ["auto", "auto", "Auto"]]:
		var tb := UI.icon_button(spec[1], spec[2], 52)
		tb.name = "Time_" + spec[0]
		for st in ["normal", "hover", "pressed"]:
			# unified r6: focused (under the pointer) takes the shared focus ring, pressed the accent border
			var glass := UI.box(Color(1, 1, 1, 0.34 if st == "normal" else 0.5), 26, {"normal": 2, "hover": UI.FOCUS_W, "pressed": 3}[st],
				{"normal": Color(1, 1, 1, 0.75), "hover": UI.FOCUS_RING, "pressed": UI.ACCENT}[st])
			glass.content_margin_left = 6
			glass.content_margin_right = 6
			glass.content_margin_top = 6
			glass.content_margin_bottom = 6
			tb.add_theme_stylebox_override(st, glass)
		var tmode: String = spec[0]
		tb.pressed.connect(func(): press_time(tmode))
		_thousand_time.add_child(tb)
		_thousand_time_btns[tmode] = tb
	# the Auto button's speed: a small badge at its corner
	_thousand_speed = UI.label("", 15, UI.TEXT)
	_thousand_speed.name = "SpeedBadge"
	_thousand_speed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_thousand_speed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thousand_speed.position = Vector2(30, 32)
	_thousand_speed.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	_thousand_speed.add_theme_constant_override("outline_size", 6)
	(_thousand_time_btns["auto"] as Button).add_child(_thousand_speed)
	for spec in [["rotate_left", "Rotate view left", -1], ["rotate_right", "Rotate view right", 1], ["zoom", "Zoom", 0]]:
		var b := UI.icon_button(spec[0], spec[1], 68)
		var dir: int = spec[2]
		b.pressed.connect(func():
			if dir == 0:
				controller.rig.toggle_zoom()
			else:
				controller.rig.rotate_step(dir))
		_cam_tools.add_child(b)
	# city r1: back to the overview that fits the whole block (the orbit camera's reset).
	_city_reset = UI.icon_button("home", "Reset view", 68)
	_city_reset.name = "CityReset"
	_city_reset.visible = false
	_city_reset.pressed.connect(func():
		Sfx.play("tap")
		controller.rig.city_reset())
	_cam_tools.add_child(_city_reset)
	_city_look = UI.icon_button("look", "Look around", 68)
	_city_look.name = "CityLook"
	_city_look.visible = false
	_city_look.pressed.connect(func():
		Sfx.play("tap")
		controller.set_city_look(not controller.city_looking))
	_cam_tools.add_child(_city_look)
	_city_pause = UI.icon_button("pause", "Pause the city", 68)
	_city_pause.name = "CityPause"
	_city_pause.visible = false
	_city_pause.pressed.connect(func():
		Sfx.play("tap")
		controller.set_city_paused(not controller.city_paused)
		_refresh_city_look())
	_cam_tools.add_child(_city_pause)
	# thousand-town: Look flies to an overview of the whole town, and back behind the child.
	_thousand_look = UI.icon_button("look", "Look around", 68)
	_thousand_look.name = "ThousandLook"
	_thousand_look.visible = false
	_thousand_look.pressed.connect(func():
		Sfx.play("tap")
		controller.set_thousand_look(not controller.thousand_looking))
	_cam_tools.add_child(_thousand_look)
	_heart_btn = UI.icon_button("heart", "Leave a heart in this room", 68)
	_heart_btn.pressed.connect(func():
		Sfx.play("pop")
		Session.toggle_heart(controller.space))
	_heart_btn.visible = false
	_cam_tools.add_child(_heart_btn)


func _refresh_friends() -> void:
	for c in _friends.get_children():
		c.queue_free()
	var peers := Session.players.keys()
	peers.sort()
	for peer in peers:
		var av: Dictionary = Session.players[peer]["avatar"]
		var chip := PanelContainer.new()
		var s := UI.box(Palette.paint(av["outfit_color"]).lerp(UI.PANEL, 0.55), 18)
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.content_margin_left = 12
		s.content_margin_right = 12
		if peer == Session.my_id:
			s.set_border_width_all(3)
			s.border_color = UI.ACCENT
		chip.add_theme_stylebox_override("panel", s)
		var crow := HBoxContainer.new()
		chip.add_child(crow)
		crow.add_child(UI.label(av["nick"], 22))
		# A friend on the other map (design 11.3): a paw while they are in the zoo, a house while
		# you are in the zoo and they are in town.
		if peer != Session.my_id and controller:
			var their: String = Places.map_of(str(Session.players[peer].get("state", {}).get("space", "town")))
			var mine: String = Places.map_of(controller.space)
			if their != mine and their != "":
				var ic := TextureRect.new()
				ic.texture = UI.icon("paw" if their == Places.ZOO else "home", 28)
				ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				crow.add_child(ic)
		_friends.add_child(chip)
	_refresh_status()


func _refresh_status() -> void:
	var text := ""
	var icon := "saved"
	if Session.state == "connecting":
		text = tr("Connecting…")
		icon = "warn"
	elif Session.state != "online":
		text = tr("Disconnected from the town")
		icon = "warn"
	elif not Session.last_save_ok:
		text = tr("Not saved yet. Trying again…")
		icon = "warn"
	else:
		text = tr("Town saved")
	if Session.mode == "solo":
		text += " · " + tr("Playing alone")
	elif Session.mode in ["client", "host"]:
		text += " · " + tr("%d of %d friends") % [Session.players.size(), Session.MAX_PLAYERS]
	_status.text = text
	_status_icon.texture = UI.icon(icon, 36)


## dest-fix r1 / unified r6: the actions this map offers (Places.offers); the others are hidden, so they are neither
## D-pad targets (PadInput.targets) nor tappable. Decorate is not offered in the cities and Thousand Town; Pets,
## Story, Hello and the lantern scrapbook not in Thousand Town. All come back on the return.
func _offer_world_actions(space: String) -> void:
	_decorate_btn.visible = Places.offers(space, "decorate")
	_pets_btn.visible = Places.offers(space, "pets")
	_story_btn.visible = Places.offers(space, "story")
	_echo_btn.visible = Places.offers(space, "hello")
	_lantern_btn.visible = Places.offers(space, "scrapbook")


func _refresh_lanterns() -> void:
	_lantern_btn.text = "%d / %d" % [Session.model.lanterns.size(), CozySpots.SPOTS.size()]


func _on_connection(state: String) -> void:
	_refresh_status()
	if state == "disconnected":
		_dialog("Disconnected from the town", "Decorating is paused until we reconnect.",
			[["Reconnect", func(): reconnect_requested.emit(), true], ["Back to start", func(): leave_requested.emit(), false]])


func _on_rejected(reason: String) -> void:
	var body := "Four friends are playing. Try again a little later." if reason == "The town is full right now" else ""
	_dialog(reason, body, [["Back to start", func(): leave_requested.emit(), true]])


# ------------------------------------------------------------- bottom bar

func _build_bottom() -> void:
	var bl := _corner(Control.PRESET_BOTTOM_LEFT)
	var bl_col := VBoxContainer.new()
	bl_col.alignment = BoxContainer.ALIGNMENT_END
	bl_col.name = "PosesAndEmotes"
	bl.add_child(bl_col)
	_bottom_left = bl_col
	_poses = HBoxContainer.new()
	_poses.visible = false
	bl_col.add_child(_poses)
	for pose in Avatar.POSES:
		var pb := UI.button(Avatar.POSE_NAMES[pose], "", false, 0)
		pb.custom_minimum_size.y = 56
		pb.set_meta("pose", pose)
		var pk: String = pose
		pb.pressed.connect(func(): Session.send_emote(pk))
		_poses.add_child(pb)
	_emotes = HBoxContainer.new()
	bl_col.add_child(_emotes)
	for e in [["wave", "Wave"], ["cheer", "Cheer"], ["dance", "Dance"], ["heart", "Love"]]:
		var b := UI.icon_button(e[0], e[1])
		var kind: String = e[0]
		b.pressed.connect(func(): Session.send_emote(kind))
		_emotes.add_child(b)

	var bc := _corner(Control.PRESET_CENTER_BOTTOM, 24)
	_context_btn = UI.button("", "door", true, 260)
	_context_btn.custom_minimum_size.y = 88
	_context_btn.add_theme_font_size_override("font_size", 28)
	_context_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.do_context())
	# thousand-town: the tram stop offers up to four journeys; when one row of them would run under the corner
	# columns (emotes at the left, Decorate at the right), the third and fourth go on a row above (_fit_context_row).
	var ctx_col := VBoxContainer.new()
	ctx_col.alignment = BoxContainer.ALIGNMENT_END
	ctx_col.add_theme_constant_override("separation", 12)
	ctx_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(ctx_col)
	_ctx_row2 = HBoxContainer.new()
	_ctx_row2.name = "ContextRow2"
	_ctx_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	_ctx_row2.add_theme_constant_override("separation", 14)
	_ctx_row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctx_row2.visible = false
	ctx_col.add_child(_ctx_row2)
	var ctx_row := HBoxContainer.new()
	ctx_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctx_row.add_theme_constant_override("separation", 14)
	ctx_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx_col.add_child(ctx_row)
	_ctx_row = ctx_row
	# unified r1: the tram stop's two local destinations, Workshop r4's Roller Coaster Workshop and the Lantern
	# Reef, on their own row above the journeys (distinct entries; each returns the child to this stop).
	_station_row = HBoxContainer.new()
	_station_row.name = "StationRow"
	_station_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_station_row.add_theme_constant_override("separation", 14)
	_station_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_station_row.visible = false
	ctx_col.add_child(_station_row)
	ctx_col.move_child(_station_row, 0)
	ctx_row.add_child(_context_btn)
	_context_btn.visible = false
	_context_alt_btn = UI.button("", "stand", false, 190)
	_context_alt_btn.custom_minimum_size.y = 88
	_context_alt_btn.add_theme_font_size_override("font_size", 26)
	_context_alt_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.do_context_alt())
	ctx_row.add_child(_context_alt_btn)
	_context_alt_btn.visible = false
	_context_alt2_btn = UI.button("", "tram", false, 190)
	_context_alt2_btn.name = "ContextAlt2"
	_context_alt2_btn.custom_minimum_size.y = 88
	_context_alt2_btn.add_theme_font_size_override("font_size", 26)
	_context_alt2_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.do_context_alt2())
	ctx_row.add_child(_context_alt2_btn)
	_workshop_btn = UI.button("Roller Coaster Workshop", "tram", true, 160)
	_workshop_btn.name = "WorkshopTram"
	UI.style_destination(_workshop_btn)   # unified r6: one look for the stop's destinations
	_workshop_btn.pressed.connect(func():
		if controller.space == Places.TOWN and controller.journey_to == "" and _ctx.get("type") == "tram" and visible:
			controller.stop_for_workshop()
			var park := preload("res://scripts/world/coaster_park.gd").new()
			park.setup(controller.get_parent()))
	_workshop_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_station_row.add_child(_workshop_btn)
	_workshop_btn.hide()
	_reef_btn = UI.button("Explore the lantern reef", "tram", true, 160)
	_reef_btn.name = "ReefTram"
	UI.style_destination(_reef_btn)
	_reef_btn.pressed.connect(func():
		if controller.space == Places.TOWN and controller.journey_to == "" and _ctx.get("type") == "tram" and visible:
			controller.stop_for_workshop()   # the same clean stop as the Workshop: no walk, no pending action
			reef_requested.emit())
	_reef_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_station_row.add_child(_reef_btn)
	_reef_btn.hide()
	_context_alt2_btn.visible = false
	_context_alt3_btn = UI.button("", "tram", false, 190)
	_context_alt3_btn.name = "ContextAlt3"
	_context_alt3_btn.custom_minimum_size.y = 88
	_context_alt3_btn.add_theme_font_size_override("font_size", 26)
	_context_alt3_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.do_context_alt3())
	ctx_row.add_child(_context_alt3_btn)
	_context_alt3_btn.visible = false

	var br := _corner(Control.PRESET_BOTTOM_RIGHT)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.name = "CornerColumn"
	br.add_child(col)
	_side_col = col
	_display_badge = UI.panel(14, UI.PANEL)
	var badge_l := UI.label("On display", 20, UI.ACCENT)
	badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display_badge.add_child(badge_l)
	_display_badge.visible = false
	col.add_child(_display_badge)
	_display_btn = UI.button("Put on display", "board", false, SIDE_W)
	_display_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_display_btn.visible = false
	_display_btn.pressed.connect(func():
		Sfx.play("tap")
		var on := Session.model.display_by(controller.space).is_empty()
		controller._ask(Session.set_display(controller.space, on), func(r):
			if r.get("ok"):
				show_toast("This place is on display now. Friends will be asked before they change it." if r.get("on") else "This place is not on display any more.")))
	col.add_child(_display_btn)
	_help_btn = UI.button("Ask friends to help", "friends", false, SIDE_W)
	_help_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_btn.visible = false
	_help_btn.pressed.connect(func():
		Sfx.play("tap")
		_send_invite("help", controller.space))
	col.add_child(_help_btn)
	_trail_btn = UI.button("Suggest a trail", "wave", false, SIDE_W)
	_trail_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trail_btn.visible = false
	_trail_btn.pressed.connect(func():
		Sfx.play("tap")
		controller._ask(Session.starter_trail(), func(r):
			if r.get("ok"):
				show_toast("Three trail signs are up. Tap one and follow the trail, or move them anywhere.")
			elif r.get("error", "") != "":
				show_hint(r["error"])
			_refresh_display()))
	col.add_child(_trail_btn)
	_bp_btn = UI.button("Blueprints", "board", false, SIDE_W)
	_bp_btn.visible = false
	_bp_btn.pressed.connect(func():
		Sfx.play("tap")
		open_blueprints())
	col.add_child(_bp_btn)
	_undo_btn = UI.button("Undo", "undo", false, SIDE_W)
	_undo_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(func(): controller.undo())
	col.add_child(_undo_btn)
	_decorate_btn = UI.button("Decorate", "decorate", true, SIDE_W)
	_decorate_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_decorate_btn.custom_minimum_size.y = 88
	_decorate_btn.add_theme_font_size_override("font_size", 28)
	_decorate_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.set_mode("play" if controller.mode == "decorate" else "decorate"))
	col.add_child(_decorate_btn)


func _on_context(ctx: Dictionary) -> void:
	_ctx = ctx
	_workshop_btn.visible = controller.mode == "play" and ctx.get("type") == "tram"
	_reef_btn.visible = _workshop_btn.visible
	_context_btn.visible = not ctx.is_empty() and controller.mode == "play"
	if not ctx.is_empty():
		_context_btn.text = ctx["label"]
		_context_btn.icon = UI.icon(ctx.get("icon", "door"))
	var alt: Dictionary = ctx.get("alt", {})
	_context_alt_btn.visible = _context_btn.visible and not alt.is_empty()
	if not alt.is_empty():
		_context_alt_btn.text = alt["label"]
		_context_alt_btn.icon = UI.icon(alt.get("icon", "stand"))
	var alt2: Dictionary = ctx.get("alt2", {})
	_context_alt2_btn.visible = _context_btn.visible and not alt2.is_empty()
	if not alt2.is_empty():
		_context_alt2_btn.text = alt2["label"]
		_context_alt2_btn.icon = UI.icon(alt2.get("icon", "tram"))
	var alt3: Dictionary = ctx.get("alt3", {})
	_context_alt3_btn.visible = _context_btn.visible and not alt3.is_empty()
	if not alt3.is_empty():
		_context_alt3_btn.text = alt3["label"]
		_context_alt3_btn.icon = UI.icon(alt3.get("icon", "tram"))
	_style_destinations(ctx.get("type") == "tram")
	_fit_context_row()


## unified r6 (Apple TV feedback): at the tram stop every destination (the zoo, the city, the web city, Thousand
## Town, the Workshop, the reef) is one kind of button in the game's theme (UI.style_destination: normal, focused,
## pressed, disabled; the tram icon; one height and text size); elsewhere the action buttons are themselves again.
func _style_destinations(tram: bool) -> void:
	for b: Button in [_context_btn, _context_alt_btn, _context_alt2_btn, _context_alt3_btn]:
		if tram and not b.has_meta("destination"):
			UI.style_destination(b)
			b.set_meta("destination", true)
		elif not tram and b.has_meta("destination"):
			UI.unstyle_destination(b, b == _context_btn, 28 if b == _context_btn else 26)
			b.remove_meta("destination")


## thousand-town: one row of action buttons when it fits between the bottom corners' columns, else the third and
## fourth (the tram stop's web city and Thousand Town) on a row above, so no button runs under Decorate or the emotes
## (seen on the iPad layout: "Ride to Thousand Town" ran under Decorate).
func _fit_context_row() -> void:
	if _ctx_row2 == null or _ctx_row == null:
		return
	for b: Button in [_context_alt2_btn, _context_alt3_btn]:
		if b.get_parent() != _ctx_row:
			b.reparent(_ctx_row, false)
	var area := get_global_rect()
	var left := area.position.x
	if _bottom_left and _bottom_left.is_visible_in_tree():
		left = _bottom_left.get_global_rect().end.x
	var right := area.end.x
	if _side_col and _side_col.is_visible_in_tree() and _side_col.get_combined_minimum_size().x > 0.0:
		right = area.end.x - _side_col.get_combined_minimum_size().x - 16.0
	var half := minf(area.get_center().x - left, right - area.get_center().x) - 12.0
	var wide := _context_alt2_btn.visible or _context_alt3_btn.visible
	if wide and _ctx_row.get_combined_minimum_size().x > 2.0 * half:
		for b: Button in [_context_alt2_btn, _context_alt3_btn]:
			b.reparent(_ctx_row2, false)
	_ctx_row2.visible = _context_alt3_btn.get_parent() == _ctx_row2 and wide
	# unified r1: when the journeys overflow onto the row above, the stop's two local destinations (Workshop, reef)
	# join that row, so every entry is one D-pad move from a neighbour: on a separate third row the cone rule of
	# PadInput.snap never chose the lone "Ride to Thousand Town" between them (the station tour, 1920x1080).
	var into: HBoxContainer = _ctx_row2 if _ctx_row2.visible else _station_row
	for b: Button in [_workshop_btn, _reef_btn]:
		if b.get_parent() != into:
			b.reparent(into, false)
	_station_row.visible = into == _station_row and _workshop_btn.visible


func _on_mode(mode: String) -> void:
	var deco := mode == "decorate"
	_workshop_btn.visible = not deco and _ctx.get("type") == "tram"
	_reef_btn.visible = _workshop_btn.visible
	_decorate_btn.text = "Done" if deco else "Decorate"
	_decorate_btn.icon = UI.icon("check" if deco else "decorate")
	_catalog.visible = deco and dock == "bottom"
	if not deco:
		_search.release_focus()
	_emotes.visible = not deco
	_undo_btn.visible = deco
	_context_btn.visible = not deco and not _ctx.is_empty()
	_context_alt_btn.visible = _context_btn.visible and _ctx.has("alt")
	_context_alt2_btn.visible = _context_btn.visible and _ctx.has("alt2")
	_context_alt3_btn.visible = _context_btn.visible and _ctx.has("alt3")
	_fit_context_row()
	if deco:
		_rebuild_catalog_tabs()
		show_hint("Tap something to move, turn, paint or put it away.")
	else:
		_hint_panel.visible = false


# ------------------------------------------------------------- catalog

## The toy box: a bottom sheet with a search field, one sideways row of tabs and
## placement filters, and the item cards (design/item-browser-ux.md).
func _build_catalog() -> void:
	var m := MarginContainer.new()
	UI.pin(m, Control.PRESET_BOTTOM_WIDE)
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", SIDE_W + 32)
	m.add_theme_constant_override("margin_bottom", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(m)
	_catalog_box = m
	_catalog = UI.panel(24)
	m.add_child(_catalog)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_catalog.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	top.add_child(UI.label("Toy box", 24, UI.ACCENT))
	_search = LineEdit.new()
	_search.placeholder_text = "Find a toy"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(260, 60)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.right_icon = UI.icon("search", 36)
	_search.add_theme_font_size_override("font_size", 22)
	_search.add_theme_color_override("font_placeholder_color", UI.MUTED)
	_search.add_theme_stylebox_override("normal", UI.box(UI.PAPER, 30, 2, UI.SOFT.darkened(0.08)))
	_search.add_theme_stylebox_override("focus", UI.box(UI.PAPER, 30, 3, UI.ACCENT))
	for s in ["normal", "focus"]:
		var sb: StyleBoxFlat = _search.get_theme_stylebox(s)
		sb.content_margin_left = 22
		sb.content_margin_right = 14
	_search.text_changed.connect(func(_t): _search_timer.start())
	_search.text_submitted.connect(func(_t):
		_search.release_focus()
		_apply_search())
	top.add_child(_search)
	# A TV has no keyboard: no search field that cannot be typed in. The category tabs browse everything.
	_search.visible = TvMode.can_type()
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.15
	_search_timer.timeout.connect(_apply_search)
	add_child(_search_timer)
	_count = UI.label("", 20, UI.MUTED)
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	top.add_child(_count)
	_things_btn = UI.button("Things here", "list", false, 0)
	_things_btn.custom_minimum_size.y = 60
	_things_btn.pressed.connect(open_things_here)
	top.add_child(_things_btn)
	var chip_scroll := ScrollContainer.new()
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # still drags sideways
	chip_scroll.custom_minimum_size.y = 62
	col.add_child(chip_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	chip_scroll.add_child(_tabs)
	_card_scroll = ScrollContainer.new()
	_card_scroll.custom_minimum_size = Vector2(0, 150)
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.get_h_scroll_bar().value_changed.connect(func(v):
		if not _row_settling:   # while a rebuilt row is being put back in place, its passing values are not the child's
			_scroll_pos[_view_key()] = v)
	col.add_child(_card_scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	_card_scroll.add_child(_cards)
	_empty = HBoxContainer.new()
	_empty.custom_minimum_size.y = 150
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.add_theme_constant_override("separation", 20)
	_empty_label = UI.label("", 24, UI.TEXT, true)
	_empty_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_empty_label.custom_minimum_size.x = 360
	_empty.add_child(_empty_label)
	_empty_btn = UI.button("Clear search", "close", true, 220)
	_empty_btn.pressed.connect(_reset_browse)
	_empty.add_child(_empty_btn)
	_empty.visible = false
	col.add_child(_empty)
	_recent = _load_recent()
	# The placement tools and hints sit just above the toy box, whatever its height.
	m.resized.connect(func():
		if _tools_box and dock == "bottom":
			_tools_box.add_theme_constant_override("margin_bottom", int(_catalog_height() + 8.0) + _idea_lift))
	_catalog.visible = false


## Tabs for the current space: Recent and Wish when they have something, the
## catalog categories, then All.
func catalog_tabs() -> Array:
	if controller.space == Places.ZOO:
		# The zoo's toy box (design 10.4): its own toys and a few picnic things.
		var zcats: Array = ["Zoo", "Picnic"]
		if _recent.any(func(k): return Catalog.offered(k, controller.space)):
			zcats.push_front("Recent")
		zcats.append("All")
		return zcats
	var cats: Array = (Catalog.TOWN_CATEGORIES if controller.space == "town" else Catalog.HOME_CATEGORIES).duplicate()
	if controller.space == "town" and not Session.model.wishes.get("active", {}).is_empty():
		cats.push_front("Wish")   # what an animal is wishing for, pinned first (nothing else is hidden)
	if _recent.any(func(k): return Catalog.has(k) and Catalog.allowed_in(k, controller.space)):
		cats.push_front("Recent")
	cats.append_array(RoomThemes.toolkits_for(controller.space))
	cats.append("All")
	return cats


func _rebuild_catalog_tabs() -> void:
	if controller == null:
		return
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var cats := catalog_tabs()
	# A Kitchen, Game room or Pet room opens on its own tab when the child arrives.
	if controller.space != _tab_space:
		_tab_space = controller.space
		var themed := RoomThemes.tab_for_room(TownModel.room_name(controller.space))
		if themed != "" and cats.has(themed) and _query == "":
			_category = themed
			_placement = ""
		elif not cats.has(_category) or RoomThemes.ROOM_TAB.values().has(_category):
			_category = ""
	if not cats.has(_category):
		var plain := cats.filter(func(c): return not c in ["Recent", "Wish", "Kitchen", "Games", "Pets"] and not RoomThemes.TOOLKITS.has(c))
		_category = "Wish" if cats.has("Wish") else (plain[0] if not plain.is_empty() else cats[0])
	var searching := _query != ""
	for cat in cats:
		var b := UI.button(cat, "recent" if cat == "Recent" else ("wish" if cat == "Wish" else ""), cat == _category and not searching, 0)
		b.custom_minimum_size.y = 56
		b.set_meta("tab", cat)
		var c2: String = cat
		b.pressed.connect(func():
			Sfx.play("tap")
			_category = c2
			_placement = ""
			_set_query("")
			if RoomThemes.TOOLKIT_IDEAS.has(c2):
				show_hint(RoomThemes.TOOLKIT_IDEAS[c2]))
		_tabs.add_child(b)
	# Placement filters derived from the catalog; only the ones that split the results.
	var base := current_kinds("")
	var chips := ItemQuery.placement_chips(Catalog.ITEMS, base) if _category != "Wish" else []
	if not chips.any(func(c): return c["id"] == _placement):
		_placement = ""
	if not chips.is_empty():
		var sep := VSeparator.new()
		sep.custom_minimum_size.x = 12
		_tabs.add_child(sep)
	for chip in chips:
		var on: bool = chip["id"] == _placement
		var b := UI.button(ItemQuery.PLACEMENTS[chip["id"]], "", on, 0)
		b.custom_minimum_size.y = 56
		b.set_meta("placement", chip["id"])
		if not on:
			b.add_theme_stylebox_override("normal", UI.box(UI.PAPER, 28, 2, UI.SOFT.darkened(0.1)))
		var id: String = chip["id"]
		b.pressed.connect(func():
			Sfx.play("tap")
			_placement = "" if _placement == id else id   # tapping the active filter turns it off
			_rebuild_catalog_tabs())
		_tabs.add_child(b)
	_rebuild_cards()


## The kinds the toy box shows right now (or for another placement filter).
func current_kinds(placement = null) -> Array:
	var p: String = _placement if placement == null else placement
	# offered(): allowed here and in the toy box at all (the tram stop is a landmark, never offered).
	var allowed := func(k): return Catalog.offered(k, controller.space)
	if controller.space == Places.ZOO and _category == "Picnic" and _query == "":
		return Catalog.ZOO_PICNIC.filter(func(k): return Catalog.has(k) and allowed.call(k) and (p == "" or ItemQuery.in_placement(Catalog.ITEMS[k], p)))
	if _category == "Wish" and _query == "":
		var out := []
		for k in Wishes.find(Session.model.wishes.get("active", {}).get("id", "")).get("kinds", []):
			if not out.has(k) and allowed.call(k) and (p == "" or ItemQuery.in_placement(Catalog.ITEMS[k], p)):
				out.append(k)
		return out
	return ItemQuery.query(Catalog.ITEMS, allowed, _category, p, _query, func(t): return tr(t), _recent, RoomThemes.extra_for(_category))


func _view_key() -> String:
	return "%s|%s|%s|%s" % [controller.space if controller else "", _category, _placement, _query]


func _rebuild_cards() -> void:
	if controller == null:
		return
	var key := _view_key()
	# Where the row goes after the rebuild. The same view rebuilt for another reason (an animal's wish
	# adds a tab, a language change, a thing placed) stays exactly where it is on screen, so no card
	# slides under a finger; only coming to a different tab, filter or search returns to the place
	# remembered for it. (Mac run of town-play r1: the remembered place was used for every rebuild, and
	# it could differ from the screen.)
	var at: float = _scroll_pos.get(key, 0.0)
	if key == _cards_key:
		at = _row_target if _row_settling else float(_card_scroll.scroll_horizontal)
	_cards_key = key
	_row_target = at
	_row_settling = true
	_row_gen += 1
	var gen := _row_gen
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var kinds := current_kinds()
	_count.text = tr("1 thing") if kinds.size() == 1 else tr("%d things") % kinds.size()
	_empty.visible = kinds.is_empty()
	_card_scroll.visible = not kinds.is_empty()
	if kinds.is_empty():
		if _query != "":
			_empty_label.text = tr("Nothing matches “%s”.") % _query
			_empty_btn.text = "Clear search"
		else:
			_empty_label.text = tr("Nothing like that here.")
			_empty_btn.text = "Show all"
	for kind in kinds:
		_cards.add_child(_card(kind))
	# Put the row in its place. One frame is not always enough: until the new cards are laid out the row
	# cannot scroll that far and the request is silently cut short (seen on the Mac), so it is repeated
	# for a few frames until it holds. A newer rebuild takes over at once.
	for attempt in 8:
		await get_tree().process_frame
		if gen != _row_gen or not is_instance_valid(_card_scroll) or key != _view_key():
			return
		if _put_row(at) and attempt >= 1:
			break
	_row_settling = false
	_scroll_pos[key] = float(_card_scroll.scroll_horizontal)   # memory and screen agree


## Scrolls the card row to `at`, or as near as its cards allow; true when it is there and the row's
## range is that of its cards. The scroll container's own range is not trusted: after the cards are
## replaced it can stay that of the previous tab's cards for as long as nothing asks it to sort again
## (traced on EC2 at the iPad layout: cards 1836 wide, range still 1268, so the row stopped at 226
## instead of 794; in other runs the range stayed too long instead). So the cards' own width says how
## far the row can go, and a range that differs is asked to sort again.
func _put_row(at: float) -> bool:
	if not _card_scroll.is_visible_in_tree():
		return true
	var bar := _card_scroll.get_h_scroll_bar()
	var content: float = _cards.get_combined_minimum_size().x
	var goal: float = clampf(at, 0.0, maxf(content - _card_scroll.size.x, 0.0))
	var range_fits: bool = absf(bar.max_value - content) < 1.0
	if not range_fits:
		_card_scroll.queue_sort()
	_card_scroll.scroll_horizontal = int(goal)
	return range_fits and absf(_card_scroll.scroll_horizontal - goal) < 1.0


## Toy box card text area: width inside the card and the name's sizes and lines (see _card).
const CARD_TEXT_W := 120.0
const CARD_NAME_LINES := 3
const CARD_NAME_SIZES := [16, 15, 14, 13]


func _card(kind: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(132, 150)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("kind", kind)
	b.tooltip_text = Catalog.ITEMS[kind]["name"]
	if kind == _last_kind:
		b.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 16, 4, UI.ACCENT))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_right = -6
	col.offset_top = 6
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.texture = thumbs.textures.get(kind)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 92)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	# The whole name, broken only between words (r13 Mac: two "Hängelampe mit..." cards could not be
	# told apart, and long German words broke mid-word): the font steps down to 13 px for up to
	# three lines, and the card widens only when a single word is wider than it (UI.fit_text).
	var fit := UI.fit_text(I18n.ui_font(), tr(Catalog.ITEMS[kind]["name"]), CARD_TEXT_W, CARD_NAME_LINES, CARD_NAME_SIZES)
	var name := UI.label(Catalog.ITEMS[kind]["name"], fit["size"], UI.TEXT, true)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD
	name.add_theme_constant_override("line_spacing", 0)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.max_lines_visible = CARD_NAME_LINES
	name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	name.custom_minimum_size.y = fit["height"]
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.set_meta("fit", fit)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, fit["width"] + 12.0)
	pic.custom_minimum_size.y = maxf(64.0, b.custom_minimum_size.y - 12.0 - 2.0 - fit["height"])
	col.add_child(name)
	b.pressed.connect(func():
		Sfx.play("tap")
		_search.release_focus()
		_last_kind = kind
		controller.begin_new(kind)
		_mark_last())
	return b


## Outline only the card of the item just taken (no rebuild, the row stays put).
func _mark_last() -> void:
	for b in _cards.get_children():
		if b.get_meta("kind", "") == _last_kind:
			b.add_theme_stylebox_override("normal", UI.box(UI.PANEL, 16, 4, UI.ACCENT))
		else:
			b.remove_theme_stylebox_override("normal")


func _apply_search() -> void:
	if _search.text.strip_edges() != _query:
		_query = _search.text.strip_edges()
		_rebuild_catalog_tabs()


func _set_query(text: String) -> void:
	_search.text = text
	_search.release_focus()
	_query = text
	_rebuild_catalog_tabs()


## Clear search and filters, keeping the tab (empty-state button).
func _reset_browse() -> void:
	Sfx.play("tap")
	_placement = ""
	_set_query("")


## Remembers an item this device just placed (Recent tab; not part of the town).
func _remember(kind: String) -> void:
	var was_empty := _recent.is_empty()
	_recent = ItemQuery.remember(_recent, kind)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("toybox", "recent", _recent)
	cfg.save(SETTINGS_PATH)
	if was_empty or _category == "Recent":
		_rebuild_catalog_tabs()


func _load_recent() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return []
	var r = cfg.get_value("toybox", "recent", [])
	return (r as Array).filter(func(k): return k is String and Catalog.has(k)) if r is Array else []


# ------------------------------------------------------------- first steps

func _load_first_steps() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK or not cfg.has_section("first_steps"):
		# Nothing stored yet: a beginner, unless this device's toy box already remembers things built.
		first_steps = FirstSteps.initial(not _load_recent().is_empty())
		return
	var stored := {}
	for k in FirstSteps.fresh():
		stored[k] = cfg.get_value("first_steps", k, false)
	first_steps = FirstSteps.sanitize(stored)


func _save_first_steps() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for k in first_steps:
		cfg.set_value("first_steps", k, first_steps[k])
	cfg.save(SETTINGS_PATH)


## The child did one of the first steps (walked, placed a first thing, opened Activities).
func first_step_done(step: String) -> void:
	if not first_steps_enabled or not FirstSteps.mark(first_steps, step):
		return
	_save_first_steps()
	if FirstSteps.all_done(first_steps) and not first_steps["hidden"]:
		show_toast(FirstSteps.PRAISE)


## Shows the line for the step the child has not done yet; notices walking.
func _tick_first_steps() -> void:
	var step := FirstSteps.current(first_steps) if first_steps_enabled else ""
	var playing: bool = controller != null and controller.world != null and Session.is_online() and Session.players.has(Session.my_id)
	var show: bool = step != "" and playing and visible and _overlay.get_child_count() == 0 and not _activity_chip.visible
	if _first_chip.visible != show:
		_first_chip.visible = show
	if not playing or step == "":
		_first_from = null
		return
	if step == "walk":
		if _first_from == null or _first_from[0] != controller.space:
			_first_from = [controller.space, controller.pos]
		elif controller.pos.distance_to(_first_from[1]) >= FirstSteps.WALK_METERS:
			first_step_done("walk")
	var stick: bool = pad_layer != null and pad_layer.shown   # a controller is in use right now
	var text := FirstSteps.line(step, stick, controller.mode == "decorate")
	if _first_label.text != text:
		_first_label.text = text
		_first_icon.texture = UI.icon(FirstSteps.icon(step), 44)


## Height of the on-screen keyboard in HUD units (0 when hidden).
func keyboard_height() -> float:
	if debug_keyboard_height > 0.0:
		return debug_keyboard_height
	var px := float(DisplayServer.virtual_keyboard_get_height())
	if px <= 0.0:
		return 0.0
	var win := float(DisplayServer.window_get_size().y)
	return px * get_viewport_rect().size.y / win if win > 0.0 else px


## While the child types, the toy box rises above the keyboard.
func _lift_for_keyboard() -> void:
	var kb := keyboard_height() if _search.has_focus() else 0.0
	var want := int(16.0 + kb)
	if _catalog_box.get_theme_constant("margin_bottom") != want:
		_catalog_box.add_theme_constant_override("margin_bottom", want)


# ------------------------------------------------------------- placement tools

func _build_tools() -> void:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	_tools_box = m
	var col := VBoxContainer.new()
	m.add_child(col)
	_tools_col = col
	_hint_panel = UI.panel(20, UI.PANEL)
	_hint = UI.label("", 22, UI.TEXT, true)
	_hint.custom_minimum_size.x = 420
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_panel.add_child(_hint)
	_hint_panel.visible = false
	col.add_child(_hint_panel)
	_tools = UI.panel(24)
	col.add_child(_tools)
	var tcol := VBoxContainer.new()
	_tools.add_child(tcol)
	_tools_inner = tcol
	_tools_name = UI.label("", 20, UI.ACCENT)
	_tools_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tcol.add_child(_tools_name)
	# What to do, or why the thing cannot go here. Until first-steps r7 this line was a panel of its own
	# above the tools; inside the tools the block is 77 px lower, which leaves enough room between its
	# two places for the thing and for the child (see _process).
	_tools_hint = UI.label("", 22, UI.TEXT, true)
	_tools_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tools_hint.visible = false
	tcol.add_child(_tools_hint)
	_swatches = HBoxContainer.new()
	_swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_child(_swatches)
	for i in Palette.PAINT.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(60, 60)
		sw.tooltip_text = Palette.PAINT[i]["name"]
		sw.focus_mode = Control.FOCUS_NONE
		sw.add_theme_stylebox_override("normal", UI.box(Palette.paint(i), 30, 3, UI.PANEL))
		sw.add_theme_stylebox_override("hover", UI.box(Palette.paint(i), 30, 4, UI.ACCENT))
		sw.add_theme_stylebox_override("pressed", UI.box(Palette.paint(i), 30, 5, UI.TEXT))
		var idx := i
		sw.pressed.connect(func():
			Sfx.play("tap")
			controller.paint_ghost(idx))
		_swatches.add_child(sw)
	_swatches.visible = false
	_tools_row = HFlowContainer.new()
	_tools_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_tools_row.add_theme_constant_override("h_separation", 4)
	_tools_row.add_theme_constant_override("v_separation", 8)
	tcol.add_child(_tools_row)
	var turn := UI.button("Turn", "turn")
	turn.pressed.connect(func(): controller.turn_ghost())
	_tools_row.add_child(turn)
	_paint_btn = UI.button("Paint", "paint")
	_paint_btn.pressed.connect(func(): _swatches.visible = not _swatches.visible)
	_tools_row.add_child(_paint_btn)
	_remove_btn = UI.button("Put away", "trash")
	_remove_btn.pressed.connect(func(): controller.put_away())
	_tools_row.add_child(_remove_btn)
	_bp_save_btn = UI.button("Blueprint", "board")
	_bp_save_btn.pressed.connect(func(): open_blueprint_save(controller.g_edit_id))
	_tools_row.add_child(_bp_save_btn)
	_gift_btn = UI.button("Gift", "gift")
	_gift_btn.pressed.connect(_open_gift_picker)
	_tools_row.add_child(_gift_btn)
	var cancel := UI.button("Cancel", "close")
	cancel.pressed.connect(func():
		var was_new: bool = controller.ghost != null and controller.g_edit_id == ""
		controller.cancel_ghost()
		if was_new:
			show_toast("Back in the toy box."))
	_tools_row.add_child(cancel)
	_place_btn = UI.button("Place here", "check", true, 200)
	_place_btn.pressed.connect(func(): controller.confirm_ghost())
	_tools_row.add_child(_place_btn)
	_tools.visible = false


func _on_ghost(info: Dictionary) -> void:
	if not info.is_empty() and not _tools.visible:
		_hide_toast()   # a new placement starts: the last placement message is stale
		_tools_hint.custom_minimum_size.y = 0.0   # a new hold: the line takes the height of its own text
	_tools.visible = not info.is_empty()
	# While a thing is held the chips at the top centre step aside, as the toy box does, and come back
	# when it is placed or put away: the tools' top place starts right under the top bar, where they
	# are (review of the r8 draft, D3: the first-steps line lay over the tools' name and instruction
	# line). Lowering that place instead would take ~90 px from the room the camera rests the thing
	# in, and on the iPad while editing the child would no longer fit between the two places. The
	# first-steps line only repeats what the tools' own line says while a thing is held.
	_set_top_chips_aside(not info.is_empty())
	# While a thing is held the toy box steps aside and the tools are at the bottom edge or at the top
	# (see _process). Which of the two depends on where the camera will rest and on the tools' size in
	# this language, known only after a layout pass: for three frames the tools take their place unseen.
	if not info.is_empty() and dock == "bottom":
		_set_dock("low")
		_pick_frames = 3
		_set_tools_unseen(true)
	# The tools take the middle at once: they must not appear where the idea line had stepped aside and
	# then jump (a tap on Place here in that frame would miss it).
	_keep_idea_clear()
	if info.is_empty():
		_set_dock("bottom")
		_pick_frames = 0
		_set_tools_unseen(false)
		_tools_hint.custom_minimum_size.y = 0.0
		_swatches.visible = false
		if controller.mode == "decorate":
			show_hint("Tap something to move, turn, paint or put it away.")
		return
	# One word for the same act, placing or editing: the line above says "then tap Place here", the
	# controller hint says "Place here", and "Done" is the corner button that closes the toy box (the
	# Mac's r7 pictures showed two Done buttons side by side).
	_place_btn.text = "Place here"
	_tools_name.text = Catalog.get_def(info["kind"]).get("name", "")
	_place_btn.disabled = info["error"] != ""
	_remove_btn.visible = info["editing"]
	_bp_save_btn.visible = info["editing"] and Blueprints.capturable(Session.model.items.get(controller.g_edit_id, {"kind": "cottage"}))
	_gift_btn.visible = info["editing"] and info["kind"] != "cottage" and Session.model.roster.size() >= 1
	_paint_btn.visible = info["paintable"]
	if not info["paintable"]:
		_swatches.visible = false
	show_hint(info["error"] if info["error"] != "" else "Drag it, turn it, then tap Place here.")


# ------------------------------------------------------------- tool placement

var _catalog_h := 330.0
## The toy box's own rectangle on screen as it was last shown. While a thing is held the tools take a
## part of that place at the bottom edge and must stay inside it: then they cover nothing that the toy
## box did not cover while it was shown, wherever the child stands (first-steps r7).
var _catalog_rest := Rect2()
var _catalog_rest_h := 0.0

## Height of the toy box when shown (remembered while it is tucked away).
func _catalog_height() -> float:
	if _catalog.visible and _catalog_box.size.y > 120.0:
		_catalog_h = _catalog_box.size.y
	return _catalog_h


## Nominal screen zones the menus occupy with the tools at the bottom or top.
## They do not depend on the current dock, so the decision cannot feed back on itself.
func zones() -> Dictionary:
	var area := get_global_rect()
	var size := _tools_col.get_combined_minimum_size()
	var x := area.position.x + (area.size.x - size.x) * 0.5 + _tools_shift
	var catalog_top := area.end.y - _catalog_height()
	var bottom := Rect2(x, catalog_top - size.y - 8.0, size.x, size.y).merge(
		Rect2(area.position.x, catalog_top, area.size.x - SIDE_W - 16.0, _catalog_height()))
	# While a thing is held the tools have the same size at both places (_fit_tools); only their
	# distance from the middle can differ, with what stands beside each place.
	var mid := area.position.x + (area.size.x - size.x) * 0.5
	var top := Rect2(mid + _dock_shift["top"], area.position.y + TOP_BAR_H, size.x, size.y)
	var low := Rect2(mid + _dock_shift["low"], area.end.y - LOW_MARGIN - size.y, size.x, size.y)
	# The whole strip of the screen at the height of the low place: a thing dragged anywhere into it
	# sends the tools up, as since r5, not only a thing dragged under the tools themselves.
	var strip := Rect2(area.position.x, low.position.y, area.size.x, low.size.y)
	return {"bottom": bottom, "top": top, "low": low, "strip": strip}


## The room on screen between the tools' two places, where the camera rests a held thing (r8).
func placing_room() -> Rect2:
	var z := zones()
	var area := get_global_rect()
	var top: float = z["top"].end.y + FRAME_GAP
	return Rect2(area.position.x, top, area.size.x, z["low"].position.y - FRAME_GAP - top)


## What the held thing and the player's own child cover on screen, as the place of the tools is
## judged: [thing, child]. While a finger drags the thing the camera stands still and this is what
## is on screen now; otherwise it is the picture the camera is gliding to, so the tools take their
## place once instead of following the glide.
func placement_rects() -> Array:
	if controller == null or controller.ghost == null or controller.rig == null:
		return [Rect2(), Rect2()]
	if controller.rig.hold:
		return [ghost_screen_rect(), avatar_screen_rect()]
	var rig: Node3D = controller.rig
	var xf: Transform3D = rig.rest_xform()
	var view: Vector2 = rig.view_size()
	var h := Catalog.height(controller.g_kind)
	var base := PlacementDock.box_base(controller.ghost.global_position, h, Catalog.anchor(controller.g_kind))
	var thing: Rect2 = rig.box_rect(xf, view, base, Catalog.get_def(controller.g_kind)["radius"], h)
	var kid: Node3D = controller.world.local_kid() if controller.world != null else null
	var me := Rect2()
	if kid != null and kid.is_visible_in_tree():
		me = rig.box_rect(xf, view, kid.global_position, 0.45, 1.85)
	return [thing, me]


const _MeshKit := preload("res://scripts/art/mesh_kit.gd")

## The held thing's own meshes on screen, for the same camera pose as placement_rects: the corners of every
## mesh's box, without the placement ring on the floor under it and without its soft contact shadow (as the
## tours measure the thing). first-steps r11: the catalog ring that placement_rects gives is narrower than
## some meshes' boxes (a round table's top), and on the Mac's r10 iPad Air sweep the left menu's German
## Hello stood 7 px2 on the table's boxes while the ring, grown by MENU_THING_GAP, missed it; the menu
## stayed. The side menus are now judged with both (_keep_menus_clear); the tools and the camera are not.
func ghost_mesh_rect() -> Rect2:
	if controller == null or controller.ghost == null or controller.rig == null or not controller.ghost.is_visible_in_tree():
		return Rect2()
	var rig: Node3D = controller.rig
	var xf: Transform3D = rig.camera.global_transform if rig.hold else rig.rest_xform()
	var view: Vector2 = rig.view_size()
	var r := Rect2()
	var first := true
	for n in controller.ghost.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == controller._ghost_ring or mi.mesh == null or not mi.is_visible_in_tree() or _is_contact_shadow(mi):
			continue
		var box: AABB = mi.get_aabb()
		for i in 8:
			var s = rig.project(xf, view, mi.global_transform * box.get_endpoint(i))
			if s == null:
				continue
			r = Rect2(s, Vector2.ZERO) if first else r.expand(s)
			first = false
	return r


## The soft round contact shadow under a thing (mesh_kit.gd blob_shadow).
static func _is_contact_shadow(mi: MeshInstance3D) -> bool:
	return mi.mesh is QuadMesh and (mi.mesh as QuadMesh).orientation == PlaneMesh.FACE_Y \
		and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).albedo_texture == _MeshKit._shadow_texture()


func _set_dock(d: String) -> void:
	if d == dock and _tools_box.has_meta("placed"):
		return
	dock = d
	_dock_since = Time.get_ticks_msec() / 1000.0
	_tools_box.set_meta("placed", true)
	for side in ["top", "bottom"]:
		_tools_box.add_theme_constant_override("margin_" + side, 0)
	if d == "top":
		UI.pin(_tools_box, Control.PRESET_CENTER_TOP)
		_tools_box.add_theme_constant_override("margin_top", int(TOP_BAR_H))
		_tools_col.move_child(_hint_panel, -1)
	elif d == "low":
		# At the bottom edge, where the toy box is when it is shown (it tucks away, as for "top").
		UI.pin(_tools_box, Control.PRESET_CENTER_BOTTOM)
		_tools_box.add_theme_constant_override("margin_bottom", LOW_MARGIN)
		_tools_col.move_child(_hint_panel, 0)
	else:
		UI.pin(_tools_box, Control.PRESET_CENTER_BOTTOM)
		_tools_box.add_theme_constant_override("margin_bottom", int(_catalog_height() + 8.0) + _idea_lift)
		_tools_col.move_child(_hint_panel, 0)
	# The toy box tucks away while the tools are at the top or at the bottom edge, so the item and the
	# child stay visible.
	_catalog.visible = controller != null and controller.mode == "decorate" and d == "bottom"


## Screen rectangle of the item being placed, or an empty rect.
func ghost_screen_rect() -> Rect2:
	if controller == null or controller.ghost == null:
		return Rect2()
	var h := Catalog.height(controller.g_kind)
	return PlacementDock.ghost_rect(controller.rig.camera, PlacementDock.box_base(controller.ghost.global_position, h, Catalog.anchor(controller.g_kind)),
		Catalog.get_def(controller.g_kind)["radius"], h)


## While a thing is placed or edited, the tools fit between what stands beside them. Editing a placed
## thing shows up to seven buttons; side by side they were 1227 px wide in English and 1437 px in
## German on a 1366 px iPad screen, under the corner column and the left menu and, in two languages,
## off the screen (measured on first-steps r3; a new thing's four buttons fit, which is why it was not
## seen). The row now wraps into two rows within the room there is, and the block stands in the
## middle of that room. Returns how far that is from the middle of the screen.
func _fit_tools() -> float:
	var area := get_global_rect()
	var widths := []
	var row_h := 0.0
	for b in _tools_row.get_children():
		if b is Control and (b as Control).visible:
			var m: Vector2 = (b as Control).get_combined_minimum_size()
			widths.append(m.x)
			row_h = maxf(row_h, m.y)
	var h_sep: float = _tools_row.get_theme_constant("h_separation")
	var v_sep: float = _tools_row.get_theme_constant("v_separation")
	var natural := 0.0
	for w in widths:
		natural += w
	natural += maxf(widths.size() - 1, 0.0) * h_sep
	# What the panel adds around the row (its own padding), and the block's height without the rows.
	var pad: float = clampf(_tools.size.x - _tools_row.size.x, 0.0, 96.0) if _tools.size.x > 1.0 else 40.0
	var size := _tools_col.size if _tools_col.size.y > 1.0 else _tools_col.get_combined_minimum_size()
	var rows_now: int = maxi(1, int(round((_tools_row.size.y + v_sep) / maxf(row_h + v_sep, 1.0)))) if _tools_row.size.y > 1.0 else 1
	var base_h: float = size.y - (rows_now * row_h + (rows_now - 1) * v_sep)
	# The room depends on the block's height (a taller block reaches up beside the left menu), and the
	# height on the rows, and the rows on the room: worked out here in one go, from one row upwards,
	# so the block takes its place at once instead of settling over several frames.
	# While a thing is held the tools can be at the bottom edge or at the top, and are given one width
	# for both, the narrower of the two rooms: the same buttons in the same rows wherever the block
	# is, and a block of the same height at both places (the camera rests the thing between them).
	var rows := 1
	var want := natural
	var places: Array = ["low", "top"] if dock != "bottom" else ["bottom"]
	var rooms := {}
	for attempt in 4:
		var h: float = base_h + rows * row_h + (rows - 1) * v_sep
		var room := INF
		for d in places:
			rooms[d] = _tools_room(d, h)
			room = minf(room, rooms[d][1] - rooms[d][0])
		want = minf(natural, maxf(room - pad, 240.0))
		# Rows the buttons need at that width, packed in order as the flow container packs them.
		var need := 1
		var used := 0.0
		for w in widths:
			if used > 0.0 and used + h_sep + w > want + 0.5:
				need += 1
				used = w
			else:
				used += (h_sep if used > 0.0 else 0.0) + w
		if need <= rows:
			break
		rows = need
	if absf(_tools_row.custom_minimum_size.x - want) > 0.5:
		_tools_row.custom_minimum_size.x = want
	var block: float = maxf(want + pad, _hint_panel.get_combined_minimum_size().x if _hint_panel.visible else 0.0)
	var rest_x: float = area.position.x + (area.size.x - block) * 0.5
	for d in places:
		_dock_shift[d] = clampf(rest_x, rooms[d][0], maxf(rooms[d][1] - block, rooms[d][0])) - rest_x
	return _dock_shift[dock] if _dock_shift.has(dock) else clampf(rest_x, rooms[dock][0], maxf(rooms[dock][1] - block, rooms[dock][0])) - rest_x


## From where to where a block of height `h` can reach at the place `d`, between what stands beside it.
func _tools_room(d: String, h: float) -> Array:
	var area := get_global_rect()
	var top: float = area.position.y + TOP_BAR_H
	if d == "bottom":
		top = area.end.y - _catalog_height() - 8.0 - h
	elif d == "low":
		top = area.end.y - LOW_MARGIN - h
	var band := Rect2(area.position.x, top - CAM_GAP, area.size.x, h + CAM_GAP * 2.0)
	var lo: float = area.position.x + 16.0
	var hi: float = area.end.x - 16.0
	for c in [_left_stack, _side_col, _cam_tools]:
		var r: Rect2 = c.get_global_rect()
		if c.is_visible_in_tree() and r.has_area() and r.intersects(band):
			if r.get_center().x < area.get_center().x:
				lo = maxf(lo, r.end.x + CAM_GAP + 4.0)
			else:
				hi = minf(hi, r.position.x - CAM_GAP - 4.0)
	if d == "low" and _catalog_rest.has_area():
		# At the bottom edge the tools stay inside the toy box's own place, side to side.
		lo = maxf(lo, _catalog_rest.position.x)
		hi = minf(hi, _catalog_rest.end.x)
	return [lo, hi]


## Screen rectangle of the player's own child, name tag included; empty when there is none on screen.
func avatar_screen_rect() -> Rect2:
	if controller == null or controller.world == null or controller.rig == null:
		return Rect2()
	var kid: Node3D = controller.world.local_kid()
	if kid == null or not kid.is_visible_in_tree():
		return Rect2()
	return PlacementDock.ghost_rect(controller.rig.camera, kid.global_position, 0.45, 1.85)


## While the toy box is browsed, the idea line sat above it in the middle of the screen, which is where
## the child stands: the Mac's pictures of first-steps r1 (iPhone layout, and Metal at the TV layout)
## show a three-line idea covering the child's face and body. Fewer lines did not help; the place was
## wrong. Now, when the line would cover the child, it steps to the side of the child that has room
## (between the left menu and the corner column), and when neither side has room it goes up under the
## top bar. With something being placed the placement tools decide as before (PlacementDock).
func _keep_idea_clear() -> void:
	if _tools_box == null or _left_stack == null:
		return
	var shift := 0.0
	var lift := 0.0
	var side := 0
	var browsing: bool = visible and controller != null and controller.mode == "decorate" and controller.ghost == null \
			and dock == "bottom" and _hint_panel.visible and not _tools.visible
	if browsing:
		var me := avatar_screen_rect()
		var area := get_global_rect()
		var size := _tools_col.get_combined_minimum_size()
		var top: float = area.end.y - _catalog_height() - 8.0 - size.y
		var rest := Rect2(area.position.x + (area.size.x - size.x) * 0.5, top, size.x, size.y)
		if me.has_area() and rest.intersects(me.grow(IDEA_GAP)):
			# How far the line can slide: between whatever stands at its height on either side.
			var band := Rect2(area.position.x, top - 8.0, area.size.x, size.y + 16.0)
			var lo: float = area.position.x + 16.0
			var hi: float = area.end.x - 16.0
			for c in [_left_stack, _side_col, _cam_tools]:
				var r: Rect2 = c.get_global_rect()
				if c.is_visible_in_tree() and r.has_area() and r.intersects(band):
					if r.get_center().x < area.get_center().x:
						lo = maxf(lo, r.end.x + IDEA_GAP)
					else:
						hi = minf(hi, r.position.x - IDEA_GAP)
			var room_right: float = hi - (me.end.x + IDEA_GAP)
			var room_left: float = (me.position.x - IDEA_GAP) - lo
			var fits_right: bool = room_right >= size.x
			var fits_left: bool = room_left >= size.x
			# Stay on the side already chosen while it still fits; else the side with more room.
			if _idea_side == 1 and fits_right or (fits_right and not (_idea_side == -1 and fits_left) and (room_right >= room_left or not fits_left)):
				side = 1
				shift = me.end.x + IDEA_GAP - rest.position.x
			elif fits_left:
				side = -1
				shift = me.position.x - IDEA_GAP - size.x - rest.position.x
			else:
				# Neither side: up under the top bar (and under the first-steps line when it is there).
				var ceiling: float = area.position.y + TOP_BAR_H + 8.0
				if _first_chip != null and _first_chip.is_visible_in_tree():
					ceiling = maxf(ceiling, _first_chip.get_global_rect().end.y + 8.0)
				if ceiling + size.y <= me.position.y - IDEA_GAP:
					lift = top - ceiling
	elif visible and controller != null and controller.mode == "decorate" and _tools.visible:
		shift = _fit_tools()
	_tools_shift = shift if _tools.visible else 0.0
	_idea_side = side
	# The box is pinned by its middle and grows both ways: twice the shift on one side moves it by the shift.
	var want_left := int(maxf(shift, 0.0) * 2.0)
	var want_right := int(maxf(-shift, 0.0) * 2.0)
	if _tools_box.get_theme_constant("margin_left") != want_left:
		_tools_box.add_theme_constant_override("margin_left", want_left)
	if _tools_box.get_theme_constant("margin_right") != want_right:
		_tools_box.add_theme_constant_override("margin_right", want_right)
	if int(lift) != _idea_lift:
		_idea_lift = int(lift)
		if dock == "bottom":
			_tools_box.add_theme_constant_override("margin_bottom", int(_catalog_height() + 8.0) + _idea_lift)
	# The box is anchored by its middle: it grows with what it holds but does not shrink by itself. When
	# the row wraps (or a line gets shorter) it would stay as wide as before, stretched over the corner
	# column; so it is pinned again whenever it is larger than what it holds.
	var held := _tools_box.get_combined_minimum_size()
	if _tools_box.size.x > held.x + 0.5 or _tools_box.size.y > held.y + 0.5:
		UI.pin(_tools_box, Control.PRESET_CENTER_TOP if dock == "top" else Control.PRESET_CENTER_BOTTOM)


## The camera buttons sit at the right edge. While decorating, the column of buttons in the bottom
## right corner grows upward and, on short screens, reached under them (seen in the Mac's pictures at
## the iPhone, iPad Air and TV layouts: Put on display over the turn and zoom buttons). When the two
## would share any height, the camera buttons move up, staying at the right edge, to end just above
## the column. (A first repair stepped them to the left of the column instead; at the TV layout that
## put them on the toy box's corner.) Only if there is no room under the top bar do they step left.
func _keep_camera_clear() -> void:
	if _cam_margin == null or _side_col == null:
		return
	var area := get_global_rect()
	var column := _side_col.get_global_rect()
	# Where the buttons are when nothing is in their way: the middle of the right edge.
	var height: float = _cam_tools.get_combined_minimum_size().y
	var rest_top: float = area.get_center().y - height * 0.5
	var meet: bool = _side_col.is_visible_in_tree() and column.size.y > 1.0 and column.position.y < rest_top + height + CAM_GAP
	var lift := 0.0
	var aside := 0
	if meet:
		lift = ceilf(rest_top + height + CAM_GAP - column.position.y)
		if rest_top - lift < area.position.y + TOP_BAR_H + CAM_GAP:
			lift = 0.0
			aside = int(column.size.x) + 12
	# The margin box is pinned by its middle and grows both ways: twice the lift below moves it up by the lift.
	if _cam_margin.get_theme_constant("margin_right") != 16 + aside:
		_cam_margin.add_theme_constant_override("margin_right", 16 + aside)
	if _cam_margin.get_theme_constant("margin_bottom") != int(lift) * 2:
		_cam_margin.add_theme_constant_override("margin_bottom", int(lift) * 2)


func _process(_delta: float) -> void:
	_tick_zoo(_delta)
	_tick_first_steps()
	_keep_camera_clear()
	_keep_idea_clear()
	_layout_tags()
	_lift_for_keyboard()
	_keep_toast_clear()
	if _catalog.is_visible_in_tree() and _catalog.size.y > 120.0:
		_catalog_rest = _catalog.get_global_rect()   # remembered for the tools' place at the bottom edge
		_catalog_rest_h = _catalog.size.y            # its height in the HUD's own units (both sit 16 above the bottom edge)
	if controller == null or controller.ghost == null or not visible:
		if controller != null and controller.rig != null:
			controller.rig.frame = Rect2()
			controller.rig.frame_low = Rect2()
			controller.rig.frame_top = Rect2()
			controller.rig.frame_strip = Rect2()
			controller.rig.frame_safe = Rect2()
		if _pick_frames > 0:
			_pick_frames = 0
			_set_tools_unseen(false)
		_set_top_chips_aside(false)
		_keep_menus_clear(Rect2(), Rect2())   # no thing held: every side menu is back (r10)
		return
	_set_top_chips_aside(true)   # again after the HUD was hidden and shown during one hold
	# The instruction line inside the tools keeps the tallest height it had during this hold: a hint that
	# arrives meanwhile (a ride nearby, a refused request, a reason one line shorter) must not shrink the
	# block, which would change the room between the two places and re-aim the camera (review D9). Not
	# in the frames after a pick, while the block's width is still being found (a line wrapped in a
	# narrow block would keep a height it does not need).
	if _pick_frames == 0 and _tools_hint.visible and _tools_hint.size.y > _tools_hint.custom_minimum_size.y + 0.5:
		_tools_hint.custom_minimum_size.y = ceilf(_tools_hint.size.y)
	# While a thing is held (first-steps r8) the tools are at the bottom edge or under the top bar,
	# the same block at both places, and the camera rests the thing in the room between the two: at
	# rest neither place covers the thing. Which place is then decided by the child: the tools leave
	# the place where the player's own child stands. (r5 and r7 chose by the thing alone and the tools
	# lay on the child; r6 weighed the two while the camera rested the thing under the top place, and
	# the tools went onto the thing. See placement_dock.gd.) While a finger drags the thing the camera
	# stands still and the thing comes first: the tools never stay on it.
	var z := zones()
	var rig: Node3D = controller.rig
	var room := placing_room()
	rig.frame_box = Vector2(Catalog.get_def(controller.g_kind)["radius"], Catalog.height(controller.g_kind))
	rig.frame = room if room.size.y >= FRAME_MIN else Rect2()
	rig.frame_gap = z["low"].position.y - z["top"].end.y   # the child must fit between the two places
	rig.frame_feet = z["low"].end.y
	# Inside a cottage the room camera keeps its view and steps back only when the thing and the child
	# leave neither place free (first-steps r9, review D2; camera_rig.gd room_fit).
	rig.frame_low = z["low"]
	rig.frame_top = z["top"]
	rig.frame_strip = z["strip"]
	rig.frame_anchor = Catalog.anchor(controller.g_kind)
	# ... and the thing rests whole inside the safe area (r10, camera_rig.gd frame_safe).
	rig.frame_safe = get_global_rect()
	var seen := placement_rects()
	# The side menus keep clear of the thing's ring and of its own meshes (r11, ghost_mesh_rect).
	var meshes := ghost_mesh_rect()
	_keep_menus_clear(seen[0].merge(meshes) if seen[0].has_area() and meshes.has_area() else (meshes if meshes.has_area() else seen[0]), seen[1])
	if rig.in_room and seen[0].has_area():
		seen[0] = seen[0].grow(rig.ROOM_THING_GAP)   # indoors the thing keeps 24 px from the tools, as outdoors (r9)
	var want: String = PlacementDock.choose_place("top" if dock == "top" else "low", seen[0], seen[1], z["low"], z["top"], z["strip"], rig.hold)
	# At the bottom edge the tools must fit inside the toy box's own place, top to bottom as well (side
	# to side: _fit_tools). A block taller than that place (not reached at any supported layout: it
	# would take a third row of buttons) goes to the top instead of reaching above the toy box's place.
	if want == "low" and _catalog_rest_h > 0.0 and _tools_col.get_combined_minimum_size().y > _catalog_rest_h + 0.5:
		want = "top"
	if want != dock and (dock == "bottom" or _pick_frames > 0 or Time.get_ticks_msec() / 1000.0 - _dock_since > DOCK_DWELL):
		_set_dock(want)
	if _pick_frames > 0:
		_pick_frames -= 1
		if _pick_frames == 0:
			_set_tools_unseen(false)


## For the frames after a pick in which the tools take their place unseen (_pick_frames), they take no
## press either (first-steps r9, review D10: in r8 they were invisible and still acted, and a press
## meant for Turn put a thing away). Their buttons ignore the pointer, which covers a finger, a mouse
## and the controller (its pointer, A, and its Turn, Place and Cancel buttons all press through the
## same GUI path); the tools' own panel, which stops the pointer, takes the press instead, so it
## neither acts on a tool nor reaches the town behind. Every hide and every restore goes through here.
func _set_tools_unseen(unseen: bool) -> void:
	_tools_box.modulate.a = 0.0 if unseen else 1.0
	_tools_inner.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if unseen else Control.MOUSE_BEHAVIOR_INHERITED


## The menus at the sides and the top bar's right part: what stays on screen beside the room while a thing
## is held (the toy box and the top chips step aside anyway).
func side_menus() -> Array:
	return [_left_stack, _top_right, _cam_tools, _side_col, _bottom_left]


const MENU_THING_GAP := 16.0   # around the thing's ring and its meshes' boxes (r11: the boxes alone reach past the ring)
const MENU_KID_GAP := 8.0      # as PlacementDock.CHILD_GAP

## While a thing is held, a side menu (or the top bar's right part) that would stand on the held thing or
## on the player's own child steps aside: unseen, it takes no press (as the unseen tools, r9 D10) and the
## controller's pointer and D-pad skip it (pad_input.gd targets). It comes back as soon as it would no
## longer stand on them, and always when the hold ends (placed, cancelled, put away). first-steps r10:
## the Mac's r9 pictures showed the left menu's Story and Hello over a painting held at the left wall on
## the iPad, and the saved-status pill over a bird mobile at the back. Only the alpha changes, never the
## layout, so nothing the tools or the camera plan with moves. `thing` and `me` are the HUD's boxes for
## the thing and the child as the tools' place is judged (placement_rects), the thing's taking in its
## meshes' boxes too (r11, ghost_mesh_rect); empty rects bring all back.
func _keep_menus_clear(thing: Rect2, me: Rect2) -> void:
	for m in side_menus():
		if m == null:
			continue
		var was: bool = _menus_aside.get(m, false)
		var k := 2.0 if was else 1.0   # once aside, it comes back only when clear by twice the gap (no flicker)
		var t := thing.grow(MENU_THING_GAP * k) if thing.has_area() else Rect2()
		var c := me.grow(MENU_KID_GAP * k) if me.has_area() else Rect2()
		var cover := false
		if m.is_visible_in_tree() and (t.has_area() or c.has_area()):
			for ch in (m as Control).get_children():
				if ch is Control and (ch as Control).is_visible_in_tree():
					var r: Rect2 = (ch as Control).get_global_rect()
					if r.has_area() and (r.intersects(t) or r.intersects(c)):
						cover = true
						break
		if cover != was:
			_set_menu_aside(m, cover)


func _set_menu_aside(m: Control, aside: bool) -> void:
	_menus_aside[m] = aside
	m.modulate.a = 0.0 if aside else 1.0
	m.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if aside else Control.MOUSE_BEHAVIOR_INHERITED


## Whether a side menu stands aside now (tests).
func menu_aside(m: Control) -> bool:
	return _menus_aside.get(m, false)


func _set_top_chips_aside(aside: bool) -> void:
	for m in _top_chips:
		if (m as Control).visible == aside:
			(m as Control).visible = not aside


func show_hint(text: String) -> void:
	_hint.text = text
	# While a thing is held the line is part of the tools; otherwise it is the idea line's own panel.
	_tools_hint.text = text
	# An emptied line keeps its height for the rest of the hold (see _process).
	_tools_hint.visible = _tools.visible and (text != "" or _tools_hint.custom_minimum_size.y > 0.0)
	_hint_panel.visible = text != "" and controller != null and controller.mode == "decorate" and not _tools.visible
	if controller and controller.mode != "decorate" and text != "":
		show_toast(text)


# ------------------------------------------------------------- messages

func _build_messages() -> void:
	var m := _corner(Control.PRESET_CENTER_TOP, 110)
	m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# One chip for whatever shared game is running, always with a way out.
	var am := _corner(Control.PRESET_CENTER_TOP, 104)
	# First steps: the same place as the activity chip (never both at once).
	var fm := _corner(Control.PRESET_CENTER_TOP, 104)
	fm.grow_horizontal = Control.GROW_DIRECTION_BOTH   # stays centered whatever the line's length
	_first_chip = UI.panel(20)
	_first_chip.name = "FirstSteps"
	# 84 px tall in all: the line ends above where messages appear (TOAST_TOP), with room to spare.
	var chip_box := _first_chip.get_theme_stylebox("panel").duplicate() as StyleBox
	chip_box.content_margin_top = 12
	chip_box.content_margin_bottom = 12
	_first_chip.add_theme_stylebox_override("panel", chip_box)
	_first_chip.visible = false
	fm.add_child(_first_chip)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	_first_chip.add_child(frow)
	_first_icon = TextureRect.new()
	_first_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_first_icon.custom_minimum_size = Vector2(44, 44)
	frow.add_child(_first_icon)
	_first_label = UI.label("", 24, UI.TEXT)
	frow.add_child(_first_label)
	var fhide := UI.icon_button("close", "Hide", 56)
	fhide.name = "HideFirstSteps"
	fhide.pressed.connect(func():
		Sfx.play("tap")
		first_steps["hidden"] = true
		_save_first_steps())
	frow.add_child(fhide)
	_activity_chip = UI.panel(24)
	_activity_chip.visible = false
	am.add_child(_activity_chip)
	var arow := HBoxContainer.new()
	_activity_chip.add_child(arow)
	var aicon := TextureRect.new()
	aicon.name = "Icon"
	aicon.texture = UI.icon("acorn", 44)
	aicon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	arow.add_child(aicon)
	_activity_label = UI.label("", 22, UI.TEXT)
	_activity_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	arow.add_child(_activity_label)
	_warmth_dots = HBoxContainer.new()
	for i in 4:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(22, 22)
		_warmth_dots.add_child(dot)
	arow.add_child(_warmth_dots)
	var inv := UI.icon_button("friends", "Invite friends", 64)
	inv.name = "InviteActivity"
	inv.pressed.connect(func():
		Sfx.play("tap")
		_send_invite("hide" if Activities.hs.get("phase", "none") != "none" else "party", ""))
	arow.add_child(inv)
	var stop := UI.button("Stop", "close", false, 120)
	stop.custom_minimum_size.y = 64
	stop.pressed.connect(func():
		if Activities.hs.get("phase", "none") != "none":
			Activities.stop_hide_and_seek()
		elif Activities.is_party():
			Activities.stop_party())
	arow.add_child(stop)
	m = _corner(Control.PRESET_CENTER_TOP, int(TOAST_TOP))
	m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast = UI.panel(24, UI.ACCENT)
	_toast_label = UI.label("", 24, UI.PANEL)
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_toast)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	_celebration = UI.panel(32, UI.PANEL)
	_celebration.visible = false
	_celebration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_celebration)
	# The story or trail in progress, with a Stop button (top center, under the toasts).
	var cm := _corner(Control.PRESET_CENTER_TOP, 96)
	_play_chip = UI.panel(18, UI.PANEL)
	_play_chip.visible = false
	cm.add_child(_play_chip)
	_top_chips = [am, fm, cm]   # stepped aside while a thing is held (_on_ghost)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 12)
	_play_chip.add_child(crow)
	_play_chip_label = UI.label("", 22, UI.ACCENT)
	_play_chip_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_play_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crow.add_child(_play_chip_label)
	_play_chip_stop = UI.button("Stop", "close", false, 0)
	_play_chip_stop.custom_minimum_size.y = 56
	_play_chip_stop.pressed.connect(func():
		Sfx.play("tap")
		if not story.is_empty():
			story = {}
		elif not trail.is_empty():
			Session.follow_trail(false)
			_set_trail({})
		_refresh_play_chip())
	crow.add_child(_play_chip_stop)


## Transient messages never cover the placement tools (r13 Mac: "Placed!" sat over Turn and
## Place here): while the tools show, the toast moves below them, or above them when they sit low.
func _keep_toast_clear(showing := false) -> bool:
	var m := _toast.get_parent() as MarginContainer
	var want := TOAST_TOP
	var active := showing or _toast.modulate.a > 0.0 or Time.get_ticks_msec() / 1000.0 < _toast_until
	if _tools_col.is_visible_in_tree() and _tools.visible and active:
		var tools := _tools_col.get_global_rect()
		var top := get_global_rect().position.y
		var toast_h := _toast.size.y
		if Rect2(_toast.global_position.x, top + TOAST_TOP, _toast.size.x, toast_h).intersects(tools.grow(8.0)):
			if tools.position.y - top >= TOAST_TOP + toast_h + 16.0 or tools.end.y + 12.0 + toast_h > get_global_rect().end.y:
				want = TOAST_TOP   # room above the tools
			else:
				want = tools.end.y - top + 12.0
			if Rect2(_toast.global_position.x, top + want, _toast.size.x, toast_h).intersects(tools.grow(8.0)):
				want = maxf(8.0, tools.position.y - top - toast_h - 12.0)
	if absf(m.get_theme_constant("margin_top") - want) > 0.5:
		m.add_theme_constant_override("margin_top", int(want))
		return true
	return false


func _hide_toast() -> void:
	if _toast_tw:
		_toast_tw.kill()
	_toast.modulate.a = 0.0
	_toast_until = 0.0


func show_toast(text: String) -> void:
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.8
	_toast_label.text = text
	var moved := _keep_toast_clear(true)   # placed before it fades in
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	if moved:
		_toast.modulate.a = 0.0
		_toast_tw.tween_interval(0.04)   # the container settles at its new place first (one layout pass)
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(2.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_lantern(spot: String, by: Array) -> void:
	_refresh_lanterns()
	Sfx.play("lantern")
	for c in _celebration.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_celebration.add_child(col)
	var icon := TextureRect.new()
	icon.texture = UI.icon("lantern", 96)
	icon.modulate = CozySpots.SPOTS[spot]["lantern"].lightened(0.2)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	col.add_child(icon)
	var head := UI.label("A new lantern is glowing!", 34, UI.ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name := UI.label(CozySpots.SPOTS[spot]["name"], 30)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name)
	var who := UI.label(tr("Made together by %s") % ", ".join(by.map(func(n): return tr(n))), 22, UI.MUTED)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(who)
	_celebration.visible = true
	_celebration.scale = Vector2.ONE * 0.8
	_celebration.pivot_offset = _celebration.size * 0.5
	var tw := create_tween()
	tw.tween_property(_celebration, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_callback(func(): _celebration.visible = false)


# ------------------------------------------------------------- landmark tags

func _tag(id: String) -> Button:
	if _tags.has(id):
		return _tags[id]
	var b := UI.button("", {"bell": "bell", "drum": "drum", "vane": "weather", "stump": "acorn", "board": "board", "tram_stop": "tram"}.get(id, "star"), false, 0)
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.pressed.connect(func(): controller.walk_to_landmark(id))
	_tag_layer.add_child(b)
	_tags[id] = b
	return b


## Names the nearby landmarks without overlaps, under the top bar and above the
## bottom controls; tapping a name walks there and uses it.
func _layout_tags() -> void:
	var show_any: bool = visible and controller != null and controller.world != null and controller.mode == "play" and _overlay.get_child_count() == 0
	var wanted := []
	if show_any:
		for t in controller.world.activity.landmark_tags(controller.rig.camera):
			# The action button already names the landmark the child stands at.
			if _context_btn.visible and controller._ctx.get("id") == t["id"]:
				continue
			var b := _tag(t["id"])
			var label: String = tr(t["text"])
			if b.text != label:
				b.text = label
			# Untried landmarks get the bright accent style so they stand out.
			if b.get_meta("new", -1) != int(t["new"]):
				b.set_meta("new", int(t["new"]))
				var style := UI.box(UI.YELLOW if t["new"] else UI.PANEL, 16, 2, UI.ACCENT if t["new"] else UI.SOFT.darkened(0.08), 0.12)
				b.add_theme_stylebox_override("normal", style)
			t["size"] = b.get_combined_minimum_size()
			wanted.append(t)
	var area := get_global_rect()
	var blocked := [Rect2(area.position, Vector2(area.size.x, TOP_BAR_H)), Rect2(area.position.x, area.end.y - 116.0, area.size.x, 116.0)]
	blocked.append_array(feedback_rects())
	blocked.append(_guide_btn.get_global_rect().grow(6.0))
	blocked.append(_pets_btn.get_global_rect().grow(6.0))
	if _activity_chip.visible:
		blocked.append(_activity_chip.get_global_rect())
	if _first_chip.visible:
		blocked.append(_first_chip.get_global_rect())
	if _context_btn.visible:
		blocked.append(_context_btn.get_global_rect())
	if _context_alt_btn.visible:
		blocked.append(_context_alt_btn.get_global_rect())   # in a cart: landmark names keep clear of Get off too
	if _context_alt2_btn.visible:
		blocked.append(_context_alt2_btn.get_global_rect())
	if _context_alt3_btn.visible:
		blocked.append(_context_alt3_btn.get_global_rect())
	var placed := TagLayout.place(wanted, area, blocked)
	var shown := {}
	for p in placed:
		var b: Button = _tags[p["id"]]
		b.global_position = p["rect"].position
		b.size = p["rect"].size
		b.visible = true
		shown[p["id"]] = true
	for id in _tags:
		if not shown.has(id):
			_tags[id].visible = false


## Where feedback is showing right now (toast, celebration): reserved space for tags.
func feedback_rects() -> Array:
	var out := []
	if Time.get_ticks_msec() / 1000.0 < _toast_until:
		out.append(_toast.get_global_rect().grow(8.0))
	if _celebration.visible:
		out.append(_celebration.get_global_rect().grow(8.0))
	return out


func visible_tag_rects() -> Array:
	return _tags.values().filter(func(b): return b.visible).map(func(b): return b.get_global_rect())


# ------------------------------------------------------------- activities

func _refresh_activity() -> void:
	var hs: Dictionary = Activities.hs
	var phase: String = hs.get("phase", "none")
	var me_hider: bool = hs.get("hider", -1) == Session.my_id
	var text := ""
	var icon := "acorn"
	_warmth_dots.visible = false
	match phase:
		"hiding":
			text = tr("Walk somewhere secret, then tap Hide the acorn here.") if me_hider else tr("%s is hiding the golden acorn. Get ready!") % tr(hs.get("hider_nick", ""))
		"seeking":
			if me_hider:
				text = tr("Your friends are looking for your acorn!")
			else:
				text = tr("The acorn is glowing now!") if hs.get("hint", false) else tr("Find the golden acorn!")
				_warmth_dots.visible = true
				for i in 4:
					var lit: bool = Activities.warmth > i
					(_warmth_dots.get_child(i) as Panel).add_theme_stylebox_override("panel", UI.box(UI.CORAL if lit else UI.SOFT, 11))
		_:
			if Activities.is_party():
				text = tr("Dance party!")
				icon = "drum"
	_activity_chip.visible = text != ""
	(_activity_chip.find_child("InviteActivity", true, false) as Control).visible = Session.players.size() > 1
	_activity_label.text = text
	(_activity_chip.find_child("Icon", true, false) as TextureRect).texture = UI.icon(icon, 44)


func _refresh_heart() -> void:
	var space: String = controller.space if controller else "town"
	_heart_btn.visible = Places.is_room(space)
	if _heart_btn.visible:
		var mine: bool = Session.model.hearts.get(space, {}).has(Session.my_pid)
		_heart_btn.modulate = Color.WHITE if mine else Color(1, 1, 1, 0.55)
		_heart_btn.tooltip_text = tr("Take back my heart") if mine else tr("Leave a heart in this room")


func _on_wish_done(animal: String, wish_id: String, _at: Vector2, by: Array) -> void:
	Sfx.play("lantern")
	var name: String = tr(AnimalBrain.SPECIES[animal]["name"])
	show_toast(tr("%s's wish came true!") % name + "  " + tr("Made together by %s") % ", ".join(by.map(func(n): return tr(n))))
	_rebuild_catalog_tabs()


func _open_panel(panel: String, data: Dictionary) -> void:
	match panel:
		"wish":
			var w := Wishes.find(data.get("id", ""))
			if w.is_empty():
				return
			var name: String = tr(AnimalBrain.SPECIES[w["animal"]]["name"])
			var col := _dialog(tr("%s has a wish!") % name, w["text"], [
				["Not now", func(): pass, false],
				["I'll help!", func():
					_category = "Wish"
					controller.set_mode("decorate")
					_rebuild_catalog_tabs(), true]])
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			for k in w["kinds"]:
				var t := TextureRect.new()
				t.texture = thumbs.textures.get(k)
				t.custom_minimum_size = Vector2(96, 96)
				t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				row.add_child(t)
			_insert(col, row)
			_insert_visit(col, w["animal"])
		"pet":
			_open_pet_card(data.get("owner", ""), data.get("pet_id", ""))
		"cook":
			_open_recipes(data.get("stove", ""))
		"snack":
			_open_snacks(data.get("tray", ""))
		"trail_sign":
			_open_trail_sign(data.get("id", ""))
		"puzzle":
			_open_puzzle(data.get("id", ""))
		"board":
			_open_board(data.get("id", ""))
		"echo":
			_open_echo(data.get("owner", ""))
		"music":
			_open_music(data.get("id", ""))
		"animal":
			_open_animal(data.get("kind", ""))
		"fetch":
			_open_fetch()
		"guest":
			_open_guest(data.get("kind", ""))
		"photo_ideas":
			var col := _dialog("Photo ideas", "Take a photo with the camera button. Ideas you catch get a check mark.", [["Close", func(): pass, true]])
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 24)
			_insert(col, grid)
			# The zoo's four ideas (design Phase 1D) follow under their own heading.
			var zoo_head := UI.label("At the zoo", 24, UI.ACCENT)
			var zoo_grid := GridContainer.new()
			zoo_grid.columns = 2
			zoo_grid.add_theme_constant_override("h_separation", 24)
			for idea in PhotoIdeas.IDEAS + PhotoIdeas.ZOO_IDEAS:
				if idea == PhotoIdeas.ZOO_IDEAS[0]:
					_insert(col, zoo_head)
					_insert(col, zoo_grid)
					grid = zoo_grid
				var done: bool = Session.model.photo_ideas.has(idea["id"])
				# Icons, not text symbols: the bundled fonts have no check-mark glyphs.
				var row := HBoxContainer.new()
				var mark := TextureRect.new()
				mark.texture = UI.icon("saved" if done else "todo", 32)
				mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				row.add_child(mark)
				var l := UI.label(idea["text"], 22, UI.ACCENT if done else UI.TEXT, true)
				l.custom_minimum_size.x = 340
				row.add_child(l)
				grid.add_child(row)
		"thousand_inspect":
			open_thousand_inspect(str(data.get("id", "")))
		"guest_book":
			var book: Dictionary = Session.model.visits.get(data.get("house", ""), {})
			var names: Array = book.values().map(func(n): return tr(n))
			var col := _dialog("Guest book", "Friends who visited this house. Leave a heart in rooms you like!", [["Close", func(): pass, true]])
			var l := UI.label(", ".join(names) if not names.is_empty() else tr("No visitors yet."), 26, UI.ACCENT, true)
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_insert(col, l)


## Who gets the present? Everyone this town has met, or anyone at all.
# ------------------------------------------------------------- activity guide

## How to play: eight illustrated cards; a card opens its how-to. Opening and
## closing the guide never changes the game (mode, placement, running games).
func open_guide(id := "") -> void:
	first_step_done("guide")
	if id == "":
		_guide_section = "do"   # the guide always opens on the eight activities
	elif ActivityGuide.MAKE.any(func(e): return e["id"] == id):
		_guide_section = "make"
	_close_overlay()
	_search.release_focus()
	var shade := ColorRect.new()
	shade.name = "Guide"
	shade.color = Color(0.2, 0.25, 0.2, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	_add_backdrop(shade)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	shade.add_child(m)
	var p := UI.panel(28)
	m.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var icon := TextureRect.new()
	icon.texture = UI.icon("guide", 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(icon)
	var title := UI.label("How to play", 32, UI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UI.button("Close", "close", false, 150)
	close.name = "GuideClose"
	close.pressed.connect(func():
		Sfx.play("tap")
		_close_overlay())
	head.add_child(close)
	_guide_body = VBoxContainer.new()
	_guide_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_guide_body)
	if id == "":
		_guide_overview()
	else:
		_guide_detail(id)


var _guide_section := "do"   # which list the guide's overview shows: "do" (the eight activities) or "make"

func guide_open() -> bool:
	return _overlay.get_node_or_null("Guide") != null


func _guide_clear() -> void:
	for c in _guide_body.get_children():
		_guide_body.remove_child(c)
		c.queue_free()


func _guide_overview() -> void:
	_guide_clear()
	# Two sections: the eight activities, and the things to build and try (the newer play).
	var sections := HBoxContainer.new()
	sections.name = "GuideSections"
	sections.add_theme_constant_override("separation", 12)
	_guide_body.add_child(sections)
	for sec in [["do", "Things to do"], ["make", "Things to build"]]:
		var sb := UI.button(sec[1], "", _guide_section == sec[0], 0)
		sb.custom_minimum_size.y = 60
		sb.set_meta("guide_section", sec[0])
		var which: String = sec[0]
		sb.pressed.connect(func():
			Sfx.play("tap")
			_guide_section = which
			_guide_scroll = 0
			_guide_overview())
		sections.add_child(sb)
	var intro := UI.label("Things to build and try. Nothing is locked." if _guide_section == "make" else "Eight things to do in town. All of them work alone, and friends can join in.", 22, UI.TEXT, true)
	_guide_body.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.name = "GuideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_guide_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "GuideCards"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var width := get_global_rect().size.x - 120.0
	grid.columns = clampi(int(width / 300.0), 2, 4)
	scroll.add_child(grid)
	for e in (ActivityGuide.MAKE if _guide_section == "make" else ActivityGuide.ENTRIES):
		grid.add_child(_guide_card(e, (width - 14.0 * (grid.columns - 1)) / grid.columns))
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = _guide_scroll


func _guide_card(e: Dictionary, w: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	# Tall enough for a picture, a name and two lines of words with room under them (at 258 a second
	# line ran down to the card's lower edge in every language; seen in the Mac's pictures).
	b.custom_minimum_size = Vector2(maxf(w, 240.0), 276)
	b.set_meta("guide_id", e["id"])
	b.add_theme_stylebox_override("normal", UI.box(UI.PAPER, 20, 2, UI.SOFT.darkened(0.06)))
	b.add_theme_stylebox_override("hover", UI.box(UI.PAPER.lerp(UI.SOFT, 0.4), 20, 2, UI.ACCENT.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", UI.box(UI.SOFT, 20, 3, UI.ACCENT))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 10
	col.offset_bottom = -8
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.name = "Art"
	pic.texture = GuideArt.texture(e["art"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 140)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var name := UI.label(e["title"], 24, UI.ACCENT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)
	var tag := UI.label(e["tagline"], 17, UI.MUTED, true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.max_lines_visible = 2
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tag)
	b.pressed.connect(func():
		Sfx.play("tap")
		var sc := _guide_body.get_node_or_null("GuideScroll") as ScrollContainer
		if sc:
			_guide_scroll = sc.scroll_vertical
		_guide_detail(e["id"]))
	return b


func _guide_detail(id: String) -> void:
	_guide_clear()
	var e := ActivityGuide.find(id)
	var tr_fn := func(t): return tr(t)
	var row := HBoxContainer.new()
	row.name = "GuideDetail"
	row.set_meta("guide_id", id)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	_guide_body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	var pic := TextureRect.new()
	pic.name = "Art"
	pic.texture = GuideArt.texture(e["art"], 2.5)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(340, 234)
	left.add_child(pic)
	var go := UI.button(e["go_label"], "", true, 340)
	go.name = "GuideGo"
	go.pressed.connect(func(): _guide_go(e))
	left.add_child(go)
	var back := UI.button("Back", "undo", false, 340)
	back.name = "GuideBack"
	back.pressed.connect(func():
		Sfx.play("tap")
		_guide_overview())
	left.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.name = "GuideText"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 10)
	scroll.add_child(text)
	text.add_child(UI.label(e["title"], 32, UI.ACCENT, true))
	var section := func(head: String, body: String, icon_name := ""):
		var h := HBoxContainer.new()
		if icon_name != "":
			var ic := TextureRect.new()
			ic.texture = UI.icon(icon_name, 32)
			ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			h.add_child(ic)
		h.add_child(UI.label(head, 22, UI.ACCENT))
		text.add_child(h)
		var l := UI.label(body, 22, UI.TEXT, true)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.add_child(l)
	section.call("Where to start", ActivityGuide.line(e["where"], tr_fn), "home")
	text.add_child(UI.label("What to do", 22, UI.ACCENT))
	var n := 0
	for s in e["steps"]:
		n += 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var num := Label.new()
		num.text = str(n)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.custom_minimum_size = Vector2(40, 40)
		num.add_theme_stylebox_override("normal", UI.box(UI.YELLOW, 20))
		num.add_theme_font_size_override("font_size", 22)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(num)
		var l := UI.label(ActivityGuide.line(s, tr_fn), 22, UI.TEXT, true)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		text.add_child(h)
	section.call("You'll know it worked", ActivityGuide.line(e["success"], tr_fn), "saved")
	section.call("Alone", ActivityGuide.line(e["alone"], tr_fn), "wave")
	section.call("With friends", ActivityGuide.line(e["friends"], tr_fn), "friends")
	if e.has("extra"):
		var x := UI.label(ActivityGuide.line(e["extra"], tr_fn), 20, UI.MUTED, true)
		x.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.add_child(x)


## Once per device, a line at the top of town about the tram (stored in settings.cfg, [zoo] intro_shown).
func _zoo_intro_line() -> void:
	if controller == null or controller.space != "town":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if bool(cfg.get_value("zoo", "intro_shown", false)):
		return
	cfg.set_value("zoo", "intro_shown", true)
	cfg.save(SETTINGS_PATH)
	show_hint("A tram to the zoo is waiting.")


## A safe next step toward the activity. It walks or opens a menu at most; it
## never starts, finishes or changes anything, and gives an honest hint when
## the step is not possible from here.
func _guide_go(e: Dictionary) -> void:
	Sfx.play("tap")
	var go: String = e["go"]
	var outdoors: bool = controller.space == "town"
	if controller.ghost != null and go != "decorate" and go != "garden":
		show_toast("Place or cancel the item first.")
		return
	if controller.space == Places.ZOO and (go in ["garden", "door", "wish"] or go.begins_with("tab:") or go.begins_with("landmark:")):
		show_toast("That is in town. Tap Ride home first.")
		return
	match go:
		"wish":
			var w: Dictionary = Session.model.wishes.get("active", {})
			if w.is_empty():
				show_toast("No wish right now. Keep playing outdoors and an animal will wish for something soon.")
				return
			_close_overlay()
			_open_panel("wish", w)
		"decorate":
			_close_overlay()
			controller.set_mode("decorate")
		"garden":
			if not outdoors:
				show_toast("Garden beds go outdoors. Go outside first.")
				return
			_close_overlay()
			controller.set_mode("decorate")
			_category = "Nature"
			_placement = ""
			_set_query("")
		"hello":
			_close_overlay()
			if Session.model.echoes.has(Session.my_pid):
				_open_echo(Session.my_pid)
			else:
				_open_echo_recorder()
		"zoo":
			if controller.space == "zoo":
				show_toast("You are already at the zoo.")
				return
			_close_overlay()
			controller.ride("zoo")
		"door":
			if not outdoors:
				show_toast("You are already inside. The heart button is on the right.")
				return
			_close_overlay()
			controller.walk_to_door()
			show_toast("Walking there.")
		_:
			if go.begins_with("tab:"):
				# Decorate, with the toy box open on the tab the guide names.
				var tab := go.trim_prefix("tab:")
				if not RoomThemes.toolkits_for(controller.space).has(tab):
					show_toast("Those things go outdoors. Go outside first.")
					return
				_close_overlay()
				controller.set_mode("decorate")
				if controller.mode != "decorate":
					return   # this place is on display: the usual question came up instead
				_category = tab
				_placement = ""
				_set_query("")
				show_hint(RoomThemes.TOOLKIT_IDEAS.get(tab, ""))
				return
			if not outdoors:
				show_toast("Go outside first. It is on the town square.")
				return
			_close_overlay()
			controller.walk_near_landmark(go.trim_prefix("landmark:"))
			show_toast("Walking there.")


# ------------------------------------------------------------- pets

func _pet_icon(family: String, size := 64) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UI.icon("pet_" + family, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	return t


## My pets (who follows, who rests at home) and adopting a new one.
func open_pets() -> void:
	var col := _dialog("Pets", "", [["Close", func(): pass, true]])
	col.get_parent().get_parent().get_parent().name = "Pets"
	var e: Dictionary = PetRules.entry(Session.model, Session.my_pid)
	if e["pets"].is_empty():
		_insert(col, UI.label("Adopt a pet friend. It follows you everywhere, and you can send it home to the Pet room.", 22, UI.TEXT, true))
	for pet in e["pets"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_pet_icon(pet["family"], 56))
		var name := UI.label(pet["name"], 26, UI.ACCENT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var following: bool = e["active"] == pet["id"] and e["mode"] == "follow"
		row.add_child(UI.label("Following you" if following else "In the Pet room", 20, UI.MUTED))
		var id: String = pet["id"]
		if following:
			var home := UI.button("Rest at home", "home", false, 0)
			home.set_meta("pet_id", id)
			home.pressed.connect(func(): Session.pet_mode("home"))
			row.add_child(home)
		else:
			var follow := UI.button("Follow me", "paw", true, 0)
			follow.set_meta("pet_id", id)
			follow.pressed.connect(func(): Session.pet_follow(id))
			row.add_child(follow)
		_insert(col, row)
	if e["pets"].size() >= PetRules.MAX_PETS:
		return
	_insert(col, UI.label("Adopt a pet", 26, UI.ACCENT))
	var fams := HBoxContainer.new()
	fams.add_theme_constant_override("separation", 10)
	for fam in PetRules.ORDER:
		var b := UI.button(PetRules.FAMILIES[fam]["name"], "pet_" + fam, fam == _adopt["family"], 0)
		b.set_meta("family", fam)
		var f: String = fam
		b.pressed.connect(func():
			_adopt = {"family": f, "color": 0, "name": 0}
			open_pets())
		fams.add_child(b)
	_insert(col, fams)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 10)
	var variants: Array = PetRules.FAMILIES[_adopt["family"]]["variants"]
	for i in variants.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(60, 60)
		sw.focus_mode = Control.FOCUS_NONE
		sw.set_meta("color", i)
		sw.tooltip_text = variants[i]["name"]
		sw.add_theme_stylebox_override("normal", UI.box(variants[i]["swatch"], 30, 5 if i == _adopt["color"] else 2, UI.ACCENT if i == _adopt["color"] else UI.PANEL))
		var ci := i
		sw.pressed.connect(func():
			_adopt["color"] = ci
			open_pets())
		opts.add_child(sw)
	opts.add_child(UI.label(variants[clampi(_adopt["color"], 0, variants.size() - 1)]["name"], 22, UI.ACCENT))
	var names: Array = PetRules.FAMILIES[_adopt["family"]]["names"]
	for i in names.size():
		var nb := UI.button(names[i], "", i == _adopt["name"], 0)
		nb.set_meta("name_index", i)
		var ni := i
		nb.pressed.connect(func():
			_adopt["name"] = ni
			open_pets())
		opts.add_child(nb)
	_insert(col, opts)
	var go := UI.button("Adopt", "heart", true, 220)
	go.name = "AdoptButton"
	go.pressed.connect(func():
		Sfx.play("place")
		controller._ask(Session.adopt_pet(_adopt["family"], _adopt["color"], _adopt["name"]), func(r):
			if r.get("ok"):
				show_toast(tr("%s is your pet now!") % tr(r["pet"]["name"]))))
	_insert(col, go)


## A pet someone tapped: pat it, or feed it at a food bowl.
func _open_pet_card(owner: String, pet_id: String) -> void:
	var pet: Dictionary = PetRules.find_pet(Session.model, owner, pet_id)
	if pet.is_empty():
		return
	var whose: String = Session.model.roster.get(owner, {}).get("nick", "")
	var body := tr("Your pet") if owner == Session.my_pid else tr("%s's pet") % tr(whose)
	var col := _dialog(tr(pet["name"]), body, [
		["Close", func(): pass, false],
		["Feed", func(): Session.pet_care(owner, pet_id, "feed"), false],
		["Pat", func(): Session.pet_care(owner, pet_id, "pat"), true]])
	_insert(col, _pet_icon(pet["family"], 96))


# ------------------------------------------------------------- play ideas (design/playability-8-12.md)

## "On display" (F10): the toggle while decorating and the badge while playing.
func _refresh_display() -> void:
	if controller == null or _display_btn == null:
		return
	var by: Dictionary = Session.model.display_by(controller.space)
	var deco: bool = controller.mode == "decorate"
	var zoo: bool = controller.space == Places.ZOO
	_display_btn.visible = deco and not zoo
	_display_btn.text = "Take off display" if not by.is_empty() else "Put on display"
	_display_badge.visible = not deco and not by.is_empty()
	var helping: bool = by.get("helpers", []).has(Session.my_pid)
	(_display_badge.get_child(0) as Label).text = "On display · you are helping" if helping else "On display"
	_help_btn.visible = deco and not zoo and by.get("pid", "") == Session.my_pid and Session.players.size() > 1
	_trail_btn.visible = deco and controller.space == "town" and Session.model.trail_signs().size() < PlayRules.MIN_TRAIL
	_bp_btn.visible = deco and not zoo


## Someone else put this place on display: ask before changing it. Yes takes it
## off display (anyone may) and starts decorating.
func _ask_display(space: String, by: Dictionary) -> void:
	var who: String = tr(by.get("nick", ""))
	_dialog("On display", tr("%s put this place on display. Change it anyway?") % who, [
		["Leave it", func(): pass, false],
		["Change it", func():
			Session.set_display(space, false)
			controller.set_mode("decorate", true), true]])


## Biscuit's card: the hobby and an invitation to play fetch (F03).
func _open_fetch() -> void:
	var def: Dictionary = AnimalBrain.SPECIES["dog"]
	var name: String = tr(def["name"])
	var col := _dialog(name, _busy_line("dog") + tr(def["hobby"]) % name, [["Close", func(): pass, false],
		["Play fetch", func(): controller.start_fetch(), true]])
	col.get_parent().get_parent().get_parent().name = "Fetch"
	_insert_visit(col, "dog")
	_insert_invite(col, "fetch", "")


## The snack card at a snack tray (F01): three bases, three toppings, one tap.
func _open_snacks(tray: String) -> void:
	var col := _dialog("Make a snack", "Pick a snack and a topping. Then tap the snack to share it.", [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "Snacks"
	for base in PlayRules.BASES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var pic := TextureRect.new()
		pic.texture = thumbs.textures.get(base)
		pic.custom_minimum_size = Vector2(80, 80)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
		var name := UI.label(Catalog.ITEMS[base]["name"], 24, UI.ACCENT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		for topping in PlayRules.TOPPING_ORDER:
			var b := UI.button(PlayRules.TOPPING_NAMES[topping], "", false, 120)
			b.add_theme_stylebox_override("normal", UI.box(Palette.paint(PlayRules.TOPPINGS[topping]).lerp(Color.WHITE, 0.55), 28, 3, Palette.paint(PlayRules.TOPPINGS[topping])))
			b.set_meta("snack", [base, topping])
			var bk: String = base
			var tk: String = topping
			b.pressed.connect(func():
				_close_overlay()
				Sfx.play("place")
				controller._ask(Session.make_snack(tray, bk, tk), func(r):
					if r.get("ok"):
						show_toast("Snack ready! Tap it and choose Share.")))
			row.add_child(b)
		_insert(col, row)


# ------------------------------------------------------------- play ideas batch 2

## Dress-up (F07): hats and clothes color, changed in town any time, seen by friends.
func open_dress_up() -> void:
	var av: Dictionary = Session.players.get(Session.my_id, {}).get("avatar", {})
	var col := _dialog("Dress up", "Pick a hat and a color. Change any time; friends see it.", [["Close", func(): pass, true]])
	col.get_parent().get_parent().get_parent().name = "DressUp"
	var wardrobe := UI.button("Wardrobe", "friends", true, 0)
	wardrobe.name = "WardrobeButton"
	wardrobe.custom_minimum_size.y = 60
	wardrobe.pressed.connect(func():
		Sfx.play("tap")
		_close_overlay()
		open_wardrobe(_wardrobe_cat))
	_insert(col, wardrobe)
	var hats := HFlowContainer.new()
	hats.add_theme_constant_override("h_separation", 8)
	hats.add_theme_constant_override("v_separation", 8)
	_insert(col, hats)
	for h in Avatar.HATS:
		var b := UI.button(Avatar.HAT_NAMES[h], "", av.get("hat", "") == h, 0)
		b.custom_minimum_size.y = 60
		b.set_meta("hat", h)
		var hk: String = h
		b.pressed.connect(func():
			Sfx.play("tap")
			controller._ask(Session.dress(hk, int(av.get("outfit_color", 0))), func(r):
				if r.get("ok"):
					open_dress_up()))
		hats.add_child(b)
	var styles := HFlowContainer.new()
	styles.add_theme_constant_override("h_separation", 8)
	_insert(col, styles)
	for o in Avatar.OUTFITS.size():
		var ob := UI.button(Avatar.OUTFITS[o], "", int(av.get("outfit", 0)) == o, 0)
		ob.custom_minimum_size.y = 56
		ob.set_meta("outfit", o)
		var ok_o: int = o
		ob.pressed.connect(func():
			Sfx.play("tap")
			controller._ask(Session.dress(str(av.get("hat", "")), int(av.get("outfit_color", 0)), ok_o), func(r):
				if r.get("ok"):
					open_dress_up()))
		styles.add_child(ob)
	var props := HFlowContainer.new()
	props.add_theme_constant_override("h_separation", 8)
	_insert(col, props)
	for pr in Avatar.PROPS:
		var pb := UI.button(Avatar.PROP_NAMES[pr], "", av.get("prop", "") == pr, 0)
		pb.custom_minimum_size.y = 56
		pb.set_meta("prop", pr)
		var pk: String = pr
		pb.pressed.connect(func():
			Sfx.play("tap")
			controller._ask(Session.dress(str(av.get("hat", "")), int(av.get("outfit_color", 0)), -1, pk), func(r):
				if r.get("ok"):
					open_dress_up()))
		props.add_child(pb)
	var colors := HBoxContainer.new()
	colors.alignment = BoxContainer.ALIGNMENT_CENTER
	_insert(col, colors)
	for i in Palette.PAINT.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(56, 56)
		sw.focus_mode = Control.FOCUS_NONE
		sw.set_meta("outfit_color", i)
		var on: bool = int(av.get("outfit_color", 0)) == i
		sw.add_theme_stylebox_override("normal", UI.box(Palette.paint(i), 28, 5 if on else 3, UI.TEXT if on else UI.PANEL))
		var idx := i
		sw.pressed.connect(func():
			Sfx.play("tap")
			controller._ask(Session.dress(str(av.get("hat", "")), idx), func(r):
				if r.get("ok"):
					open_dress_up()))
		colors.add_child(sw)


## Story (F05): pick an inspiration card, then the camera takes three pictures.
func open_story_cards() -> void:
	var col := _dialog("Make a story", "Pick a card, set up a scene, then take three pictures. Friends can pose!", [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "StoryCards"
	_insert_invite(col, "story", "")
	for c in Story.CARDS:
		var b := UI.button(c["title"] if c["title"] != "" else "No title", "book", false, 520)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 64
		b.set_meta("story_card", c["id"])
		b.tooltip_text = c["prompt"]
		var cid: String = c["id"]
		b.pressed.connect(func():
			_close_overlay()
			Sfx.play("place")
			story = {"card": cid, "panels": []}
			show_toast(Story.card(cid)["prompt"])
			_refresh_play_chip())
		_insert(col, b)


## A picture for the story in progress (from the camera); after the third the
## child arranges them.
func story_add_panel(img: Image) -> void:
	if story.is_empty():
		return
	story["panels"].append(img)
	Sfx.play("photo")
	_refresh_play_chip()
	if story["panels"].size() >= Story.PANELS:
		_open_story_arrange([0, 1, 2])


func _open_story_arrange(order: Array) -> void:
	_close_overlay()
	var card: Dictionary = Story.card(story.get("card", "none"))
	var col := _dialog(card["title"] if card["title"] != "" else "Your story", "Move the pictures to change the story. Then keep it.", [
		["Start over", func():
			story["panels"] = []
			_refresh_play_chip(), false],
		["Keep story", func():
			story_kept.emit(story["panels"], order, story["card"])
			story = {}
			_refresh_play_chip(), true]])
	col.get_parent().get_parent().get_parent().name = "StoryArrange"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_insert(col, row)
	for slot in order.size():
		var v := VBoxContainer.new()
		row.add_child(v)
		var pic := TextureRect.new()
		pic.texture = ImageTexture.create_from_image(story["panels"][order[slot]])
		pic.custom_minimum_size = Vector2(200, 150)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		v.add_child(pic)
		var arrows := HBoxContainer.new()
		arrows.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(arrows)
		for d in [-1, 1]:
			var b := UI.icon_button("rotate_left" if d < 0 else "rotate_right", "Move left" if d < 0 else "Move right", 56)
			b.disabled = slot + d < 0 or slot + d >= order.size()
			b.set_meta("story_move", [slot, d])
			var sl: int = slot
			var dd: int = d
			b.pressed.connect(func(): _open_story_arrange(Story.move(order, sl, dd)))
			arrows.add_child(b)


func _refresh_play_chip() -> void:
	if _play_chip == null:
		return
	_poses.visible = not story.is_empty()
	if not story.is_empty():
		var card: Dictionary = Story.card(story["card"])
		var title: String = tr(card["title"]) if card["title"] != "" else tr("Story")
		_play_chip_label.text = "%s · %s" % [title, tr("picture %d of %d") % [mini(story["panels"].size() + 1, Story.PANELS), Story.PANELS]]
		_play_chip.visible = true
	elif not trail.is_empty():
		var signs: Array = Session.model.trail_signs()
		var next: Dictionary = signs[trail["found"]] if trail["found"] < signs.size() else {}
		var clue: String = PlayRules.clue_of(next) if not next.is_empty() else ""
		_play_chip_label.text = tr("Trail: sign %d of %d · %s there") % [trail["found"] + 1, trail["total"], tr(CLUE_NAMES.get(clue, ""))]
		_play_chip.visible = true
	else:
		_play_chip.visible = false
	controller.world.play_fx.trail_target = "" if trail.is_empty() else _next_trail_sign_id()


const CLUE_NAMES := {"wave": "Wave", "cheer": "Cheer", "dance": "Dance", "heart": "Love"}


func _next_trail_sign_id() -> String:
	var signs: Array = Session.model.trail_signs()
	return signs[trail["found"]]["id"] if trail.get("found", 0) < signs.size() else ""


func _set_trail(t: Dictionary) -> void:
	trail = t
	_refresh_play_chip()


## Trail progress from the authority (F06).
func _on_trail(peer: int, found: int, total: int, done: bool, nick: String) -> void:
	if peer == Session.my_id:
		if done:
			_set_trail({})
			Sfx.play("lantern")
			show_toast("You walked the whole trail! A keepsake sticker is in the scrapbook.")
		else:
			if found > 0:
				Sfx.play("place")
				show_toast(tr("Sign %d found!") % found)
			_set_trail({"found": found, "total": total})
	elif done:
		show_toast(tr("%s walked the whole trail!") % tr(nick))


## A trail sign (F06): its clue, change the clue, or follow the trail.
func _open_trail_sign(id: String) -> void:
	var it: Dictionary = Session.model.items.get(id, {})
	if it.is_empty():
		return
	var clue := PlayRules.clue_of(it)
	var col := _dialog(tr("Trail sign %d") % int(it.get("num", 1)), tr("Clue: %s next to this sign.") % tr(CLUE_NAMES[clue]), [
		["Close", func(): pass, false],
		["Change clue", func():
			controller._ask(Session.change_face(id), func(r):
				if r.get("ok"):
					_open_trail_sign(id)
				elif r.get("error", "") != "":
					show_hint(r["error"])), false],
		["Follow the trail", func():
			controller._ask(Session.follow_trail(true), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					show_toast(r["error"])), true]])
	col.get_parent().get_parent().get_parent().name = "TrailSign"
	_insert_invite(col, "trail", id)
	var ic := TextureRect.new()
	ic.texture = UI.icon(clue, 72)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_insert(col, ic)


const EMOTE_NAMES := {"wave": "Wave", "cheer": "Cheer", "dance": "Dance", "heart": "Love"}

func _emote_row(on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Emotes"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for e in Echoes.EMOTES:
		var b := UI.icon_button(e, EMOTE_NAMES[e], 72)
		b.set_meta("emote", e)
		var kind: String = e
		b.pressed.connect(func():
			Sfx.play("tap")
			on_pick.call(kind))
		row.add_child(b)
	return row


func _emote_icons(emotes: Array, size := 56) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for e in emotes:
		var t := TextureRect.new()
		t.texture = UI.icon(str(e), size)
		t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		t.custom_minimum_size = Vector2(size + 8, size + 8)
		row.add_child(t)
	return row


## Leave a hello: pick three emotes, then leave them where the child stands. It replaces the
## child's last hello, stays seven days, and friends can answer it with one emote.
func _open_echo_recorder(picked: Array = []) -> void:
	var buttons := [["Close", func(): pass, false]]
	if not picked.is_empty():
		buttons.append(["Start over", func(): _open_echo_recorder([]), false])
	if picked.size() == Echoes.LENGTH:
		buttons.append(["Leave it here", func():
			controller._ask(Session.leave_echo(picked), func(r):
				if r.get("ok"):
					show_toast("Your hello is here for seven days. Friends who come by can answer.")
				elif r.get("error", "") != "":
					show_hint(r["error"])), true])
	var body := "Pick three emotes. Friends who come by see them and can answer with one."
	if picked.size() == Echoes.LENGTH:
		body = "Leave this hello here? It replaces your last one."
	var col := _dialog("Leave a hello", body, buttons)
	col.get_parent().get_parent().get_parent().name = "EchoRecorder"
	if not picked.is_empty():
		var shown := _emote_icons(picked)
		shown.name = "Picked"
		_insert(col, shown)
	if picked.size() < Echoes.LENGTH:
		_insert(col, _emote_row(func(kind): _open_echo_recorder(picked + [kind])))


## A hello's card. The child's own: who answered, how long it stays, Take it away, Leave a new one.
## A friend's: the three emotes and four buttons to answer with one.
func _open_echo(owner: String) -> void:
	var e: Dictionary = Session.model.echoes.get(owner, {})
	if e.is_empty():
		return
	var days: int = Echoes.days_left(e, Session.echo_now())
	if owner == Session.my_pid:
		var lines := []
		for a in e["answers"].values():
			lines.append(tr("%s answered: %s") % [tr(a["nick"]), tr(EMOTE_NAMES.get(a["emote"], "Wave"))])
		if lines.is_empty():
			lines.append(tr("Nobody has answered yet."))
		lines.append(tr("It stays for %d more days.") % days)
		var col := _dialog("Your hello", "\n".join(lines), [["Close", func(): pass, false],
			["Take it away", func():
				controller._ask(Session.delete_echo(), func(r):
					if r.get("ok"):
						show_toast("Your hello is gone.")), false],
			["Leave a new one", func(): _open_echo_recorder([]), true]])
		col.get_parent().get_parent().get_parent().name = "Echo"
		_insert(col, _emote_icons(e["emotes"]))
		Session.seen_echo()
		return
	var col := _dialog(tr("A hello from %s") % tr(e["nick"]), tr("Answer with one emote. %s sees it on the next visit.") % tr(e["nick"]), [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "Echo"
	_insert(col, _emote_icons(e["emotes"]))
	_insert(col, _emote_row(func(kind):
		_close_overlay()
		controller._ask(Session.answer_echo(owner, kind), func(r):
			if r.get("ok"):
				Session.send_emote(kind)
				show_toast(tr("Your answer is waiting for %s.") % tr(e["nick"]))
			elif r.get("error", "") != "":
				show_hint(r["error"]))))


var _board_color := 1   # the paint color picked on the picture board's card (1 to 8; 0 rubs out)

## The picture board's card: eight paint colors and a rubber, and the 8 x 8 picture. A tap paints one
## square in the picked color. Friends' squares appear while the card is open.
func _open_board(id: String) -> void:
	if not Session.model.items.has(id):
		return
	var col := _dialog("Picture board", "Pick a color, then tap squares. Everyone can add to the picture.", [["Close", func(): pass, true]])
	var root := col.get_parent().get_parent().get_parent()
	root.name = "Board"
	root.set_meta("item_id", id)
	var colors := HBoxContainer.new()
	colors.name = "Colors"
	colors.alignment = BoxContainer.ALIGNMENT_CENTER
	colors.add_theme_constant_override("separation", 6)
	_insert(col, colors)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = PictureBoard.SIDE
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var holder := CenterContainer.new()
	holder.add_child(grid)
	_insert(col, holder)
	var paint_cell := func(b: Button, d: int):
		var c: Color = Palette.paint(d - 1) if d > 0 else UI.PAPER
		b.add_theme_stylebox_override("normal", UI.box(c, 8, 2, UI.SOFT.darkened(0.12)))
		b.add_theme_stylebox_override("hover", UI.box(c, 8, 3, UI.ACCENT))
		b.add_theme_stylebox_override("pressed", UI.box(c, 8, 4, UI.TEXT))
		b.set_meta("color", d)
	var mark := func():
		for sw in colors.get_children():
			var d: int = sw.get_meta("color")
			var c: Color = Palette.paint(d - 1) if d > 0 else UI.PAPER
			sw.add_theme_stylebox_override("normal", UI.box(c, 26, 5 if d == _board_color else 2, UI.TEXT if d == _board_color else UI.SOFT.darkened(0.12)))
	for d in range(1, Palette.PAINT.size() + 1) + [0]:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(52, 52)
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = Palette.PAINT[d - 1]["name"] if d > 0 else "Rub out"
		sw.set_meta("color", d)
		if d == 0:
			sw.icon = UI.icon("close", 28)
			sw.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var pick: int = d
		sw.pressed.connect(func():
			Sfx.play("tap")
			_board_color = pick
			mark.call())
		colors.add_child(sw)
	mark.call()
	var pix: String = PictureBoard.sanitize(Session.model.items[id].get("pix"))
	for i in PictureBoard.CELLS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("cell", i)
		paint_cell.call(b, PictureBoard.cell(pix, i))
		var at: int = i
		b.pressed.connect(func():
			Sfx.play("pop")
			controller._ask(Session.set_pixel(id, at, _board_color), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					show_hint(r["error"])))
		grid.add_child(b)
	# Squares painted by anyone, while the card is open. The card owns the connection.
	var on_item := func(item: Dictionary):
		if item.get("id", "") == id and is_instance_valid(grid):
			var now: String = PictureBoard.sanitize(item.get("pix"))
			for b in grid.get_children():
				if b.get_meta("color") != PictureBoard.cell(now, b.get_meta("cell")):
					paint_cell.call(b, PictureBoard.cell(now, b.get_meta("cell")))
	Session.item_changed.connect(on_item)
	root.tree_exiting.connect(func():
		if Session.item_changed.is_connected(on_item):
			Session.item_changed.disconnect(on_item))


## The treasure chest's card (puzzle rooms): what the chest still needs, the one rule of the puzzle,
## Open when everything is right, and Start again for anyone at any time.
func _open_puzzle(id: String) -> void:
	var it: Dictionary = Session.model.items.get(id, {})
	if it.is_empty():
		return
	var space: String = it["space"]
	var st: Dictionary = Session.puzzle_state(space)
	var p: Dictionary = Puzzles.progress(Session.model, space, st)
	var body := ""
	if p["open"]:
		body = tr("The chest is open! Start again to hide the treasure once more.")
		if not st["by"].is_empty():
			body = tr("Opened by %s!") % ", ".join(st["by"].map(func(n): return tr(n))) + "\n" + body
	elif p["ready"]:
		body = tr("Every key and every picture is right. Open it!")
	else:
		var lines := []
		if p["keys"] > 0:
			lines.append(tr("Keys found: %d of %d") % [p["keys_found"], p["keys"]])
		if p["dials"] > 0:
			lines.append(tr("Pictures right: %d of %d") % [p["dials_right"], p["dials"]])
		lines.append(tr("Find the keys. Turn each picture dial to the picture on the clue card with the same color and dots."))
		body = "\n".join(lines)
	var buttons := [["Close", func(): pass, false],
		["Start again", func():
			controller._ask(Session.reset_puzzle(space), func(r):
				if r.get("ok"):
					show_toast("The puzzle is ready to play again.")
				elif r.get("error", "") != "":
					show_hint(r["error"])), false]]
	if p["ready"]:
		buttons.append(["Open the chest", func():
			controller._ask(Session.use_puzzle(id), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					show_hint(r["error"])), true])
	var col := _dialog("Treasure chest", body, buttons)
	var root := col.get_parent().get_parent().get_parent()
	root.name = "Puzzle"
	root.set_meta("item_id", id)


## Everyone in the place hears who opened the chest.
func _on_puzzle_changed(space: String, st: Dictionary, was: Dictionary) -> void:
	if controller == null or space != controller.space:
		return
	if bool(st.get("open", false)) and not bool(was.get("open", false)):
		var names: Array = Array(st.get("by", [])).map(func(n): return tr(str(n)))
		show_toast(tr("%s opened the treasure chest!") % ", ".join(names) if not names.is_empty() else tr("The treasure chest is open!"))


## The music box card (F08): 4 sounds x 8 steps, Play/Stop, and this device's mute.
func _open_music(id: String) -> void:
	if not Session.model.items.has(id):
		return
	var col := _dialog("Music box", "Tap the squares to make a tune. Everyone near hears it.", [["Close", func(): pass, true]])
	var root := col.get_parent().get_parent().get_parent()
	root.name = "Music"
	root.set_meta("item_id", id)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = TownModel.MUSIC_STEPS + 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_insert(col, grid)
	for r in PlayRules.SOUNDS.size():
		# The row name is also the "my part" button: tap it to play this part (optional).
		var name_b := UI.button(PlayRules.SOUND_NAMES[PlayRules.SOUNDS[r]], "", false, 0)
		name_b.custom_minimum_size = Vector2(120, 52)
		name_b.set_meta("part", r)
		var pr: int = r
		name_b.pressed.connect(func():
			Sfx.play("tap")
			controller._ask(Session.claim_music_part(id, pr), func(res):
				if not res.get("ok") and res.get("error", "") != "":
					show_hint(res["error"])))
		grid.add_child(name_b)
		for st in TownModel.MUSIC_STEPS:
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(52, 52)
			cell.focus_mode = Control.FOCUS_NONE
			cell.set_meta("note", [r, st])
			var rr: int = r
			var ss: int = st
			cell.pressed.connect(func():
				if not Sfx.music_boxes_muted:
					Sfx.play("mb_" + PlayRules.SOUNDS[rr])
				controller._ask(Session.toggle_note(id, rr, ss), func(res):
					if not res.get("ok") and res.get("error", "") != "":
						show_hint(res["error"])))
			grid.add_child(cell)
	var row := HBoxContainer.new()
	row.name = "Controls"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_insert(col, row)
	var play := UI.button("Play", "play", true, 160)
	play.name = "PlayButton"
	play.pressed.connect(func():
		var on: bool = not Session.model.items.get(id, {}).get("on", false)
		controller._ask(Session.play_music(id, on), func(res):
			if not res.get("ok") and res.get("error", "") != "":
				show_hint(res["error"])))
	row.add_child(play)
	var mute := UI.button("Mute music boxes" if not Sfx.music_boxes_muted else "Hear music boxes", "music", false, 0)
	mute.name = "MuteButton"
	mute.pressed.connect(func():
		Sfx.set_music_boxes_muted(not Sfx.music_boxes_muted)
		mute.text = "Mute music boxes" if not Sfx.music_boxes_muted else "Hear music boxes")
	row.add_child(mute)
	_insert_invite(col, "music", id)
	_refresh_music_grid(id)


func _refresh_music_grid(id: String) -> void:
	var root := _overlay.get_node_or_null("Music")
	if root == null:
		return
	var it: Dictionary = Session.model.items.get(id, {})
	var song: Array = TownModel.sanitize_song(it.get("song"))
	for cell in root.find_children("*", "Button", true, false):
		if cell.has_meta("note"):
			var rc: Array = cell.get_meta("note")
			var on: bool = int(song[rc[0]]) & (1 << rc[1]) != 0
			var c: Color = [Color("#f2c75c"), Palette.paint(2), Color("#9fd0ea"), Palette.paint(5)][rc[0]]
			cell.add_theme_stylebox_override("normal", UI.box(c if on else UI.PAPER, 14, 3, c.darkened(0.25)))
			cell.add_theme_stylebox_override("hover", UI.box(c.lightened(0.2) if on else UI.PAPER, 14, 3, c.darkened(0.25)))
			cell.set_meta("on", on)
	var play := root.find_child("PlayButton", true, false) as Button
	if play:
		play.text = "Stop" if it.get("on", false) else "Play"
		play.icon = UI.icon("close" if it.get("on", false) else "play")
	var parts: Dictionary = Session.music_part_names(id)
	for b in root.find_children("*", "Button", true, false):
		if b.has_meta("part"):
			var row: int = b.get_meta("part")
			var who: String = parts.get(row, "")
			var sound: String = tr(PlayRules.SOUND_NAMES[PlayRules.SOUNDS[row]])
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = sound if who == "" else "%s · %s" % [sound, tr(who)]
			b.set_meta("holder", who)


# ------------------------------------------------------------- r12: wardrobe

## Which slot a wardrobe category fills (held bags go in the hand, like umbrellas).
const WARDROBE_SLOT := {"Tops": "top", "Bottoms": "bottom", "Dress-up": "dress", "Headwear": "head",
	"Accessories": "face", "Socks": "socks", "Shoes": "shoes", "Bags": "bag", "Umbrellas": "hand"}
var _wardrobe_cat := "Tops"
var _wardrobe_scroll := {}   # category -> scroll position, kept while the wardrobe is reopened


## The wardrobe (r12): every accepted wearable, by category, free; tap to wear, tap Take it off.
func open_wardrobe(category := "Tops") -> void:
	_wardrobe_cat = category
	var av: Dictionary = Session.players.get(Session.my_id, {}).get("avatar", {})
	var worn: Dictionary = av.get("wear", {})
	var col := _dialog("Wardrobe", "Everything is free. Tap something to wear it; friends see it.", [
		["Back", func(): open_dress_up(), false], ["Close", func(): pass, true]])
	col.get_parent().get_parent().get_parent().name = "Wardrobe"
	# When the card was built and how many pictures existed then: readiness is measured from here.
	col.get_parent().get_parent().get_parent().set_meta("built_ms", Time.get_ticks_msec())
	col.get_parent().get_parent().get_parent().set_meta("renders_at_build", wardrobe_thumbs().renders)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	_insert(col, tabs)
	for cat in Wearables.CATEGORIES:
		var t := UI.button(cat, "", cat == category, 0)
		t.custom_minimum_size.y = 56
		t.set_meta("wear_cat", cat)
		var ck: String = cat
		t.pressed.connect(func():
			Sfx.play("tap")
			_close_overlay()
			open_wardrobe(ck))
		tabs.add_child(t)
	var slots: Array = [WARDROBE_SLOT[category]]
	if category == "Bags":
		slots.append("hand")   # a hand-held bag is worn in the hand
	var here := Wearables.ids_in(category)
	here.sort_custom(func(a, b): return tr(Wearables.get_def(a)["name"]).naturalnocasecmp_to(tr(Wearables.get_def(b)["name"])) < 0)   # in the player's language
	var wearing := slots.filter(func(sl): return worn.has(sl) and here.has(worn[sl]))
	var off := UI.button("Take it off", "close", false, 0)
	off.custom_minimum_size.y = 56
	off.set_meta("wear_off", category)
	off.disabled = wearing.is_empty()
	off.pressed.connect(func():
		Sfx.play("tap")
		for sl in wearing:
			controller._ask(Session.wear(sl, ""), func(r):
				if r.get("ok"):
					_close_overlay()
					open_wardrobe(category)))
	_insert(col, off)
	var waiting := Wearables.gated().values().filter(func(g): return g["category"] == category).size()
	if waiting > 0:
		_insert(col, UI.label(tr("%d more are still being checked and come later.") % waiting, 18, UI.MUTED, true))
	var scroll := ScrollContainer.new()
	scroll.name = "WardrobeScroll"
	scroll.custom_minimum_size = Vector2(560, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_insert(col, scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for id in here:
		var def := Wearables.get_def(id)
		var on: bool = worn.get(def["slot"], "") == id
		var b := _wardrobe_tile(id, def["name"], on)
		var iid: String = id
		var sl: String = def["slot"]
		b.pressed.connect(func():
			Sfx.play("tap")
			_wardrobe_scroll[category] = scroll.scroll_vertical
			controller._ask(Session.wear(sl, iid), func(r):
				if r.get("ok"):
					_close_overlay()
					open_wardrobe(category)
				elif r.get("error", "") != "":
					show_toast(r["error"])))
		grid.add_child(b)
	# Short screens (iPhone landscape, long German tab names): the list takes only the height the
	# rest of the card leaves inside the safe area. Refit whenever the card's layout settles or
	# changes (fonts, wrapped tabs and names, locale, safe area), not once after a fixed frame:
	# r12 Mac, a German card measured before its tabs wrapped stayed 985 px on a 969 px screen.
	var card: Control = col.get_parent()   # the panel (its CenterContainer re-centers it)
	var refit := func(): _fit_wardrobe(card, scroll)
	card.minimum_size_changed.connect(refit, CONNECT_DEFERRED)
	resized.connect(refit, CONNECT_DEFERRED)
	card.tree_exiting.connect(func(): resized.disconnect(refit))
	_fit_wardrobe(card, scroll)
	# Pictures (r14): only for the rows on screen (plus one row ahead), refreshed while scrolling and
	# when the card resizes; closing the card or opening another tab replaces the wanted list.
	var thumbs := wardrobe_thumbs()
	var on_pic := func(pid: String, tex: Texture2D): _show_wear_picture(grid, pid, tex)
	thumbs.picture_ready.connect(on_pic)
	card.tree_exiting.connect(func():
		thumbs.picture_ready.disconnect(on_pic)
		thumbs.want([]))
	# Back to where the child was in this tab once the list is laid out (r14 Mac: a position set one
	# frame after building was clamped to 0 when layout was not final yet, so a reopened tab showed other
	# rows). Re-applied each frame until the scroll range and position hold still (bounded).
	var target := int(_wardrobe_scroll.get(category, 0))
	var prev_max := -1.0
	var still := 0
	for i in 40:
		await get_tree().process_frame
		if not is_instance_valid(scroll):
			return
		_fit_wardrobe(card, scroll)
		var bar := scroll.get_v_scroll_bar()
		var want_v := clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
		scroll.scroll_vertical = want_v
		still = still + 1 if absf(bar.max_value - prev_max) < 0.5 and scroll.scroll_vertical == want_v else 0
		prev_max = bar.max_value
		if still >= 2:
			break
	# Follow scrolling and resizing only once the remembered position is back, so the rows at the top are
	# not pictured on the way to it; the card is "settled" from here on (tests wait for it before tapping).
	var follow := func(): _want_visible_pictures(scroll, grid)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): follow.call_deferred())
	scroll.resized.connect(func(): follow.call_deferred())
	_want_visible_pictures(scroll, grid)
	var root := card.get_parent().get_parent()
	if is_instance_valid(root):
		root.set_meta("settled", true)
		root.set_meta("settled_ms", Time.get_ticks_msec())


## Wardrobe tile size and the picture above the name.
const WEAR_TILE_W := 272.0
const WEAR_PIC_H := 76.0
const WEAR_NAME_SIZES := [20, 18, 16]

var _wear_thumbs: Node   # created the first time the Wardrobe opens, never at startup


## The on-demand picture maker for wardrobe tiles (wear_thumbs.gd), made on first use.
func wardrobe_thumbs() -> Node:
	if _wear_thumbs == null:
		_wear_thumbs = WearThumbs.new()
		_wear_thumbs.name = "WearThumbs"
		add_child(_wear_thumbs)
	return _wear_thumbs


## One wardrobe tile: the item's picture above its whole localized name (broken only between words,
## up to three lines, UI.fit_text); a check badge marks what is worn. The tile is the touch target.
func _wardrobe_tile(id: String, name_en: String, on: bool) -> Button:
	var b := UI.button("", "", on, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("wear_item", id)
	b.tooltip_text = name_en
	var fit := UI.fit_text(I18n.ui_font(), tr(name_en), WEAR_TILE_W - 24.0, 3, WEAR_NAME_SIZES)
	b.custom_minimum_size = Vector2(WEAR_TILE_W, 8.0 + WEAR_PIC_H + 4.0 + fit["height"] + 10.0)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 8
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.name = "Pic"
	pic.custom_minimum_size = Vector2(0, WEAR_PIC_H)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = wardrobe_thumbs().get_cached(id)
	col.add_child(pic)
	var name := UI.label(name_en, fit["size"], UI.PANEL if on else UI.TEXT, true)
	name.name = "Name"
	name.autowrap_mode = TextServer.AUTOWRAP_WORD
	name.add_theme_constant_override("line_spacing", 0)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.max_lines_visible = 3
	name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	name.custom_minimum_size.y = fit["height"]
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)
	if on:
		var badge := TextureRect.new()
		badge.name = "Worn"
		badge.texture = UI.icon("check", 36)
		badge.position = Vector2(8, 6)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
	return b


## Asks for pictures of the tiles inside the visible part of the list, plus one row below.
func _want_visible_pictures(scroll: ScrollContainer, grid: GridContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(grid) or _wear_thumbs == null:
		return
	var view := scroll.get_global_rect()
	view.size.y += WEAR_PIC_H + 60.0   # one row ahead
	var ids := []
	for b in grid.get_children():
		if b.has_meta("wear_item") and (b as Control).get_global_rect().intersects(view):
			ids.append(b.get_meta("wear_item"))
	_wear_thumbs.want(ids)


func _show_wear_picture(grid: GridContainer, id: String, tex: Texture2D) -> void:
	if not is_instance_valid(grid) or tex == null:
		return
	for b in grid.get_children():
		if b.get_meta("wear_item", "") == id:
			(b.find_child("Pic", true, false) as TextureRect).texture = tex


## Gives the wardrobe list the height the safe area leaves (at most 360, at least about two rows).
func _fit_wardrobe(card: Control, scroll: ScrollContainer) -> void:
	if not is_instance_valid(card) or not is_instance_valid(scroll):
		return
	var rest: float = card.get_combined_minimum_size().y - scroll.custom_minimum_size.y
	var h: float = clampf(get_global_rect().size.y - 16.0 - rest, 150.0, 360.0)
	if absf(h - scroll.custom_minimum_size.y) > 0.5:
		scroll.custom_minimum_size.y = h
		card.reset_size()


# ------------------------------------------------------------- r11: invitations, animal games, blueprints

## An "Invite friends" button for a card, shown when friends are in town (F10).
## House visits (r18, design/animal-visits.md): "Come home with me" on an animal's card, or "Say goodbye"
## when it is already visiting this child. Tumble (too big for the door) gets neither.
## Animal passengers: while this child sits in a cart at its station, an animal's card offers a ride
## in the trailer; an animal already in this child's trailer can be let out.
func _insert_ride(col: VBoxContainer, kind: String) -> void:
	var station: String = Session.ride_of(Session.my_id)
	if station == "" or not AnimalBrain.VISITORS.has(kind):
		return
	var mine: bool = Animals.riders.get(kind, "") == station
	if not mine and Session.rides[station]["phase"] != "ready":
		return
	var b := UI.button("Hop out" if mine else "Come for a ride", "stand" if mine else "sit", false, 0)
	b.custom_minimum_size.y = 56
	b.name = "RideOut" if mine else "RideInvite"
	b.pressed.connect(func():
		_close_overlay()
		Sfx.play("tap")
		controller._ask(Session.ride_with_animal(kind, not mine), func(r):
			if r.get("ok") and not mine:
				show_toast(tr("%s is coming for a ride!") % tr(AnimalBrain.SPECIES[kind]["name"]))
			elif not r.get("ok") and r.get("error", "") != "":
				show_toast(r["error"])))
	_insert(col, b)


func _insert_visit(col: VBoxContainer, kind: String) -> void:
	_insert_ride(col, kind)
	if not AnimalBrain.VISITORS.has(kind):
		return
	var mine: bool = Animals.guests.get(kind, 0) == Session.my_id
	var b := UI.button("Say goodbye" if mine else "Come home with me", "wave" if mine else "home", false, 0)
	b.custom_minimum_size.y = 56
	b.name = "VisitGoodbye" if mine else "VisitInvite"
	b.pressed.connect(func():
		_close_overlay()
		Sfx.play("tap")
		ask_visit(kind, not mine))
	_insert(col, b)


## Asks the authority to start (on) or end a visit and says what happened.
func ask_visit(kind: String, on: bool) -> void:
	var name: String = tr(AnimalBrain.SPECIES[kind]["name"])
	controller._ask(Session.visit_animal(kind, on), func(r):
		if r.get("ok"):
			show_toast(tr("%s is coming home with you!") % name if on else tr("%s went back outside.") % name)
		elif r.get("error", "") != "":
			show_toast(r["error"]))


## A visiting animal's card indoors: its hobby, the emote tip and Say goodbye.
func _open_guest(kind: String) -> void:
	if not AnimalBrain.SPECIES.has(kind):
		return
	var name: String = tr(AnimalBrain.SPECIES[kind]["name"])
	var col := _dialog(name, tr(AnimalBrain.SPECIES[kind]["hobby"]) % name + "\n" + tr("Do an emote and %s answers with a move!") % name,
		[["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "Guest"
	_insert_visit(col, kind)


func _insert_invite(col: VBoxContainer, kind: String, target: String) -> void:
	if Session.players.size() <= 1:
		return
	var b := UI.button("Invite friends", "friends", false, 0)
	b.custom_minimum_size.y = 56
	b.set_meta("invite", kind)
	b.pressed.connect(func():
		Sfx.play("tap")
		_send_invite(kind, target))
	_insert(col, b)


func _send_invite(kind: String, target: String) -> void:
	controller._ask(Session.send_invite(kind, target), func(r):
		if r.get("ok"):
			show_toast("Your friends got your invitation. They can join or say not now.")
		elif r.get("error", "") != "":
			show_toast(r["error"]))


## One card per inviter: a newer invitation from the same friend replaces it.
func _on_invited(card: Dictionary) -> void:
	if _invites_box == null:
		var m := _corner(Control.PRESET_CENTER_RIGHT, 16)
		m.add_theme_constant_override("margin_right", 120)
		_invites_box = VBoxContainer.new()
		_invites_box.add_theme_constant_override("separation", 8)
		m.add_child(_invites_box)
	for old in _invites_box.get_children():
		if old.get_meta("from", "") == card["from"]:
			_invites_box.remove_child(old)
			old.queue_free()
	Sfx.play("pop")
	var p := UI.panel(20, UI.PANEL)
	p.set_meta("from", card["from"])
	p.custom_minimum_size.x = 340
	var v := VBoxContainer.new()
	p.add_child(v)
	var l := UI.label(tr("%s invites you:") % tr(card["nick"]), 20, UI.MUTED, true)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(l)
	v.add_child(UI.label(Invites.KINDS.get(card["kind"], ""), 24, UI.ACCENT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var later := UI.button("Not now", "", false, 0)
	later.custom_minimum_size.y = 56
	later.set_meta("invite_answer", "not_now")
	later.pressed.connect(func():
		Sfx.play("tap")
		Session.answer_invite(card["from"], "not_now")
		p.queue_free())
	row.add_child(later)
	var join := UI.button("Join", "check", true, 0)
	join.custom_minimum_size.y = 56
	join.set_meta("invite_answer", "join")
	join.pressed.connect(func():
		Sfx.play("tap")
		p.queue_free()
		controller._ask(Session.answer_invite(card["from"], "join"), func(r):
			if not r.get("ok"):
				show_toast(r.get("error", ""))
				return
			if card["kind"] == "help":
				show_toast(tr("You are helping %s. Tap Decorate to change things.") % tr(card["nick"]))
			controller.travel_to(card["space"], Vector2(card["x"], card["z"]))))
	row.add_child(join)
	_invites_box.add_child(p)
	var card_ref: WeakRef = weakref(p)   # the card may be answered (freed) long before it expires
	get_tree().create_timer(Invites.LIFETIME).timeout.connect(func():
		var still: Node = card_ref.get_ref()
		if still:
			still.queue_free())


## A living town: what this animal is busy with right now ("Wooly loves this music!"), as the first
## line of its card; "" when it is on its own routine.
func _busy_line(kind: String) -> String:
	var line: String = Animals.focus_line(kind)
	return tr(line) % tr(AnimalBrain.SPECIES[kind]["name"]) + "\n" if line != "" else ""


## The other animals' games (F03): one card per animal, with its own game.
const ANIMAL_GAMES := {
	"sheep": ["Sing with Wooly", "Do an emote: Wooly answers with a move of its own."],
	"rabbit": ["Garden with Bramble", "Bramble tends the nearest garden bed, and it grows a little."],
	"pig": ["Splash with Pip", "Pip runs to the nearest water and splashes. Come and watch!"],
	"elephant": ["Fountain with Tumble", "Pick a shape and Tumble sprays it."],
}


func _open_animal(kind: String) -> void:
	if not AnimalBrain.GAMES.has(kind):
		return
	var def: Dictionary = AnimalBrain.SPECIES[kind]
	var name: String = tr(def["name"])
	var g: Array = ANIMAL_GAMES[kind]
	var col := _dialog(name, _busy_line(kind) + tr(def["hobby"]) % name + "\n" + tr(g[1]), [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "Animal"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_insert(col, row)
	var options: Array = [["", 0]] if kind != "elephant" else [["Heart", 0], ["Star", 1], ["Round", 2]]
	for o in options:
		var b := UI.button(g[0] if o[0] == "" else o[0], "play", true, 0)
		b.custom_minimum_size.y = 60
		b.set_meta("animal_game", [kind, o[1]])
		var opt: int = o[1]
		b.pressed.connect(func():
			_close_overlay()
			Sfx.play("place")
			controller._ask(Session.play_with_animal(kind, opt), func(r):
				if r.get("ok"):
					show_toast(tr("%s is coming to play!") % name if r.get("result") == "started" else tr("You joined %s's game.") % name)
				elif r.get("error", "") != "":
					show_toast(r["error"])))
		row.add_child(b)
	_insert_visit(col, kind)
	_insert_invite(col, "animal", kind)


## Saved blueprints (F09): place one, or let it go.
func open_blueprints() -> void:
	var list := Blueprints.load_all()
	var col := _dialog("Blueprints", "Save a group of things you like (tap one thing, then Blueprint) and build it again anywhere." if list.is_empty() else "Pick a blueprint, then tap where it should go.", [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "Blueprints"
	for i in list.size():
		var bp: Dictionary = list[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var use := UI.button(tr(bp["name"]) + "  ·  " + (tr("1 thing") if bp["pieces"].size() == 1 else tr("%d things") % bp["pieces"].size()), "board", false, 360)
		use.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		use.alignment = HORIZONTAL_ALIGNMENT_LEFT
		use.custom_minimum_size.y = 60
		use.set_meta("blueprint", i)
		var chosen: Dictionary = bp
		use.pressed.connect(func():
			_close_overlay()
			controller.begin_blueprint(chosen))
		row.add_child(use)
		var drop := UI.icon_button("trash", "Let it go", 60)
		drop.set_meta("blueprint_drop", i)
		var idx: int = i
		drop.pressed.connect(func():
			var all := Blueprints.load_all()
			all.remove_at(idx)
			Blueprints.save_all(all)
			open_blueprints())
		row.add_child(drop)
		_insert(col, row)


## Save the picked thing and what is around it as a blueprint (a name from the list).
func open_blueprint_save(center_id: String) -> void:
	var cap := Blueprints.capture(Session.model, center_id)
	if cap["pieces"].is_empty():
		show_hint("That cannot go in a blueprint.")
		return
	controller.cancel_ghost()
	var col := _dialog("Save a blueprint", tr("%d things around it will be saved on this device. Pick a name.") % cap["pieces"].size(), [["Close", func(): pass, false]])
	col.get_parent().get_parent().get_parent().name = "BlueprintSave"
	var thumbs_row := HFlowContainer.new()
	_insert(col, thumbs_row)
	for p in cap["pieces"]:
		var t := TextureRect.new()
		t.texture = thumbs.textures.get(p["kind"])
		t.custom_minimum_size = Vector2(56, 56)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbs_row.add_child(t)
	var names := HFlowContainer.new()
	names.add_theme_constant_override("h_separation", 8)
	names.add_theme_constant_override("v_separation", 8)
	_insert(col, names)
	for n in Blueprints.NAMES:
		var b := UI.button(n, "", false, 0)
		b.custom_minimum_size.y = 56
		b.set_meta("blueprint_name", n)
		var nm: String = n
		b.pressed.connect(func():
			_close_overlay()
			var all := Blueprints.load_all()
			all.append({"name": nm, "pieces": cap["pieces"]})
			if Blueprints.save_all(all):
				Sfx.play("place")
				show_toast(tr("Saved as %s. Find it under Blueprints.") % tr(nm)))
		names.add_child(b)


func _on_blueprint(info: Dictionary) -> void:
	if _bp_tools == null:
		var m := _corner(Control.PRESET_CENTER_BOTTOM, 24)
		m.add_theme_constant_override("margin_bottom", 300)
		_bp_tools = UI.panel(20, UI.PANEL)
		m.add_child(_bp_tools)
		var v := VBoxContainer.new()
		_bp_tools.add_child(v)
		_bp_label = UI.label("", 22, UI.ACCENT, true)
		_bp_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_bp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_bp_label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		for spec in [["Turn", "turn", func(): controller.turn_blueprint()], ["Place here", "check", func(): controller.place_blueprint()],
				["Cancel", "close", func(): controller.cancel_blueprint()]]:
			var b := UI.button(spec[0], spec[1], spec[0] == "Place here", 0)
			b.custom_minimum_size.y = 60
			b.name = "Bp" + spec[0].replace(" ", "")
			var cb: Callable = spec[2]
			b.pressed.connect(func():
				Sfx.play("tap")
				cb.call())
			row.add_child(b)
	_bp_tools.visible = not info.is_empty()
	_catalog.visible = info.is_empty() and controller.mode == "decorate" and dock == "bottom"
	if not info.is_empty():
		_bp_label.text = "%s · %s" % [tr(info["name"]), tr("%d of %d fit here. Tap the ground to move it.") % [info["fits"], info["total"]]]


# ------------------------------------------------------------- cooking

## The recipe card at a stove: what each dish needs, and Cook when it can be made here.
func _open_recipes(stove: String) -> void:
	var col := _dialog("What shall we cook?", "Ingredients come from this room. Everything is free.", [["Close", func(): pass, false]])
	var busy: bool = Session.cooking.has(stove)
	for recipe in Cooking.ORDER:
		var r: Dictionary = Cooking.RECIPES[recipe]
		var missing: Array = Cooking.missing(Session.model, controller.space, recipe)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var pic := TextureRect.new()
		pic.texture = thumbs.textures.get(r["dish"])
		pic.custom_minimum_size = Vector2(80, 80)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(r["name"], 24, UI.ACCENT))
		var needs := HBoxContainer.new()
		for n in r["needs"]:
			var ic := TextureRect.new()
			ic.texture = UI.icon("todo" if missing.has(n) else "saved", 28)
			ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			needs.add_child(ic)
			needs.add_child(UI.label(Catalog.ITEMS[n]["name"], 18, UI.MUTED if missing.has(n) else UI.TEXT))
		info.add_child(needs)
		row.add_child(info)
		var cook := UI.button("Cook", "cook", missing.is_empty() and not busy, 150)
		cook.set_meta("recipe", recipe)
		cook.disabled = not missing.is_empty() or busy
		var rid: String = recipe
		cook.pressed.connect(func():
			_close_overlay()
			Sfx.play("tap")
			Session.cook(stove, rid))
		row.add_child(cook)
		_insert(col, row)
	if busy:
		_insert(col, UI.label("Something is already cooking here. It is nearly ready!", 20, UI.MUTED, true))


# ------------------------------------------------------------- picking in a crowd

## One row for an item already placed: thumbnail, name and where it sits.
func _item_row(id: String, on_pick: Callable) -> Button:
	var item: Dictionary = Session.model.items[id]
	var def := Catalog.get_def(item["kind"])
	var busy: bool = Session.locks.get(id, 0) not in [0, Session.my_id]
	var text := tr(def.get("name", ""))
	if item.has("host"):
		text += "  ·  " + tr("on a table")
	elif busy:
		text += "  ·  " + tr("a friend is moving it")
	var b := UI.button(text, "", false, 420)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = thumbs.textures.get(item["kind"])
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 56)
	b.custom_minimum_size.y = 72
	b.disabled = busy
	b.set_meta("item_id", id)
	b.pressed.connect(func():
		Sfx.play("tap")
		_close_overlay()
		on_pick.call(id))
	return b


## Every item in this room (or the town), nearest first; a row picks it up.
func open_things_here() -> void:
	if controller == null:
		return
	_search.release_focus()
	controller.cancel_ghost()
	var col := _dialog("Things here", "Tap one to move, turn, paint or put it away.", [["Close", func(): pass, false]])
	var ids: Array = Session.model.items_in(controller.space).map(func(i): return i["id"])
	var me: Vector2 = controller.pos
	ids.sort_custom(func(a, b):
		var ia: Dictionary = Session.model.items[a]
		var ib: Dictionary = Session.model.items[b]
		return me.distance_squared_to(Vector2(ia["x"], ia["z"])) < me.distance_squared_to(Vector2(ib["x"], ib["z"])))
	if ids.is_empty():
		_insert(col, UI.label("Nothing here yet. Pick something from the toy box.", 22, UI.MUTED, true))
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, minf(ids.size() * 80.0, get_global_rect().size.y - 420.0))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in ids:
		list.add_child(_item_row(id, func(x): controller.select_item(x)))
	_insert(col, scroll)


## A tap landed on several things: let the child say which one (nothing moves yet).
func open_chooser(ids: Array, at: Vector2) -> void:
	_close_overlay()
	var shade := Control.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_overlay())
	_overlay.add_child(shade)
	var p := UI.panel(24)
	p.name = "Chooser"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	col.add_child(UI.label("Which one?", 24, UI.ACCENT))
	for id in ids:
		if Session.model.items.has(id):
			col.add_child(_item_row(id, func(x): controller.select_item(x)))
	shade.add_child(p)
	# Next to the finger, inside the safe area and above the toy box.
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	var area := get_global_rect()
	var size := p.get_combined_minimum_size()
	var pos := at + Vector2(24, -size.y * 0.5)
	if pos.x + size.x > area.end.x - 16:
		pos.x = at.x - 24 - size.x
	var bottom := area.end.y - (_catalog_height() if _catalog.visible else 0.0) - 8.0
	pos.x = clampf(pos.x, area.position.x + 16, area.end.x - size.x - 16)
	pos.y = clampf(pos.y, area.position.y + TOP_BAR_H, maxf(area.position.y + TOP_BAR_H, bottom - size.y))
	p.global_position = pos


func chooser_rect() -> Rect2:
	for c in _overlay.get_children():
		var p := c.get_node_or_null("Chooser") as Control
		if p:
			return p.get_global_rect()
	return Rect2()


func _open_gift_picker() -> void:
	var col := _dialog("Wrap it as a present", "It stays right here with a bow until they open it.", [["Cancel", func(): controller.cancel_ghost(), false]])
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_insert(col, flow)
	var paper := randi_range(1, 7)
	var anyone := UI.button("For anyone", "gift", true, 200)
	anyone.pressed.connect(func():
		_close_overlay()
		controller.wrap_selected("", paper))
	flow.add_child(anyone)
	for pid in Session.model.roster:
		if pid == Session.my_pid:
			continue
		var entry: Dictionary = Session.model.roster[pid]
		var b := UI.button(tr("For %s") % tr(entry.get("nick", "")), "", false, 160)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_stylebox_override("normal", UI.box(Palette.paint(int(entry.get("color", 0))).lerp(UI.PANEL, 0.55), 16, 2, UI.SOFT))
		var id: String = pid
		b.pressed.connect(func():
			_close_overlay()
			controller.wrap_selected(id, paper))
		flow.add_child(b)


## A dialog's shade lies inside the safe area like everything else in the HUD; on a TV (and on a phone
## with insets) that left a bright frame of undimmed town around it (the Mac's TV pictures). This puts
## the shade's color on a child that reaches out to the window's edges, drawn before the dialog; the
## dialog's own layout does not change. (Not a top-level node: that would be drawn over the dialog.)
func _add_backdrop(shade: ColorRect) -> void:
	var back := ColorRect.new()
	back.name = "Backdrop"
	back.color = shade.color
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.show_behind_parent = true
	shade.add_child(back)
	shade.color = Color(shade.color.r, shade.color.g, shade.color.b, 0.0)   # the backdrop is the one shade now
	var fit := func():
		if is_instance_valid(back):
			var area := get_global_rect()
			var win := get_viewport().get_visible_rect()
			back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			back.offset_left = win.position.x - area.position.x
			back.offset_top = win.position.y - area.position.y
			back.offset_right = win.end.x - area.end.x
			back.offset_bottom = win.end.y - area.end.y
	fit.call()
	back.tree_entered.connect(fit)
	resized.connect(fit)
	back.tree_exiting.connect(func():
		if resized.is_connected(fit):
			resized.disconnect(fit))


func _dialog(title: String, body: String, buttons: Array) -> Control:
	_close_overlay()
	if controller and controller.look_id != "":
		controller.end_look()   # Look ends when a dialog opens (zoo design 11.1)
	var shade := ColorRect.new()
	shade.color = Color(0.2, 0.25, 0.2, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	_add_backdrop(shade)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(c)
	var p := UI.panel(28)
	p.custom_minimum_size.x = 560
	c.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	col.add_child(UI.label(title, 32, UI.ACCENT, true))
	if body != "":
		col.add_child(UI.label(body, 24, UI.TEXT, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	for spec in buttons:
		var b := UI.button(spec[0], "", spec[2], 160)
		b.set_meta("dialog_button", spec[0])
		var cb: Callable = spec[1]
		b.pressed.connect(func():
			_close_overlay()
			cb.call())
		row.add_child(b)
	return col


## tv-diag r2 (the controller audit, finding 2): the controller's A on Leave town asks first. B (or Not now)
## keeps playing; touch is unchanged (a finger reaches the button deliberately).
func confirm_leave() -> void:
	_dialog("Leave town", "", [["Not now", func(): pass, false], ["Leave town", func(): leave_requested.emit(), true]])


## Adds content to a dialog above its button row.
func _insert(col: VBoxContainer, node: Control) -> void:
	col.add_child(node)
	col.move_child(node, col.get_child_count() - 2)


func _close_overlay() -> void:
	for c in _overlay.get_children():
		# A closing dialog gives up its name at once: a card that reopens itself from one of its own
		# buttons (the hello's recorder after each pick) is found by its name again in the same frame.
		if not c.is_queued_for_deletion():
			c.name = "Closing%d" % c.get_instance_id()
		c.queue_free()


func _confirm_remove(item: Dictionary, contents: int) -> void:
	_dialog("Put this house away?", tr("Its %d things inside will be packed away with it. You can undo this.") % contents,
		[["Keep it", func(): controller.cancel_ghost(), false], ["Put it away", func(): controller.put_away(true), true]])


func open_language() -> void:
	var col := _dialog("Language", "", [["Close", func(): pass, false]])
	var grid := GridContainer.new()
	grid.columns = 2
	_insert(col, grid)
	for code in I18n.LOCALES:
		var b := UI.button(I18n.native_names.get(code, code), "", code == I18n.current, 250)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var c2: String = code
		b.pressed.connect(func():
			I18n.set_locale(c2)
			open_language())
		grid.add_child(b)


## Music on/off and volume, and sound effects on/off. Saved on this device.
func open_sound() -> void:
	var col := _dialog("Sound and music", "", [["Close", func(): pass, true]])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	_insert(col, grid)
	var toggle := func(on: bool, setter: Callable) -> Button:
		var b := UI.button("On" if on else "Off", "check" if on else "close", on, 180)
		b.pressed.connect(func():
			setter.call(not on)
			open_sound())
		return b
	grid.add_child(UI.label("Music", 26))
	grid.add_child(toggle.call(Music.music_on, Music.set_music_on))
	grid.add_child(UI.label("Music volume", 26))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = Music.music_volume
	slider.custom_minimum_size = Vector2(260, 64)
	slider.editable = Music.music_on
	slider.value_changed.connect(Music.set_music_volume)
	grid.add_child(slider)
	grid.add_child(UI.label("Sounds", 26))
	grid.add_child(toggle.call(Music.sounds_on, Music.set_sounds_on))
	# Decorative motion (r20): fans, hanging decorations and lantern glow stay still when on.
	if controller and controller.world:
		grid.add_child(UI.label("Reduce motion", 26))
		var rm: Button = toggle.call(controller.world.reduce_motion, controller.world.set_reduce_motion)
		rm.name = "ReduceMotion"
		grid.add_child(rm)
	# TV build: a controller that reports its buttons the other way round can swap confirm and back.
	if TvMode.active() or not Input.get_connected_joypads().is_empty():
		grid.add_child(UI.label("Swap A and B", 26))
		var sw: Button = toggle.call(PadInput.load_swap(), PadInput.set_swap)
		sw.name = "SwapAB"
		grid.add_child(sw)


## Lanterns and photos the friends have made together.
## The scrapbook's "Zoo friends" page (design 10.6): per species, the animals' names, the answers
## found with who found them, and a hint for the next one. Back returns to the scrapbook.
func _open_zoo_friends() -> void:
	var col := _dialog("Zoo friends", "", [["Back", func(): open_scrapbook.call_deferred(), false]])
	var zoo_found = {}
	var zoo_maps = Session.model.get("maps")
	if zoo_maps is Dictionary and zoo_maps.get("zoo") is Dictionary:
		zoo_found = zoo_maps["zoo"].get("found", {})
	for row in ActivityGuide.zoo_friend_rows(zoo_found):
		var zbox := VBoxContainer.new()
		zbox.name = "ZooFriends_" + str(row["species"])
		var znames := UI.label(", ".join(row["names"]), 20, UI.ACCENT, true)
		znames.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		zbox.add_child(znames)
		for f in row["found"]:
			zbox.add_child(UI.label(f["text"], 17, UI.TEXT, true))
			if not f["by"].is_empty():
				var zby := UI.label(tr("Found by %s") % ", ".join(f["by"].map(func(n): return tr(n))), 17, UI.MUTED, true)
				zby.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				zbox.add_child(zby)
		if row["hint"] != "":
			zbox.add_child(UI.label(row["hint"], 17, UI.MUTED, true))
		_insert(col, zbox)
	# CC BY 4.0 attribution for the imported zoo animals (zoo r2; docs/assets.md). The credit itself is a
	# name and a licence, so it is not translated; only its frame is.
	var credit := UI.label(tr("Animal models: %s") % "Everything Library © David OReilly, CC BY 4.0", 15, UI.MUTED, true)
	credit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	credit.name = "AnimalModelCredit"
	_insert(col, credit)


func open_scrapbook() -> void:
	var col := _dialog("Scrapbook", tr("Lanterns lit: %d of %d") % [Session.model.lanterns.size(), CozySpots.SPOTS.size()], [["Close", func(): pass, true]])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_insert(col, grid)
	for spot in CozySpots.ORDER:
		var lit: bool = Session.model.lanterns.has(spot)
		var card := PanelContainer.new()
		var bg: Color = CozySpots.SPOTS[spot]["lantern"].lerp(UI.PANEL, 0.6) if lit else UI.PAPER
		card.add_theme_stylebox_override("panel", UI.box(bg, 18))
		card.custom_minimum_size = Vector2(230, 170)
		grid.add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		var icon := TextureRect.new()
		icon.texture = UI.icon("lantern", 52)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.modulate = CozySpots.SPOTS[spot]["lantern"] if lit else Color(0.6, 0.6, 0.6, 0.5)
		v.add_child(icon)
		v.add_child(UI.label(CozySpots.SPOTS[spot]["name"] if lit else "Not found yet", 22, UI.TEXT, true))
		var sub := tr("Made together by %s") % ", ".join(Session.model.lanterns[spot]["by"].map(func(n): return tr(n))) if lit else tr(CozySpots.SPOTS[spot]["hint"])
		var l := UI.label(sub, 17, UI.MUTED, true)
		v.add_child(l)
	var stickers: Array = Session.model.wishes.get("stickers", [])
	if not stickers.is_empty():
		var srow := HFlowContainer.new()
		srow.add_theme_constant_override("h_separation", 8)
		for st in stickers.slice(-12):
			var chip := HBoxContainer.new()
			chip.tooltip_text = tr(Wishes.find(st.get("id", "")).get("text", ""))
			var star := TextureRect.new()
			star.texture = UI.icon("wish", 32)
			star.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			chip.add_child(star)
			chip.add_child(UI.label(AnimalBrain.SPECIES.get(st.get("animal", ""), {}).get("name", ""), 20, UI.ACCENT))
			srow.add_child(chip)
		_insert(col, UI.label("Wish stickers", 24, UI.ACCENT))
		_insert(col, srow)
	if not Session.model.keepsakes.is_empty():
		_insert(col, UI.label("Trail keepsakes", 24, UI.ACCENT))
		var krow := HFlowContainer.new()
		krow.add_theme_constant_override("h_separation", 8)
		for k in Session.model.keepsakes.slice(-8):
			var chip := HBoxContainer.new()
			var ic := TextureRect.new()
			ic.texture = UI.icon("wave", 32)
			ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			chip.add_child(ic)
			var kl := UI.label(", ".join(k["by"].map(func(n): return tr(n))), 20, UI.ACCENT)
			kl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			chip.add_child(kl)
			krow.add_child(chip)
		_insert(col, krow)
	# The zoo's own page (design 10.6), so the scrapbook stays as short as before.
	var zoo_btn := UI.button("Zoo friends", "paw", false, 0)
	zoo_btn.custom_minimum_size.y = 56
	zoo_btn.pressed.connect(func():
		Sfx.play("tap")
		_open_zoo_friends())
	_insert(col, zoo_btn)
	var stories := Story.list()
	if not stories.is_empty():
		_insert(col, UI.label("Stories", 24, UI.ACCENT))
		for st in stories.slice(0, 1):   # the newest; older ones stay on the device
			var img := Image.load_from_file(ProjectSettings.globalize_path(st["png"]))
			if img == null or img.is_empty():
				continue
			var title: String = Story.card(st["card"])["title"]
			if title != "":
				_insert(col, UI.label(title, 20, UI.TEXT))
			var r := TextureRect.new()
			r.texture = ImageTexture.create_from_image(img)
			r.custom_minimum_size = Vector2(640, 150)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_insert(col, r)
	_insert(col, UI.label("Photos", 24, UI.ACCENT))
	if TvMode.active():
		_insert(col, UI.label("Photos and stories on this TV may be removed when the TV needs space.", 20, UI.MUTED, true))
	var photos := HBoxContainer.new()
	_insert(col, photos)
	# This device's scrapbook photos, also from earlier sessions (PhotoStore): the newest four, each
	# loaded only now; a missing or damaged file is simply left out.
	var shown := []
	for name in PhotoStore.list().slice(-8):
		var tex: Texture2D = _photo_thumbs.get(name)
		if tex == null:
			tex = PhotoStore.thumbnail(name)
			if tex:
				_photo_thumbs[name] = tex
		if tex:
			shown.append(tex)
	shown = shown.slice(-4)
	if shown.is_empty():
		shown = _photos.slice(-4)   # this session's photos when none could be kept on the device
	if shown.is_empty():
		photos.add_child(UI.label("No photos yet. Tap the camera to take one.", 20, UI.MUTED))
	for tex in shown:
		var r := TextureRect.new()
		r.set_meta("photo", true)
		r.texture = tex
		r.custom_minimum_size = Vector2(220, 165)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photos.add_child(r)
	_scroll_body(col, 2)   # title and the lantern count stay put


## A tall dialog (the Scrapbook with lanterns, stickers, keepsakes, a story and photos) scrolls between its
## heading and its buttons instead of running off the screen (a TV's safe area, a phone), so Close and
## every photo can be reached. `head` is the number of leading children (title, body) that stay put.
## (Written for the Apple TV lane, where the controller tour found Close off-screen at TV size.)
func _scroll_body(col: VBoxContainer, head: int) -> void:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 18)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := col.get_children().slice(head, col.get_child_count() - 1)
	for n in body:
		col.remove_child(n)
		inner.add_child(n)
	var scroll := ScrollContainer.new()
	scroll.name = "DialogScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(inner)
	var room := maxf(160.0, get_global_rect().size.y - 300.0)   # title, body, buttons and margins
	scroll.custom_minimum_size = Vector2(0, minf(inner.get_combined_minimum_size().y, room))
	_insert(col, scroll)


func add_photo(tex: Texture2D, announce := true, stored_name := "") -> void:
	_photos.append(tex)
	if stored_name != "":
		_photo_thumbs[stored_name] = tex
	if announce:
		show_toast("Photo saved to the scrapbook")


## The system's answer about saving a photo to Photos (iPhone and iPad).
func photo_result(result: String, retry: Callable, settings: Callable) -> void:
	match result:
		"saved":
			show_toast("Saved to Photos and the scrapbook.")
		"denied":
			_dialog("Photos access is off", "Your photo is in the scrapbook. To also keep it in Photos, allow adding photos in Settings.",
				[["Not now", func(): pass, false], ["Open Settings", settings, false], ["Try again", retry, true]])
		"failed":
			_dialog("The photo could not be saved to Photos.", "Your photo is still in the scrapbook.",
				[["Not now", func(): pass, false], ["Try again", retry, true]])
		_:
			show_toast("Photo saved to the scrapbook")


## "Floor 2 · Bedroom" inside cottages; "Zoo · Lion Hill" in the zoo, with Ride home beside it
## (design 11.3); hidden in town.
func _refresh_location() -> void:
	var space: String = controller.space if controller else "town"
	var r := TownModel.parse_room(space)
	var zoo := space == Places.ZOO
	var city := Places.is_city(space)
	var thousand := space == Places.THOUSAND
	_location.visible = not r.is_empty() or zoo or city or thousand
	if _ride_home:
		_ride_home.visible = zoo or city or thousand
	if _city_reset:
		_city_reset.visible = space == Places.CITY   # city-web: the page has its own camera and reset
	_refresh_city_look()
	_refresh_thousand()
	if _zoo_invite:
		# Only while a friend is somewhere else (the card asks them to "Come to the zoo with me").
		_zoo_invite.visible = zoo and Session.players.keys().any(func(id): return id != Session.my_id \
			and Places.map_of(str(Session.players[id].get("state", {}).get("space", "town"))) != Places.ZOO)
	if city:
		# "City · Cafe" inside a building (or on its terrace), "City" in the streets.
		var where := ""
		for b in CityMap.BUILDINGS:
			if (CityMap.BUILDINGS[b]["rect"] as Rect2).has_point(controller.pos):
				where = CityMap.BUILDINGS[b]["name"]
		_location.text = tr(Places.NAMES[space]) + ((" · " + tr(where)) if where != "" else "")
	elif thousand:
		# "Thousand Town · Mall" at a building's door or on a place, "Thousand Town" in the streets. A door
		# wins over the place it opens onto, so the line names the building that "Who's here?" offers.
		var tw: Node3D = controller.world.thousand_world if controller.world else null
		var b: Dictionary = tw.door_near(controller.pos, controller.THOUSAND_DOOR_REACH) if tw else {}
		if b.is_empty() and tw:
			b = tw.building_at(controller.pos)
		_location.text = tr(Places.NAMES[space]) + ((" · " + tr(str(b["name"]))) if not b.is_empty() else "")
	elif zoo:
		var hab := ZooMap.habitat_at(controller.pos)
		_location.text = tr("Zoo") + ((" · " + tr(ZooMap.HABITAT_NAMES[hab])) if hab != "" else "")
	elif not r.is_empty():
		_location.text = (tr("Floor %d") % (r["floor"] + 1)) + " · " + tr(TownModel.room_name(space))


func location_text() -> String:
	return _location.text if _location.visible else ""


func _refresh_texts() -> void:
	theme.default_font = I18n.ui_font()
	if controller:
		_refresh_location()
		if _catalog.visible:
			_rebuild_catalog_tabs()   # counts, empty-state text and the name order follow the language
		if _overlay.get_node_or_null("Wardrobe") != null:
			open_wardrobe(_wardrobe_cat)   # names are fitted per language (whole words, three lines)
	_refresh_friends()
	_refresh_lanterns()
	_refresh_status()


# ------------------------------------------------------------- the zoo: journey card, Look strip

var _journey_card: Control
var _journey_tram: TextureRect
var _journey_t := 0.0
var _look_strip: PanelContainer
var _look_name: Label
var _look_doing: Label
var _look_place := "low"


## The journey card (design 12.3): a full-screen card in the guide's style with a tram moving along
## a dotted line from the town to the zoo. Still under Reduce Motion. It takes every input while up.
func _on_journey(phase: String, to: String) -> void:
	if phase == "start":
		if _journey_card == null:
			_build_journey_card()
		var title: Label = _journey_card.get_node("Box/V/Title")
		title.text = tr("To the zoo") if to == Places.ZOO else (tr("To the city") if Places.is_city(to) else (tr("To Thousand Town") if to == Places.THOUSAND else tr("Back to town")))
		# Thousand Town's destination info carries its credit (CC BY 4.0, design/thousand-town.md section 0).
		var credit: Label = _journey_card.get_node("Box/V/Credit")
		credit.text = thousand_credit()
		credit.visible = to == Places.THOUSAND
		_journey_card.visible = true
		_journey_card.modulate.a = 0.0
		_journey_t = 0.0
		create_tween().tween_property(_journey_card, "modulate:a", 1.0, 0.0 if _reduced() else 0.3)
	elif _journey_card:
		var tw := create_tween()
		tw.tween_property(_journey_card, "modulate:a", 0.0, 0.0 if _reduced() else 0.35)
		tw.tween_callback(func(): _journey_card.visible = false)
		_refresh_location()
		_refresh_friends()


func _reduced() -> bool:
	return controller != null and controller.world != null and controller.world.reduce_motion


func _build_journey_card() -> void:
	_journey_card = Control.new()
	_journey_card.name = "JourneyCard"
	_journey_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journey_card.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under the card can be pressed
	add_child(_journey_card)
	var shade := ColorRect.new()
	shade.color = Color("#cfe9ef")
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journey_card.add_child(shade)
	var box := UI.panel(32)
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(620, 300)
	box.position = Vector2(-310, -150)
	_journey_card.add_child(box)
	var v := VBoxContainer.new()
	v.name = "V"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	box.add_child(v)
	var title := UI.label("", 34, UI.ACCENT)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(title)
	var line := Control.new()
	line.custom_minimum_size = Vector2(560, 90)
	v.add_child(line)
	for i in 13:
		var dot := ColorRect.new()
		dot.color = UI.SOFT.darkened(0.2)
		dot.size = Vector2(10, 10)
		dot.position = Vector2(60 + i * 36, 60)
		line.add_child(dot)
	for pair in [["home", 0.0], ["paw", 520.0]]:
		var end := TextureRect.new()
		end.texture = UI.icon(pair[0], 56)
		end.position = Vector2(pair[1], 36)
		line.add_child(end)
	_journey_tram = TextureRect.new()
	_journey_tram.texture = UI.icon("tram", 64)
	_journey_tram.position = Vector2(60, 0)
	line.add_child(_journey_tram)
	var credit := UI.label("", 15, UI.MUTED, true)
	credit.name = "Credit"
	credit.custom_minimum_size.x = 560
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	credit.visible = false
	v.add_child(credit)


func _tick_zoo(delta: float) -> void:
	if controller == null:
		return
	if _journey_card and _journey_card.visible and not _reduced():
		_journey_t += delta
		var k: float = fmod(_journey_t / 1.6, 1.0)
		var going_home: bool = controller.journey_to == Places.TOWN
		_journey_tram.position.x = lerpf(460.0, 60.0, k) if going_home else lerpf(60.0, 460.0, k)
	if controller.space == Places.ZOO or Places.is_city(controller.space) or controller.space == Places.THOUSAND:
		_loc_t -= delta
		if _loc_t <= 0.0:
			_loc_t = 0.5
			_refresh_location()
	if controller.space == Places.THOUSAND:
		_tt_t -= delta
		if _tt_t <= 0.0:
			_tt_t = 0.25
			_refresh_thousand_play()   # the countdowns, the ETA and the show buttons follow the clock
			_refresh_thousand_clock()
	if _look_strip and _look_strip.visible:
		_place_look_strip()


## Look (design 11.1, 11.2): a small strip, not a dialog, with the name, what the animal is doing,
## Offer a treat and Done. It takes one of the two places the placement tools use, chosen by the
## same rule (PlacementDock.choose_place) with the animal's head box as the "thing".
func _on_look(id: String) -> void:
	if id == "":
		if _look_strip:
			_look_strip.visible = false
		return
	if _look_strip == null:
		_build_look_strip()
	_look_strip.set_meta("id", id)
	_look_strip.visible = true
	_refresh_look_text()


func _build_look_strip() -> void:
	_look_strip = UI.panel(24)
	_look_strip.name = "LookStrip"
	add_child(_look_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_look_strip.add_child(row)
	var col := VBoxContainer.new()
	row.add_child(col)
	_look_name = UI.label("", 26, UI.ACCENT)
	_look_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_look_name)
	_look_doing = UI.label("", 18, UI.MUTED)
	_look_doing.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_look_doing)
	var offer := UI.button("Offer a treat", "paw", true, 0)
	offer.name = "Offer"
	offer.pressed.connect(func():
		var zoo := get_node_or_null("/root/Zoo")
		if zoo and _look_strip.has_meta("id"):
			Sfx.play("pop")
			controller._ask(zoo.offer(str(_look_strip.get_meta("id"))), func(r):
				if not r.get("ok", false) and str(r.get("error", "")) != "":
					show_hint(r["error"])))
	row.add_child(offer)
	var done := UI.button("Done", "check", false, 0)
	done.name = "Done"
	done.pressed.connect(func():
		Sfx.play("tap")
		controller.end_look())
	row.add_child(done)


func _refresh_look_text() -> void:
	var id: String = str(_look_strip.get_meta("id", ""))
	if id == "" or not ZooMap.RESIDENTS.has(id):
		return
	var name: String = tr(ZooMap.RESIDENTS[id]["name"])
	_look_name.text = name
	var zoo := get_node_or_null("/root/Zoo")
	var line := ""
	if zoo:
		for st in zoo.states.get("animals", []):
			if st["id"] == id and str(st.get("line", "")) != "":
				line = tr(ZooLife.LINES.get(st["line"], "")) % name
	_look_doing.text = line
	_look_doing.visible = line != ""


func _place_look_strip() -> void:
	_refresh_look_text()
	var z := zones()
	var node: Node3D = controller.world.zoo_world.animal_node(str(_look_strip.get_meta("id", ""))) if controller.world.zoo_world else null
	if node == null:
		return
	var head := PlacementDock.ghost_rect(controller.rig.camera, node.global_position, 0.6, node.usual_height())
	var low: Rect2 = z["low"]
	var top: Rect2 = z["top"]
	_look_place = PlacementDock.choose_place(_look_place, head, avatar_screen_rect(), low, top, z["strip"])
	var size := _look_strip.get_combined_minimum_size()
	var area := get_global_rect()
	var x := area.position.x + (area.size.x - size.x) * 0.5
	_look_strip.position = Vector2(x, top.position.y) if _look_place == "top" else Vector2(x, low.end.y - size.y)


## city r2: the Look button shows its state (Look around / Stop looking), and Pause shows only while looking.
func _refresh_city_look() -> void:
	if _city_look == null:
		return
	_refresh_city_weather()
	var city: bool = controller.space == Places.CITY
	var looking: bool = controller.city_looking
	_city_look.visible = city
	_city_look.tooltip_text = "Stop looking" if looking else "Look around"
	_city_look.modulate = Color(1.0, 0.92, 0.6) if looking else Color.WHITE   # lit while on
	_city_pause.visible = city and looking
	var paused: bool = controller.city_paused
	_city_pause.icon = UI.icon("play" if paused else "pause", 64)
	_city_pause.tooltip_text = "Resume" if paused else "Pause the city"


## city r3: the weather buttons show in the city; the current weather's button is lit (fully opaque).
func _refresh_city_weather() -> void:
	if _city_weather == null:
		return
	_city_weather.visible = controller.space == Places.CITY
	var city := get_node_or_null("/root/City")
	var cur := 0
	if city and (city.states as Dictionary).has("weather"):
		cur = int(city.states["weather"])
	for i in _city_weather_btns.size():
		_city_weather_btns[i].modulate = Color(1, 1, 1, 1.0) if i == cur else Color(1, 1, 1, 0.72)



# ------------------------------------------------------------- Thousand Town (design/thousand-town.md sections 4, 5)

## The credit line, translated (the upstream title and author stay as written).
static func thousand_credit() -> String:
	return TranslationServer.translate(THOUSAND_CREDIT) % [THOUSAND_TITLE, THOUSAND_AUTHOR]


## The mode the time buttons show as chosen, and the speed (from the newest Thousand state).
func _thousand_mode() -> Dictionary:
	var t := get_node_or_null("/root/Thousand")
	if t == null:
		return {"mode": "auto", "speed": 1}
	return {"mode": str(t.states.get("mode", "auto")), "speed": int(t.states.get("speed", 1))}


## A time button: Day, Dusk or Night hold that time; Auto runs the clock, and pressed again while it runs it
## changes the speed (1x, 2x, 4x). The authority decides (Thousand.srv_time_mode through Session's requests).
func press_time(mode: String) -> void:
	Sfx.play("tap")
	var t := get_node_or_null("/root/Thousand")
	if t == null:
		return
	var cur := _thousand_mode()
	var speed := 0
	if mode == "auto" and cur["mode"] == "auto":
		speed = t.next_speed(int(cur["speed"]))
	controller._ask(t.set_time_mode(mode, speed), func(r):
		if not r.get("ok", false) and str(r.get("error", "")) != "":
			show_hint(str(r["error"])))


## The time buttons and Look show in Thousand Town; the chosen mode's button is lit, Auto carries its speed.
func _refresh_thousand() -> void:
	if _thousand_time == null or controller == null:
		return
	var here: bool = controller.space == Places.THOUSAND
	_thousand_time.visible = here
	_thousand_look.visible = here
	_refresh_thousand_play()
	var looking: bool = controller.thousand_looking
	_thousand_look.tooltip_text = "Stop looking" if looking else "Look around"
	_thousand_look.modulate = Color(1.0, 0.92, 0.6) if looking else Color.WHITE
	var cur := _thousand_mode()
	for m in _thousand_time_btns:
		(_thousand_time_btns[m] as Button).modulate = Color(1, 1, 1, 1.0) if m == cur["mode"] else Color(1, 1, 1, 0.72)
	_thousand_speed.text = "%d\u00d7" % int(cur["speed"])
	_refresh_thousand_clock()


## unified r4: the clock line. Auto runs the shared town clock by itself (one town minute a second, times the
## speed: a day lasts 24, 12 or 6 minutes); Day, Dusk and Night jump to 12:00, 18:40 or 21:30 and keep the time
## there until Auto is chosen again (net/thousand.gd). The line says which, with the time now.
static func thousand_clock_text(minute: float, mode: String, speed: int) -> String:
	var m := int(floor(fposmod(minute, 1440.0)))
	var hm := "%02d:%02d" % [m / 60, m % 60]
	if mode == "auto":
		return "%s  \u00b7  %s" % [hm, TranslationServer.translate("Auto: time runs by itself (%s)") % ("%d\u00d7" % speed)]
	var name := {"day": "Day", "dusk": "Dusk", "night": "Night"}.get(mode, "Day") as String
	return "%s  \u00b7  %s" % [hm, TranslationServer.translate("Stays at %s. Auto lets time run again.") % TranslationServer.translate(name)]


func _refresh_thousand_clock() -> void:
	if _thousand_clock == null or controller == null:
		return
	var here: bool = controller.space == Places.THOUSAND
	_thousand_clock.visible = here
	if not here:
		return
	var tw: Node3D = controller.world.thousand_world if controller.world else null
	var vt: Dictionary = tw.view_time() if tw else {}
	var cur := _thousand_mode()
	var text := thousand_clock_text(float(vt.get("minute", 480.0)), str(cur["mode"]), int(cur["speed"]))
	if _thousand_clock.text != text:
		_thousand_clock.text = text


## unified r4: the controller's time button in Thousand Town (PadInput role "time"): Day -> Dusk -> Night -> Auto
## -> Day, the same requests as the glass buttons, so Auto is always one or more presses away and says so.
func cycle_time() -> void:
	var order := ["day", "dusk", "night", "auto"]
	var cur := str(_thousand_mode()["mode"])
	press_time(order[(order.find(cur) + 1) % order.size()] if order.has(cur) else "auto")


## The speed badge's text now ("1x" written with a times sign); tests read it.
func thousand_speed_badge() -> String:
	return _thousand_speed.text if _thousand_speed else ""


## "Who's here?": the inspect panel for a building of Thousand Town (UI shell; data from inspect_provider).
func open_thousand_inspect(id: String) -> void:
	# The simulation's answer (core/thousand_inspect.gd) unless a test put its own provider in.
	var tw: Node3D = controller.world.thousand_world if controller and controller.world else null
	var data: Dictionary = inspect_provider.call(id) if inspect_provider.is_valid() else ThousandInspect.provide(tw, id)
	if data.is_empty():
		var name_en := str(tw.NAMES.get(id, id)) if tw else id
		data = {"id": id, "name": name_en, "open": true, "count": 0, "counts": {}, "here": [], "lives": []}
	var col := _dialog(tr(str(data.get("name", id))), "", [["Close", func(): pass, true]])
	col.get_parent().get_parent().get_parent().name = "ThousandInspectDialog"
	var panel: VBoxContainer = ThousandPanel.new()
	panel.set_meta("building", id)
	_insert(col, panel)
	panel.resident_picked.connect(func(rid: String): _thousand_picked(panel, rid))
	panel.set_data(data)


## The open inspect panel, or null.
func thousand_inspect_panel() -> Node:
	var d := _overlay.get_node_or_null("ThousandInspectDialog")
	if d == null or d.is_queued_for_deletion():
		return null
	return d.find_child("ThousandInspect", true, false)


# ------------------------------------------------------------- Thousand Town's interactions (world/thousand_play.gd)

func _build_thousand_play() -> void:
	var m := _corner(Control.PRESET_TOP_RIGHT, 16)
	m.add_theme_constant_override("margin_top", int(TOP_BAR_H) + 4)
	# left of the camera buttons and the time buttons (68 + 12 + 52 + 12 from the right edge), so neither is covered
	m.add_theme_constant_override("margin_right", 16 + 68 + 12 + 52 + 16)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tt_box = VBoxContainer.new()
	_tt_box.name = "ThousandPlay"
	_tt_box.add_theme_constant_override("separation", 10)
	_tt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tt_box.visible = false
	m.add_child(_tt_box)
	_tt_chip = UI.panel(20)
	_tt_chip.name = "ThousandChip"
	_tt_chip.visible = false
	_tt_box.add_child(_tt_chip)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_tt_chip.add_child(cv)
	_tt_chip_label = UI.label("", 22, UI.ACCENT, true)
	_tt_chip_label.name = "ChipText"
	_tt_chip_label.custom_minimum_size.x = 420
	_tt_chip_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cv.add_child(_tt_chip_label)
	_tt_chip_btns = HBoxContainer.new()
	_tt_chip_btns.name = "ChipButtons"
	_tt_chip_btns.alignment = BoxContainer.ALIGNMENT_END
	_tt_chip_btns.add_theme_constant_override("separation", 10)
	cv.add_child(_tt_chip_btns)
	_tt_card = UI.panel(24)
	_tt_card.name = "ResidentCard"
	_tt_card.visible = false
	_tt_box.add_child(_tt_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_tt_card.add_child(v)
	_tt_card_name = UI.label("", 30, UI.ACCENT, true)
	_tt_card_name.name = "Name"
	_tt_card_name.custom_minimum_size.x = 420
	_tt_card_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_tt_card_name)
	_tt_card_who = _tt_card_line(v, UI.TEXT)
	_tt_card_who.name = "Who"
	_tt_card_now = _tt_card_line(v, UI.TEXT)
	_tt_card_now.name = "Now"
	_tt_card_heading = _tt_card_line(v, UI.MUTED)
	_tt_card_heading.name = "Heading"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_tt_card_follow = UI.button("Follow", "wave", true, 160)
	_tt_card_follow.name = "Follow"
	_tt_card_follow.pressed.connect(func():
		var tp: Node = controller.thousand_play
		tp.start_follow(tp.selected))
	row.add_child(_tt_card_follow)
	var close := UI.button("Close", "close", false, 140)
	close.name = "CloseCard"
	close.pressed.connect(func():
		Sfx.play("tap")
		controller.thousand_play.close_card())
	row.add_child(close)
	# the shows: bottom right, where Decorate is elsewhere (Thousand Town has no toy box)
	for spec in [["fireworks", "fireworks"], ["fountain", "fountain"]]:
		var b := UI.button("", spec[1], false, SIDE_W)
		b.name = "Show_" + spec[0]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size.y = 72
		b.visible = false
		var kind: String = spec[0]
		b.pressed.connect(func():
			Sfx.play("tap")
			controller.thousand_play.press_show(kind))
		_side_col.add_child(b)
		_side_col.move_child(b, 0)
		_tt_shows[kind] = b


func _tt_card_line(parent: Control, color: Color) -> Label:
	var l := UI.label("", 21, color, true)
	l.custom_minimum_size.x = 420
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(l)
	return l


## Shows what the interactions report: the chip, the card and the show buttons; nothing outside Thousand Town.
func _refresh_thousand_play() -> void:
	if _tt_box == null or controller == null:
		return
	var tp: Node = controller.get("thousand_play")
	var here: bool = controller.space == Places.THOUSAND and tp != null and controller.journey_to == ""
	_tt_box.visible = here
	for k in _tt_shows:
		(_tt_shows[k] as Button).visible = here
	if not here:
		_tt_chip.visible = false
		_tt_card.visible = false
		return
	var chip: Dictionary = tp.chip()
	_tt_chip.visible = not chip.is_empty()
	if not chip.is_empty():
		_tt_chip_label.text = str(chip.get("text", ""))
		var want: Array = chip.get("buttons", [])
		var have: Array = _tt_chip_btns.get_children().filter(func(n): return not n.is_queued_for_deletion()).map(func(n): return [n.get_meta("label", ""), n.get_meta("action", "")])
		if have != want:
			for n in _tt_chip_btns.get_children():
				_tt_chip_btns.remove_child(n)
				n.queue_free()
			for spec: Array in want:
				var b := UI.button(str(spec[0]), "close" if spec[1] == "end" else ("look" if spec[1] == "inspect" else ("stand" if str(spec[1]).ends_with("_off") else "bus")), spec[1] != "end", 0)
				b.name = "Chip_" + str(spec[1])
				b.custom_minimum_size.y = 60
				b.set_meta("label", spec[0])
				b.set_meta("action", spec[1])
				var action: String = spec[1]
				b.pressed.connect(func(): controller.thousand_play.chip_action(action))
				_tt_chip_btns.add_child(b)
		_tt_chip_btns.visible = not want.is_empty()
	var card: Dictionary = tp.card()
	_tt_card.visible = not card.is_empty()
	if not card.is_empty():
		_tt_card_name.text = str(card.get("name", ""))
		_tt_card_who.text = str(card.get("who", ""))
		_tt_card_now.text = str(card.get("now", ""))
		_tt_card_heading.text = str(card.get("heading", ""))
		_tt_card_heading.visible = _tt_card_heading.text != ""
		_tt_card_follow.visible = bool(card.get("can_follow", false))
	for spec: Dictionary in tp.show_buttons():
		var b: Button = _tt_shows.get(spec["kind"])
		if b:
			b.text = str(spec["label"])
			b.modulate = Color.WHITE if bool(spec["on"]) else Color(1, 1, 1, 0.82)


## A resident picked in "Who's here?": the marker goes to them (over the door while they are inside), and while
## they are out on the street a Follow button joins their details.
func _thousand_picked(panel: Node, rid: String) -> void:
	var tp: Node = controller.get("thousand_play") if controller else null
	if tp == null:
		return
	var index := -1
	for key in ["here", "lives"]:
		for r: Dictionary in panel.data.get(key, []):
			if str(r.get("id", "")) == rid and r.has("index"):
				index = int(r["index"])
	if index < 0:
		return
	tp.selected = index
	tp.changed.emit()
	var detail: Node = panel.find_child("Detail", true, false)
	if detail == null or not tp.can_follow(index):
		return
	var b := UI.button("Follow", "wave", true, 0)
	b.name = "FollowResident"
	b.custom_minimum_size.y = 60
	b.pressed.connect(func():
		_close_overlay()
		tp.start_follow(index))
	detail.add_child(b)
