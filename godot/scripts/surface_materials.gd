extends RefCounted
## Small deterministic PBR tiles, built once and shared across the scene.
## World triplanar mapping keeps grain at a consistent size on long roads and walls.
const SIZE := 128
const PERIOD := SIZE - 1
static var materials: Dictionary = {}
static var textures: Dictionary = {}

static func make(kind: String, tint: Color, world_space: bool = true) -> StandardMaterial3D:
    var key := kind + tint.to_html() + str(world_space)
    if materials.has(key):
        return materials[key]
    var pattern := "asphalt" if kind == "paint" else kind
    if not textures.has(pattern):
        textures[pattern] = _tile(pattern)
    var maps: Array = textures[pattern]
    var material := StandardMaterial3D.new()
    material.resource_name = kind + "_" + tint.to_html(false)
    material.albedo_color = tint
    material.albedo_texture = maps[0]
    material.normal_enabled = true
    material.normal_texture = maps[1]
    material.normal_scale = 0.18 if kind in ["metal", "paint", "fabric"] else 0.45
    material.roughness = 1.0
    material.roughness_texture = maps[2]
    material.metallic = 0.55 if kind in ["metal", "roof"] else 0.0
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.texture_repeat = true
    material.uv1_triplanar = true
    material.uv1_world_triplanar = world_space
    material.uv1_triplanar_sharpness = 4.0
    var density := 0.5 if kind in ["grass", "concrete"] else 1.0
    if kind in ["wood", "bark", "leaf", "metal"]:
        density = 2.0
    elif kind == "fabric":
        density = 10.0
    material.uv1_scale = Vector3.ONE * density
    materials[key] = material
    return material

static func _grain(x: int, y: int, seed_value: int) -> float:
    var value := ((x % PERIOD) * 73856093) ^ ((y % PERIOD) * 19349663) ^ seed_value
    value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
    return float(value % 65536) / 65535.0

static func _tile(kind: String) -> Array:
    var noise := FastNoiseLite.new()
    noise.seed = int(kind.hash() % 2147483647)
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = 0.045
    noise.fractal_octaves = 3
    var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
    var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
    var roughness := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
    var heights := PackedFloat32Array()
    heights.resize(SIZE * SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            var u := float(x) / PERIOD
            var v := float(y) / PERIOD
            # Blend opposing samples so the image and its normal map tile seamlessly.
            var a := lerpf(noise.get_noise_2d(u * SIZE, v * SIZE), noise.get_noise_2d(u * SIZE - SIZE, v * SIZE), u)
            var b := lerpf(noise.get_noise_2d(u * SIZE, v * SIZE - SIZE), noise.get_noise_2d(u * SIZE - SIZE, v * SIZE - SIZE), u)
            var cloud := lerpf(a, b, v)
            var grain := _grain(x, y, noise.seed) - 0.5
            var value := 0.86 + cloud * 0.18 + grain * 0.10
            var height := cloud * 0.12 + grain * 0.04
            var rough := 0.90 + grain * 0.12
            match kind:
                "asphalt":
                    value = 0.78 + cloud * 0.12 + grain * 0.27
                    height = grain * 0.10
                "concrete":
                    if x == 0 or y == 0 or x == PERIOD or y == PERIOD:
                        value *= 0.82
                        height -= 0.035
                "grass", "leaf":
                    value = 0.79 + cloud * 0.33 + grain * 0.15
                    height = cloud * 0.18 + grain * 0.12
                "wood", "bark":
                    var rings := sin(u * TAU * 12.0 + cloud * 5.0)
                    value = 0.77 + rings * 0.11 + cloud * 0.09 + grain * 0.06
                    height = rings * 0.10 + grain * 0.02
                "roof":
                    var rib := cos(u * TAU * 12.0)
                    value = 0.81 + rib * 0.10 + grain * 0.04
                    height = rib * 0.24
                    rough = 0.67 + grain * 0.12
                "metal":
                    value = 0.85 + cloud * 0.10 + grain * 0.07
                    height = grain * 0.02
                    rough = 0.60 + cloud * 0.15 + grain * 0.10
                "fabric":
                    var weave := sin(u * TAU * 24.0) * sin(v * TAU * 24.0)
                    value = 0.87 + weave * 0.07 + grain * 0.04
                    height = weave * 0.035
            value = clampf(value, 0.35, 1.0)
            albedo.set_pixel(x, y, Color(value, value, value))
            rough = clampf(rough, 0.35, 1.0)
            roughness.set_pixel(x, y, Color(rough, rough, rough))
            heights[y * SIZE + x] = height
    for y in range(SIZE):
        for x in range(SIZE):
            var left := heights[(y % PERIOD) * SIZE + (x + PERIOD - 1) % PERIOD]
            var right := heights[(y % PERIOD) * SIZE + (x + 1) % PERIOD]
            var up := heights[((y + PERIOD - 1) % PERIOD) * SIZE + x % PERIOD]
            var down := heights[((y + 1) % PERIOD) * SIZE + x % PERIOD]
            var vector := Vector3((left - right) * 3.0, (down - up) * 3.0, 1.0).normalized()
            normal.set_pixel(x, y, Color(vector.x * 0.5 + 0.5, vector.y * 0.5 + 0.5, vector.z * 0.5 + 0.5))
    albedo.generate_mipmaps()
    normal.generate_mipmaps(true)
    roughness.generate_mipmaps()
    return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(normal), ImageTexture.create_from_image(roughness)]
