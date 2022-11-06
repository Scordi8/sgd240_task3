@tool
class_name Room extends Node3D

@export var boundingBox : AABB

@onready var contentNode : Node3D = $Content ## Node tha contains all the content
@export var roomMeshNode : NodePath ## Nodepath to node with all mesh and collision
@export var doorNodesRoot : NodePath ## Nodepath to node with all door Markers
var doorData : Array[Marker3D] = [] ## list of all the door markers
const visualizerMaterial : String = "res://Assets/Resources/Models/materials/Visualizer.tres"

## Editor bool to trigger validation and visualization
@export var _validate : bool = false :
	get:return false
	set(_v):
		_validate = false
		validate()
## Editor bool to trigger visualization only
@export var _visualize : bool = false :
	get:return false
	set(_v):
		_visualize = false
		visualize()

@export var visualizermeshNode : NodePath
var visualizermesh : MeshInstance3D

## retrieve the data of all the doors without re-validifying the room
func get_doorData() -> Array[Array]:
	var arr : Array = []
	for door in get_node(doorNodesRoot).get_children():
		arr.append([door, door.get_meta("alignment")])
	return arr

func validate():
	print("Validating")
	visualizermesh = get_node(visualizermeshNode)
	
	### Check and generate an AABB for the room, ceil it up
	var min_pos : Vector3 = Vector3.ZERO
	var max_size : Vector3 = Vector3.ZERO
	var decendants : Array[Node] = []
	if contentNode == null: contentNode = $Content
	contentNode.position = Vector3.ZERO
	visualizermesh.position = Vector3.ZERO
	decendants.append_array(get_node(roomMeshNode).get_children())
	while decendants.size() > 0:
		var child : Node = decendants.pop_front()
		
		## Check for other children
		var children : Array[Node] = child.get_children()
		if children.size() > 0: decendants.append_array(children)
		
		## If it's a mesh child, get it's aabb
		if child.is_class("MeshInstance3D"):
			if child.name == "Visualizer": continue ## Ignore the visualizer mesh
			var aabb : AABB = child.get_transformed_aabb()
			min_pos = Vector3(min(min_pos.x, aabb.position.x),
							min(min_pos.y, aabb.position.y),
							min(min_pos.z, aabb.position.z))
			max_size = Vector3(max(max_size.x, aabb.end.x),
							max(max_size.y, aabb.end.y),
							max(max_size.z, aabb.end.z))
	min_pos = floor(min_pos)
	max_size = ceil(max_size)
	boundingBox = AABB(min_pos, max_size)
	## AABB setup ended
	
	## Marker position rounding
	for _child in get_node(doorNodesRoot).get_children():
		var child : Marker3D = _child
		child.position = round(child.position)

		## get closest side
		var mid : Vector3 = boundingBox.get_center()
		var disttowall : Vector3 ## How far away from the wall it is
		var wallpos : Vector3 ## Where the wall is
		print(mid, child.position)
		print(child.position.x > mid.x)
		print(boundingBox.position.x, " ", child.position.x)


		if child.position.x > mid.x:
			wallpos.x = boundingBox.position.x
			disttowall.x = abs(boundingBox.position.x - child.position.x)
		else:
			wallpos.x = boundingBox.size.x
			disttowall.x = abs(boundingBox.size.x - child.position.x)
		
		if child.position.y < mid.y:
			wallpos.y = boundingBox.position.y
			disttowall.y = wallpos.y + child.position.y
		else:
			wallpos.y = boundingBox.size.y
			disttowall.y = wallpos.y - child.position.y
		
		if child.position.z < mid.z:
			wallpos.z = boundingBox.position.z
			disttowall.z = wallpos.z + child.position.z
		else:
			wallpos.z = boundingBox.size.z
			disttowall.z = wallpos.z - child.position.z
		
		var clampX : Callable = func(_c:Marker3D, _bb:AABB) -> float: return clamp(_c.position.x,
			min(_bb.position.x, _bb.size.x),
			max(_bb.position.x, _bb.size.x))
		
		var clampY : Callable = func(_c:Marker3D, _bb:AABB) -> float: return clamp(_c.position.y,
			min(_bb.position.y, _bb.size.y),
			max(_bb.position.y, _bb.size.y))
		
		var clampZ : Callable = func(_c:Marker3D, _bb:AABB) -> float: return clamp(_c.position.z,
			min(_bb.position.z, _bb.size.z),
			max(_bb.position.z, _bb.size.z))
		
		print("Wall pos: ", wallpos)
		print("Dist to wall: ", disttowall)
		## Get the closest wall
		if disttowall.x <= disttowall.y: # X is closer then y
			if disttowall.x <= disttowall.z: # x is closer then z
				print("X is closest")
				## Wallpos X is the closest
				child.position.x = wallpos.x
				child.position.y = clampY.call(child, boundingBox)
				child.position.z = clampZ.call(child, boundingBox)
				child.set_meta("alignment", (int(wallpos.x > mid.x) + (int(wallpos.x < mid.x) * -1)))
			else: # X is closer then y, but not closer then z, z is closest
				print("Z is closest A")
				## Wallpos Z is the closest
				child.position.x = clampX.call(child, boundingBox)
				child.position.y = clampY.call(child, boundingBox)
				child.position.z = wallpos.z
				child.set_meta("alignment", (int(wallpos.z > mid.z) + (int(wallpos.z < mid.z) * -1)))
		else:
			if disttowall.y < disttowall.z:
				print("Y is closest")
				## Wallpos Y is the closest
				child.position.x = clampX.call(child, boundingBox)
				child.position.y = wallpos.y
				child.position.z = clampZ.call(child, boundingBox)
				child.set_meta("alignment", (int(wallpos.y > mid.y) + (int(wallpos.y < mid.y) * -1)))
			else:
				print("Z is closest B")
				## Wallpos Z is the closest
				child.position.x = clampX.call(child, boundingBox)
				child.position.y = clampY.call(child, boundingBox)
				child.position.z = wallpos.z
				child.set_meta("alignment", (int(wallpos.z > mid.z) + (int(wallpos.z < mid.z) * -1)))
		doorData.append(child)
	## Marker position ended
	
	## Reposition everything so it fits within the boundries
	contentNode.position = -boundingBox.position
	visualizermesh.position = -boundingBox.position
	## Repositioning done
	
	visualize() ## Update the AABB visualizer

