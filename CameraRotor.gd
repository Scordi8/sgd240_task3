extends Node3D

const SPEED : float = 3.0
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var rotor : Vector2 = Input.get_vector("ui_right", "ui_left", "ui_down", "ui_up")
	
	
	self.rotate_y(rotor.x * SPEED * delta)
	$RotorB.rotate_x(rotor.y * SPEED * delta)
