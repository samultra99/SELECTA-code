"""
This class controls the main gameplay scene including music playback, reading and storing song analysis data,
controlling timers for beats and onsets that control related events, and resyncing game elements when the tempo changes.
It also controls the GUI related to the score and BPM. 
It was created by Samuel Shipp with debug support from Claude 3.7 Sonnet by Anthropic which was prompted with relevant code snippets,
for example when the timing of beats and scheduled inputs was drifting, and I couldn't see why, Claude suggested fully precalculating
all beat timestamps to avoid the latency of doing beat time calculations at runtime.
You can see the chat from April 2025 here: https://claude.ai/share/4096142b-b17c-45eb-a475-0d22e6ba1132
"""

extends Node2D

# Audio settings
@export var audio_file_path: String = GlobalVars.song_path
@export var bpm: float 

# BPM variables
@export var current_bpm: float # Match default to original BPM
@export var min_bpm: float = 0.0     # Minimum allowed BPM
@export var max_bpm: float   # Maximum allowed BPM
@export var bpm_step: float = 1.0       # Step size for BPM changes

# Playback speed controls
var speed_ratio: float = 1.0            # Ratio between current_bpm and original bpm
var original_seconds_per_beat: float    # Store the original timing for reference
var next_beat_time = 0.0
var next_onset_time = 0.0

# Retrieve data from text file
var lines = []
var song_data = GlobalVars.analysis_file_path

# Beat visualisation 
# 'Flashing' processes are retained as unused function-like structures for reference and prototyping new features
@export var beat_flash_duration: float = 0.1
@export var onset_flash_duration: float = 0.05
@export var circle_radius: float = 50
@export var circle_spacing: float = 50

# Frequency visualisation settings 
@export var min_frequency_y: float = 500  # Lower bound for y position
@export var max_frequency_y: float = 200  # Upper bound for y position 
@export var frequency_smoothing: float = 0.5  # Value between 0-1

# Array to store beat timestamps and control iteration in beat arrays
var beat_timestamps = []
var current_beat_index = 0
var is_playing = false
var flash_timer = 0.0
var is_flashing = false
var seconds_per_beat

# Array to store onset timestamps and control iteration in onset arrays
var onsets = []
var current_onset_index = 0
var flash_timer_o = 0.0
var is_flashing_o = false

# Mean frequencies data for singing phase
var mean_frequencies = []
var current_frequency = 0.0
var target_frequency = 0.0
var current_frequency_y = 25  # Starting y position

# For storing energy levels
var vocal_energy = []
var drum_energy = []

# Onready variables - retrieving child nodes for use
@onready var audio_player = $AudioStreamPlayer
@onready var beat_timer = $BeatTimer
@onready var onset_timer = $OnsetTimer
@onready var remix_timer = $RemixTimer
@onready var gameplay = $Gameplay
@onready var slowSlide = $SlowSlide
@onready var fastSlide = $FastSlide
@onready var bpm_indicator = $BPMindicator
@onready var bpm_label = $bpmLabel
@onready var score_label = $scoreLabel
@onready var beginText = $begin2
@onready var beginX = $xSymbol

# Audio bus names and indices
var master_bus_index = 0
var main_bus_index = 0
var fx_bus_index = 0

# Track selection variables for swapping audio effects normal/reverb/distortion
var active_track_index = 0
var tracks = []

# Effect types 
enum EffectType {NONE, DISTORTION, REVERB}
var current_effect = EffectType.NONE

# BPM slider GUI variables
var old_slide_bpm
var indicator_default

# Begin rewards / penalties for inputs
var game_begins = false

