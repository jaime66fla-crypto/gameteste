@tool
class_name AgentSkillContainer
extends VBoxContainer

@onready var skill_list_container: VBoxContainer = %SkillListContainer
@onready var list_title: Label = %ListTitle
@onready var add_skill_button: Button = %AddSkillButton
@onready var skill_list: VBoxContainer = %SkillList
@onready var skill_edit_container: VBoxContainer = %SkillEditContainer
#@onready var smart_recognition_input: TextEdit = %SmartRecognitionInput
@onready var skill_name_input: LineEdit = %SkillNameInput
@onready var skill_description_input: TextEdit = %SkillDescriptionInput
@onready var skill_content_input: TextEdit = %SkillContentInput
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var open_skill_dir_button: Button = %OpenSkillDirButton

const SKILL_ITEM = preload("uid://dkic1ui7mmhyy")

var edited_skill = null
var _setting_ready_connected: bool = false

func _ready() -> void:
	visibility_changed.connect(on_visibility_changed)
	add_skill_button.pressed.connect(on_add_skill_button_pressed)
	confirm_button.pressed.connect(on_confirm_button_pressed)
	cancel_button.pressed.connect(on_cancel_button_pressed)
	open_skill_dir_button.pressed.connect(on_open_skill_dir_button_pressed)

	# 等待 setting_ready 后再渲染技能列表
	if not _setting_ready_connected:
		_setting_ready_connected = true
		AlphaAgentPlugin.global_setting.setting_ready.connect(_on_setting_ready, CONNECT_ONE_SHOT)

func _on_setting_ready():
	if visible:
		_try_render()

func _try_render():
	if not AlphaAgentPlugin.global_setting.setting_is_ready:
		return
	clear_skill_nodes()
	add_skill_nodes()

func on_visibility_changed():
	if visible:
		_try_render()
		skill_list_container.show()
		skill_edit_container.hide()
	else:
		clear_skill_nodes()

func clear_skill_nodes():
	for item in skill_list.get_children():
		item.queue_free()


func add_skill_nodes():
	var skill_manager = AlphaAgentPlugin.global_setting.skill_manager
	if skill_manager == null:
		return

	var skills = skill_manager.skills
	for skill in skills:
		if skill == null:
			continue
		var skill_item = SKILL_ITEM.instantiate()
		skill_list.add_child(skill_item)
		skill_item.set_skill(skill)
		skill_item.edit.connect(on_edit_skill_button_pressed.bind(skill))
		skill_item.delete.connect(on_delete_skill_button_pressed.bind(skill, skill_item))

func on_edit_skill_button_pressed(skill: AgentSkillResource):
	if skill == null:
		return
	skill_list_container.hide()
	skill_edit_container.show()
	edited_skill = skill
	skill_name_input.text = skill.skill_name
	skill_name_input.editable = false
	skill_description_input.text = skill.skill_description
	skill_content_input.text = skill.skill_content

func on_delete_skill_button_pressed(skill: AgentSkillResource, skill_item: AgentSkillItem):
	AlphaAgentPlugin.global_setting.skill_manager.delete_skill(skill)
	skill_item.queue_free()

func on_add_skill_button_pressed():
	skill_list_container.hide()
	skill_edit_container.show()
	edited_skill = null
	skill_name_input.editable = true
	skill_name_input.text = ""
	skill_description_input.text = ""
	skill_content_input.text = ""

func on_confirm_button_pressed():
	if edited_skill:
		edited_skill.skill_name = skill_name_input.text
		edited_skill.skill_description = skill_description_input.text
		edited_skill.skill_content = skill_content_input.text
		AlphaAgentPlugin.global_setting.skill_manager.update_skill(edited_skill)
	else:
		var skill = AgentSkillResource.new()
		skill.skill_name = skill_name_input.text
		skill.skill_description = skill_description_input.text
		skill.skill_content = skill_content_input.text
		AlphaAgentPlugin.global_setting.skill_manager.add_skill(skill)
		clear_skill_nodes()
		add_skill_nodes()
	skill_list_container.show()
	skill_edit_container.hide()

func on_cancel_button_pressed():
	skill_list_container.show()
	skill_edit_container.hide()

func on_open_skill_dir_button_pressed():
	OS.shell_show_in_file_manager(AlphaAgentPlugin.global_setting.skill_directory)
