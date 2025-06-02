'''
This script handles the Main Menu UI and user interaction for uploading and analysing a song, 
which is processed by an external Python executable. 
'''

extends Node2D

# Python script preparation
@onready var python_script_path: String
@onready var interpreter_path: String
var output = []
var script_executed = false
var analysis_file_path = ""
var song_path = ""

# UI variables
var first_x_pressed = false
var file_dialog = FileDialog.new()
var dir_helper

# Instruction panel animation and menu items
@onready var inst_anim = $AnimationPlayer
@onready var delay_timer = Timer.new()
@onready var begin1 = $menuContainer/begin
@onready var begin2 = $menuContainer/begin2
@onready var begin3 = $menuContainer/xSymbol
@onready var analyse_label = $menuContainer/analyseLabel
@onready var quick_label = $menuContainer/quickLabel
@onready var x2 = $menuContainer/xSymbol2
@onready var square = $menuContainer/sqrSymbol

func _ready():
	print("=== GODOT DEBUG START ===")
	
	# Prepare for Python
	# Get actual filesystem paths
	var base_dir = OS.get_executable_path().get_base_dir()
	
	if OS.has_feature("editor"):
		# In editor, convert res:// to actual paths
		python_script_path = ProjectSettings.globalize_path("res://PythonFiles/scripts/analyseSong2")
		interpreter_path = ProjectSettings.globalize_path("res://PythonFiles/venv2/bin/python3.11")
		dir_helper = ProjectSettings.globalize_path("res://PythonFiles/scripts/uploaded_audio")
	else:
		# In exported game, use paths relative to executable
		python_script_path = base_dir.path_join("PythonFiles/scripts/analyseSong2")
		interpreter_path = base_dir.path_join("PythonFiles/bin/python3.11")
		dir_helper = base_dir.path_join("PythonFiles/scripts/uploaded_audio")
	
	# Connect animation finished signal
	inst_anim.animation_finished.connect(_on_animation_finished)
	begin1.visible = true
	begin2.visible = true
	begin3.visible = true
	
	# Hide the second set of menu items initially
	analyse_label.visible = false
	quick_label.visible = false
	x2.visible = false
	square.visible = false
	
	# Set up delay timer
	delay_timer.one_shot = true
	delay_timer.wait_time = 1.0
	delay_timer.timeout.connect(_on_delay_timer_timeout)
	add_child(delay_timer)
	
	add_child(file_dialog)
	
	# Main menu 'flare' animation accessed
	var anim : Animation= $flare_main/AnimationPlayer.get_animation("new_animation")
	anim.loop_mode =(Animation.LOOP_LINEAR)
	

func _input(event):
	# First state: Initial X press shows option menu
	if (event.is_action_pressed("xJoy")) and not first_x_pressed:
		begin1.visible = false
		begin2.visible = false
		begin3.visible = false
		analyse_label.visible = true
		quick_label.visible = true
		x2.visible = true
		square.visible = true
		first_x_pressed = true
	
	# Second state: After showing options, handle X and S keys
	elif first_x_pressed and not script_executed:
		if (event.is_action_pressed("xJoy")):
			# Hide option menu items
			analyse_label.visible = false
			quick_label.visible = false
			x2.visible = false
			square.visible = false
			# Play animation and continue with original flow
			inst_anim.play("instructionPanel")
			script_executed = true
		elif (event.is_action_pressed("sqrJoy")):
				handle_quick_analysis()

