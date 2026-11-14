extends CharacterBody3D

const WALK_SPEED := 5.0
const RUN_SPEED := 8.7
const CROUCH_SPEED := 2.7
const JUMP_VELOCITY := 8.5
const MOUSE_SENSITIVITY := 0.0025
const MAG_SIZE := 15

var yaw := 0.0
var pitch := -0.14
var aiming := false
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

func _ready() -> void:
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.34
    capsule.height = 1.8
    collision.shape = capsule
    collision.position.y = 0.9
    add_child(collision)
    avatar = Node3D.new()
    add_child(avatar)
    _make_avatar()
    arm_pivot = Node3D.new()
    arm_pivot.position = Vector3(0, 1.55, 0)
    add_child(arm_pivot)
    var spring := SpringArm3D.new()
    spring.spring_length = cam_distance
    spring.margin = 0.15
    spring.position.x = 0.6
    arm_pivot.add_child(spring)
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 72
    spring.add_child(camera)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _material(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.metallic = 0.08
    return m

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
    _part(gun,"PistolBody",Vector3(0,0,-0.22),Vector3(0.16,0.20,0.52),Color(0.08,0.09,0.10))
    _part(gun,"Grip",Vector3(0,-0.16,-0.08),Vector3(0.13,0.30,0.13),Color(0.11,0.11,0.12))
    gun_flash = OmniLight3D.new()
    gun_flash.position = Vector3(0,0,-0.57)
    gun_flash.light_color = Color(1,0.65,0.25)
    gun_flash.light_energy = 0
    gun.add_child(gun_flash)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * MOUSE_SENSITIVITY
        pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.15, 0.95)

func _physics_process(delta: float) -> void:
    aiming = Input.is_action_pressed("aim")
    crouching = Input.is_action_pressed("crouch")
    rotation.y = yaw
    arm_pivot.rotation.x = pitch
    var desired_fov := 52.0 if aiming else 72.0
    camera.fov = lerpf(camera.fov, desired_fov, minf(1,delta * 10))
    var spring: SpringArm3D = camera.get_parent()
    spring.spring_length = lerpf(spring.spring_length, 2.15 if aiming else cam_distance, minf(1,delta * 9))
    arm_pivot.position.y = lerpf(arm_pivot.position.y, 1.05 if crouching else 1.55, minf(1,delta * 10))
    avatar.position.y = lerpf(avatar.position.y, -0.36 if crouching else 0.0, minf(1,delta * 10))
    var input_vec := Input.get_vector("move_left","move_right","move_forward","move_back")
    var movement := Vector3(input_vec.x,0,input_vec.y).rotated(Vector3.UP,yaw)
    var speed := CROUCH_SPEED if crouching else (RUN_SPEED if Input.is_action_pressed("sprint") and not aiming else WALK_SPEED)
    velocity.x = movement.x * speed
    velocity.z = movement.z * speed
    if not is_on_floor():
        velocity.y -= 22.0 * delta
    elif Input.is_action_just_pressed("jump") and not crouching:
        velocity.y = JUMP_VELOCITY
    else:
        velocity.y = -0.1
    move_and_slide()
    fire_delay = maxf(0, fire_delay - delta)
    gun_flash.light_energy = move_toward(gun_flash.light_energy, 0, delta * 55)
    if reloading:
        reload_timer -= delta
        if reload_timer <= 0:
            ammo = MAG_SIZE
            reloading = false
    if Input.is_action_just_pressed("reload") and ammo < MAG_SIZE and not reloading:
        _reload()
    if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and fire_delay <= 0 and not reloading:
        _shoot()

func _shoot() -> void:
    if ammo <= 0:
        _reload()
        return
    ammo -= 1
    shots += 1
    fire_delay = 0.22
    gun_flash.light_energy = 2.8
    var origin := camera.global_position
    var target := origin - camera.global_transform.basis.z * 250.0
    var query := PhysicsRayQueryParameters3D.create(origin,target)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        print("Acerto: ", hit["position"])

func _reload() -> void:
    if reloading:
        return
    reloading = true
    reload_timer = 1.3

func status_text() -> String:
    var state := "MIRANDO" if aiming else "LIVRE"
    if crouching:
        state += " / AGACHADO"
    return "ARMA: PISTOLA  %s/%s  |  TIROS: %s  |  %s" % [ammo, MAG_SIZE, shots, "RECARREGANDO" if reloading else state]