func _ready():
	
	# GUI instructing player how to start level appears
	beginText.visible = true
	beginX.visible = true
	
	# Setup audio buses
	setup_audio_buses()
	
	# Read audio data
	lines = read_file_by_lines(song_data)
	
	# Read & assign BPM
	bpm = lines[1].split(": ")[1].to_float()
	print(bpm)
	current_bpm = bpm
	max_bpm = bpm*2
	old_slide_bpm = bpm
	lines = read_file_by_lines(song_data)
	bpm = lines[1].split(": ")[1].to_float()
	print("Attempting to load audio from: ", audio_file_path) 
	print("Direct GlobalVars path: ", GlobalVars.song_path)

	# Get ready to load up the actual song for playback
	var bytes := FileAccess.get_file_as_bytes(audio_file_path)
	if bytes.size() == 0:
		push_error("Could not open file: %s" % audio_file_path)
		return
	var stream: AudioStream
	match GlobalVars.song_extension.to_lower().trim_prefix("."):
		"mp3":
			var mp3 = AudioStreamMP3.new()
			mp3.data = bytes
			stream = mp3
		"wav": # This is problematic in the final game - should be fixed before widespread release.
			var wav = AudioStreamWAV.new()
			wav.data = bytes
			stream = wav
		_:
			push_error("Unsupported audio extension: %s" % GlobalVars.song_extension)
			return

	audio_player.stream = stream
	
	# Calculate original seconds per beat for beat scheduling
	original_seconds_per_beat = 60.0 / bpm
	
	# Initialize speed ratio
	speed_ratio = current_bpm / bpm
	
	# Score/BPM GUI bar set to default position
	indicator_default = bpm_indicator.position.x
	
	randomize()  # Initialize randomness for use throughout
	
	# Configure main track outputs to appropriate buses
	audio_player.bus = "Main"
	tracks = [audio_player]
	
	# Store mean frequencies from vocals
	parse_mean_frequencies()
	
	# Calculate and store all timestamps in advance
	precalculate_beat_timestamps()
	precalculate_onset_timestamps()
	precalculate_vocal_energy()
	precalculate_drum_energy()
	
	# Connect signals
	audio_player.finished.connect(_on_audio_finished)
	beat_timer.timeout.connect(_on_beat_timer_timeout)
	onset_timer.timeout.connect(_on_onset_timer_timeout)
	remix_timer.timeout.connect(_on_remix_timer_timeout)
	
	# Start function in 'gameplay' class runs - this sets up most of the runtime game logic and is passed all relevant data
	gameplay.start(beat_timestamps, onsets, mean_frequencies, vocal_energy, drum_energy)

func _input(event):
	# Check if the X key was pressed, begin level
	if event.is_action_pressed("ui_right") and GlobalVars.track_finished == false and game_begins == false:
		game_begins = true
		
		# Reset everything
		beginText.visible = false
		beginX.visible = false
		current_beat_index = 0
		current_onset_index = 0
		is_flashing = false
		is_flashing_o = false
		flash_timer = 0.0
		flash_timer_o = 0.0
		
		# Set first frequency
		if mean_frequencies.size() > 0:
			current_frequency = mean_frequencies[0]
			target_frequency = current_frequency
			update_frequency_y_position()
		
		# Reset all buses
		reset_all_buses()
		
		# Apply speed settings
		update_playback_speed()
		
		# Start the song
		audio_player.play()
		
		# Set this track as 'active'
		switch_to_track(0)
		is_playing = true
		
		# Initial flashes 
		trigger_beat_flash()
		
		# Schedule timers for the next events
		schedule_next_beat()
		schedule_next_onset()
		schedule_remix()

func setup_audio_buses():
	# Get the master bus index
	master_bus_index = AudioServer.get_bus_index("Master")
	
	# Create a main bus for the full mix if it doesn't exist
	if AudioServer.get_bus_index("Main") == -1:
		AudioServer.add_bus()
		main_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(main_bus_index, "Main")
		AudioServer.set_bus_send(main_bus_index, "Master")
	else:
		main_bus_index = AudioServer.get_bus_index("Main")
	
	# Create an FX bus if it doesn't exist (for sending effects)
	if AudioServer.get_bus_index("FX") == -1:
		AudioServer.add_bus()
		fx_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(fx_bus_index, "FX")
		AudioServer.set_bus_send(fx_bus_index, "Master")
	else:
		fx_bus_index = AudioServer.get_bus_index("FX")
	
	# Initialize bus volumes
	AudioServer.set_bus_volume_db(main_bus_index, 0)
	AudioServer.set_bus_volume_db(fx_bus_index, -80)     # Start muted
	
	# Add limiter to master bus to prevent clipping
	add_limiter_to_bus(master_bus_index)
	
	#print("Audio buses setup complete")

