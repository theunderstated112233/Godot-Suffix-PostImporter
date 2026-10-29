@tool
class_name SuffixRule
extends Resource
## One suffix -> scene mapping.

# Explicit values keep existing .tres files valid (NONE/CONVEX/TRIMESH were 0/1/2).
enum Collision {
	NONE = 0,
	BOX = 3,
	SPHERE = 4,
	CAPSULE = 5,
	CYLINDER = 6,
	CONVEX = 1,
	SIMPLIFIED_CONVEX = 7,
	TRIMESH = 2,
}

enum Axis { AUTO, X, Y, Z }

## Suffix at the end of the Blender object name, e.g. "-worldhazard". Case-insensitive.
@export var suffix: String = "-example"
## Scene to instance. Its root must be a Node3D or a child of Node3D.
@export var scene: PackedScene
## Node inside `scene` to put the Blender mesh under. If not found, the scene root is used.
@export var mesh_slot: String = "MeshSlot"
## Build a collision shape from the mesh. Scene root must be a physics body or Area3D.
## BOX/SPHERE/CAPSULE/CYLINDER fit the mesh's bounding box (cheapest, best for RigidBody3D).
## CONVEX/SIMPLIFIED_CONVEX wrap the mesh. TRIMESH only for static bodies / areas.
@export var collision: Collision = Collision.NONE:
	set(v):
		collision = v
		notify_property_list_changed()
## Long axis for CAPSULE/CYLINDER. AUTO picks the mesh's longest side.
@export var shape_axis: Axis = Axis.AUTO


func _validate_property(property: Dictionary) -> void:
	if property.name == "shape_axis" and collision not in [Collision.CAPSULE, Collision.CYLINDER]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
