extends Resource
## Stable identity and editable visual path; never store mutable gameplay stats here.
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export_file("*.tscn") var visual_scene: String = ""
@export var required_resources: PackedStringArray = []

@export_group("Braços em primeira pessoa")
## Matches the procedural first-person arms to this character's clothes and skin.
@export var fp_sleeve := Color("#56603f")
## rolled: sleeve rolled below the elbow; long: sleeve to the wrist;
## short: t-shirt sleeve, bare arm from mid upper arm; none: bare arm.
@export_enum("rolled", "long", "short", "none") var fp_sleeve_style := "rolled"
@export var fp_skin := Color("#8a624d")
@export var fp_gloves := true
@export var fp_glove := Color("#1c1e21")
## Elbow/wrist joint colour (alpha 0 = same as the surface around it).
@export var fp_joint := Color(0, 0, 0, 0)
