extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	for path in ["res://assets/approved_portal/Portal.fbx","res://models/props.glb"]:
		var n = load(path).instantiate()
		root.add_child(n)
		if path.ends_with("props.glb"):
			n = n.get_node("SpawnGate")
		print("SCENE ",path)
		walk(n)
	quit()
func walk(n):
	if n is MeshInstance3D:
		print(n.get_path()," xform=",n.global_transform," aabb=",n.get_aabb())
		for i in n.mesh.get_surface_count():
			var m=n.get_active_material(i)
			print("MAT ",m.resource_name if m else "NULL"," color=",m.albedo_color if m is StandardMaterial3D else "")
	for c in n.get_children(): walk(c)


