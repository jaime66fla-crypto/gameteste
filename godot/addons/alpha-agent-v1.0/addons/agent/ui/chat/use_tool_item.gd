@tool
extends PanelContainer
@onready var title_label: Button = %TitleLabel
@onready var tool_request: TextEdit = %ToolRequest
@onready var tool_response: TextEdit = %ToolResponse
@onready var detail_container: VBoxContainer = %DetailContainer

var id: String = ""

func update_title(title: String):
	title_label.text = title

func update_request(argument_string: String):
	tool_request.text = _pretty_json_or_raw(argument_string)

func update_response(result_string: String):
	tool_response.text = _pretty_json_or_raw(result_string)

func _pretty_json_or_raw(text: String) -> String:
	var parsed = _parse_json_safely(text)
	if parsed == null:
		return text
	return JSON.stringify(parsed, "\t")

func _parse_json_safely(text: String):
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.get_data()

func _on_title_label_pressed() -> void:
	detail_container.visible = not detail_container.visible
