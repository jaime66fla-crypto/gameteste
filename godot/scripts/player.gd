extends CharacterBody3D
## Emitted once per trigger pull with the visible tracer path (online matches relay it).
signal shot_fired(weapon_id: String, from: Vector3, to: Vector3)

# Ghost-style configurable character dimensions and movement (Godot 4).
@export_category("Atributos do Soldado")
@export_range(1.5, 2.1, 0.01) var height: float = 1.80
@export_range(2.0, 10.0, 0.1) var speed: float = 5.0
@export_range(1.0, 2.5, 0.05) var sprint_multiplier: float = 1.6
@export_range(2.0, 12.0, 0.1) var jump_velocity: float = 8.5
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(0.24, 0.48, 0.01) var collision_radius: float = 0.34
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const CROUCH_SPEED := 2.7
@export_range(1.0, 60.0, 0.5) var acceleration := 24.0
@export_range(1.0, 60.0, 0.5) var deceleration := 30.0
var body_collision: CollisionShape3D
var body_capsule: CapsuleShape3D
var standing_probe: CapsuleShape3D
var sprinting := false
const WeaponData = preload("res://scripts/weapon_data.gd")
const MAG_SIZE := 15
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const HumanoidAvatarScript = preload("res://scripts/avatar/avatar_controller.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const FirstPersonViewmodel = preload("res://scripts/weapons/first_person_viewmodel.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
## Holding aim (except the sniper scope) switches to a CS-style first-person view.
const FIRST_PERSON_FOV := 68.0
const FIRST_PERSON_CUTOFF := 0.45 # spring length below which the body is hidden
var viewmodel: Node3D
var first_person_view := false
var hit_shake := 0.0 # camera jolt when this player takes damage
var last_shot_origin := Vector3.ZERO
@export var character_id: String = ""
var requested_character_id := ""
var character_fallback_reason := ""

var yaw := 0.0
var pitch := -0.14
var aiming := false
var scope_zoom := 4.0
var scope_was_active := false
var crouching := false
var ammo := MAG_SIZE
var reloading := false
var shots := 0
var fire_delay := 0.0
var reload_timer := 0.0
var camera: Camera3D
var arm_pivot: Node3D
var avatar: Node3D
var gun: Node3D
var gun_flash: OmniLight3D
var cam_distance := 3.6
var sound_fx: Node
var muzzle_flare: MeshInstance3D
var gun_kick := 0.0
var current_weapon := "pistol"
var weapon_holstered := false
var reserve_ammo := {"pistol": 90, "smg": 150, "rifle": 150, "shotgun": 36, "sniper": 25}
var magazines := {"pistol": 15, "smg": 30, "rifle": 30, "shotgun": 6, "sniper": 5}
var weapon_model: Node3D
var locomotion_clock := 0.0
var presentation_offset := Vector3.ZERO
var avatar_anim_time := 0.0
var equipped_external_model := false
var jaime_model: Node3D
var jaime_animation: AnimationPlayer
var jaime_animation_name := ""
var gun_uses_model_mount := false
var humanoid_avatar: Node3D

func _ready() -> void:
    # Characters share a layer: they block each other but bullets ignore the
    # capsules and hit body-part hitboxes instead.
    collision_layer = HitboxScript.LAYER_CHARACTERS
    collision_mask = HitboxScript.LAYER_WORLD | HitboxScript.LAYER_CHARACTERS
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = minf(collision_radius, height * 0.3)
    capsule.height = height
    collision.shape = capsule
    collision.position.y = height * 0.5
    add_child(collision)
    body_collision = collision
    body_capsule = capsule
    standing_probe = CapsuleShape3D.new()
    standing_probe.radius = capsule.radius
    standing_probe.height = height
    avatar = Node3D.new()
    add_child(avatar)
    _make_avatar()
    _install_selected_character()
    if humanoid_avatar != null and humanoid_avatar.has_method("bind_weapon"):
        _rebuild_weapon_model()
    sound_fx = SoundFXScript.new()
    sound_fx.name = "SoundFX"
    sound_fx.spatial_audio = false # Own shots/steps stay consistent as the camera moves.
    gun.add_child(sound_fx)
    arm_pivot = Node3D.new()
    arm_pivot.position = Vector3(0, height * 0.86, 0)
    add_child(arm_pivot)
    var spring := SpringArm3D.new()
    spring.spring_length = cam_distance
    spring.margin = 0.15
    spring.position.x = 1.0
    arm_pivot.add_child(spring)
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 72
    spring.add_child(camera)
    spring.add_excluded_object(get_rid())
    viewmodel = FirstPersonViewmodel.new()
    viewmodel.name = "FirstPersonViewmodel"
    viewmodel.visible = false
    camera.add_child(viewmodel)
    _rebuild_viewmodel()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _install_selected_character() -> void:
    requested_character_id = character_id if not character_id.is_empty() else CharacterRegistry.load_selection()
    character_id = requested_character_id
    var chosen := CharacterRegistry.create_visual(character_id)
    if chosen != null:
        chosen.scale *= height / 1.8
        avatar.add_child(chosen)
        var mount := chosen.get("weapon_mount") as Node3D
        var valid := not chosen.has_method("is_visual_ready") or bool(chosen.call("is_visual_ready"))
        if mount != null and valid:
            humanoid_avatar = chosen
            for part_name in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
                var part := avatar.get_node_or_null(part_name) as Node3D
                if part:
                    part.visible = false
            gun.reparent(mount, false)
            gun.position = Vector3.ZERO
            gun.rotation = Vector3.ZERO
            gun_uses_model_mount = true
            humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)
            return
        avatar.remove_child(chosen)
        chosen.queue_free()
    character_fallback_reason = "Visual indisponível; usando Jaime Original. Escolha outro em Personagens."
    character_id = CharacterRegistry.DEFAULT_ID
    _install_humanoid_avatar()

