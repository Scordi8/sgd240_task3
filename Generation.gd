@tool
extends Node3D

var smap : SizeMap

@export var offsetScale : float = 1.0

@export var roomList : Array[PackedScene] = []

## always false bool used for in-editor generation
@export var _generate : bool = false :
	get:return false
	set(_v):
		if Engine.is_editor_hint():
			generate()
		_generate = false
## in-editor value for checking individual cells
@export var _debugVectorVisualizer : Vector3i = Vector3i.ZERO :
	get: return _debugVectorVisualizer
	set(_v):
		_debugVectorVisualizer = _v
		if Engine.is_editor_hint():
			debugVectorVisualizer()
## always false bool used for in-editor generation
@export var _queryCellData : bool = false:
	get: return false
	set(_v):
		if Engine.is_editor_hint():
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

## SizeMap class contains several 3d textures, with room placing capabilities, and prodcural hallways. 
class SizeMap:
	var size : Vector3 = Vector3(50, 50, 50) ## The dimensions of the SizeMap
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
		## Generate several 3d arrys to contain nessecary values
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
				i_x.append(w_y.duplicate()) ## Duplicate to prevent reusing arrays, as reuse causes issues
			cells.append(_x)
			cells_nz.append(nz_x)
			cells_weight.append(w_x)
			cells_index.append(i_x)
		load_dict() ## Load the dictionary used for hallways

	func load_dict() -> void:
		jointDict = {}
		jointDict["y"] = { ## Hallway segments with space above and underneath
			"1s":load("res://Assets/Resources/Generated/Prebuilt/y1s.obj"),
			"2":load("res://Assets/Resources/Generated/Prebuilt/y2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y2c.obj"),
			"2s":load("res://Assets/Resources/Generated/Prebuilt/y2s.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y4.obj")
		}
		jointDict["y1-"] = { ## Hallway segments with space above
			"2":load("res://Assets/Resources/Generated/Prebuilt/y1-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y1-2c.obj"),
			"2e":load("res://Assets/Resources/Generated/Prebuilt/y1-2e.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y1-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y1-4.obj")
		}
		jointDict["y-1-"] = { ## Hallway segments with space underneath
			"2":load("res://Assets/Resources/Generated/Prebuilt/y-1-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y-1-2c.obj"),
			"2e":load("res://Assets/Resources/Generated/Prebuilt/y-1-2e.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y-1-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y-1-4.obj")
		}
		jointDict["y0-"] = { ## Hallway segments without any space above or beneath
			"2":load("res://Assets/Resources/Generated/Prebuilt/y0-2.obj"),
			"2c":load("res://Assets/Resources/Generated/Prebuilt/y0-2c.obj"),
			"3":load("res://Assets/Resources/Generated/Prebuilt/y0-3.obj"),
			"4":load("res://Assets/Resources/Generated/Prebuilt/y0-4.obj")
		}
	
	## Returns the distance vectors at requested cell
	func get_cell_space(cell:Vector3) -> Vector3:
		return cells[cell.x][cell.y][cell.z]
	
	## Set a cell to zero and update all the dependant cells. 
	## Used for marking how much space is between the set cell, and obstructions/walls
	func zero_cell_recursive(cell:Vector3, isEdge:bool=false) -> void:
		
		## For all the cells after the set cell
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
		
		## For all the cells before the set cell
		for x in range(cell.x):
			cells[x][cell.y][cell.z].x -= max(cells[x][cell.y][cell.z].x - x, 0)
		for y in range(cell.y):
			cells[cell.x][y][cell.z].y -= max(cells[cell.x][y][cell.z].y - y, 0)
		for z in range(cell.z):
			cells[cell.x][cell.y][z].z -= max(cells[cell.x][cell.y][z].z - z, 0)
		
		cells_nz[cell.x][cell.y][cell.z] = -1 ## Flag cell as non-zero
		if not isEdge: cells_index[cell.x][cell.y][cell.z] = 1 ## If it's not 1, it's free. used in pathfinding
	
	## Update the SizeMap space with the shape at position
	## Zero all the cells that get used
	func place_shape(pos:Vector3, _size:Vector3) -> void:
		for x in range(_size.x+1):
			for y in range(_size.y+1):
				for z in range(_size.z+1):
					var _pos = pos + Vector3(x, y, z)
					zero_cell_recursive(_pos, (x == _size.x or y == _size.y or z == _size.z))
	
	## Check is the provided size will fit at the provided position
	func check_fit(pos:Vector3, _size:Vector3, debugDepth:int=0) -> bool:
		var space : Vector3 = get_cell_space(pos)
		var res = (space.x >= _size.x and space.y >= _size.y and space.z >= _size.z)
		if res: print("Remaining space: ", space, ", returns: ", res, " for position: ", pos, ", taking ", debugDepth, " tries")
		return res
	
	## Within a given space, try fit a provided shape within bounds
	func fit_in_bounds(_lowerBounds:Vector3, upperBounds:Vector3, roomSize:Vector3, debugDepth:int=0) -> Array:
		for x in range(0, upperBounds.x):
			for y in range(0, upperBounds.y):
				for z in range(0, upperBounds.z):
					var pos : Vector3 = Vector3(x, y, z)
					if check_fit(pos, roomSize+Vector3.ONE, debugDepth):
						place_shape(pos, roomSize)
						return [true, pos]
		return [false, null]
	
	## Fit a provided box within the shape. Vector3 roomSize is size in meters, shapeGrowthWeights is what direction the shape grows in
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
	
	## with a provided room, try find a spot in the SizeMap to place it. pushes warning if unable to add
	func add_room_to_map(room:Room) -> void:
		print("Room size: ", abs(room.boundingBox.position + room.boundingBox.size))
		var res = boxfit(abs(room.boundingBox.position + room.boundingBox.size))
		if res[0]: scenes.append([room, res[1]]) ## add it to scene array to check later
		else: push_warning("Could not add room")
	
	## Register doors must be called *after* the scene nodes are part of the world.
	## Gets the data of all the doors to be used in hallway generation
	func register_doors() -> void:
		print("Registering Doors")
		for _scene in scenes: ## For each scene
			var room : Room = _scene[0] ## Get the room
			var doorArr : Array[Array] = room.get_doorData()
			for door in doorArr: ## For all the doors in the room
				var door_pos : Vector3 = door[0].global_position
				var test_pos : Vector3 = door_pos + (Vector3(door[1], door[1], door[1])/2)
				var path_pos : Vector3 = door_pos + Vector3(door[1], door[1], door[1])
				doorCells.append([door_pos, door[1], test_pos, path_pos]) ## Door position, direction, connected cell
	
	## Part of weightmap Algorithm, mark position's depth, and return valid neighouring positions
	func create_map(pos:Vector3, path_open:Array[Vector3], level:int) -> Array[Vector3]:
		## Generate a distance based on the map
		path_open.erase(pos) ## Remove the cell ad checked
		var x_valid : bool = pos.x >= 1 and pos.x < size.x-1 ## Is within the X bounds, prevent checking outside of SizeMap
		var y_valid : bool = pos.y >= 1 and pos.y < size.y-1 ## Is within the Y bounds ^
		var z_valid : bool = pos.z >= 1 and pos.z < size.z-1 ## Is within the Z bounds ^
		if not (x_valid and y_valid and z_valid): return path_open ## End the function if it's not within the bounds
		for offset in NEUMANN_OFFSET:
			var test_pos : Vector3 = pos + offset
			if (cells_index[test_pos.x][test_pos.y][test_pos.z] != 1 and ## If the cell isnt obstructed
			cells_weight[test_pos.x][test_pos.y][test_pos.z] == -1): ## If the cell hasn't been checked yet
				cells_weight[test_pos.x][test_pos.y][test_pos.z] = level ## Set the cell in the map to the depth
				path_open.append(test_pos) ## add the cell to the path
		return path_open
	
	## Part of weightmap algorithm, Recursively calculates the distance from a provided position
	func weightmap_generate(startingpos:Vector3=Vector3.ZERO) -> void:
		print("Calculating Weightmap")
		var path_open : Array[Vector3] = [startingpos] ## Where the algorithm starts from
		var level : int = 0 ## the depth / distance from the starting point
		while len(path_open) > 0 and level < 500: ## While there's still unchecked rooms
			var _path_open = path_open.duplicate() ## Make a unique copy to prevent for loop issues 
			for point in _path_open:
				path_open = create_map(point, path_open, level)
			level += 1
			if level % 50 == 1: ## Make sure the Engine has time to update every 50 loops
				await tree.process_frame
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
			## track the cells that get used to avoid looping over every cell later
			pathCells.append(cell)
	
	## Root function for weightmap generation, pathfinding, and hallway generation
	func generate_paths(start:Vector3=Vector3(10, 10, 10)):
		register_doors()
		await weightmap_generate(start)

		## Pathfind from one cell to another
		await pathCells.append(start + Vector3(0.5, 0.5, 0.5)) ## Vector3 0.5 to compensate for offsets
		for cellA in doorCells: ## For every door, get a path from it to the start
			weightmap_get_path(cellA[2])
	
	## Calculate the type of hallway, the orientation, and the corrosponding ArrayMesh
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
				## Which direction the door would be facing in.
				if door[1] < 0:
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
		
		var prefix : String = "" ## Prefix used in getting the Mesh
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
				cfix = "2" ## Fallback
		elif count == 0: ## No horisontal connections
			if order[4] and order[5]: 
				cfix = "2s" ## marks as only up and down
			else:
				cfix = "2" ## Fallback
		print(prefix, cfix, " ", count)
		var ori : float = 0 ## Orientation of the object
		## Calculate the vertical rotation of the object
		### WARNING -- NOT ALL CASES ARE CHECKED, THERE MAY BE ISSUES --
		match count: ## Match the amount of horisontal connections the cll has
			0:
				pass ## No connections, Orientation doesn't matter
			1:
				if order[0]: ori = 0
				if order[1]: ori = -PI/2
				if order[2]: ori = PI
				if order[3]: ori = -PI/2
			2:
				if order[0] == order[2]: ## if parallel
					if order[0]:
						ori = PI/2
					else:
						ori = 0
				else: ## It's not parallel
					match [order[0], order[1], order[2], order[3]]:
						[1, 1, 0, 0]:
							ori = PI/2
						[0, 1, 1, 0]:
							ori = PI
						[0, 0, 1, 1]:
							ori = -PI/2
						[1, 0, 0, 1]:
							ori = 0
						_:
							pass ## Fallback, technically shouldn't be needed, better safe then with errors
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
				pass ## All connections, orientation doesn't matter
		return [jointDict[prefix][cfix], ori, count, order]
	
	## With a provided cell position, parent node, optional offset and material, add the Mesh into the world
	func spawn_cell(cell:Vector3, target:Node3D, offset:Vector3=Vector3.ZERO, material:Material=null) -> void:
		var cdata : Array = get_cell_load_data(cell)
		var mi : MeshInstance3D = MeshInstance3D.new()
		mi.position = cell + offset
		mi.mesh = cdata[0]
		mi.rotate_y(cdata[1])
		if material: mi.material_override = material
		target.call_deferred("add_child", mi)
	
	## Load all the path cells into the world
	func load_all_paths(target:Node3D, material:Material=null) -> void:
		print("Loading cells")
		for cell in pathCells:
			spawn_cell(cell, target, Vector3.ZERO, material)
	
	## Debug function used to check the generation of weightmap rooms
	func showUsedCells(target:Node3D) -> void:
		print("Showing used cells")
		for x in size.x:
			for y in size.y:
				for z in size.z:
					if cells_index[x][y][z] == 1:
						spawn_cell(Vector3(x, y, z), target, Vector3(0.5, 0.5, 0.5))

