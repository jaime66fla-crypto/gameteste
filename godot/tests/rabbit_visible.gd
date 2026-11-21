extends SceneTree
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    if DisplayServer.get_name() == "headless":
        print("RABBIT VISIBILITY: SKIP (requires a rendering device)")
        quit(0)
        return
    var scene := Node3D.new();root.add_child(scene);current_scene=scene
    var rabbit=load("res://scripts/survival/animal.gd").new()
    rabbit.setup("rabbit", "rabbit",15);scene.add_child(rabbit);rabbit.set_physics_process(false)
    for i in 8: await process_frame
    var box := AABB()
    var first := true
    for node in rabbit.find_children("*","MeshInstance3D",true,false):
        var posed=node.bake_mesh_from_current_skeleton_pose() if node.skin != null else node.mesh
        var bounds: AABB=node.global_transform*posed.get_aabb()
        box=bounds if first else box.merge(bounds);first=false
    var length := maxf(box.size.x,box.size.z)
    var ok := length > .55 and length < .85 and absf(box.position.y) < .12
    print("RABBIT POSED BOUNDS: ",box)
    print("RABBIT VISIBILITY: ","PASS" if ok else "FAIL")
    scene.queue_free();await process_frame;quit(0 if ok else 1)