func parse_mean_frequencies():
	# Parse the provided mean_frequenciesV from text file
	var frequency_data_key = "mean_frequenciesV:"
	
	for line in lines:
		if line.begins_with(frequency_data_key):
			var data_part = line.substr(frequency_data_key.length())
			data_part = data_part.strip_edges().replace("[", "").replace("]", "")
			var freq_strings = data_part.split(",")
			
			mean_frequencies.clear()
			for freq in freq_strings:
				mean_frequencies.append(freq.strip_edges().to_float())
			
			#print("Loaded ", mean_frequencies.size(), " frequency values")
			return

func precalculate_beat_timestamps():
	# Clear any existing timestamps
	beat_timestamps.clear()
	
	# Calculate seconds per beat using original BPM
	original_seconds_per_beat = 60.0 / bpm
	
	# Calculate how many beats we expect for the duration of the song
	var song_duration = 0.0
	if audio_player.stream:
		song_duration = audio_player.stream.get_length()
	else:
		song_duration = 180.0  # Default to 3 minutes if no stream loaded yet
	
	var beat_count = int(song_duration / original_seconds_per_beat) + 1
	
	# Generate all beat timestamps
	for i in range(beat_count):
		beat_timestamps.append(i * original_seconds_per_beat)
	
	GlobalVars.beat_timestamps = beat_timestamps
	
	#print("Precalculated ", beat_timestamps.size(), " beat timestamps")

# Does what it says - but also accounts for speed_ratio
func schedule_next_beat():
	current_beat_index += 1
	if current_beat_index < beat_timestamps.size():
		var current_time = audio_player.get_playback_position()
		GlobalVars.current_time = current_time
		var next_beat_time = beat_timestamps[current_beat_index]
		var time_to_next_beat = (next_beat_time - current_time) / speed_ratio
		
		beat_timer.wait_time = time_to_next_beat
		beat_timer.one_shot = true
		beat_timer.start()

func precalculate_onset_timestamps():
	var onsetParse = lines[2].split(": ")
	var onset_string = onsetParse[1].strip_edges().replace("[", "").replace("]", "")
	var onset_strings = onset_string.split(",")
	
	# Convert strings to floats and store in onsets array
	onsets.clear()
	for time in onset_strings:
		onsets.append(time.strip_edges().to_float())

	# print("Precalculated ", onsets.size(), " onset timestamps")

func precalculate_vocal_energy():
	var ve_parse = lines[4].split(": ")
	var ve_string = ve_parse[1].strip_edges().replace("[", "").replace("]", "")
	var ve_strings = ve_string.split(",")
	
	vocal_energy.clear()
	for time in ve_strings:
		vocal_energy.append(time.strip_edges().to_float())

func precalculate_drum_energy():
	var de_parse = lines[5].split(": ")
	var de_string = de_parse[1].strip_edges().replace("[", "").replace("]", "")
	var de_strings = de_string.split(",")
	
	drum_energy.clear()
	for time in de_strings:
		drum_energy.append(time.strip_edges().to_float())

# Iterate through the analysis text file so that each line break (separates the data categories) is stored separately
func read_file_by_lines(song_data: String) -> PackedStringArray:
	var file = FileAccess.open(song_data, FileAccess.READ)
	if file == null:
		print("Failed to open file: " + song_data)
		return []

	while not file.eof_reached():
		var line = file.get_line()
		lines.append(line)
	file.close()
	return lines

# For testing tempo shifting
func _on_speed_up_pressed():
	set_bpm(current_bpm + bpm_step)

# For testing tempo shifting
func _on_speed_down_pressed():
	set_bpm(current_bpm - bpm_step)

func set_bpm(new_bpm: float):
	# Store old speed ratio for comparison
	var old_speed_ratio = speed_ratio
	
	# Clamp BPM to valid range
	current_bpm = clamp(new_bpm, min_bpm, max_bpm)
	
	# Calculate new speed ratio
	speed_ratio = current_bpm / bpm
	GlobalVars.speed = speed_ratio
	
	# Update audio players' pitch scales
	update_playback_speed()
	
	# Update BPM GUI bar
	bpm_slider()
	
	# If the change in speed ratio is significant, force a resync
	if is_playing and abs(speed_ratio - old_speed_ratio) > 0.05:
		var current_time = audio_player.get_playback_position()
		resync_beats_and_onsets(current_time)
	# Otherwise use the standard resync if playing
	elif is_playing:
		resync_timers_to_new_speed()

