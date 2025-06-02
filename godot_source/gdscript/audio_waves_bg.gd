# Applies audio-reactive background shader to ColorRect node

extends ColorRect

@onready var ar_shade: ShaderMaterial = material as ShaderMaterial

# Line
var i = 0
var flicking = false

# Record Spin
var initial_offset = Vector2(0, 0)  
var target_offset = Vector2(0.3, 0)  

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ar_shade.shader = preload("res://audio_waves.gdshader") 
	initial_offset = ar_shade.get_shader_parameter("offset")
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:	
	# Colour of line randomised
	if i < GlobalVars.beat_timestamps.size() and GlobalVars.current_time >= (GlobalVars.beat_timestamps[i]) and flicking == false:
		ar_shade.set_shader_parameter("animate_flick", true)
		flicking = true
		var r = randf()  
		var g = randf()
		var b = randf()
		ar_shade.set_shader_parameter("line2_color", Vector4(r, g, b, 1.0))
		i += 1
		
	if flicking == true:
		_flicking_control()
		
		# Record spinning shader moves in time with the music
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_method(self.update_offset, 0.0, 0.3, 0.15)

func _flicking_control() -> void:
	# Flicking animation of line controlled here, starts 59% way through animation for best effect
	var progress = ar_shade.get_shader_parameter("anim_progress")
	if progress < 0.59:
		progress = 0.59
	progress += 0.01
	if progress >= 0.6 && progress < 0.8:
		ar_shade.set_shader_parameter("line2_thickness", 0.2)
	if progress >= 0.8 && progress < 1.0:
		var thickness_modifier = remap(progress, 0.8, 0.99, 0.2, 0.0)
		ar_shade.set_shader_parameter("line2_thickness", thickness_modifier)
	ar_shade.set_shader_parameter("anim_progress", progress)
	if progress >= 1.0:
		flicking = false
		ar_shade.set_shader_parameter("animate_flick", false)
		ar_shade.set_shader_parameter("anim_progress", 0.59)
		ar_shade.set_shader_parameter("line2_thickness", 0.0)

func update_offset(progress: float):
	# Record spin offset animation effect updated.
	# Calculate the current offset using linear interpolation
	var current_offset = initial_offset
	current_offset.x = initial_offset.x + (target_offset.x - initial_offset.x) * progress
	
	# Update the shader parameter
	ar_shade.set_shader_parameter("offset", current_offset)
