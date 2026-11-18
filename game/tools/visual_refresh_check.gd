extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://main.tscn") as PackedScene
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.hud._pick_hero("akame")
	await create_timer(1.0).timeout
	game.run_cheat("-lvl 12")
	for id in ["short_sword", "potion", "antimagic"]:
		game.player.receive(id, 0)
	game.player.recalc_stats(true)
	game.hud._toggle_character_sheet()
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("D:/Anime Team Survival/character-visual.png")
	assert(err == OK, "Could not save character sheet screenshot")
	assert(game.hud.character_sheet.visible)
	game.hud._toggle_character_sheet()
	assert(not game.hud.character_sheet.visible)
	var z: Zone = game.zones[0]
	game.camera.center_on(z.portals[0].pos, true)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	err = root.get_texture().get_image().save_png("D:/Anime Team Survival/portal-visual.png")
	assert(err == OK)
	game.hud.toggle_shop()
	await process_frame
	await RenderingServer.frame_post_draw
	err = root.get_texture().get_image().save_png("D:/Anime Team Survival/shop-visual.png")
	assert(err == OK)
	print("VISUAL_QA PASS: character sheet open/close, items, shop, portal rendered.")
	quit()