func update_playback_speed():
	# Update audio players' pitch scales
	audio_player.pitch_scale = speed_ratio

func resync_timers_to_new_speed():
	# Get current playback position
	var current_time = audio_player.get_playback_position()
	
	# Resync beat timer
	beat_timer.stop()
	if current_beat_index < beat_timestamps.size():
		var next_beat_time = beat_timestamps[current_beat_index]
		var time_to_next_beat = (next_beat_time - current_time) / speed_ratio
		time_to_next_beat = max(0.001, time_to_next_beat - 0.02)
		beat_timer.wait_time = time_to_next_beat
		beat_timer.start()
	
	# Resync onset timer
	onset_timer.stop()
	if current_onset_index < onsets.size():
		var next_onset_time = onsets[current_onset_index]
		var time_to_next_onset = (next_onset_time - current_time) / speed_ratio
		time_to_next_onset = max(0.001, time_to_next_onset - 0.02)
		onset_timer.wait_time = time_to_next_onset
		onset_timer.start()
	
	# Resync remix timer
	remix_timer.stop()
	schedule_remix()

func reset_all_buses():
	# Clear all effects from all buses except master (which keeps its limiter)
	clear_bus_effects(main_bus_index)
	clear_bus_effects(fx_bus_index)
	
	# Reset volumes
	AudioServer.set_bus_volume_db(main_bus_index, 0)
	AudioServer.set_bus_volume_db(fx_bus_index, -80)
	limiter_on_master()
	
	current_effect = EffectType.NONE

func clear_bus_effects(bus_index: int):
	# Remove all effects from a bus
	while AudioServer.get_bus_effect_count(bus_index) > 0:
		AudioServer.remove_bus_effect(bus_index, 0)

func limiter_on_master():
	# Check if master already has a limiter
	var has_limiter = false
	for i in range(AudioServer.get_bus_effect_count(master_bus_index)):
		if AudioServer.get_bus_effect(master_bus_index, i) is AudioEffectLimiter:
			has_limiter = true
			break
	
	# If not, add one
	if not has_limiter:
		add_limiter_to_bus(master_bus_index)

func schedule_next_onset():
	current_onset_index += 1
	if current_onset_index < onsets.size():
		var current_time = audio_player.get_playback_position()
		var next_onset_time = onsets[current_onset_index]
		var time_to_next_onset = (next_onset_time - current_time) / speed_ratio
		
		onset_timer.wait_time = time_to_next_onset
		onset_timer.one_shot = true
		onset_timer.start()

func schedule_remix():
	# Calculate the remix interval (e.g. every 4 beats)
	var remix_interval = 4 * original_seconds_per_beat / speed_ratio
	# Get the current playback time
	var current_time = audio_player.get_playback_position()
	# Compute the next multiple of remix_interval relative to the start
	var next_remix_time = (floor(current_time / remix_interval) + 1) * remix_interval
	# Wait time is the difference between that and the current time
	var wait_time = next_remix_time - current_time
	
	remix_timer.wait_time = wait_time
	remix_timer.one_shot = true
	remix_timer.start()

func _on_start_button_pressed():
	# Reset everything
	current_beat_index = 0
	current_onset_index = 0
	is_flashing = false
	is_flashing_o = false
	flash_timer = 0.0
	flash_timer_o = 0.0
	
	# Set initial frequency
	if mean_frequencies.size() > 0:
		current_frequency = mean_frequencies[0]
		target_frequency = current_frequency
		update_frequency_y_position()
	
	# Reset all buses
	reset_all_buses()
	
	# Apply speed settings
	update_playback_speed()
	
	# Start song
	audio_player.play()
	
	# Set track to 'active'
	switch_to_track(0)
	is_playing = true
	
	# Initial flashes
	trigger_beat_flash()
	
	# Schedule timers for the next events
	schedule_next_beat()
	schedule_next_onset()
	schedule_remix()

