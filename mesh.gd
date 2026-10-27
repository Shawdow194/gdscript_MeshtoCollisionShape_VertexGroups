@tool
extends Node3D

@export_node_path
var skeleton_path: NodePath

##Edits collision shapes of all children Physical Bones
@export_node_path
var physical_simulator_path: NodePath

##Select path of meshes (usually Skeleton3D again), or a single mesh path
@export_node_path
var mesh_instance_path: NodePath

@export_range(0.0, 1.0, 0.01)
var weight_threshold: float = 0.25
@export_range(1, 20, 1)
var min_points_for_convex: int = 6

@export var remove_existing_collision_shapes: bool = true

const ARRAY_VERTEX := Mesh.ARRAY_VERTEX
const ARRAY_BONES := Mesh.ARRAY_BONES
const ARRAY_WEIGHTS := Mesh.ARRAY_WEIGHTS

func _ready() -> void:
	generate_collision_shapes()


func generate_collision_shapes() -> void:
	var mesh_instance: Node3D = get_node_or_null(mesh_instance_path)
	var skeleton: Skeleton3D = get_node_or_null(skeleton_path)
	var simulator: Node3D = get_node_or_null(physical_simulator_path)

	if not mesh_instance:
		push_error("Mesh instance not found. Set mesh_instance_path.")
		return
	if not skeleton:
		push_error("Skeleton3D not found. Set skeleton_path.")
		return
	if not simulator:
		push_error("PhysicalBoneSimulator3D not found. Set physical_simulator_path.")
		return
		
	var meshs: Array = []
	if mesh_instance is MeshInstance3D:
		meshs.append(mesh_instance)
	meshs += mesh_instance.get_children().filter(func(c): return c is MeshInstance3D)
	print(meshs)
		
	if meshs.is_empty():
		push_error("No MeshInstance3D found under mesh_instance_path")
		return

	var bone_vertex_map := {}
	var bone_count := skeleton.get_bone_count()
	for i in range(bone_count):
		bone_vertex_map[i] = []
	
	for m in meshs:
		var mesh: Mesh = m.mesh
		var surface_count := mesh.get_surface_count()
		for s in range(surface_count):
			var arrays := mesh.surface_get_arrays(s)
			if arrays.size() == 0:
				continue
			if ARRAY_VERTEX >= arrays.size():
				continue
			var verts: PackedVector3Array = arrays[ARRAY_VERTEX]
			if verts.is_empty():
				continue

			if ARRAY_BONES >= arrays.size() or ARRAY_WEIGHTS >= arrays.size():
				continue
			var bones_arr = arrays[ARRAY_BONES]
			var weights_arr = arrays[ARRAY_WEIGHTS]

			if bones_arr.size() < verts.size() * 4 or weights_arr.size() < verts.size() * 4:
				continue
		
			print("Surface: ", s, " Verts: ", verts.size(), " Bones_length: ", bones_arr.size(), " Weights_length: ", weights_arr.size())
			
			for vi in range(verts.size()):
				var v: Vector3 = verts[vi]
				var base_idx := vi * 4
				for j in range(4):
					var bidx := int(bones_arr[base_idx + j])
					var w := float(weights_arr[base_idx + j])
					if w >= weight_threshold and bidx >= 0 and bidx < bone_count:
						bone_vertex_map[bidx].append(v)
	
	var mesh_global_xform: Transform3D = mesh_instance.global_transform
	#print(bone_vertex_map)
	for bone_idx in bone_vertex_map.keys():
		print("Bone: ", bone_idx, " Name:", skeleton.get_bone_name(bone_idx), " Count:", bone_vertex_map[bone_idx].size())
		var bone_name = skeleton.get_bone_name(bone_idx)
		if bone_name == "":
			continue

		var physical_bone_node: Node3D = null
		if simulator.has_node(bone_name):
			physical_bone_node = simulator.get_node(bone_name)
		else:
			var alt_name = "Physical Bone " + bone_name
			if simulator.has_node(alt_name):
				physical_bone_node = simulator.get_node(alt_name)
			else:
				for child in simulator.get_children():
					if child is Node3D and bone_name in child.name:
						physical_bone_node = child
						break

		if not physical_bone_node:
			continue

		if remove_existing_collision_shapes:
			for child in physical_bone_node.get_children():
				if child is CollisionShape3D:
					child.queue_free()

		var raw_points: Array = bone_vertex_map[bone_idx]
		if raw_points.is_empty():
			continue

		var transformed_points := []
		var inv_phys_xform := physical_bone_node.global_transform.affine_inverse()
		for v in raw_points:
			var global_v = mesh_global_xform * v
			var local_v = inv_phys_xform * global_v
			transformed_points.append(local_v)

		transformed_points = _unique_points(transformed_points, 0.001)

		if transformed_points.size() >= min_points_for_convex:
			var convex_shape := ConvexPolygonShape3D.new()
			var pva := PackedVector3Array()
			for p in transformed_points:
				pva.append(p *0.85)
			convex_shape.points = pva
			var cs := CollisionShape3D.new()
			cs.shape = convex_shape
			physical_bone_node.add_child(cs)
			cs.owner = physical_bone_node.owner
		else:
			var aabb := _points_aabb(transformed_points)
			var radius = max(aabb.size.x, aabb.size.y, aabb.size.z) * 0.5
			if radius <= 0.001:
				radius = 0.05
			var sphere := SphereShape3D.new()
			sphere.radius = radius
			var cs := CollisionShape3D.new()
			cs.shape = sphere
		#cs.translation = aabb.position + aabb.size * 0.5
			physical_bone_node.add_child(cs)
			cs.owner = physical_bone_node.owner
	
	print("Bone collision generation complete.")


func _unique_points(points: Array, eps: float) -> Array:
	var unique = {}
	for p in points:
		var snapped = p.snapped(Vector3(eps, eps, eps))
		unique[snapped] = p
	return unique.values()


func _points_aabb(points: Array) -> AABB:
	if points.is_empty():
		return AABB()
	var minp = points[0]
	var maxp = points[0]
	for p in points:
		minp = Vector3(min(minp.x, p.x), min(minp.y, p.y), min(minp.z, p.z))
		maxp = Vector3(max(maxp.x, p.x), max(maxp.y, p.y), max(maxp.z, p.z))
	return AABB(minp, maxp - minp)
