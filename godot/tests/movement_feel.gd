extends SceneTree
## Pulo tolerante (coyote time + buffer), pouco controle no ar e aterrissagem.
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _frames(count: int) -> void:
    for frame in range(count):
        await physics_frame
        await process_frame

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.position = pos
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    parent.add_child(body)
    return body

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    # Plataforma alta e isolada, longe do mapa, para cair dela.
    var origin := Vector3(400, 30, 400)
    var platform := _solid(scene, origin, Vector3(4, 1, 4))
    var landing := _solid(scene, origin + Vector3(0, -12, -6), Vector3(30, 1, 30))
    player.global_position = origin + Vector3(0, 0.55, 1.2)
    player.set("yaw", 0.0)
    await _frames(30)
    _check(player.is_on_floor(), "Player did not settle on platform")

    # Jump buffer: espaço apertado um instante antes de tocar o chão vale.
    # Cai de 1,5 m (o coyote time já acabou) e aperta a ~20 cm do chão.
    player.velocity = Vector3.ZERO
    player.global_position = origin + Vector3(0, 2.0, 1.2)
    var top := origin.y + 0.5
    for frame in range(90):
        await _frames(1)
        if player.global_position.y - top < 0.2:
            break
    _check(not player.is_on_floor(), "Player should be in the air for buffer test")
    _check(float(player.get("_coyote_left")) <= 0.0, "Coyote time still active during buffer test")
    Input.action_press("jump")
    await _frames(1)
    Input.action_release("jump")
    var jumped := false
    for frame in range(12):
        await _frames(1)
        if player.velocity.y > 4.0:
            jumped = true
            break
    _check(jumped, "Jump pressed just before landing was dropped (no buffer)")
    for frame in range(90):
        await _frames(1)
        if player.is_on_floor():
            break

    # Coyote time: sai da beirada andando e pula logo depois.
    player.global_position = origin + Vector3(0, 0.55, -1.6)
    player.velocity = Vector3.ZERO
    await _frames(10)
    Input.action_press("move_forward") # -Z: sai da beirada
    var left_floor := false
    for frame in range(60):
        await _frames(1)
        if not player.is_on_floor():
            left_floor = true
            break
    _check(left_floor, "Player never walked off the ledge")
    await _frames(2)
    Input.action_press("jump")
    await _frames(1)
    Input.action_release("jump")
    _check(player.velocity.y > 4.0, "Jump right after leaving the ledge was refused (no coyote time)")

    # Pouco controle no ar: soltar a direção não freia o corpo no ar.
    Input.action_release("move_forward")
    var air_speed := Vector2(player.velocity.x, player.velocity.z).length()
    await _frames(6)
    var later := Vector2(player.velocity.x, player.velocity.z).length()
    _check(player.is_on_floor() or later > air_speed * 0.9, "Air momentum lost when input released (%.2f -> %.2f)" % [air_speed, later])

    # Aterrissagem: queda alta registra impacto e afunda a câmera.
    player.set("last_landing_strength", 0.0)
    for frame in range(180):
        await _frames(1)
        if player.is_on_floor():
            break
    _check(player.is_on_floor(), "Player never landed")
    _check(float(player.get("last_landing_strength")) > 0.3, "Hard landing not registered")
    _check(float(player.get("_land_recovery")) > 0.0 or float(player.get("_land_dip")) > 0.0, "Landing had no recovery/dip")
    platform.queue_free()
    landing.queue_free()
    scene.queue_free()
    await _frames(2)
    for failure in failures:
        printerr(failure)
    print("MOVEMENT FEEL: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