func apply_random_effect_to_active_track():
	# Get the index of the active bus
	var active_bus_index = get_active_bus_index()
	
	# Clear existing effects from the active bus
	clear_bus_effects(active_bus_index)
	
	# Add a high probability of no effect 
	var effect_choice = randi() % 10
	
	match effect_choice:
		7: # Distortion (10% chance)
			# EFFECT DEACTIVATED FOR NOW
			current_effect = EffectType.NONE
			#print("Applied distortion effect to active track")
		8: # Reverb (10% chance)
			add_reverb_to_bus(active_bus_index)
			current_effect = EffectType.REVERB
			#print("Applied reverb effect to active track")
		_: # No effect (80% chance)
			current_effect = EffectType.NONE
			#print("No audio effect applied this cycle")

func get_active_bus_index() -> int:
	match active_track_index:
		0: return main_bus_index
		_: return main_bus_index

func add_distortion_to_bus(bus_index: int):
	var effect = AudioEffectDistortion.new()
	effect.drive = randf_range(0.1, 0.5)
	AudioServer.add_bus_effect(bus_index, effect)

func add_reverb_to_bus(bus_index: int):
	var effect = AudioEffectReverb.new()
	effect.room_size = randf_range(0.1, 0.5)
	effect.damping = randf_range(0.2, 0.6)
	AudioServer.add_bus_effect(bus_index, effect)

func add_limiter_to_bus(bus_index: int):
	var limiter = AudioEffectLimiter.new()
	
	# Configure the limiter
	limiter.ceiling_db = -0.5    # Maximum output level 
	limiter.threshold_db = -6.0  # Start limiting at this level
	limiter.soft_clip_db = 2.0   # Soft clipping for smoother sound
	
	AudioServer.add_bus_effect(bus_index, limiter)

func _on_beat_timer_timeout():
	# Visual feedback for beat
	trigger_beat_flash()
	
	# Update frequency for the current beat
	update_beat_frequency()
	
	# Schedule next beat
	schedule_next_beat()

func update_beat_frequency():
	# Update the frequency based on the current beat
	if current_beat_index < mean_frequencies.size():
		target_frequency = mean_frequencies[current_beat_index]
	else:
		# If we've run out of frequency data, use the last known value
		target_frequency = mean_frequencies[mean_frequencies.size() - 1] if mean_frequencies.size() > 0 else 0.0

func update_frequency_y_position():
	# Map the frequency to a y position
	var min_freq = 1000.0  # Minimum expected frequency
	var max_freq = 8500.0  # Maximum expected frequency
	
	# Clamp the frequency to expected range
	var clamped_freq = clamp(current_frequency, min_freq, max_freq)
	
	# Calculate the normalised position 
	var normalized_pos = (clamped_freq - min_freq) / (max_freq - min_freq)
	
	# Map to the y range 
	current_frequency_y = lerp(min_frequency_y, max_frequency_y, normalized_pos)

func _on_onset_timer_timeout():
	# Visual feedback for onset
	trigger_onset_flash()
	
	# Schedule next onset
	schedule_next_onset()

func _on_remix_timer_timeout():
	# Choose a new track with weighted random selection
	var index = choose_weighted_track()
	
	# Smoothly fade to the new track
	smooth_track_transition(index)
	
	# Apply a random effect to the active track
	apply_random_effect_to_active_track()
	
	# Reschedule the remix event 
	schedule_remix()

func choose_weighted_track() -> int:
	# TRACK SWITCHING DISABLED FOR NOW
	# Weighted random selection
	var weights = [1, 0, 0]
	var total_weight = 0
	for weight in weights:
		total_weight += weight
	var rand_pick = randi() % total_weight
	for i in range(weights.size()):
		if rand_pick < weights[i]:
			return i
		rand_pick -= weights[i]
	return 0  # fallback

func smooth_track_transition(index: int) -> void:
	# Only transition if changing to a different track
	if index == active_track_index:
		return
	
	# Store the new active track index
	active_track_index = index
	
	# Prepare volume targets for each bus
	var target_volumes = {
		main_bus_index: -80.0,    # Default to muted
	}
	
	# Set the target for the active bus to full volume
	match index:
		0: target_volumes[main_bus_index] = 0.0
	
	fade_buses(target_volumes)

