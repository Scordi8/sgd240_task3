@tool
extends EditorScript

## This script is a Tool Editor Script, allowing for engine code to be run without running the executeable
## Use this to test functions that need continuous adjustment with provided inputs.

# Called when the script is executed (using File -> Run in Script Editor).
func _run() -> void:
	var order : Array[int] = [0, 0, 0, 0, 1, 1] ## N E S W U D
	
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
		if order[4] or order[5]:
			cfix = "2e" ## Mark as elbow / vertical corner 
	elif count == 0: ## No horisontal connections
		if order[4] and order[5]: 
			cfix = "2s" ## marks as only up and down
	
	var ori : float = 0 ## Orientation of the object
	match count:
		0:
			pass ## Orientation doesn't matter
		1:
			if order[0]: ori = PI # North
			if order[1]: ori = -PI/2 # East
			if order[2]: ori = 0 # South
			if order[3]: ori = PI/2 # West
		2:
			if order[0] == order[2]: ## if parallel
				if order[0]:
					ori = PI/2
				else:
					ori = 0
			else:
				match [order[0], order[1], order[2], order[3]]:
					[1, 1, 0, 0]:
						ori = PI
					[0, 1, 1, 0]:
						ori = PI/2
					[0, 0, 1, 1]:
						ori = 0
					[1, 0, 0, 1]:
						ori = -PI/2
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
	print(prefix," ", cfix)
