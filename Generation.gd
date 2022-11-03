@tool
extends Node3D

var map : GridMap

@export var offsetScale : float = 1.0

@export var roomList : Array[PackedScene] = []

@export var _generate : bool = false :
	get:return false
	set(_v):
		generate()
		_generate = false

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
	var size : Vector3 = Vector3(100, 100, 100)
	var scenes : Array ## All added Scenes
	var cells : Array ## All cells
	var cells_nz : Array ## Non-Zero cells
	var cells_weight : Array ## Weight map for cells
	var cells_index : Array ## Cell index map
	var doorCells : Array ## Array of cells that connect to doors, and their orientation
	
	func _init(_size:Vector3=size) -> void:
		size = _size
		for x in range(size.x):
			var _x : Array = []
			var nz_x : Array = []
			var w_x : Array = []
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
			cells.append(_x)
			cells_nz.append(nz_x)
			cells_weight.append(w_x)
			cells_index.append(w_x)
	
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
	func zero_cell_recursive(cell:Vector3) -> void:
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
	
	## Update the SizeMap space with the shape at position
	func place_shape(pos:Vector3, _size:Vector3) -> void:
		for x in range(_size.x):
			for y in range(_size.y):
				for z in range(_size.z):
					var _pos = pos + Vector3(x, y, z)
					zero_cell_recursive(_pos)
	
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
					if check_fit(pos, roomSize, debugDepth):
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
		var res = boxfit(abs(room.boundingBox.position + room.boundingBox.size) + Vector3.ONE)
		if res[0]: scenes.append([room, res[1]])
		else: push_warning("Could not add room")
	
	func register_doors() -> void:
		for _scene in scenes: ## For each door
			var room : Room = _scene[0]
			var door : Array = room.doorData
			var door_pos : Vector3 = door[0].position + _scene[1] ## get it's cell position (room pos + local pos)
			var test_pos : Vector3 = door_pos + door[1]
			if cells_nz[test_pos.x][test_pos.y][test_pos.z] == -1:
				test_pos = door_pos - door[1]
			doorCells.append([door_pos, door[1], test_pos]) ## Door position, direction, connected cell
	
	func create_map(pos:Vector3, path_open:Array[Vector3], level:int) -> Array[Vector3]:
		## Generate a distance based on the map
		path_open.erase(pos)
		var x_valid : bool = pos.x >= 0 and pos.x <= size.x ## Is within the X bounds
		var y_valid : bool = pos.y >= 0 and pos.y <= size.y ## Is within the X bounds
		var z_valid : bool = pos.z >= 0 and pos.z <= size.z ## Is within the X bounds
		if not (x_valid and y_valid and z_valid): return path_open
		for offset in NEUMANN_OFFSET:
			var test_pos : Vector3 = pos + offset
			## (below) Checkng the cell beneath is not a room, and hasn't been set yet
			if (cells_nz[test_pos.x][test_pos.y][test_pos.z] != -1 and ## If the cell isnt obstructed
			cells_weight[test_pos.x][test_pos.y][test_pos.z] != -1): ## If the cell hasn't been checked yet
				cells_weight[test_pos.x][test_pos.y][test_pos.z] = level ## Set the cell in the map to the depth
				path_open.append(test_pos) ## add the cell to the path
		return path_open
	
	func weightmap_generate() -> void:
		print("Calculating Weightmap")
		var startingpos : Vector3 = Vector3.ZERO
		var path_open : Array[Vector3] = [startingpos]
		var level : int = 1 ## the depth / distance from the starting point
		while len(path_open) > 0 and level < 10000: ## While there's still unchecked rooms
			var _path_open = path_open.duplicate()
			for point in _path_open:
				path_open = create_map(point, path_open, level)
			level += 1
	
	func sort_by_2nd(a:Array, b:Array) -> bool: return a[1] > b[1]
	
	## Weighmap backtrack gets the lowest weighted cell within the sizemap's bounds
	func weightmap_backtrack(pos:Vector3, path:Array[Vector3]) -> Array[Vector3]:
		var _path : Array[Vector3] = [] ## Array to contain the possible neighbours
		var _result : Array[Vector3] = path.duplicate() ## Duplicate as to not alter the original
		
		for offset in NEUMANN_OFFSET: ## For each neighouring cell
			var test_pos : Vector3 = pos + offset
			var test_depth : int = cells_weight[test_pos.x][test_pos.y][test_pos.z]
			## Method of removing lattice, if there's aready a connected hallway, end the path
			if cells_weight[test_pos.x][test_pos.y][test_pos.z] != -1:
				_result.append(test_pos)
				return _result
			## Check if the cell isn't a wall
			if cells_nz[test_pos.x][test_pos.y][test_pos.z] != -1:
				_path.append([test_pos, test_depth]) ## Make it checkable
		
		_path.sort_custom(self.sort_by_2nd) ## Sorts via the 2nd element of array
		_result.append(_path[-1][0]) ## Add lowest cell to path
		return _result ## Return path
	
	## Backtracks the path from a provided destination to the lowest weightmap point
	func weightmap_get_path(dest:Vector3) -> void:
		var path : Array[Vector3] = [dest]
		var dist : int = cells_weight[dest.x][dest.y][dest.z]
		if dist == 0: return ## Already at lowest depth
		for i in range(dist):
			path = weightmap_backtrack(path[-1], path)
		
		for cell in path:
			## Set the cells to 0. default is -1, so anything that's not -1 will be checked later
			cells_index[cell.x][cell.y][cell.z] = 0

	func weightmap_directional_pass() -> void:
		pass

func generate():
	print("Generating")
	
	var smap : SizeMap = SizeMap.new()
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