func fade_buses(target_volumes: Dictionary):
	# Create a temporary timer for the fade
	var fade_timer = Timer.new()
	add_child(fade_timer)
	
	# Set up the fade duration 
	var fade_duration = 0.3
	var fade_steps = 10
	var step_time = fade_duration / fade_steps
	
	# Starting volumes converted db to linear figures
	var start_linears = {}
	for bus_idx in target_volumes:
		var start_db = AudioServer.get_bus_volume_db(bus_idx)
		start_linears[bus_idx] = db_to_linear(start_db)
	
	# Starting volumes converted db to linear figures
	var target_linears = {}
	for bus_idx in target_volumes:
		var target_db = target_volumes[bus_idx]
		target_linears[bus_idx] = db_to_linear(target_db)
	
	# Calculate linear step increments
	var step_linears = {}
	for bus_idx in target_volumes:
		var start_linear = start_linears[bus_idx]
		var target_linear = target_linears[bus_idx]
		step_linears[bus_idx] = (target_linear - start_linear) / fade_steps
	
	# Iterate the fade steps
	for step in range(fade_steps):
		for bus_idx in target_volumes:
			var new_linear = start_linears[bus_idx] + (step_linears[bus_idx] * (step + 1))
			var new_db = linear_to_db(new_linear)
			AudioServer.set_bus_volume_db(bus_idx, new_db)
		
		# Wait for the next step
		fade_timer.wait_time = step_time
		fade_timer.one_shot = true
		fade_timer.start()
		await fade_timer.timeout
	
	# Ensure final volumes are set 
	for bus_idx in target_volumes:
		AudioServer.set_bus_volume_db(bus_idx, target_volumes[bus_idx])
	
	# Destroy timer
	fade_timer.queue_free()

func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)

func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0  # Silence
	return 20.0 * log(linear) / log(10.0)

func switch_to_track(index: int) -> void:
	# Update the active track index
	active_track_index = index
	
	# Set bus volumes immediately (no fade)
	AudioServer.set_bus_volume_db(main_bus_index, 0 if index == 0 else -80)

func trigger_beat_flash():
	is_flashing = true
	flash_timer = beat_flash_duration
	queue_redraw()

func trigger_onset_flash():
	is_flashing_o = true
	flash_timer_o = onset_flash_duration
	queue_redraw()

func _on_audio_finished():
	is_playing = false
	is_flashing = false
	is_flashing_o = false
	beat_timer.stop()
	onset_timer.stop()
	remix_timer.stop()
	print("Playback finished")
	GlobalVars.track_finished = true

func _process(delta):
	# 'Flashing' processes are retained as unused function-like structures for reference and prototyping new features
	# Handle beat flash timing, occurs every beat
	if is_flashing:
		flash_timer -= delta
		if flash_timer <= 0:
			is_flashing = false
			queue_redraw()
	
	# Handle onset flash timing, occurs every onset
	if is_flashing_o:
		flash_timer_o -= delta
		if flash_timer_o <= 0:
			is_flashing_o = false
			queue_redraw()
	
	# Update BPM based on score from child node
	if is_playing:
		update_bpm_from_score()
		
		# Smoothly interpolate the current frequency towards the target 
		current_frequency = lerp(current_frequency, target_frequency, frequency_smoothing * delta * 10)
		update_frequency_y_position()
		queue_redraw()
	
	# Detect if audio was restarted manually or skipped
	if is_playing and audio_player.playing:
		var current_time = audio_player.get_playback_position()
	
	# Add continuous beat timing monitoring when playing
	if is_playing and audio_player.playing:
		var current_time = audio_player.get_playback_position()
		GlobalVars.current_time = current_time
		
		# If position changed significantly, resync both timers
		if current_beat_index > 0 and current_beat_index < beat_timestamps.size() and abs(current_time - beat_timestamps[current_beat_index - 1]) > 0.1:
			resync_beats_and_onsets(current_time)
		
		# Check if we're approaching the next beat
		if current_beat_index < beat_timestamps.size():
			var next_beat_time = beat_timestamps[current_beat_index]
			var time_difference = (next_beat_time - current_time) / speed_ratio
			
			# If we're very close to the expected beat time but haven't triggered it
			# This helps catch beats that might be missed due to timing issues
			if time_difference < 0 and time_difference > -0.1:
				# We missed a beat that should have happened, trigger it now
				trigger_beat_flash()
				update_beat_frequency()
				schedule_next_beat()
				
			# If the timing is significantly off, do a full resync
			elif abs(time_difference) > 0.1:
				resync_beats_and_onsets(current_time)