## Main Generation function
func generate():
	print("Generating")
	
	smap = SizeMap.new(get_tree()) ## Create a new SizeMap
	for child in get_children(): child.queue_free() ## Remove all the current children
	
	## For all the rooms in the edtior-visible scene list
	for room in roomList:
		if room.get_class() == "PackedScene": ## Check to make sure it's the right type
			var inst = room.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) ## Create an instance
			smap.add_room_to_map(inst) ## Try add it to the world
	if smap.scenes.size(): ## If the scenes were added successfully
		for scene in smap.scenes:
			scene[0].position = scene[1]*offsetScale ## Apply any scale offset
			self.call_deferred("add_child", scene[0]) ## Add it as a child
		await get_tree().process_frame ## Wait a frame to make sure everything can catch up
		await smap.generate_paths() ## Wait for the weightmap and paths to be generated
		smap.load_all_paths(self, load("res://DebugMaterial.tres")) ## Load all the paths, using the debug material
	print("Generation complete")

## Debug cell visualizer, to be used sparingly
func debugVectorVisualizer():
	print("Debug cell visualizing: ", _debugVectorVisualizer)
	if smap == null: 
		push_warning("smap is null, please generate SizeMap first")
		return
	smap.spawn_cell(_debugVectorVisualizer, self, Vector3(0.5, 0.5, 0.5))

## Debug function to get data from a specific cell
func query_cell_data():
	if smap == null: 
		push_warning("smap is null, please generate SizeMap first")
		return

	print({
	"Cell Weight":smap.cells_weight[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z],
	"Cell Index":smap.cells_index[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z],
	"Cell NZ":smap.cells_nz[_debugVectorVisualizer.x][_debugVectorVisualizer.y][_debugVectorVisualizer.z]
	})

func _ready() -> void:
	if not Engine.is_editor_hint():
		generate()
