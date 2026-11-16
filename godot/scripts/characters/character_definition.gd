extends Resource
## Stable identity and editable visual path; never store mutable gameplay stats here.
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export_file("*.tscn") var visual_scene: String = ""
@export var required_resources: PackedStringArray = []