func visualize():
	var bb : AABB = boundingBox ## Shortened variable name. saves my fingers
	## Define the 8 vertexes of a rectangluar prism
	var v1 : Vector3 = Vector3(bb.position.x, bb.position.y, bb.position.z)
	var v2 : Vector3 = Vector3(bb.position.x, bb.position.y, bb.size.z)
	var v3 : Vector3 = Vector3(bb.size.x, bb.position.y, bb.position.z)
	var v4 : Vector3 = Vector3(bb.size.x, bb.position.y, bb.size.z)
	var v5 : Vector3 = Vector3(bb.position.x, bb.size.y, bb.position.z)
	var v6 : Vector3 = Vector3(bb.position.x, bb.size.y, bb.size.z)
	var v7 : Vector3 = Vector3(bb.size.x, bb.size.y, bb.position.z)
	var v8 : Vector3 = Vector3(bb.size)
	
	## Define the 6 faces (2 tris per face) of a rectangular prism
	var f1 : PackedVector3Array = [v1, v3, v2, v3, v4, v2] ## -Y Face
	var f2 : PackedVector3Array = [v1, v5, v3, v5, v7, v3] ## -Z Face
	var f3 : PackedVector3Array = [v1, v2, v5, v5, v2, v6] ## -X Face
	var f4 : PackedVector3Array = [v5, v6, v7, v6, v8, v7] ## +Y Face
	var f5 : PackedVector3Array = [v4, v8, v6, v2, v4, v6] ## +Z Face
	var f6 : PackedVector3Array = [v3, v7, v4, v7, v8, v4] ## +X Face
	
	## Create the mesh that fits the AABB 
	var arr_mesh : ArrayMesh = ArrayMesh.new()
	for face in [f1, f2, f3, f4, f5, f6]: ## For every face
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = face
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	## Make it visible in the game world
	visualizermesh = $Visualizer
	visualizermesh.mesh = arr_mesh
	
	visualizermesh.material_override = load(visualizerMaterial)
