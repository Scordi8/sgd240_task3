@tool
extends Node
## Global is a singleton script, it functions outside of the node tree thus remains persistant through scene changes, and pausing

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_viewport().size_changed.connect(self.screensize_changed) ## connection the viewport changing singal to function
	screensize_changed() ## Make sure the function runs anyway

## Update shader uniform on viewport size changed
func screensize_changed():
	RenderingServer.global_shader_parameter_set("ViewportSize", get_viewport().get_visible_rect())
