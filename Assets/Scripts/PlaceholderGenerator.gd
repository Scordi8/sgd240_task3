@tool
extends EditorScript

## Pattern: North East South West Up Down
## North = z+
## East = x+
## Up = y+

var filedest : String = "res://Assets/Resources/Generated/Segments/"

var ft : Array[bool] = [false, true]

var depth : int = 0

func _run():
	_stuff()

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

func getmesh(N, E, S, W, U, D, quadverts) -> ArrayMesh:
	# Initialize the ArrayMesh.
	var arr_mesh : ArrayMesh = ArrayMesh.new()

	if N: # If there's a north component
		addface(arr_mesh, Vector3.UP, 0, quadverts)

	if E: # If there's a east component
		addface(arr_mesh, Vector3.UP, -PI/2, quadverts)

	if S: # If there's a south component
		addface(arr_mesh, Vector3.UP, PI, quadverts)

	if W: # If there's a west component
		addface(arr_mesh, Vector3.UP, PI/2, quadverts)

	if U: # If there's a up component
		addface(arr_mesh, Vector3.LEFT, PI/2, quadverts)

	if D: # If there's a up component
		addface(arr_mesh, Vector3.LEFT, -PI/2, quadverts)
	return arr_mesh



func _stuff():
	var quadverts : PackedVector3Array = [
	Vector3(-1, 1, 1),
	Vector3(1, -1, 1),
	Vector3(1, 1, 1),
	Vector3(-1, 1, 1),
	Vector3(-1, -1, 1),
	Vector3(1, -1, 1)]
	depth = 0
	for D in ft:
		for U in ft:
			for W in ft:
				for S in ft:
					for E in ft:
						for N in ft:
							var mesh : ArrayMesh = getmesh(N, E, S, W, U, D, quadverts)
							var path : String = filedest + "Segment_" + str(depth) + ".tres"
							ResourceSaver.save(mesh, path)
							depth += 1
