# Godot Suffix Post Importer

A simple Blender import pipeline using suffix tags (inspired by Godot's own way of
automatically turning a mesh named with a `-col` suffix into a collision shape).

Godot only gives you `-col`, `-colonly`, `-convcol` and friends. This addon lets you define
your own suffixes and map each one to a scene of your choice, so a Blender object named
`crate-breakable` imports as your breakable-crate scene with the Blender mesh already inside it.

Tested on Godot 4.7.

## Install

1. Copy `addons/suffix_importer/` into your project.
2. Enable **Godot Suffix Post Importer** in *Project > Project Settings > Plugins*.
3. Enabling it adds the setting `suffix_importer/rules_path`, pointing at
   `res://addons/suffix_importer/suffix_rules.tres` by default. Point it anywhere you like.

## Usage

This addon introduces `SuffixRule` and `SuffixRuleSet` custom resource types that you can
create and edit in the Inspector.

Create a `SuffixRuleSet` resource, save it, and set `suffix_importer/rules_path` to it.
A `SuffixRuleSet` holds an array of `SuffixRule`, which consist of the following:

| Field | What it does |
| --- | --- |
| **Suffix** | The suffix tag you put in the object name in Blender. For an object named `mesh-example` you put in `-example`, or your choice of suffix. Case-insensitive. |
| **Scene** | The scene instanced in place of the imported object. Usually a physics body or an `Area3D` with whatever scripts and children you want. Its root has to be a `Node3D` or derived. |
| **Mesh Slot** | Name of the node inside **Scene** that the Blender mesh gets parented to. Defaults to `MeshSlot`. If no node by that name exists, the mesh goes directly under the scene root. |
| **Collision** | Builds a `CollisionShape3D` from the mesh, or `None` to skip it. **Scene**'s root has to be a physics body or `Area3D`. |
| **Shape Axis** | Long axis for `Capsule`/`Cylinder` only. `Auto` picks the mesh's longest side. Hidden for every other collision type. |

### Collision types

| Type | Notes |
| --- | --- |
| `None` | No shape. Use this when the scene already has its own collision. |
| `Box` / `Sphere` / `Capsule` / `Cylinder` | Fitted to the mesh's bounding box. Cheapest, and the right pick for a `RigidBody3D`. |
| `Convex` | Wraps the mesh in a convex hull. |
| `Simplified Convex` | Same, with fewer points. |
| `Trimesh` | Exact mesh shape. **Static bodies and areas only** — Godot can't use a concave shape on a `RigidBody3D`. |

## Suffix examples

| Blender object name | Rule | Result |
| --- | --- | --- |
| `light-lamppost` | `-lamppost` -> `lamppost.tscn` (StaticBody3D), Trimesh | A lamp post you can drive into, named `light` in the scene tree |
| `rock-worldhazard` | `-worldhazard` -> `world_hazard.tscn` (RigidBody3D), Convex | A loose rock that gets knocked around |
| `crate-breakable` | `-breakable` -> `breakable.tscn` (Area3D + script), Box | A crate that plays its breaking animation on `body_entered` |

Reimport the file (or just save the .blend again) and the objects come in already wired up.

## What the importer does

For every imported node whose name ends in a configured suffix:

1. Instances **Scene** in its place, keeping the object's position in the file.
2. Names the instance after the object with the suffix stripped off — `light-lamppost`
   becomes `light`.
3. Renames the Blender mesh to `Mesh` and reparents it into **Mesh Slot**, correcting its
   transform so it doesn't move.
4. Adds a `Collision` child built from the mesh, if **Collision** asks for one.

## Notes

- The instance takes the object's position and rotation; **scale stays on the mesh**, because
  physics bodies misbehave under a scaled parent. Collision shapes are sized with the scale
  baked in rather than inherited.
- Blender duplicates match too: `Rock-breakable.001` arrives as `Rock-breakable_001` and still
  hits the `-breakable` rule.
- The importer turns on **Editable Children** for the instances it creates. It has to — Godot
  won't save nodes added below a non-editable instance's own children, so the mesh would
  silently vanish from the imported scene. It also means edits you make to the template scene
  still propagate.
- Rules are matched in order, first one wins, so put more specific suffixes before general ones.
- The importer prints what it did to the Output panel, including the resulting tree. If a name
  doesn't match anything it prints the node names it found in the file, which is usually enough
  to spot the typo.

### Note
Claude made this bc I was too lazy to get up and make a feature complete tool addon (I just wanted a blender importing pipeline to quickly set up godot scenes)
