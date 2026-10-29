@tool
extends EditorPlugin

const SETTING := "suffix_importer/rules_path"
const DEFAULT_PATH := "res://addons/suffix_importer/suffix_rules.tres"

var _importer: EditorScenePostImportPlugin


func _enter_tree() -> void:
	if not ProjectSettings.has_setting(SETTING):
		ProjectSettings.set_setting(SETTING, DEFAULT_PATH)
		ProjectSettings.save()
	ProjectSettings.set_initial_value(SETTING, DEFAULT_PATH)
	ProjectSettings.add_property_info({
		"name": SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res",
	})
	_importer = preload("suffix_post_import.gd").new()
	add_scene_post_import_plugin(_importer)


func _exit_tree() -> void:
	remove_scene_post_import_plugin(_importer)
	_importer = null
