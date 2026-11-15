extends SceneTree
var failures: Array[String] = []

class Target extends StaticBody3D:
    var damage := 0.0
    func take_damage(amount: float) -> void:
        damage += amount

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func _frames(count: int) -> void:
    for frame in range(count):
        await physics_frame
        await process_frame

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    player.position = Vector3(0, 0.1, 10)
    player.set("yaw", 0.0)
    player.set("pitch", 0.0)
    player.call("_equip_weapon", "sniper")
    Input.action_press("aim")
    await _frames(45)
    _check(player.has_method("is_scope_active"), "Sniper must expose scoped aim state")
    var overlay: Control = scene.get("scope_overlay") if "scope_overlay" in scene else null
    _check(overlay != null, "Closed scope overlay exists")
    if player.has_method("is_scope_active") and overlay != null:
        _check(player.call("is_scope_active"), "Right button opens sniper scope")
        _check(overlay.visible, "Scope overlay visible while aiming")
        _check(not (player.get("avatar") as Node3D).visible, "Avatar must not obstruct the optic")
        _check(not (scene.get("crosshair") as Control).visible, "Normal crosshair is replaced by scope reticle")
        _check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Scope must not intercept shooting or looking")
        var camera: Camera3D = player.get("camera")
        var base_tangent := tan(deg_to_rad(72.0) * 0.5)
        _check(absf(base_tangent / tan(deg_to_rad(camera.fov) * 0.5) - 4.0) < 0.05, "Initial zoom is real 4x")
        for click in range(12):
            var wheel := InputEventMouseButton.new()
            wheel.button_index = MOUSE_BUTTON_WHEEL_UP
            wheel.pressed = true
            player.call("_unhandled_input", wheel)
        await _frames(45)
        _check(absf(base_tangent / tan(deg_to_rad(camera.fov) * 0.5) - 8.0) < 0.05, "Zoom clamps at real 8x")
        # Headless display cannot capture a cursor. Exercise the same look method used by the input handler.
        for click in range(12):
            var wheel := InputEventMouseButton.new()
            wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
            wheel.pressed = true
            player.call("_unhandled_input", wheel)
        await _frames(45)
        _check(absf(base_tangent / tan(deg_to_rad(camera.fov) * 0.5) - 4.0) < 0.05, "Zoom clamps at minimum 4x")
        for click in range(4):
            var wheel := InputEventMouseButton.new()
            wheel.button_index = MOUSE_BUTTON_WHEEL_UP
            wheel.pressed = true
            player.call("_unhandled_input", wheel)
        await _frames(45)
        var before_yaw: float = player.get("yaw")
        player.call("_apply_mouse_look", Vector2(100, 0))
        _check(absf(float(player.get("yaw")) - before_yaw) < 0.0625, "8x reduces mouse sensitivity")
        player.set("yaw", 0.0)
        await _frames(5)
        var target := Target.new()
        var collision := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(2, 2, 0.5)
        collision.shape = box
        target.add_child(collision)
        target.position = camera.global_position - camera.global_basis.z * 20.0
        scene.add_child(target)
        await _frames(2)
        # Exercise the production shot path; cursor capture is unavailable in headless display.
        player.call("_shoot")
        var tracer: MeshInstance3D = null
        for child in scene.get_children():
            if child is MeshInstance3D and child.mesh is CylinderMesh:
                tracer = child
                break
        _check(tracer != null, "Scoped shot produces a tracer")
        if tracer != null:
            var start_point: Vector3 = tracer.global_position - tracer.global_basis.y * tracer.mesh.height * 0.5
            var in_camera := camera.to_local(start_point)
            _check(Vector2(in_camera.x, in_camera.y).length() < 0.001, "Scoped tracer must originate on the reticle axis")
            _check(in_camera.z < -camera.near, "Scoped tracer starts beyond the near clip plane")
            var radius_pixels: float = tracer.mesh.top_radius * float(root.size.y) * 0.5 / (-in_camera.z * tan(deg_to_rad(camera.fov) * 0.5))
            _check(radius_pixels < 3.0, "8x tracer must not become a large flash across the reticle")
        await _frames(2)
        _check(target.damage > 0, "Scoped shot hits the target under the center reticle")
        _check(int(player.get("ammo")) == 4, "Scoped fire consumes one sniper round")
        var start := player.position
        Input.action_press("move_forward")
        await _frames(15)
        Input.action_release("move_forward")
        _check(player.position.distance_to(start) > 0.5, "Movement remains available while scoped")
        player.call("_reload")
        await _frames(2)
        _check(not player.call("is_scope_active") and not overlay.visible, "Reload closes the scope")
        player.call("_equip_weapon", "rifle")
        await _frames(45)
        _check(not overlay.visible, "Switching to rifle removes sniper mask")
        _check((player.get("avatar") as Node3D).visible, "Avatar returns for shoulder aim")
        _check(absf(camera.fov - 52.0) < 0.1, "Rifle retains normal shoulder zoom")
        Input.action_release("aim")
        await _frames(45)
        _check(absf(camera.fov - 72.0) < 0.1, "Releasing aim restores normal FOV")
        player.call("_equip_weapon", "sniper")
        Input.action_press("aim")
        await _frames(5)
        var escape := InputEventKey.new()
        escape.keycode = KEY_ESCAPE
        escape.pressed = true
        player.call("_unhandled_input", escape)
        await _frames(5)
        _check(not overlay.visible and not player.call("is_scope_active"), "Escape closes scoped aim")
    Input.action_release("aim")
    Input.action_release("fire")
    Input.action_release("move_forward")
    scene.queue_free()
    await process_frame
    for failure in failures:
        printerr(failure)
    print("SNIPER SCOPE: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