func _install_humanoid_avatar() -> void:
    humanoid_avatar = HumanoidAvatarScript.new()
    humanoid_avatar.name = "HumanoidAvatar"
    # Match the visible character to the configured collision height.
    humanoid_avatar.scale = Vector3.ONE * (height / 2.09)
    avatar.add_child(humanoid_avatar)
    for old_part in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
        var node := avatar.get_node_or_null(old_part) as Node3D
        if node != null:
            node.visible = false
    var mount := humanoid_avatar.get_node_or_null("WeaponMount") as Node3D
    if mount != null:
        gun.reparent(mount, false)
        gun.position = Vector3.ZERO
        gun.rotation = Vector3.ZERO
        gun_uses_model_mount = true
    humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)

func _material(c: Color) -> StandardMaterial3D:
    var kind := "wood" if c.to_html(false) == "765b43" else "metal"
    return SurfaceMaterials.make(kind, c, false)

func _part(parent: Node3D, name: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = name
    var mesh := BoxMesh.new()
    mesh.size = size
    part.mesh = mesh
    part.position = pos
    part.material_override = _material(color)
    parent.add_child(part)
    return part

func _make_avatar() -> void:
    var uniform := Color(0.17,0.21,0.24)
    _part(avatar,"Torso",Vector3(0,1.25,0),Vector3(0.7,0.77,0.35),uniform)
    _part(avatar,"Head",Vector3(0,1.84,0),Vector3(0.35,0.36,0.34),Color(0.58,0.42,0.31))
    _part(avatar,"LeftLeg",Vector3(-0.18,0.48,0),Vector3(0.25,0.85,0.27),uniform)
    _part(avatar,"RightLeg",Vector3(0.18,0.48,0),Vector3(0.25,0.85,0.27),uniform)
    _part(avatar,"LeftArm",Vector3(-0.48,1.20,-0.17),Vector3(0.20,0.65,0.23),uniform)
    _part(avatar,"RightArm",Vector3(0.48,1.20,-0.17),Vector3(0.20,0.65,0.23),uniform)
    gun = Node3D.new()
    avatar.add_child(gun)
    gun.position = Vector3(0.33,1.28,-0.48)
    weapon_model = Node3D.new()
    gun.add_child(weapon_model)
    _part(weapon_model,"PistolBody",Vector3(0,0,-0.22),Vector3(0.16,0.20,0.52),Color(0.08,0.09,0.10))
    _part(weapon_model,"Grip",Vector3(0,-0.16,-0.08),Vector3(0.13,0.30,0.13),Color(0.11,0.11,0.12))
    _part(weapon_model,"Slide",Vector3(0,0.105,-0.27),Vector3(0.18,0.10,0.46),Color("#34393e"))
    _part(weapon_model,"SightRear",Vector3(0,0.18,-0.07),Vector3(0.11,0.05,0.06),Color("#141719"))
    _part(weapon_model,"SightFront",Vector3(0,0.18,-0.48),Vector3(0.08,0.05,0.05),Color("#141719"))
    _part(weapon_model,"Barrel",Vector3(0,0,-0.53),Vector3(0.10,0.10,0.20),Color("#262a30"))
    muzzle_flare = MeshInstance3D.new()
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.15
    flash_mesh.height = 0.32
    muzzle_flare.mesh = flash_mesh
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("#ffc267")
    muzzle_flare.material_override = glow
    muzzle_flare.position = Vector3(0,0,-0.69)
    muzzle_flare.visible = false
    gun.add_child(muzzle_flare)
    gun_flash = OmniLight3D.new()
    gun_flash.position = Vector3(0,0,-0.57)
    gun_flash.light_color = Color(1,0.65,0.25)
    gun_flash.light_energy = 0
    gun.add_child(gun_flash)
    _rebuild_weapon_model()

func _find_descendant(node: Node, name_query: String) -> Node:
    if node.name == name_query:
        return node
    for child in node.get_children():
        var match_node := _find_descendant(child, name_query)
        if match_node != null:
            return match_node
    return null

func _first_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _first_animation_player(child)
        if found != null:
            return found
    return null

func _load_jaime_avatar() -> void:
    # Use either the saved inherited scene or the original imported GLB.
    var model_path := "res://assets/jaime/jaime.glb"
    if not ResourceLoader.exists(model_path):
        return
    var path := "res://scenes/jaime personagem.tscn"
    if not ResourceLoader.exists(path):
        path = model_path
    var packed := load(path) as PackedScene
    if packed == null:
        packed = load(model_path) as PackedScene
    if packed == null:
        return
    var instance := packed.instantiate() as Node3D
    if instance == null:
        return
    jaime_model = instance
    jaime_model.name = "JaimeOriginal"
    avatar.add_child(jaime_model)
    # Rotate the mesh only, never the player controller or camera.
    jaime_model.rotation.y = PI
    jaime_animation = _first_animation_player(jaime_model)
    CharacterRegistry.configure_locomotion_loops(jaime_model)
    var embedded_weapon := _find_descendant(jaime_model, "Weapon_pistol") as Node3D
    if embedded_weapon != null:
        embedded_weapon.visible = false
    var weapon_mount := _find_descendant(jaime_model, "OperatorWeaponMount") as Node3D
    if weapon_mount != null:
        gun.reparent(weapon_mount, false)
        gun.position = Vector3.ZERO
        gun.rotation = Vector3.ZERO
        gun_uses_model_mount = true
    for part_name in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
        var primitive := avatar.get_node_or_null(part_name) as Node3D
        if primitive != null:
            primitive.visible = false
    _play_jaime_animation("idle")

func _play_jaime_animation(clip_name: String) -> void:
    if jaime_animation == null:
        return
    var chosen := ""
    for animation_name in jaime_animation.get_animation_list():
        if String(animation_name).to_lower().get_slice("/", String(animation_name).get_slice_count("/") - 1) == clip_name:
            chosen = String(animation_name)
            break
    if chosen == "":
        for library_name in jaime_animation.get_animation_library_list():
            var library := jaime_animation.get_animation_library(library_name)
            for animation_name in library.get_animation_list():
                if String(animation_name).to_lower() == clip_name:
                    chosen = String(library_name) + "/" + String(animation_name) if String(library_name) != "" else String(animation_name)
                    break
            if chosen != "":
                break
    if chosen != "" and chosen != jaime_animation_name:
        jaime_animation_name = chosen
        jaime_animation.play(chosen, 0.16)

func is_scope_active() -> bool:
    return current_weapon == "sniper" and aiming and not reloading

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and is_scope_active():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            scope_zoom = clampf(scope_zoom + 1.0, 4.0, 8.0)
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            scope_zoom = clampf(scope_zoom - 1.0, 4.0, 8.0)
            return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_Q and humanoid_avatar != null and humanoid_avatar.has_method("play_action"):
            humanoid_avatar.call("play_action", "punch")
            return
        if event.physical_keycode == KEY_E and humanoid_avatar != null and humanoid_avatar.has_method("play_action"):
            humanoid_avatar.call("play_action", "elbow_punch")
            return
        if event.physical_keycode == KEY_H:
            _toggle_weapon_holster()
            return
        var key_slots := {KEY_1: "rifle", KEY_2: "sniper", KEY_3: "pistol", KEY_4: "shotgun", KEY_5: "smg"}
        if key_slots.has(event.physical_keycode):
            _equip_weapon(key_slots[event.physical_keycode])
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.action_release("aim")
        aiming = false
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _apply_mouse_look(event.relative)

func _apply_mouse_look(relative: Vector2) -> void:
    var sensitivity := mouse_sensitivity / scope_zoom if is_scope_active() else mouse_sensitivity
    yaw -= relative.x * sensitivity
    pitch = clampf(pitch - relative.y * sensitivity, -1.15, 0.95)

func _can_stand() -> bool:
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = standing_probe
    query.collision_mask = collision_mask
    query.exclude = [get_rid()]
    # Lift the probe just above floor contact, retaining conservative head clearance.
    query.transform = global_transform
    query.transform.origin += global_basis.y * (height * 0.5 + 0.005)
    return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _update_crouch(delta: float) -> void:
    var requested := Input.is_action_pressed("crouch")
    crouching = requested or (body_capsule.height < height - 0.001 and not _can_stand())
    var target_height := maxf(body_capsule.radius * 2.0, height * 0.86) if crouching else height
    body_capsule.height = move_toward(body_capsule.height, target_height, delta * 3.0)
    # Preserve the foot origin through every intermediate capsule size.
    body_collision.position.y = body_capsule.height * 0.5

func _physics_process(delta: float) -> void:
    aiming = not weapon_holstered and Input.is_action_pressed("aim")
    _update_crouch(delta)
    rotation.y = yaw
    arm_pivot.rotation.x = pitch
    var scoped := is_scope_active()
    var wants_first_person := aiming and not scoped
    var desired_fov := FIRST_PERSON_FOV if wants_first_person else 72.0
    if scoped:
        desired_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(72.0) * 0.5) / scope_zoom))
    # Closing the optic restores the shoulder frame before showing the body.
    camera.fov = desired_fov if scope_was_active and not scoped else lerpf(camera.fov, desired_fov, 1.0 - exp(-delta * 14.0))
    scope_was_active = scoped
    hit_shake = move_toward(hit_shake, 0.0, delta * 3.5)
    camera.h_offset = randf_range(-1.0, 1.0) * hit_shake * 0.06
    camera.v_offset = randf_range(-1.0, 1.0) * hit_shake * 0.06
    var spring: SpringArm3D = camera.get_parent()
    var camera_blend := minf(1, delta * 16)
    spring.spring_length = lerpf(spring.spring_length, 0.0 if wants_first_person else (2.15 if aiming else cam_distance), camera_blend)
    spring.position.x = lerpf(spring.position.x, 0.0 if wants_first_person else 1.0, camera_blend)
    var eye_height := height * (0.62 if crouching else 0.92)
    var shoulder_height := height * (0.59 if crouching else 0.86)
    arm_pivot.position.y = lerpf(arm_pivot.position.y, eye_height if wants_first_person else shoulder_height, minf(1,delta * 12))
    # The body hides once the camera is inside the head; the viewmodel replaces it.
    first_person_view = wants_first_person and spring.spring_length < FIRST_PERSON_CUTOFF
    avatar.visible = not scoped and not first_person_view
    viewmodel.visible = first_person_view
    var crouch_offset := 0.0 # Feet stay anchored; crouch belongs to the rig and capsule.
    avatar.position.y = lerpf(avatar.position.y, crouch_offset if crouching else 0.0, minf(1,delta * 10))
    var input_vec := Input.get_vector("move_left","move_right","move_forward","move_back")
    var movement := Vector3(input_vec.x,0,input_vec.y).rotated(Vector3.UP,yaw)
    var current_speed: float = CROUCH_SPEED if crouching else (speed * sprint_multiplier if Input.is_action_pressed("sprint") and not aiming else speed)
    var horizontal := Vector2(velocity.x, velocity.z)
    var desired_velocity := Vector2(movement.x, movement.z) * current_speed
    var rate := deceleration if desired_velocity.length_squared() < horizontal.length_squared() or horizontal.dot(desired_velocity) < 0.0 else acceleration
    horizontal = horizontal.move_toward(desired_velocity, rate * delta)
    velocity.x = horizontal.x
    velocity.z = horizontal.y
    if not is_on_floor():
        velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
    elif Input.is_action_just_pressed("jump") and not crouching:
        velocity.y = jump_velocity
    else:
        velocity.y = -0.1
    move_and_slide()
    var actual_velocity := get_real_velocity()
    var actual_move := clampf(Vector2(actual_velocity.x, actual_velocity.z).length() / maxf(current_speed, 0.01), 0.0, 1.0)
    sprinting = Input.is_action_pressed("sprint") and not aiming and not crouching and actual_velocity.slide(Vector3.UP).length() > speed + 0.2 and input_vec.length() > 0.1
    _animate_avatar(delta, actual_move, is_on_floor())
    fire_delay = maxf(0, fire_delay - delta)
    gun_flash.light_energy = move_toward(gun_flash.light_energy, 0.0, delta * 55.0)
    muzzle_flare.visible = gun_flash.light_energy > 0.05
    gun_kick = move_toward(gun_kick, 0.0, delta * 5.0)
    # Presentation-only animation: never changes projectile aim or character movement.
    var movement_weight := clampf(input_vec.length(), 0.0, 1.0)
    if is_on_floor() and movement_weight > 0.1:
        locomotion_clock += delta * (13.0 if Input.is_action_pressed("sprint") else 8.5)
    var bob := sin(locomotion_clock) * 0.018 * movement_weight if is_on_floor() else 0.0
    var desired_offset := Vector3(-0.045, 0.025, 0.07) if aiming else Vector3.ZERO
    presentation_offset = presentation_offset.lerp(desired_offset, minf(delta * 12.0, 1.0))
    if gun_uses_model_mount:
        gun.position = Vector3(0.0, 0.0, gun_kick * 0.3)
        gun.rotation.x = 0.0
    else:
        gun.position = Vector3(0.33, 1.28 + bob, -0.48 + gun_kick) + presentation_offset
        gun.rotation.x = lerpf(gun.rotation.x, -0.065 if aiming else 0.0, minf(delta * 10.0, 1.0))
    if humanoid_avatar != null and humanoid_avatar.has_method("refresh_weapon_grip"):
        humanoid_avatar.call("refresh_weapon_grip")
    if first_person_view:
        viewmodel.call("animate", delta, gun_kick, bob * 0.5, muzzle_flare.visible, reloading, _first_person_clearance())
    if reloading:
        reload_timer -= delta
        if reload_timer <= 0:
            var stats: Dictionary = WeaponData.stats(current_weapon)
            var missing: int = int(stats["mag"]) - ammo
            var supplied: int = mini(missing, int(reserve_ammo[current_weapon]))
            ammo += supplied
            reserve_ammo[current_weapon] -= supplied
            magazines[current_weapon] = ammo
            reloading = false
    if not weapon_holstered and Input.is_action_just_pressed("reload") and ammo < int(WeaponData.stats(current_weapon)["mag"]) and not reloading and int(reserve_ammo[current_weapon]) > 0:
        _reload()
    if not weapon_holstered and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and fire_delay <= 0 and not reloading:
        _shoot()

