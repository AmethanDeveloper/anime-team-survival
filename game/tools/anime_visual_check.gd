extends SceneTree
var failed := false
func check(ok: bool,label: String) -> void:
	print("CHECK ",label,": ",ok)
	if not ok:
		push_error(label)
		failed=true
func shot(name: String):
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("D:/Anime Team Survival/"+name+".png")==OK,"save "+name)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hud._pick_hero("akame")
	await create_timer(1.0).timeout
	game.hud.announce_box.visible=false
	game.hud.error_label.visible=false
	game.camera.edge_pan=false
	game.camera.set_process(false)
	game.camera.center_on(game.player.global_position,true)
	await process_frame
	check(game.hud.ability_buttons.size()==6,"six ability controls")
	check(game.hud.item_slots.size()==6,"six item controls")
	check(game.hud.super_slot.visible and not game.hud.super_slot.shown,"set slot visible while locked")
	var view := root.get_visible_rect()
	for b in game.hud.ability_buttons+game.hud.item_slots:
		check(b.is_visible_in_tree() and view.encloses(b.get_global_rect()),"slot visible within viewport")
	var row: HBoxContainer = game.hud.console_root.get_child(1)
	for panel in row.get_children():
		check(view.encloses(panel.get_global_rect()),"console panel within viewport")
	for i in range(1,row.get_child_count()):
		var prev: Control=row.get_child(i-1)
		var next: Control=row.get_child(i)
		check(prev.get_global_rect().end.x<=next.get_global_rect().position.x,"panels do not overlap")
	var cast := InputEventMouseButton.new()
	cast.button_index=MOUSE_BUTTON_LEFT
	cast.pressed=true
	game.hud.ability_buttons[5]._gui_input(cast)
	check(game.targeting != 5,"locked set cannot target")
	await shot("anime-hud-locked")
	game.run_cheat("-lvl 12")
	for id in ["short_sword","potion","antimagic"]:
		game.player.receive(id,0)
	game.run_cheat("-set")
	game.player.recalc_stats(true)
	await process_frame
	await process_frame
	check(game.hud.super_slot.shown,"set highlights when equipped")
	await create_timer(1.1).timeout
	await shot("anime-hud")
	game.hud._toggle_character_sheet()
	await shot("anime-character")
	check(game.hud.character_sheet.visible,"character sheet opens")
	game.hud._toggle_character_sheet()
	check(not game.hud.character_sheet.visible,"character sheet closes")
	game.hud.toggle_shop()
	await shot("anime-shop")
	game.hud.toggle_shop()
	var z: Zone = game.zones[0]
	game.camera.dist=23.0
	game.camera.target_dist=23.0
	game.camera.pitch=38.0
	game.camera.center_on(z.spawns[0],true)
	await shot("anime-spawn-portal")
	var portal = load("res://assets/approved_portal/spawn_portal.gd").make()
	check(portal.get_child_count()>0,"approved portal instantiated")
	portal.free()
	print("ANIME_VISUAL_QA ", "FAILED" if failed else "PASS")
	quit(1 if failed else 0)

