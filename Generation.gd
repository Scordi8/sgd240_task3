@tool
extends Node3D

var smap : SizeMap

@export var offsetScale : float = 1.0

@export var roomList : Array[PackedScene] = []

@export var _generate : bool = false :
	get:return false
	set(_v):
		generate()
		_generate = false

@export var _debugVectorVisualizer : Vector3i = Vector3i.ZERO :
	get: return _debugVectorVisualizer
	set(_v):
		_debugVectorVisualizer = _v
		debugVectorVisualizer()
@export var _queryCellData : bool = false:
	get: return false
	set(_v):
		query_cell_data()
		_queryCellData = false

const NEUMANN_OFFSET : Array[Vector3] = [
							Vector3(1, 0, 0), ## Positive X		0
							Vector3(-1, 0, 0), ## Negative X	1
							Vector3(0, 1, 0), ## Positive Y		2
							Vector3(0, -1, 0), ## Negative Y	3
							Vector3(0, 0, 1), ## Positive Z		4
							Vector3(0, 0, -1) ## Negative Z		5
							]

var childNodes : Array[Node3D] = []

class SizeMap:
	var size : Vector3 = Vector3(50, 50, 50)
	var scenes : Array ## All added Scenes
	var cells : Array ## All cells
	var cells_nz : Array ## Non-Zero cells
	var cells_weight : Array ## Weight map for cells
	var cells_index : Array ## Cell index map
	var doorCells : Array ## Array of cells that connect to doors, and their orientation
	var jointDict : Dictionary = {} ## Dictionary to contain the hallway joints
	var pathCells : Array[Vector3]
	var tree : SceneTree
	
	func _init(_tree:SceneTree, _size:Vector3=size) -> void:
		tree = _tree
		size = _size
		for x in range(size.x):
			var _x : Array = []
			var nz_x : Array = []
			var w_x : Array = []
			var i_x : Array = []
			for y in range(size.y):
				var _y : Array = []
				var nz_y : Array = []
				var w_y : Array = []
				for z in range(size.y):
					_y.append(Vector3(size.x-x, size.y-y, size.z-z))
					nz_y.append(0)
					w_y.append(-1)
				_x.append(_y)
				nz_x.append(nz_y)
				w_x.append(w_y)
				i_x.append(w_y.duplicate())
			cells.append(_x)
			cells_nz.append(nz_x)
			cells_weight.append(w_x)
			cells_index.append(i_x)
		load_dict()

	func load_dict() -> void:
		jointDict = {}
		jointDict["y"] = {
			"1s":load("res://Assets/Resources/Generated/Prebuilt/y1s.obj"),
			"2":load("res://Assets/Resources/Generated/Prebuilt/y2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y2c.obj"),
			"2s":load("res://Assets/Resources/Generated/Prebuilt/y2s.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y4.obj")
		}
		jointDict["y1-"] = {
			"2":load("res://Assets/Resources/Generated/Prebuilt/y1-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y1-2c.obj"),
			"2e":load("res://Assets/Resources/Generated/Prebuilt/y1-2e.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y1-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y1-4.obj")
		}
		jointDict["y-1-"] = {
			"2":load("res://Assets/Resources/Generated/Prebuilt/y-1-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y-1-2c.obj"),
			"2e":load("res://Assets/Resources/Generated/Prebuilt/y-1-2e.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y-1-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y-1-4.obj")
		}
		jointDict["y0-"] = {
			"2":load("res://Assets/Resources/Generated/Prebuilt/y0-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y0-2c.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y0-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y0-4.obj")
		}
	
	## Returns the distance vectors at requested cell
	func get_cell_space(cell:Vector3) -> Vector3:
		return cells[cell.x][cell.y][cell.z]
	
	## Returns the neighbouring cells
	func get_cell_neumann(cell:Vector3, _require_free:bool=false) -> PackedVector3Array:
		var arr : PackedVector3Array = []
		for offset in NEUMANN_OFFSET: ## For every neighouring cell
			var celloffset : Vector3 = cell + offset
			if _require_free: ## If we're looking for pathfindable cells only
				if cells_nz[celloffset.x][celloffset.y][celloffset.z] < 1: ## check the cell is free
					arr.append(celloffset)
			else: ## Doesn't care if the cell is obstructed
				arr.append(celloffset)
		return arr
	
	## Set a cell to zero and update all the dependant cells
	func zero_cell_recursive(cell:Vector3, isEdge:bool=false) -> void:
		for x in range(cell.x, size.x):
			cells[x][cell.y][cell.z].x = max(min(cells[x][cell.y][cell.z].x,
			(cells[x][cell.y][cell.z].x - cell.x)), 0)
		for y in range(cell.y, size.y):
			cells[cell.x][y][cell.z].y = max(min(cells[cell.x][y][cell.z].y,
			(cells[cell.x][y][cell.z].y - cell.y)), 0)
		for z in range(cell.z, size.y):
			cells[cell.x][cell.y][z].z = max(min(cells[cell.x][cell.y][z].z,
			(cells[cell.x][cell.y][z].z - cell.z)), 0)
		cells[cell.x][cell.y][cell.z] = Vector3.ZERO
		
		for x in range(cell.x):
			cells[x][cell.y][cell.z].x -= max(cells[x][cell.y][cell.z].x - x, 0)
		for y in range(cell.y):
			cells[cell.x][y][cell.z].y -= max(cells[cell.x][y][cell.z].y - y, 0)
		for z in range(cell.z):
			cells[cell.x][cell.y][z].z -= max(cells[cell.x][cell.y][z].z - z, 0)
		
		cells_nz[cell.x][cell.y][cell.z] = -1 ## Flag cell as non-zero
		if not isEdge: cells_index[cell.x][cell.y][cell.z] = 1 ## If it's not 1, it's free
	
	## Update the SizeMap space with the shape at position
	func place_shape(pos:Vector3, _size:Vector3) -> void:
		for x in range(_size.x+1):
			for y in range(_size.y+1):
				for z in range(_size.z+1):
					var _pos = pos + Vector3(x, y, z)
					zero_cell_recursive(_pos, (x == _size.x or y == _size.y or z == _size.z))
	
	func check_fit(pos:Vector3, _size:Vector3, debugDepth:int=0) -> bool:
		var space : Vector3 = get_cell_space(pos)
		var res = (space.x >= _size.x and space.y >= _size.y and space.z >= _size.z)
		if res: print("Remaining space: ", space, ", returns: ", res, " for position: ", pos, ", taking ", debugDepth, " tries")
		return res
	
	func fit_in_bounds(_lowerBounds:Vector3, upperBounds:Vector3, roomSize:Vector3, debugDepth:int=0) -> Array:
		for x in range(0, upperBounds.x):
			for y in range(0, upperBounds.y):
				for z in range(0, upperBounds.z):
					var pos : Vector3 = Vector3(x, y, z)
					if check_fit(pos, roomSize+Vector3.ONE, debugDepth):
						place_shape(pos, roomSize)
						return [true, pos]
		return [false, null]
	
	func boxfit(roomSize:Vector3, shapeGrowthWeights:Vector3=Vector3.ONE) -> Array:
		var lowerBounds : Vector3 = Vector3.ZERO
		var upperBounds : Vector3 = Vector3.ONE
		var res : bool = false
		var pos : Vector3
		var depth :int = 0
		## While a position isn't found, and the bounds aren't all used
		while (not res) and (lowerBounds.x < size.x or lowerBounds.y < size.y or lowerBounds.z < size.z):
			var _res = fit_in_bounds(lowerBounds, upperBounds, roomSize, depth)
			if _res[0]:
				res = true
				pos = _res[1]
				break
			
			## Increase the boundry size to check a greater area
			lowerBounds = upperBounds
			upperBounds += shapeGrowthWeights
			depth += 1
		if res == false: return [false, null] ## No space left
		else: return [true, pos] ## It found a spot, return the info
	
	func add_room_to_map(room:Room) -> void:
		print("Room size: ", abs(room.boundingBox.position + room.boundingBox.size))
		var res = boxfit(abs(room.boundingBox.position + room.boundingBox.size))
		if res[0]: scenes.append([room, res[1]])
		else: push_warning("Could not add room")
	
	## Register doors must be called *after* the scene nodes are part of the world
	func register_doors() -> void:
		print("Registering Doors")
		for _scene in scenes: ## For each scene
			var room : Room = _scene[0]
			var doorArr : Array[Array] = room.get_doorData()
			for door in doorArr:
				var door_pos : Vector3 = door[0].global_position ##room.position + door[0].position ## get it's cell position (room pos + local pos)
				##print(room.global_position, " ", door[0].global_position, " ", door_pos)
				var test_pos : Vector3 = door_pos + (Vector3(door[1], door[1], door[1])/2)
				var path_pos : Vector3 = door_pos + Vector3(door[1], door[1], door[1])

				doorCells.append([door_pos, door[1], test_pos, path_pos]) ## Door position, direction, connected cell

	func create_map(pos:Vector3, path_open:Array[Vector3], level:int) -> Array[Vector3]:
		## Generate a distance based on the map
		path_open.erase(pos)
		var x_valid : bool = pos.x >= 1 and pos.x < size.x-1 ## Is within the X bounds
		var y_valid : bool = pos.y >= 1 and pos.y < size.y-1 ## Is within the X bounds
		var z_valid : bool = pos.z >= 1 and pos.z < size.z-1 ## Is within the X bounds
		if not (x_valid and y_valid and z_valid): return path_open
		for offset in NEUMANN_OFFSET:
			var test_pos : Vector3 = pos + offset
			if (cells_index[test_pos.x][test_pos.y][test_pos.z] != 1 and ## If the cell isnt obstructed
			cells_weight[test_pos.x][test_pos.y][test_pos.z] == -1): ## If the cell hasn't been checked yet
				#print("cell is valid")
				cells_weight[test_pos.x][test_pos.y][test_pos.z] = level ## Set the cell in the map to the depth
				path_open.append(test_pos) ## add the cell to the path
		return path_open
	
	func weightmap_generate(startingpos:Vector3=Vector3.ZERO) -> void:
		print("Calculating Weightmap")
		var path_open : Array[Vector3] = [startingpos]
		var level : int = 0 ## the depth / distance from the starting point
		while len(path_open) > 0 and level < 500: ## While there's still unchecked rooms
			var _path_open = path_open.duplicate()
			for point in _path_open:
				path_open = create_map(point, path_open, level)
			level += 1
			if level % 50 == 1:
				await tree.process_frame
				print(level)
		print("Weightmap highest depth: ", level)
		return
	
	func sort_by_2nd(a:Array, b:Array) -> bool: return a[1] > b[1]
	
	## Weighmap backtrack gets the lowest weighted cell within the sizemap's bounds
	func weightmap_backtrack(pos:Vector3, path:Array[Vector3]) -> Array[Vector3]:
		var _path : Array[Array] = [] ## Array to contain the possible neighbours
		var _result : Array[Vector3] = path.duplicate() ## Duplicate as to not alter the original
		
		for offset in NEUMANN_OFFSET: ## For each neighouring cell
			var test_pos : Vector3 = pos + offset
			var test_depth : int = cells_weight[test_pos.x][test_pos.y][test_pos.z]
			## Method of removing lattice, if there's aready a connected hallway, end the path
			if test_pos in pathCells:
				_result.append(test_pos)
				return _result
			## Check if the cell isn't a wall
			if cells_index[test_pos.x][test_pos.y][test_pos.z] == -1:
				_path.append([test_pos, test_depth]) ## Make it checkable
		
		_path.sort_custom(self.sort_by_2nd) ## Sorts via the 2nd element of array
		_result.append(_path[-1][0]) ## Add lowest cell to path
		return _result ## Return path
	
	## Backtracks the path from a provided destination to the lowest weightmap point
	func weightmap_get_path(dest:Vector3) -> void:
		var path : Array[Vector3] = [dest]
		var dist : int = cells_weight[dest.x][dest.y][dest.z]
		if dist <= 0:
			print("Distance <= 0, returning")
			return ## Already at lowest depth
		else:
			print("Backtracking from %s, distance of %s" % [dest, dist])
		for i in range(dist):
			path = weightmap_backtrack(path[-1], path)
		for cell in path:
			## Set the cells to 0. default is -1, so anything that's not -1 will be checked later
			pathCells.append(cell)
	
	func generate_paths(start:Vector3=Vector3(10, 10, 10)):
		register_doors()
		await weightmap_generate(start)

		## Pathfind from one cell to another
		await pathCells.append(start + Vector3(0.5, 0.5, 0.5))
		for cellA in doorCells:
			weightmap_get_path(cellA[2])
	
	func get_cell_load_data(cell:Vector3) -> Array: ## Returns: [ArrayMesh, orientation]
		var order : Array[int] = [0, 0, 0, 0, 0, 0] ## N E S W U D	
		
		## Check for connected cells
		order[0] = int((cell + Vector3(0, 0, 1)) in pathCells)
		order[1] = int((cell + Vector3(1, 0, 0)) in pathCells)
		order[2] = int((cell + Vector3(0, 0, -1)) in pathCells)
		order[3] = int((cell + Vector3(-1, 0, 0)) in pathCells)
		order[4] = int((cell + Vector3(0, 1, 0)) in pathCells)
		order[5] = int((cell + Vector3(0, -1, 0)) in pathCells)
		
		## Check for doors

		for door in doorCells:
			if door[0] == cell - Vector3(0.5, 0.5, 0.5): ## Compensate for 0.5 offset
				print("Door cell found")
				if door[1] < 0: ## If it's -1, so backwards
					if cells_index[cell.x+1][cell.y][cell.z] == 1:
						order[0] = 1
					if cells_index[cell.x][cell.y+1][cell.z] == 1:
						order[4] = 1
					if cells_index[cell.x][cell.y][cell.z+1] == 1:
						order[1] = 1
				else: ## It's 1, so fowards
					if cells_index[cell.x-1][cell.y][cell.z] == 1:
						order[3] = 1
					if cells_index[cell.x][cell.y-1][cell.z] == 1:
						order[5] = 1
					if cells_index[cell.x][cell.y][cell.z-1] == 1:
						order[2] = 1
		print(order)
		
		var prefix : String = ""
		## Get the vertical prefix
		if order[4]: ## Up
			if order[5]: ## Up and Down
				prefix = "y"
			else: ## Only Up
				prefix = "y1-"
		elif order[5]: ## down, no up
			prefix = "y-1-"
		else: ## No up or down
			prefix = "y0-"
		
		# Get the horisontal connects 
		var count : int = order[0] + order[1] + order[2] + order[3]
		var cfix : String = str(count)
		
		if count == 2: ## If there's two horisontal connections
			if order[0] != order[2]: ## If they're not parallel
				cfix = "2c" ## Mark as corner
		elif count == 1: ## Only one horisontal connection
			if order[4] and order[5]:
				cfix = "1s"
			elif order[4] or order[5]:
				cfix = "2e" ## Mark as elbow / vertical corner 
			else:
				cfix = "2"
		elif count == 0: ## No horisontal connections
			if order[4] and order[5]: 
				cfix = "2s" ## marks as only up and down
			else:
				cfix = "2"
		print(prefix, cfix, " ", count)
		var ori : float = 0 ## Orientation of the object
		match count:
			0:
				pass ## Orientation doesn't matter
			1:
				if order[0]: ori = 0 # North
				if order[1]: ori = 0#-PI/2 # East
				if order[2]: ori = PI # South
				if order[3]: ori = -PI/2 # West
			2:
				if order[0] == order[2]: ## if parallel
					if order[0]:
						ori = PI/2
					else:
						ori = 0
				else:
					match [order[0], order[1], order[2], order[3]]:
						[1, 1, 0, 0]:
							ori = 0
						[0, 1, 1, 0]:
							ori = PI ## Checked
						[0, 0, 1, 1]:
							ori = -PI/2
						[1, 0, 0, 1]:
							ori = 0#PI/2
						_:
							pass
			3:
				if not order[0]:
					ori = 0
				if not order[1]:
					ori = -PI/2
				if not order[2]:
					ori = PI
				if not order[3]:
					ori = PI/2
			4:
				pass ## Orientation doesn't matter
		
		return [jointDict[prefix][cfix], ori, count, order]
	
	func spawn_cell(cell:Vector3, target:Node3D, offset:Vector3=Vector3.ZERO, material:Material=null) -> void:
		#print(cell)
		var cdata : Array = get_cell_load_data(cell)
		var mi : MeshInstance3D = MeshInstance3D.new()
		mi.position = cell + offset
		mi.mesh = cdata[0]
		mi.rotate_y(cdata[1])
		if material: mi.material_override = material
		target.call_deferred("add_child", mi)
	
	func load_all_paths(target:Node3D, material:Material=null) -> void:
		print("Loading cells")
		for cell in pathCells:
			spawn_cell(cell, target, Vector3.ZERO, material)
	
	func showUsedCells(target:Node3D) -> void:
		print("Showing used cells")
		for x in size.x:
			for y in size.y:
				for z in size.z:
					if cells_index[x][y][z] == 1:
						spawn_cell(Vector3(x, y, z), target, Vector3(0.5, 0.5, 0.5))


func generate():
	print("Generating")
	
	smap = SizeMap.new(get_tree())
	for child in get_children():
		child.queue_free()
	
	for room in roomList:
		if room.get_class() == "PackedScene":
			var inst = room.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
			smap.add_room_to_map(inst)
	if smap.scenes.size():
		for scene in smap.scenes:
			scene[0].position = scene[1]*offsetScale
			self.call_deferred("add_child", scene[0])
		await get_tree().process_frame
		await smap.generate_paths()
		smap.load_all_paths(self, load("res://DebugMaterial.tres"))
#		smap.showUsedCells(self)
	print("Generation complete")

func debugVectorVisualizer():
	print("Debug cell visualizing: ", _debugVectorVisualizer)
	if smap == null: 
		push_warning("smap is null, please generate SizeMap first")
		return
	smap.spawn_cell(_debugVectorVisualizer, self, Vector3(0.5, 0.5, 0.5))

func query_cell_data():
	if smap == null: 
		push_warning("smap is null, please generate SizeMap first")
		return
	
	## Weight/depth
	## Is free
	print({
	"Cell Weight":smap.cells_weight[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z],
	"Cell Index":smap.cells_index[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z],
	"Cell NZ":smap.cells_nz[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z]
	})
