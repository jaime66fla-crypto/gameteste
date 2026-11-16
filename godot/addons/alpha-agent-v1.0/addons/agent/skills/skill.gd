@tool
class_name AgentSkillResource
extends Resource

# 技能名称
@export var skill_name: String = ""
# 技能描述
@export var skill_description: String = ""
# 技能内容
@export_multiline var skill_content: String = ""

# 关联的文件夹路径
var skill_folder_path: String = ""

# 从 SKILL.md 解析（静态工厂方法）
static func load_from_folder(folder_path: String) -> AgentSkillResource:
	var skill = AgentSkillResource.new()
	skill.skill_folder_path = folder_path

	var md_path = folder_path + "/SKILL.md"
	if not FileAccess.file_exists(md_path):
		AlphaAgentPlugin.print_alpha_message("技能文件夹缺少 SKILL.md: {0}".format([folder_path]))
		return skill

	var content = FileAccess.get_file_as_string(md_path)
	if content.is_empty():
		return skill

	# 解析 YAML front matter
	var front_matter_end = content.find("\n---\n", 4)  # 跳过第一个---
	if front_matter_end != -1:
		var front_matter = content.substr(4, front_matter_end - 4)
		# 简单解析 YAML (name: xxx, description: xxx)
		for line in front_matter.split("\n"):
			if line.begins_with("name:"):
				skill.skill_name = line.substr(5).strip_edges()
			elif line.begins_with("description:"):
				skill.skill_description = line.substr(12).strip_edges()

		skill.skill_content = content.substr(front_matter_end + 5)
	else:
		# 无 front matter，整个文件作为 content
		skill.skill_content = content

	return skill

# 保存到 SKILL.md
func save_to_folder() -> bool:
	if skill_folder_path.is_empty():
		AlphaAgentPlugin.print_alpha_message("技能文件夹路径为空，无法保存")
		return false

	var md_path = skill_folder_path + "/SKILL.md"
	var front_matter = "---\nname: {name}\ndescription: {desc}\n---\n\n{content}".format({
		"name": skill_name,
		"desc": skill_description,
		"content": skill_content
	})

	var file = FileAccess.open(md_path, FileAccess.WRITE)
	if file == null:
		AlphaAgentPlugin.print_alpha_message("无法保存技能到: {0}".format([md_path]))
		return false
	file.store_string(front_matter)
	file.close()
	return true

# 获取技能的markdown格式内容
func get_skill_markdown() -> String:
	return "---\nname: {skill_name}\ndescription: {skill_description}\n---\n\n{skill_content}".format({
		"skill_name": skill_name,
		"skill_description": skill_description,
		"skill_content": skill_content
	})