func _toggle_weapon_holster() -> void:
    weapon_holstered = not weapon_holstered
    aiming = false
    Input.action_release("aim")
    if weapon_holstered:
        reloading = false
        reload_timer = 0.0
        gun_kick = 0.0
        if gun_flash != null:
            gun_flash.light_energy = 0.0
        if muzzle_flare != null:
            muzzle_flare.visible = false
        if sound_fx != null and sound_fx.has_node("ReloadAudio"):
            (sound_fx.get_node("ReloadAudio") as AudioStreamPlayer).stop()
    if weapon_model != null:
        weapon_model.visible = not weapon_holstered
    if humanoid_avatar != null and humanoid_avatar.has_method("set_armed"):
        humanoid_avatar.call("set_armed", not weapon_holstered)
        if not weapon_holstered and humanoid_avatar.has_method("refresh_weapon_grip"):
            humanoid_avatar.call("refresh_weapon_grip")

func _shoot() -> void:
    if ammo <= 0:
        _reload()
        return
    var stats: Dictionary = WeaponData.stats(current_weapon)
    ammo -= 1
    magazines[current_weapon] = ammo
    shots += 1
    fire_delay = float(stats["interval"])
    gun_flash.light_energy = 2.8
    gun_kick = float(stats["kick"])
    sound_fx.shot(current_weapon)
    if humanoid_avatar != null and humanoid_avatar.has_method("notify_shot"):
        humanoid_avatar.call("notify_shot")
    var origin := camera.global_position
    var forward := -camera.global_transform.basis.z
    if not first_person_view and not is_scope_active():
        # Shoulder camera: start the aim ray level with the character, so a
        # tree or wall between the camera and the player cannot eat the shot.
        var chest := global_position + Vector3(0, height * 0.75, 0)
        origin += forward * maxf(0.0, (chest - origin).dot(forward))
    var muzzle := weapon_model.get_node_or_null("Muzzle") as Marker3D
    last_shot_origin = muzzle.global_position if muzzle else gun_flash.global_position
    if first_person_view:
        # CS-style: the round leaves the eye/crosshair axis; the tracer starts at
        # the visible viewmodel barrel, and the hidden third-person gun is ignored.
        muzzle = null
        last_shot_origin = viewmodel.call("muzzle_position")
    # Accuracy: tighter when aiming, wider when running or airborne.
    var planar_speed := Vector2(velocity.x, velocity.z).length()
    var spread := float(stats["spread"]) * (0.4 if aiming else 1.0)
    spread *= 1.0 + clampf(planar_speed / speed, 0.0, 1.6) * 0.6
    if not is_on_floor():
        spread *= 1.8
    for pellet in range(int(stats["pellets"])):
        # Uniform disc (not a square) around the crosshair.
        var angle := randf() * TAU
        var radius := sqrt(randf()) * spread
        var direction := (forward + camera.global_transform.basis.x * cos(angle) * radius + camera.global_transform.basis.y * sin(angle) * radius).normalized()
        var target := origin + direction * float(stats["range"])
        var query := PhysicsRayQueryParameters3D.create(origin, target, HitboxScript.SHOT_MASK)
        query.exclude = [get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        var endpoint: Vector3 = hit["position"] if not hit.is_empty() else target
        if muzzle:
            # Camera chooses the aim point; the actual shot starts at the barrel.
            # A wall near the weapon must block it even when the camera sees past it.
            var barrel_direction := (endpoint-last_shot_origin).normalized()
            var barrel_query := PhysicsRayQueryParameters3D.create(last_shot_origin, endpoint+barrel_direction*0.02, HitboxScript.SHOT_MASK)
            barrel_query.exclude = [get_rid()]
            barrel_query.hit_from_inside = true
            var barrel_hit := get_world_3d().direct_space_state.intersect_ray(barrel_query)
            # Retain a camera hit if numerical rounding at its surface misses it.
            if not barrel_hit.is_empty():
                hit = barrel_hit
            var grip := weapon_model.get_node_or_null("Grip") as Marker3D
            if grip:
                # The barrel may already protrude through a very close wall.
                var guard := PhysicsRayQueryParameters3D.create(grip.global_position,last_shot_origin,HitboxScript.LAYER_WORLD)
                guard.exclude = [get_rid()]
                guard.hit_from_inside = true
                var guard_hit := get_world_3d().direct_space_state.intersect_ray(guard)
                if not guard_hit.is_empty():
                    hit = guard_hit
            if not hit.is_empty():
                endpoint = hit["position"]
        if pellet == 0:
            var tracer_origin := last_shot_origin
            if is_scope_active():
                var offset := clampf(origin.distance_to(endpoint) * 0.5, camera.near * 2.0, 2.0)
                tracer_origin = origin + forward * offset
            _shot_tracer(tracer_origin, endpoint)
            shot_fired.emit(current_weapon, last_shot_origin, endpoint)
        if not hit.is_empty():
            var target_node: Object = hit["collider"]
            if target_node != null and target_node.has_method("take_hit"):
                # Body-part hitbox: the match controller handles feedback and the server damage.
                target_node.call("take_hit", float(stats["damage"]), endpoint, hit["normal"], current_weapon)
                continue
            if target_node != null and target_node.has_method("take_damage"):
                target_node.call("take_damage", float(stats["damage"]))
            _impact_mark(endpoint)

## Called by the online match when the server reports damage to this player.
func add_hit_shake(strength: float) -> void:
    hit_shake = clampf(hit_shake + strength, 0.0, 1.2)
    # A small aim punch upward, like being struck.
    pitch = clampf(pitch + strength * 0.03, -1.15, 0.95)

func _shot_tracer(from: Vector3, to: Vector3) -> void:
    var delta_pos := to - from
    var length := minf(delta_pos.length(), 45.0)
    if length < 0.1:
        return
    var tracer := MeshInstance3D.new()
    tracer.name = "ShotTracer"
    var cylinder := CylinderMesh.new()
    var radius := 0.011
    if is_scope_active():
        # Keep the scoped trail near one pixel wide even at maximum magnification.
        var viewport_height := maxf(camera.get_viewport().get_visible_rect().size.y,1.0)
        radius = 2.0 * camera.global_position.distance_to(from) * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = length
    cylinder.radial_segments = 5
    tracer.mesh = cylinder
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("#ffd08c")
    tracer.material_override = glow
    tracer.position = from + delta_pos.normalized() * length * 0.5
    tracer.quaternion = Quaternion(Vector3.UP, delta_pos.normalized())
    get_tree().current_scene.add_child(tracer)
    var tween := tracer.create_tween()
    tween.tween_property(tracer, "transparency", 1.0, 0.075)
    tween.tween_callback(tracer.queue_free)

func _impact_mark(point: Vector3) -> void:
    var impact := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.085
    sphere.height = 0.17
    impact.mesh = sphere
    impact.material_override = _material(Color("#eacb91"))
    get_tree().current_scene.add_child(impact)
    impact.global_position = point
    var tween := impact.create_tween()
    tween.tween_property(impact, "scale", Vector3.ZERO, 0.23)
    tween.tween_callback(impact.queue_free)



func _animate_avatar(delta: float, input_amount: float, grounded: bool) -> void:
    if humanoid_avatar != null:
        if humanoid_avatar.has_method("set_aim_pitch"):
            humanoid_avatar.call("set_aim_pitch", pitch)
        var running := sprinting
        humanoid_avatar.call("animate", delta, input_amount, running, crouching, aiming, not grounded, reloading, Input.get_vector("move_left", "move_right", "move_forward", "move_back"), humanoid_avatar.global_basis.inverse() * get_real_velocity())
        return
    if jaime_model != null and jaime_animation != null:
        var moving := input_amount > 0.1 and grounded
        var next_clip := "idle"
        if not grounded:
            next_clip = "jump" if velocity.y > 0.0 else "fall"
        elif reloading:
            next_clip = "reload_walk" if moving else "reload"
        elif crouching:
            next_clip = "crouch_aim_walk" if aiming and moving else ("crouch_aim" if aiming else ("crouch_walk" if moving else "crouch"))
        elif aiming:
            next_clip = "aim_walk" if moving else "aim"
        elif moving:
            next_clip = "run" if sprinting else "walk"
        _play_jaime_animation(next_clip)
        return
    # Compact procedural animation for the prototype mesh; animation resources can replace it later.
    var running := sprinting
    var moving := input_amount > 0.1 and grounded
    var pace := 11.0 if running else (5.5 if crouching else 7.5)
    if moving:
        avatar_anim_time += delta * pace
    var stride := sin(avatar_anim_time) * (0.54 if running else (0.20 if crouching else 0.37)) if moving else 0.0
    var blend := minf(delta * 11.0, 1.0)
    var left_leg := avatar.get_node_or_null("LeftLeg") as Node3D
    var right_leg := avatar.get_node_or_null("RightLeg") as Node3D
    var left_arm := avatar.get_node_or_null("LeftArm") as Node3D
    var right_arm := avatar.get_node_or_null("RightArm") as Node3D
    if left_leg != null:
        left_leg.rotation.x = lerpf(left_leg.rotation.x, stride, blend)
    if right_leg != null:
        right_leg.rotation.x = lerpf(right_leg.rotation.x, -stride, blend)
    if left_arm != null:
        var hold_left := -0.42 if aiming else -0.22
        left_arm.rotation.x = lerpf(left_arm.rotation.x, hold_left - stride * 0.12, blend)
    if right_arm != null:
        var hold_right := -0.45 if aiming else -0.22
        right_arm.rotation.x = lerpf(right_arm.rotation.x, hold_right + stride * 0.12, blend)
    var torso := avatar.get_node_or_null("Torso") as Node3D
    if torso != null:
        torso.rotation.z = lerpf(torso.rotation.z, -0.04 * stride, blend)

func _equip_weapon(weapon_id: String) -> void:
    if current_weapon == weapon_id:
        return
    magazines[current_weapon] = ammo
    current_weapon = weapon_id
    ammo = int(magazines[current_weapon])
    reloading = false
    reload_timer = 0.0
    fire_delay = 0.12
    gun_kick = 0.0
    _rebuild_weapon_model()
    if humanoid_avatar != null:
        humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)

