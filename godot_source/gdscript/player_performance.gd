extends Node

'''
This class records and exports noteworthy player interactions so we can 
test the game and various musicological hypotheses using data gathered from players.
Created by Samuel Shipp
'''

# Where am I? Find current directory to store player data at end.
var executable_dir
var target_dir
var player_lib_path
var song_name
var file_name
var file_extension
var full_path
var file

# Main storage arrays!
var main_phase_doubles: PackedVector2Array = PackedVector2Array()
var ap_triples: PackedVector3Array = PackedVector3Array()
var sp_doubles: PackedVector2Array = PackedVector2Array()
var score_doubles: PackedVector2Array = PackedVector2Array()

# Get parent and grandparent
var gameplay
var control

# Called when the node enters the scene tree for the first time.
# Create a new text file for new player data
func _ready() -> void:
	
	# Get parent and grandparent
	gameplay = get_parent()
	control = gameplay.get_parent()
	
	# Get the directory of the executable
	executable_dir = OS.get_executable_path().get_base_dir()
	
	# Navigate three directories back from the current location
	target_dir = executable_dir
	for i in range(3):
		target_dir = target_dir.get_base_dir()
	
	# Construct path to player_lib folder in the target directory
	player_lib_path = target_dir.path_join("player_lib")
	
	# Create the player_lib directory if it doesn't exist
	var dir = DirAccess.open(target_dir)
	if dir and not dir.dir_exists("player_lib"):
		dir.make_dir("player_lib")
	
	# Generate unique filename based on song name
	song_name = GlobalVars.song_name
	file_name = song_name
	file_extension = ".txt"
	full_path = player_lib_path.path_join(file_name + file_extension)
	
	# Check if file exists and append numbers if needed
	var counter = 1
	while FileAccess.file_exists(full_path):
		file_name = song_name + str(counter)
		full_path = player_lib_path.path_join(file_name + file_extension)
		counter += 1
	
	# Create and write to the file
	file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_string("Created file for song: " + GlobalVars.song_name + "\n")
		print("Successfully created file: " + full_path)
	else:
		print("Failed to create file. Error code: " + str(FileAccess.get_open_error()))

func main_phase_data(global_differential: float) -> void:
	
	var bpm = control.current_bpm
	main_phase_doubles.push_back(Vector2(bpm, global_differential))

# drumming event
func ap_data(hit_percentage: float, total_onsets: float) -> void:
	
	var bpm = control.current_bpm
	ap_triples.push_back(Vector3(bpm, hit_percentage, total_onsets))

# singing event
func sp_data(sp_score: float) -> void:
	
	var bpm = control.current_bpm
	sp_doubles.push_back(Vector2(bpm, sp_score))

func score_data(score: float) -> void:
	
	var bpm = control.current_bpm
	score_doubles.push_back(Vector2(bpm, score))

func song_ends() -> void:
	# Open the existing file to append data
	file = FileAccess.open(full_path, FileAccess.READ_WRITE)
	
	if file:
		# Move to end of file
		file.seek_end()
		
		# Write the main phase data
		file.store_string("\n\n--- MAIN PHASE DATA ---\n")
		for data_point in main_phase_doubles:
			file.store_string("BPM: " + str(data_point.x) + ", Differential: " + str(data_point.y) + "\n")
		
		# Write the AP data
		file.store_string("\n--- AP DATA ---\n")
		for data_point in ap_triples:
			file.store_string("BPM: " + str(data_point.x) + ", Hit %: " + str(data_point.y) + ", Total Onsets: " + str(data_point.z) + "\n")
		
		# Write the SP data
		file.store_string("\n--- SP DATA ---\n")
		for data_point in sp_doubles:
			file.store_string("BPM: " + str(data_point.x) + ", SP Score: " + str(data_point.y) + "\n")
		
		# Write the score data
		file.store_string("\n--- SCORE DATA ---\n")
		for data_point in score_doubles:
			file.store_string("BPM: " + str(data_point.x) + ", Score: " + str(data_point.y) + "\n")
		
		# Close the file
		file.close()
		print("Successfully wrote player data to: " + full_path)
	else:
		print("Failed to open file for writing." + str(FileAccess.get_open_error()))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