func update_bpm_from_score():
	# Get the score from the child node
	var score = gameplay.score
	
	# Calculate new BPM based on original BPM plus score
	var new_bpm = bpm + score
	
	# Set the BPM using existing function
	set_bpm(new_bpm)

func resync_beats_and_onsets(current_time):
	# Find the closest upcoming beat and resync
	for i in range(beat_timestamps.size()):
		if beat_timestamps[i] > current_time:
			current_beat_index = i
			var time_to_next_beat = (beat_timestamps[i] - current_time) / speed_ratio  # Adjust for speed
			beat_timer.stop()
			beat_timer.wait_time = time_to_next_beat
			beat_timer.one_shot = true
			beat_timer.start()
			
			# Also update frequency for the new time position
			if i > 0 and i-1 < mean_frequencies.size():
				current_frequency = mean_frequencies[i-1]
				target_frequency = current_frequency
				update_frequency_y_position()
			
			break

	# Find the closest upcoming onset and resync
	for j in range(onsets.size()):
		if onsets[j] > current_time:
			current_onset_index = j
			var time_to_next_onset = (onsets[j] - current_time) / speed_ratio  # Adjust for speed
			onset_timer.stop()
			onset_timer.wait_time = time_to_next_onset
			onset_timer.one_shot = true
			onset_timer.start()
			break

func _draw():
	# Prototype circles that get 'flashed' (blink) on beats and onsets
	# or move according to frequency, left in for reference and future development
	var circle_positions = [
		Vector2(circle_spacing, 25),
		Vector2(2 * circle_spacing, 25),
		Vector2(3 * circle_spacing, current_frequency_y)  # The third circle's y position is based on frequency
	]
	
	var normal_colors = [Color.BLACK, Color.BLACK, Color.BLUE]  
	var beat_flash_colors = [Color.RED, Color.BLACK, Color.BLUE]
	var onset_flash_colors = [Color.BLACK, Color.GREEN, Color.BLUE]
	
	# Default to normal colors
	var colors_to_use = normal_colors.duplicate()
	
	# Apply beat flash (left circle)
	if is_flashing:
		colors_to_use[0] = beat_flash_colors[0]
	
	# Apply onset flash (middle circle)
	if is_flashing_o:
		colors_to_use[1] = onset_flash_colors[1]
	
	# Draw all circles
	#for i in range(circle_positions.size()):
		#draw_circle(circle_positions[i], circle_radius, colors_to_use[i])

func bpm_slider():
	# !! Starts with the text labels for bpm and score
	bpm_label.text = str(current_bpm)
	score_label.text = str(gameplay.score)
	
	# Calculate the difference between current and default BPM
	var slide_value = current_bpm - bpm
	
	# Reset the position of the BPM indicator based on the slide value
	bpm_indicator.position.x = indicator_default + (2 * slide_value)
	
	# Handle fast side (positive BPM difference)
	if slide_value > 0:
		# Calculate the size directly based on the slide value
		fastSlide.size.x = 2 * slide_value
		
		# Ensure fastSlide doesn't exceed the right boundary of bpm_indicator
		var max_width = bpm_indicator.position.x + bpm_indicator.size.x - fastSlide.position.x
		fastSlide.size.x = min(fastSlide.size.x, max_width)
		
		# Reset the slow slide since we're in the fast part
		slowSlide.size.x = 0
		slowSlide.position.x = bpm_indicator.position.x
	
	# Handle slow side (negative BPM difference)
	elif slide_value < 0:
		# The absolute value of slide_value determines the size
		slowSlide.size.x = 2 * abs(slide_value)
		
		# Position the slow slide to extend leftward from bpm_indicator
		slowSlide.position.x = bpm_indicator.position.x 
		
		# Ensure slowSlide doesn't go beyond any left boundary 
		var min_x_position = 0  
		if slowSlide.position.x < min_x_position:
			var overflow = min_x_position - slowSlide.position.x
			slowSlide.size.x -= overflow
			slowSlide.position.x = min_x_position
		
		# Reset the fast slide since we're in the fast part
		fastSlide.size.x = 0
	
	else:
		# Reset both slides when at default BPM
		fastSlide.size.x = 0
		slowSlide.size.x = 0
		slowSlide.position.x = bpm_indicator.position.x
	
	# Store the current BPM for the next comparison
	old_slide_bpm = current_bpm
