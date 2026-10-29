@tool
extends EditorScenePostImportPlugin

const SETTING := "suffix_importer/rules_path"

# Blender duplicates like "Rock-breakable.001" arrive as "Rock-breakable_001"
var _dup_regex := RegEx.create_from_string("[_.]\\d+$")


func _post_process(scene: Node) -> void:
	print("SuffixImporter: processing '%s'" % scene.name)
	var path: String = ProjectSettings.get_setting(SETTING, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("SuffixImporter: no rules file at '%s' (Project Settings > suffix_importer/rules_path)." % path)
		return
	var rule_set := load(path) as SuffixRuleSet
	if rule_set == null:
		push_warning("SuffixImporter: '%s' is not a SuffixRuleSet resource." % path)
		return
	if rule_set.rules.is_empty():
		push_warning("SuffixImporter: '%s' has no rules." % path)
		return
	for r in rule_set.rules:
		if r and r.scene == null:
			push_warning("SuffixImporter: rule '%s' has no scene set, it will be ignored." % r.suffix)

	# Collect first, then modify, so we don't mutate while iterating.
	var targets: Array = []
	_collect(scene, rule_set.rules, targets)
	if targets.is_empty():
		print("SuffixImporter: no names matched. Node names in this file:")
		_print_tree(scene, "  ")
		return
	for t in targets:
		print("SuffixImporter: '%s' (%s) -> %s" % [t[0].name, t[0].get_class(), t[1].scene.resource_path])
		_replace(scene, t[0], t[1])
	print("SuffixImporter: result:")
	_print_tree(scene, "  ")


func _print_tree(node: Node, indent: String) -> void:
	for c in node.get_children():
		var o := String(c.owner.name) if c.owner else "NONE"
		print("%s%s (%s) owner=%s" % [indent, c.name, c.get_class(), o])
		_print_tree(c, indent + "  ")


func _collect(node: Node, rules: Array[SuffixRule], out: Array) -> void:
	for child in node.get_children():
		var rule := _match(child.name, rules)
		if rule:
			out.append([child, rule])
		_collect(child, rules, out)


func _match(node_name: StringName, rules: Array[SuffixRule]) -> SuffixRule:
	var n := _dup_regex.sub(String(node_name), "").to_lower()
	for r in rules:
		if r and r.scene and not r.suffix.is_empty() and n.ends_with(r.suffix.to_lower()):
			return r
	return null


func _base_name(node_name: StringName, suffix: String) -> String:
	var n := _dup_regex.sub(String(node_name), "")
	return n.substr(0, n.length() - suffix.length())


func _replace(root: Node, node: Node, rule: SuffixRule) -> void:
	if not node is Node3D:
		push_warning("SuffixImporter: '%s' is not a Node3D, skipped." % node.name)
		return
	# GEN_EDIT_STATE_INSTANCE: same as the editor's "Instantiate Child Scene", so nodes
	# we add under the instance get saved instead of being dropped on pack().
	var inst := rule.scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if inst == null:
		push_warning("SuffixImporter: scene for '%s' has no Node3D root." % rule.suffix)
		return

	var src := node as Node3D
	var parent := src.get_parent()
	var idx := src.get_index()
	var src_xf := src.transform

	# Instance gets position + rotation; scale stays on the mesh (physics bodies hate scale).
	var inst_xf := Transform3D(src_xf.basis.orthonormalized(), src_xf.origin)
	inst.transform = inst_xf
	var base := _base_name(src.name, rule.suffix)
	inst.name = base if not base.is_empty() else rule.scene.resource_path.get_file().get_basename()

	parent.remove_child(src)
	parent.add_child(inst, true)
	parent.move_child(inst, idx)
	inst.owner = root
	# Required for anything we add BELOW the instance's own children to survive pack().
	# A direct child of the instance root (e.g. Collision) saves without this, but a node at
	# inst/MeshSlot/Mesh does not: that path is only valid when the instance is editable.
	root.set_editable_instance(inst, true)

	# Move the mesh into the slot.
	var slot: Node3D = null
	if not rule.mesh_slot.is_empty():
		slot = inst.find_child(rule.mesh_slot, true, false) as Node3D
	if slot == null:
		slot = inst
	var slot_xf := _xf_to(slot, inst)
	src.transform = slot_xf.affine_inverse() * (inst_xf.affine_inverse() * src_xf)
	src.name = "Mesh"
	src.owner = null  # avoid "owner inconsistent" warning; re-set below
	slot.add_child(src, true)
	_set_owner(src, root)

	if rule.collision != SuffixRule.Collision.NONE:
		_add_collision(root, inst, src, rule)


func _add_collision(root: Node, inst: Node3D, mesh_node: Node3D, rule: SuffixRule) -> void:
	if not inst is CollisionObject3D:
		push_warning("SuffixImporter: '%s' root isn't a body/area, no collision added." % inst.name)
		return
	if not mesh_node is MeshInstance3D or (mesh_node as MeshInstance3D).mesh == null:
		push_warning("SuffixImporter: '%s' has no mesh, no collision added." % inst.name)
		return

	var mesh := (mesh_node as MeshInstance3D).mesh
	var xf := _xf_to(mesh_node, inst)  # mesh offset/rotation/scale relative to the body
	var col := CollisionShape3D.new()
	col.name = "Collision"

	match rule.collision:
		SuffixRule.Collision.CONVEX, SuffixRule.Collision.SIMPLIFIED_CONVEX:
			var simplify := rule.collision == SuffixRule.Collision.SIMPLIFIED_CONVEX
			var s := mesh.create_convex_shape(true, simplify)
			s.points = xf * s.points  # bake transform into the points
			col.shape = s
		SuffixRule.Collision.TRIMESH:
			var s := mesh.create_trimesh_shape()
			s.set_faces(xf * s.get_faces())
			col.shape = s
		_:
			_fit_primitive(col, mesh.get_aabb(), xf, rule)

	inst.add_child(col, true)
	col.owner = root


# Fits BOX/SPHERE/CAPSULE/CYLINDER to the mesh's bounding box.
# Scale goes into the shape's size, never onto the CollisionShape3D node.
func _fit_primitive(col: CollisionShape3D, aabb: AABB, xf: Transform3D, rule: SuffixRule) -> void:
	var size := (aabb.size * xf.basis.get_scale()).abs()
	var basis := xf.basis.orthonormalized()
	var center := xf * aabb.get_center()

	match rule.collision:
		SuffixRule.Collision.BOX:
			var s := BoxShape3D.new()
			s.size = size
			col.shape = s

		SuffixRule.Collision.SPHERE:
			var s := SphereShape3D.new()
			s.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5
			col.shape = s

		SuffixRule.Collision.CAPSULE, SuffixRule.Collision.CYLINDER:
			var axis := _pick_axis(size, rule.shape_axis)
			var length: float = size[axis]
			var radius: float = maxf(size[(axis + 1) % 3], size[(axis + 2) % 3]) * 0.5
			# Godot's capsule/cylinder are Y-up; rotate Y onto the chosen axis.
			if axis == Vector3.AXIS_X:
				basis = basis * Basis(Vector3.BACK, -PI / 2)
			elif axis == Vector3.AXIS_Z:
				basis = basis * Basis(Vector3.RIGHT, PI / 2)
			if rule.collision == SuffixRule.Collision.CAPSULE:
				var s := CapsuleShape3D.new()
				s.radius = radius
				s.height = maxf(length, radius * 2.0)  # height includes the caps
				col.shape = s
			else:
				var s := CylinderShape3D.new()
				s.radius = radius
				s.height = length
				col.shape = s

	col.transform = Transform3D(basis, center)


func _pick_axis(size: Vector3, axis: SuffixRule.Axis) -> int:
	match axis:
		SuffixRule.Axis.X: return Vector3.AXIS_X
		SuffixRule.Axis.Y: return Vector3.AXIS_Y
		SuffixRule.Axis.Z: return Vector3.AXIS_Z
	return size.max_axis_index()


# Transform of `n` relative to ancestor `top`.
func _xf_to(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _set_owner(n: Node, owner_node: Node) -> void:
	n.owner = owner_node
	for c in n.get_children():
		_set_owner(c, owner_node)
