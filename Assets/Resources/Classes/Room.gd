@tool
class_name Room extends Node3D

@export var boundingBox : AABB

@onready var contentNode : Node3D = $Content
@export var roomMeshNode : NodePath
@export var doorNodesRoot : NodePath
var doorData : Array[Array] = []

@export var _validate : bool = false :
	get:return false
	set(_v):
		_validate = false
		validate()

@export var _visualize : bool = false :
	get:return false
	set(_v):
		_visualize = false
		visualize()

var visualizermesh : MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func validate():
	print("Validating")
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
		var door : Array = [child, Vector3.ZERO] ## Node , direction
		child.position = round(child.position)

		## get closest side
		var mid : Vector3 = boundingBox.get_center()
		var disttowall : Vector3 ## How far away from the wall it is
		var wallpos : Vector3 ## Where the wall is
		
		if child.position.x < mid.x:
			wallpos.x = boundingBox.position.x
			disttowall.x = wallpos.x + child.position.x
		else:
			wallpos.x = boundingBox.size.x
			disttowall.x = wallpos.x - child.position.x
		
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
			min(_bb.position.x+1, _bb.end.x-1),
			max(_bb.position.x+1, _bb.end.x-1))
		
		var clampY : Callable = func(_c:Marker3D, _bb:AABB) -> float: return clamp(_c.position.y,
			min(_bb.position.y+1, _bb.size.y-1),
			max(_bb.position.y+1, _bb.size.y-1))
		
		var clampZ : Callable = func(_c:Marker3D, _bb:AABB) -> float: return clamp(_c.position.z,
			min(_bb.position.z+1, _bb.end.z-1),
			max(_bb.position.z+1, _bb.end.z-1))
		
		## Get the closest wall
		if wallpos.x < wallpos.y:
			if wallpos.x < wallpos.z:
				## Wallpos X is the closest
				child.position.x = wallpos.x
				child.position.y = clampY.call(child, boundingBox)
				child.position.z = clampZ.call(child, boundingBox)
				door[1] = Vector3(1, 0, 0)
		else:
			if wallpos.y < wallpos.z:
				## Wallpos Y is the closest
				child.position.x = clampX.call(child, boundingBox)
				child.position.y = wallpos.y
				child.position.z = clampZ.call(child, boundingBox)
				door[1] = Vector3(0, 1, 0)
			else:
				## Wallpos Z is the closest
				child.position.x = clampX.call(child, boundingBox)
				child.position.y = clampY.call(child, boundingBox)
				child.position.z = wallpos.z
				door[1] = Vector3(0, 0, 1)
		doorData.append(door)
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