func _rebuild_weapon_model() -> void:
    _rebuild_viewmodel()
    if humanoid_avatar == null or not humanoid_avatar.has_method("bind_weapon"):
        _rebuild_legacy_weapon_model()
        return
    var imported := WeaponProportions.create_model(current_weapon)
    if imported == null:
        _rebuild_legacy_weapon_model()
    else:
        weapon_model.transform = Transform3D.IDENTITY
        for child in weapon_model.get_children():
            weapon_model.remove_child(child)
            child.queue_free()
        weapon_model.add_child(imported)
    equipped_external_model = imported != null
    if WeaponProportions.apply(weapon_model, current_weapon, imported):
        humanoid_avatar.call("bind_weapon", weapon_model)
        var muzzle := weapon_model.get_node("Muzzle") as Marker3D
        gun_flash.position = gun.to_local(muzzle.global_position)
        muzzle_flare.position = gun_flash.position

## Free distance in front of the eye, so the viewmodel can pull back from walls.
func _first_person_clearance() -> float:
    var from := camera.global_position
    var forward := -camera.global_basis.z
    var query := PhysicsRayQueryParameters3D.create(from, from + forward * 1.2)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return INF if hit.is_empty() else from.distance_to(hit["position"])

func _rebuild_viewmodel() -> void:
    # Built before the camera exists during _make_avatar; _ready calls it again.
    if viewmodel != null and viewmodel.is_inside_tree():
        viewmodel.call("build", current_weapon)

