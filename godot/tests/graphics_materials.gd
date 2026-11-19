extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
func _texture_check(material: StandardMaterial3D, title: String) -> void:
    _check(material.albedo_texture != null, title + " must have surface texture")
    _check(material.normal_enabled and material.normal_texture != null, title + " must have relief")
    _check(material.roughness_texture != null, title + " must have surface roughness")
    if material.albedo_texture == null:
        return
    var image := material.albedo_texture.get_image()
    _check(image != null and image.has_mipmaps(), title + " has mipmaps to avoid distant shimmer")
    if image == null:
        return
    var low := 1.0
    var high := 0.0
    for x in range(image.get_width()):
        for y in range(image.get_height()):
            var value := image.get_pixel(x,y).r
            low = minf(low,value)
            high = maxf(high,value)
        _check(image.get_pixel(x,0).is_equal_approx(image.get_pixel(x,image.get_height()-1)), title + " seamless vertical tiling")
        _check(image.get_pixel(0,x).is_equal_approx(image.get_pixel(image.get_width()-1,x)), title + " seamless horizontal tiling")
    _check(high - low > 0.06, title + " texture must add visible variation")
func _run() -> void:
    var begin := Time.get_ticks_msec()
    root.get_node("Net").set("in_match", true) # a cidade (WorldPolish) é o mapa online
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var world = scene.get_node("WorldPolish")
    for fixture in [["#414950","Asphalt"],["#a9aaa1","Sidewalk"],["#719168","Grass"],["#c7b596","Wall"],["#68503c","Bark"]]:
        _texture_check(world.call("_mat",fixture[0]), fixture[1])
    var player: Node = scene.get_node("Jaime")
    var avatar: Node = player.get("humanoid_avatar")
    var shirt: MeshInstance3D = avatar.get_node("Hips/Torso/Chest")
    _texture_check(shirt.material_override, "Uniform")
    var weapon: Node = player.get("weapon_model")
    var slide: MeshInstance3D = weapon.get_node("Slide")
    _texture_check(slide.material_override, "Weapon metal")
    var env: Environment = (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
    _check(env.background_mode == Environment.BG_SKY and env.sky != null, "Sky has a horizon gradient")
    for child in scene.get_children():
        if child is DirectionalLight3D:
            _check(child.light_energy + env.ambient_light_energy <= 1.3, "Lighting budget avoids washed-out white surfaces")
    print("GRAPHICS INITIALIZATION: ",Time.get_ticks_msec()-begin,"ms")
    scene.queue_free()
    await process_frame
    for failure in failures.slice(0,12):
        printerr(failure)
    print("GRAPHICS MATERIALS: ", "PASS" if failures.is_empty() else "FAIL", " (",failures.size()," failures)")
    quit(0 if failures.is_empty() else 1)
