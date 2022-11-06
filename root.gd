@tool
extends Node3D

## This script was used to check procedural mesh generation, is not used, but has too much potential and tech use to remove 

@export var generate : bool = false:
	get:return false
	set(_v):
		_generate()
		generate = false

@export_flags(N,E,S,W,U,D) var sides : int = 0

func rotateVec3Arr(arr:PackedVector3Array, axis:Vector3, angle:float) -> PackedVector3Array:
	var newarr : PackedVector3Array = []
	for v in arr: newarr.append(v.rotated(axis, angle))
	return newarr

func addface(arr_mesh:ArrayMesh, axis:Vector3, angle:float, quadverts:PackedVector3Array) -> void:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = rotateVec3Arr(quadverts, axis, angle)
	# Create the Mesh.
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _generate():
	print("Generating")
	var quadverts : PackedVector3Array = [
	Vector3(-1, 1, 1),
	Vector3(1, -1, 1),
	Vector3(1, 1, 1),
	Vector3(-1, 1, 1),
	Vector3(-1, -1, 1),
	Vector3(1, -1, 1)]

	var mesh : MeshInstance3D = $MeshInstance3d
	var arr_mesh : ArrayMesh = ArrayMesh.new()

	if (sides >> 0) % 2: # If there's a north component
		addface(arr_mesh, Vector3.UP, 0, quadverts)

	if (sides >> 1) % 2: # If there's a east component
		addface(arr_mesh, Vector3.UP, -PI/2, quadverts)

	if (sides >> 2) % 2: # If there's a south component
		addface(arr_mesh, Vector3.UP, PI, quadverts)

	if (sides >> 3) % 2: # If there's a west component
		addface(arr_mesh, Vector3.UP, PI/2, quadverts)

	if (sides >> 4) % 2: # If there's a up component
		addface(arr_mesh, Vector3.LEFT, PI/2, quadverts)

	if (sides >> 5) % 2: # If there's a down component
		addface(arr_mesh, Vector3.LEFT, -PI/2, quadverts)

	mesh.mesh = arr_mesh