func _rebuild_legacy_weapon_model() -> void:
    equipped_external_model = false
    weapon_model.scale = Vector3.ONE
    for child in weapon_model.get_children():
        weapon_model.remove_child(child)
        child.queue_free()
    # Optional imported .glb files live in res://assets/weapons/.
    # If none is supplied, the procedural weapon remains fully playable.
    var external_path := "res://assets/weapons/%s.glb" % current_weapon
    if ResourceLoader.exists(external_path):
        var packed := load(external_path) as PackedScene
        if packed != null:
            var imported := packed.instantiate() as Node3D
            if imported != null:
                imported.name = "ImportedWeapon"
                imported.position = Vector3.ZERO
                imported.rotation_degrees = Vector3(0, 180, 0)
                weapon_model.add_child(imported)
                equipped_external_model = true
    if equipped_external_model:
        var length_override := 0.54
        match current_weapon:
            "smg": length_override = 0.82
            "rifle": length_override = 1.18
            "shotgun": length_override = 1.27
            "sniper": length_override = 1.55
        gun_flash.position.z = -0.58 if current_weapon == "pistol" else -length_override * 0.99
        muzzle_flare.position.z = gun_flash.position.z - 0.035
        return
    if current_weapon in ["rifle", "sniper"]:
        weapon_model.scale = Vector3.ONE * 0.7
    var dark := Color("#22272d")
    var steel := Color("#59616a")
    var wood := Color("#765b43")
    var polymer := Color("#343a35")
    var accent := Color("#ab9360")
    var length := 0.54
    if current_weapon == "pistol":
        _part(weapon_model, "Slide", Vector3(0, 0.075, -0.27), Vector3(0.16, 0.16, 0.50), steel)
        _part(weapon_model, "Grip", Vector3(0, -0.15, -0.08), Vector3(0.13, 0.29, 0.14), dark)
        _part(weapon_model, "TriggerGuard", Vector3(0, -0.13, -0.29), Vector3(0.12, 0.045, 0.18), dark)
        _part(weapon_model, "FrontSight", Vector3(0, 0.19, -0.47), Vector3(0.08, 0.055, 0.06), accent)
        _part(weapon_model, "RearSight", Vector3(0, 0.19, -0.08), Vector3(0.12, 0.055, 0.06), dark)
    else:
        if current_weapon == "smg":
            length = 0.82
        elif current_weapon == "rifle":
            length = 1.18
        elif current_weapon == "shotgun":
            length = 1.27
        else:
            length = 1.55
        _part(weapon_model, "Receiver", Vector3(0, 0, -length * 0.35), Vector3(0.19, 0.23, length * 0.52), steel)
        _part(weapon_model, "Barrel", Vector3(0, 0.03, -length * 0.76), Vector3(0.09, 0.09, length * 0.45), dark)
        _part(weapon_model, "Stock", Vector3(0, -0.035, 0.15), Vector3(0.15, 0.16, 0.38), wood if current_weapon == "shotgun" else dark)
        _part(weapon_model, "Grip", Vector3(0, -0.18, -0.21), Vector3(0.12, 0.29, 0.15), dark)
        _part(weapon_model, "Handguard", Vector3(0, -0.035, -length * 0.56), Vector3(0.22, 0.18, length * 0.30), polymer)
        _part(weapon_model, "Rail", Vector3(0, 0.145, -length * 0.36), Vector3(0.17, 0.045, length * 0.42), dark)
        _part(weapon_model, "TriggerGuard", Vector3(0, -0.145, -0.33), Vector3(0.12, 0.045, 0.17), dark)
        if current_weapon != "shotgun":
            _part(weapon_model, "Magazine", Vector3(0, -0.23, -length * 0.39), Vector3(0.13, 0.38, 0.16), dark)
        if current_weapon == "shotgun":
            _part(weapon_model, "Pump", Vector3(0, -0.065, -0.72), Vector3(0.24, 0.15, 0.31), wood)
            _part(weapon_model, "Tube", Vector3(0, -0.12, -0.90), Vector3(0.08, 0.08, 0.45), steel)
        elif current_weapon == "sniper":
            _part(weapon_model, "Scope", Vector3(0, 0.23, -0.34), Vector3(0.15, 0.15, 0.48), dark)
            _part(weapon_model, "Lens", Vector3(0, 0.23, -0.59), Vector3(0.115, 0.115, 0.018), Color("#345d6a"))
            _part(weapon_model, "BipodLeft", Vector3(-0.12, -0.23, -1.04), Vector3(0.045, 0.32, 0.045), dark)
            _part(weapon_model, "BipodRight", Vector3(0.12, -0.23, -1.04), Vector3(0.045, 0.32, 0.045), dark)
        else:
            _part(weapon_model, "FrontSight", Vector3(0, 0.18, -length * 0.91), Vector3(0.085, 0.10, 0.065), dark)
            if current_weapon == "rifle":
                # M4-style silhouette from the supplied reference: rail, holo and foregrip.
                _part(weapon_model, "BufferTube", Vector3(0, 0.015, 0.12), Vector3(0.08, 0.08, 0.38), dark)
                _part(weapon_model, "StockPad", Vector3(0, -0.045, 0.35), Vector3(0.17, 0.28, 0.055), dark)
                _part(weapon_model, "Foregrip", Vector3(0, -0.21, -0.68), Vector3(0.11, 0.28, 0.13), polymer)
                _part(weapon_model, "HoloBase", Vector3(0, 0.205, -0.34), Vector3(0.20, 0.07, 0.23), dark)
                _part(weapon_model, "HoloLeft", Vector3(-0.085, 0.315, -0.34), Vector3(0.035, 0.19, 0.07), dark)
                _part(weapon_model, "HoloRight", Vector3(0.085, 0.315, -0.34), Vector3(0.035, 0.19, 0.07), dark)
                _part(weapon_model, "HoloTop", Vector3(0, 0.405, -0.34), Vector3(0.20, 0.035, 0.07), dark)
                for rib in range(7):
                    _part(weapon_model, "RailRib", Vector3(0, 0.015, -0.55 - rib * 0.045), Vector3(0.245, 0.20, 0.018), dark)
    var muzzle_z := -0.58 if current_weapon == "pistol" else -length * 0.99
    gun_flash.position.z = muzzle_z * weapon_model.scale.z
    muzzle_flare.position.z = gun_flash.position.z - 0.035

func _reload() -> void:
    if reloading:
        return
    if int(reserve_ammo[current_weapon]) <= 0 or ammo >= int(WeaponData.stats(current_weapon)["mag"]):
        return
    reloading = true
    reload_timer = float(WeaponData.stats(current_weapon)["reload"])
    sound_fx.reload()

func status_text() -> String:
    var state := "ARMA GUARDADA (H: SACAR)" if weapon_holstered else ("MIRANDO" if aiming else "LIVRE (H: GUARDAR)" )
    if crouching:
        state += " / AGACHADO"
    var stats: Dictionary = WeaponData.stats(current_weapon)
    if is_scope_active():
        state = "LUNETA %.0f× | RODA: 4–8×" % scope_zoom
    var definition := CharacterRegistry.definition(character_id)
    var character_name: String = definition.display_name if definition != null else "Jaime Original"
    var notice := "\n" + character_fallback_reason if not character_fallback_reason.is_empty() else ""
    return "PERSONAGEM: %s%s\n" % [character_name, notice] + "ARMA: %s  %s/%s +%s  |  TIROS: %s  |  %s" % [stats["name"], ammo, stats["mag"], reserve_ammo[current_weapon], shots, "RECARREGANDO" if reloading else state]