# Function to handle quick analysis (Down Arrow Key/Square key press)
func handle_quick_analysis():
	
	# Configure file dialog
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	
	# Get the base directory, accounting for macOS app bundle structure
	var executable_dir = OS.get_executable_path().get_base_dir()
	
	# Check if we're inside a macOS app bundle and adjust the path
	if executable_dir.ends_with("/Contents/MacOS"):
		# Go up three levels from MacOS directory to get to the app's parent directory
		executable_dir = executable_dir.get_base_dir().get_base_dir().get_base_dir()
	
	# Set the default directory to 'uploaded_audio' folder in the base directory
	var uploaded_audio_dir = executable_dir.path_join("uploaded_audio")
	
	# Check if the directory exists, create it if it doesn't
	var dir = DirAccess.open(executable_dir)
	if !dir.dir_exists("uploaded_audio"):
		dir.make_dir("uploaded_audio")
		print("Created directory: ", uploaded_audio_dir)
	else:
		print("Using existing directory: ", uploaded_audio_dir)
	
	file_dialog.current_dir = uploaded_audio_dir
	file_dialog.add_filter("*.wav", "WAV Audio Files")
	file_dialog.add_filter("*.mp3", "MP3 Audio Files")
	file_dialog.title = "Select a Song"
	
	# Set size and center on screen
	var window_size = get_viewport().get_visible_rect().size
	file_dialog.size = Vector2(window_size.x * 0.8, window_size.y * 0.8)
	file_dialog.position = Vector2(window_size.x * 0.1, window_size.y * 0.1)
	
	# Connect signal
	if !file_dialog.file_selected.is_connected(_on_file_selected):
		file_dialog.file_selected.connect(_on_file_selected)
	
	# Show the dialog
	file_dialog.popup()
	
	print("File dialog opened with directory: ", file_dialog.current_dir)

func _on_file_selected(path):
	# Set the selected song path
	GlobalVars.song_path = path
	print("Selected song: " + path)
	
	# Extract just the song filename from the path
	var song_filename = path.get_file()
	var song_name = song_filename.get_basename()  # Removes the extension
	GlobalVars.song_extension = song_filename.get_extension()
	GlobalVars.song_name = song_name
	
	# Get the directory of the song file
	var song_dir = path.get_base_dir()
	
	# Navigate one folder back from the song directory
	var parent_dir = song_dir.get_base_dir()
	
	# Construct the analysis path: parent_dir/analysis_results/song_name_analysis.txt
	var analysis_dir = parent_dir.path_join("analysis_results")
	var analysis_file = analysis_dir.path_join(song_name + "_analysis.txt")
	
	# Set the analysis file path
	GlobalVars.analysis_file_path = analysis_file
	
	print("Analysis will be saved to: " + GlobalVars.analysis_file_path)
	
	# Add error handling to check if the analysis file exists
	if FileAccess.file_exists(GlobalVars.analysis_file_path):
		print("Analysis file found!")
	else:
		print("WARNING: Analysis file does not exist at: " + GlobalVars.analysis_file_path)
	
	# Proceed to the next scene
	GlobalVars.track_finished = false
	load_music_control()

# Called when animation finishes
func _on_animation_finished(anim_name):
	if anim_name == "instructionPanel":
		# Start the 1-second delay
		delay_timer.start()

# Called when the delay timer finishes
func _on_delay_timer_timeout():
	run_python_script()

func run_python_script():
	var args = []
	
	# 1. Where am I?
	var exe_full_path: String = OS.get_executable_path()
	var exe_dir: String = exe_full_path.get_base_dir()
	
	# 2. Navigate up one directory from the MacOS folder when in app bundle
	if exe_dir.ends_with("/Contents/MacOS"):
		# We're in a macOS app bundle, need to go up to the AudioAnalysisData directory
		exe_dir = exe_dir.get_base_dir().get_base_dir().get_base_dir() # Go up three levels
	
	# 3. Name of bundled Python executable
	var program_name: String = "AnalyseSong" # make sure it's +x
	
	# 4. Build full path
	var program_path: String = "%s/%s" % [exe_dir, program_name]
	
	# 5. Check presence
	if not FileAccess.file_exists(program_path):
		# Try one more location as fallback
		var fallback_path: String = "/Users/samuel/AudioAnalysisData/AnalyseSong"
		if FileAccess.file_exists(fallback_path):
			program_path = fallback_path
		else:
			push_error("Cannot find Python program at: %s" % program_path)
			push_error("Also checked fallback path: %s" % fallback_path)
			return {"exit_code": -1, "output": []}
	
	# 6. Run it (blocking) and collect stdout
	var output: Array = []
	var exit_code: int = OS.execute(program_path, args, output)
	
	print("Python script executed with exit code: ", exit_code)
	if output.size() > 0:
		print("Output: ", output[0])
	
	get_tree().reload_current_scene()

func load_music_control():
	# Change scene to the new scene
	get_tree().change_scene_to_file("res://2DMain.tscn")
	# Note: queue_free() is not needed as change_scene_to_file handles cleanup

func _exit_tree():
	print("\n=== CLEAN SHUTDOWN ===")
