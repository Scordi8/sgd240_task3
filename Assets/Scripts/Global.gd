@tool
extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_viewport().size_changed.connect(self.screensize_changed)
	screensize_changed()

func screensize_changed():
	RenderingServer.global_shader_parameter_set("ViewportSize", get_viewport().get_visible_rect())

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
