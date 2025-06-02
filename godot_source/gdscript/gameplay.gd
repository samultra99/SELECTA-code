"""
This class controls the core gameplay systems and their synchronisation with audio,
including input icons, evaluating input timing, updating score,
changing difficulty over time, beginning special drumming and singing phases,
controlling most of the GUI and processing of audio data for gameplay.
It was created by Samuel Shipp with debug support from Claude 3.7 Sonnet by Anthropic 
which was prompted with relevant code snippets,
for example when I was having trouble getting a second special event identical to the 
drumming phase (attention phase) to work, I prompted with my code to spot the issue.
View the chat here: https://claude.ai/share/ac54c55f-5f54-41cb-8f79-96733757d102
"""

# Glossary:
# Attention phase is drumming phase
# Rects are the moving icons representing scheduled inputs
# Left, up and right refers to left, middle or right button icon

extends Node2D

# Preload and setup all UI elements and relevant materials and parameters
# Characters
@onready var happy_char = $character2happy
@onready var flare = $character2happy/flare
@onready var necklace = $character2happy/necklace
@onready var sad_char = $character2sad
@onready var sad_eyes = $character2sad/sadeyes
@onready var flare_anim = $character2happy/flare_anim
@onready var dj = $dj_char

# Background
@onready var bg := $ColorRect.material as ShaderMaterial
var colorBoost = 1.9

# Special event UI
@onready var ap_rect = $AttenRect
@onready var ap_text = $AttenLabel
@onready var ap_anim = $AttenAnim
@onready var ap_timer = $AttenTimer
@onready var ap_guide = $ap_guide
@onready var drum_tex = preload("res://Visual Assets/drum.png")
@onready var hit_color = Color(0.3, 0.8, 0.3, 1.0)  # Green for hits
@onready var miss_color = Color(0.9, 0.2, 0.2, 1.0)  # Red for misses
@onready var default_color = Color(1.0, 1.0, 1.0, 1.0)  # White for default
var drum_sprites = []
var onset_sprite_map = {}

# Textual feedback
@onready var hit_rating = $hitRating
@onready var ap_rating = $hitRating2
@onready var perfect_material := ShaderMaterial.new()
@onready var ok_material := ShaderMaterial.new()
@onready var missed_material := ShaderMaterial.new()
@onready var dupe_material := ShaderMaterial.new()
@onready var default_material := ShaderMaterial.new()
var rect_a
var rect_b


# Audio data arrays prepared for input scheduling
var beats: Array # Final beats for gameplay
var original_beats: Array = []
# 'Special' beats that will bypass the minimum gap requirement here (duplicates)
var special_beats = [] 
var onsets: Array
var vocal_energy: Array
var drum_energy: Array
var beat_index: int = 0
var audio_player: AudioStreamPlayer

# Game phases control variables (except singing)
var game_begun = false
var in_intro_phase: bool = true
var intro_beats_counted: int = 0
var in_attention_phase: bool = false
var ap_warmup: bool = false
var warmup_ends: float = 0
var attention_phase_end_time: float = 0.0
var attention_phase_onsets: Array = []
var attention_phase_hits: int = 0
var attention_phase_total_onsets: int = 0
var attention_input_window: float = 0.15  # Timing window in seconds for input during attention phase
var eval_timer

# Singing phase control variables
@onready var sp_analyse = $singingAnalysis
@onready var mic_sprite = $microphone
@onready var player_sing_label = $microphone/player_sing_label
@onready var target_sing_label = $microphone/target_sing_label
@onready var advice_sing_label = $microphone/advice_sing_label
@onready var mic_mat := ShaderMaterial.new()
@onready var good_sing := ShaderMaterial.new()
@onready var bad_sing := ShaderMaterial.new()
var in_singing_phase: bool = false
var sp_warmup: bool = false
var sp_warmup_ends: float = 0.0
var sp_end_time: float = 0.0
var sp_frequencies: Array = []
var sp_total_frequencies: int = 0
var sp_score: float = 0.0
var sp_beat_index: int = 0
var sp_start_index: int = 0
var sp_done = false

# track ends screen and control objects/variables
@onready var sf_player = $SongFinishedPlayer
var final_press = 0

# user input thesholds
var perfect_timing_window: float = 0.05  # 100ms window for "perfect" timing
var end_timing_buffer: float = 0.2  # Time buffer before rectangle disappears
var good_after_perfect_window: float = 0.2  # Additional time for GOOD hits after perfect window

# for recording user data
var player_data
var global_differential

# Scheduled input icon (rect) variables and structures are below (multiple segments)
# direction (of scheduled input) constants
const UP = 0
const LEFT = 1
const RIGHT = 2
var directionInit: float = 0

# start/end coordinates for each rect
const upEndy = 613
const leftEndy = 613
const rightEndy = 613
const upSpawny = upEndy - 600
const leftSpawny = leftEndy - 600
const rightSpawny = rightEndy - 600

# number of rect instances to create for each direction, for assignment as scheduled inputs
const INSTANCES_PER_DIRECTION = 5

# arrays to hold all rect instances - the actual Sprite2D nodes
var up_rects: Array = []
var left_rects: Array = []
var right_rects: Array = []

# structure for active rects (holds data about scheduled inputs when they are on screen)
class ActiveRect:
	var direction: int       # Direction (UP/LEFT/RIGHT)
	var instance_index: int  # Which instance of the direction is being used
	var end_time: float      # When this rect should disappear
	var perfect_time: float  # When this rect should be hit perfectly
	var perfect_end_time: float  # When perfect window ends
	var hit: bool = false    # Whether this rect has been hit 
	
	func _init(dir: int, idx: int, end: float, perfect_buffer: float = 0.1, good_buffer: float = 0.2):
		direction = dir
		instance_index = idx
		perfect_time = end - perfect_buffer  # Perfect timing is slightly before end time
		perfect_end_time = end - perfect_buffer + perfect_buffer  # End of perfect window
		end_time = perfect_end_time + good_buffer  # Extended end time for good hits

# Array of ActiveRect objects, how many are duplicates, and how long to be ready for disappearance animation
var active_rects: Array = []
var animation_warn = 2.0
var duplicates: Array = []


# Initial score
var score: float = 0

func _ready() -> void:
	# Retrieve song player node from parent
	audio_player = get_parent().get_node("AudioStreamPlayer")
	if audio_player == null:
		print("AudioStreamPlayer node not found!")
	else:
		print("AudioStreamPlayer node cached.")
	
	# Retrieve player data script to store performance data when song ends
	player_data = get_node("PlayerData")
	
	# Reset GUI for game start (ap = attention phase)
	ap_rect.visible = false
	ap_text.visible = false
	ap_timer.visible = false
	ap_guide.visible = false
	mic_sprite.visible = false
	# Timer for attention phase countdown
	eval_timer = Timer.new()
	add_child(eval_timer)
	eval_timer.wait_time = 2.0       
	eval_timer.one_shot = true     
	eval_timer.autostart = false
	eval_timer.timeout.connect(_on_eval_timer_timeout) 
	hit_rating.visible = false
	ap_rating.visible = false
	
	# Retrieve shaders and apply default states
	perfect_material.shader = preload("res://perfect.gdshader")
	ok_material.shader = preload("res://ok.gdshader")
	missed_material.shader = preload("res://missed.gdshader")
	dupe_material.shader = preload("res://greenSlideShimmer.gdshader")
	default_material.shader = preload("res://menuX.gdshader")
	mic_mat.shader = preload("res://microphone.gdshader")
	bad_sing.shader = preload("res://bad_singer.gdshader")
	good_sing.shader = preload("res://good_singer.gdshader")
	default_material.set_shader_parameter("tint_color", Vector4(1.0,1.0,1.0,1.0))
	
	# Set characters to default visual modes
	happy_char.visible = true
	flare.visible = true
	necklace.visible = true
	flare_anim.play("flare_spiral")
	sad_char.visible = false
	sad_eyes.visible = false
	dj.visible = true
	
	# Create rect instances for each direction
	_create_rect_instances()

# Create multiple instances of each direction's ColorRect
func _create_rect_instances() -> void:
	# Get the original rect Sprite2Ds as templates
	var up_template = get_node("DownArrow")
	var left_template = get_node("LeftArrow")
	var right_template = get_node("RightArrow")
	
	# Hide the originals 
	up_template.visible = false
	left_template.visible = false
	right_template.visible = false
	
	# Create multiple instances of Up rects
	for i in range(INSTANCES_PER_DIRECTION):
		var new_up = _duplicate_rect(up_template, "DownArrow_" + str(i))
		new_up.rotate(1.5707963268)
		up_rects.append(new_up)
	
	# Create multiple instances of Left rects
	for i in range(INSTANCES_PER_DIRECTION):
		var new_left = _duplicate_rect(left_template, "LeftArrow_" + str(i))
		left_rects.append(new_left)
	
	# Create multiple instances of Right rects
	for i in range(INSTANCES_PER_DIRECTION):
		var new_right = _duplicate_rect(right_template, "RightArrow_" + str(i))
		new_right.rotate(3.1415926536)
		right_rects.append(new_right)
	
	#print("Created rect pools: " + str(up_rects.size()) + " up, " + 
		#str(left_rects.size()) + " left, " + str(right_rects.size()) + " right")

func _duplicate_rect(template: Sprite2D, name: String) -> Sprite2D:
	var new_rect = Sprite2D.new()
	new_rect.name = name
	new_rect.position = template.position
	new_rect.texture = template.texture  
	new_rect.scale = template.scale      
	new_rect.material = default_material
	
	new_rect.visible = false
	add_child(new_rect)
	return new_rect

# !! INPUT SCHEDULING ALGORITHM !! Activated by 2dMain as scene enters tree
func start(beats_input: Array, onsets_input: Array, freqs_input: Array, vocal_input: Array, drum_input: Array) -> void:
	
	# Assign audio data to global variables
	original_beats = beats_input
	onsets = onsets_input
	sp_frequencies = freqs_input
	vocal_energy = vocal_input
	drum_energy = drum_input
	
	# Create a new array for processed beats
	var processed_beats: Array = []
	
	# Set background shader to starting colours
	bg.set_shader_parameter("highlightColor", Vector3(0.3, 0.3, 1.9))
	colorBoost = 1.9
	
	# INPUT SCHEDULING STARTS
	# include all original beats as the foundation
	for beat in original_beats:
		processed_beats.append(beat)
		# select 10% of these beats to be 'special' duplicates requiring 2 inputs
		if randi() % 10 == 0:
			special_beats.append(beat)
		
	# add some half-beats between original beats based on difficulty tier
	if original_beats.size() > 1:
		for i in range(original_beats.size() - 1):
			var current_beat = original_beats[i]
			var next_beat = original_beats[i+1]
			var beat_gap = next_beat - current_beat
			var current_tier = get_difficulty_tier(current_beat)
			
			# Only add half-beats when there's enough space between beats
			# The minimum gap changes based on difficulty tier
			var min_gap_for_insertion = 1.0 - (current_tier * 0.1) # Tier 1: 0.9s, Tier 4: 0.6s
			
			if beat_gap >= min_gap_for_insertion:
				# Calculate time for half-beat
				var half_beat = current_beat + (beat_gap / 2.0)
				
				# Insertion probability increases with difficulty tier
				var insertion_chance = 0.2 + (current_tier * 0.1) # Tier 1: 30%, Tier 4: 60%
				if randf() < insertion_chance:
					processed_beats.append(half_beat)
					
					# Only add quarter and three-quarter beats in higher difficulty tiers
					if current_tier >= 3 and beat_gap >= 1.2 and randf() < 0.2:
						var quarter_beat = current_beat + (beat_gap * 0.25)
						processed_beats.append(quarter_beat)
					
					if current_tier >= 4 and beat_gap >= 1.2 and randf() < 0.2:
						var three_quarter_beat = current_beat + (beat_gap * 0.75)
						processed_beats.append(three_quarter_beat)

	# Sort all beats chronologically 
	processed_beats.sort()
	
	# Apply a minimum gap filter that varies by difficulty tier
	var final_beats: Array = []
	var last_beat_time = -1.0
	for beat_time in processed_beats:
		var current_tier = get_difficulty_tier(beat_time)
		var min_gap = 0.7 - (current_tier * 0.05) # Tier 1: 0.65s, Tier 4: 0.5s
	
		# Exception! if the beat is in the special_beats list, skip the minimum gap check
		if beat_time in special_beats:
			final_beats.append(beat_time)
			final_beats.append(beat_time)
			last_beat_time = beat_time
		elif last_beat_time < 0 or (beat_time - last_beat_time) >= min_gap:
			final_beats.append(beat_time)
			last_beat_time = beat_time
	
	beats = final_beats
	# Get ready to iterate during the song
	beat_index = 0

func get_difficulty_tier(timestamp: float) -> int:
	if timestamp >= 90.0: # 90 seconds
		return 4  # Very hard
	elif timestamp >= 60.0: 
		return 3  # Hard
	elif timestamp >= 30.0:  
		return 2  # Medium
	else: 
		return 1  # Easy

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# if ready
	if audio_player:
		# if song has ended, take appropriate action
		if GlobalVars.track_finished == true:
			_hide_all_visible_rects()
			song_ends()
		
		var current_time = audio_player.get_playback_position()
		var adjusted_time = current_time
		
		# Check if gameplay has begun, whether to accept inputs
		game_begun = get_parent().game_begins

		# Check if attention phase has ended based on time
		if in_attention_phase and current_time >= attention_phase_end_time:
			in_attention_phase = false
			_evaluate_attention_phase_performance()
			
			# UI for end of attention phase
			delete_sprites()
			ap_timer.visible = false
			ap_guide.visible = false
			dj.visible = true
			ap_anim.play("atten_back")
			ap_anim.animation_finished.connect(func(anim_name):
				if anim_name == "atten_back":
					ap_rect.visible = false
					ap_text.visible = false
			)
		
		# Similarly check if singing phase has ended
		if in_singing_phase and current_time >= sp_end_time:
			in_singing_phase = false
			
			# Stop singing analysis
			sp_analyse.stop_analysis()
			
			# UI for end of singing phase
			mic_sprite.visible = false
			player_sing_label.visible = false
			target_sing_label.visible = false
			advice_sing_label.visible = false
			dj.visible = true
			
			# Record player performance data
			player_data.sp_data(sp_score)
			
			# Animations for end of singing phase
			ap_anim.play("atten_back")
			ap_anim.animation_finished.connect(func(anim_name):
				if anim_name == "atten_back":
					ap_rect.visible = false
					ap_text.visible = false
					
			)

		# Don't do anything for first 4 bars 'intro phase'
		if in_intro_phase:
			# Count beats from original_beats that have passed
			while intro_beats_counted < original_beats.size() and adjusted_time >= original_beats[intro_beats_counted]:
				print("Intro beat " + str(intro_beats_counted + 1) + " at time: " + str(original_beats[intro_beats_counted]))
				intro_beats_counted += 1
				if intro_beats_counted >= 4:  
					in_intro_phase = false
					print("Intro phase complete")
					break

		# MAIN GAMEPLAY PROCESS
		# Process gameplay beats only if not in intro phase
		if not in_intro_phase:
			while beat_index < beats.size() and adjusted_time >= beats[beat_index]:
				# Skip processing new phases if already in a special phase
				if in_attention_phase or in_singing_phase or ap_warmup or sp_warmup:
					beat_index += 1
					continue

				var current_tier = get_difficulty_tier(beats[beat_index])
				var attention_phase_chance = get_attention_phase_chance(current_tier)
				var singing_phase_chance = get_singing_phase_chance(current_tier)
				
				# Checks drum energy to see if scheduling a drumming phase is valid
				var ap_valid = false 
				if beat_index + 8 < drum_energy.size():
					for i in range(8):
						var current_energy = drum_energy[beat_index + i]
						if current_energy > 0.1:
							ap_valid = true
				
				# Checks vocal energy to see if scheduling a singing phase is valid
				var sp_valid = false
				if beat_index + 8 < vocal_energy.size():
					for i in range(8):
						var current_energy = vocal_energy[beat_index + i]
						if current_energy > 0.1:
							sp_valid = true
				
				# Attention phase only happens if valid and no other phases
				if (randf() < attention_phase_chance) and ap_valid == true:
					print("ATTENTION PHASE!")
					
					# Sets up AP, timings for it and sets warmup time
					var attention_beats = 20
					var current_beat_time = beats[beat_index]
					warmup_ends = beats[beat_index + 4]
					var next_beat_index_in_original = find_next_beat_index(current_beat_time)
					var end_beat_index = min(next_beat_index_in_original + attention_beats, original_beats.size() - 1)
					attention_phase_end_time = original_beats[end_beat_index]
					ap_warmup = true
					
					# AP GUI activated
					ap_rect.visible = true
					ap_text.text = "TAP THE DRUM RHYTHM"
					ap_text.visible = true
					ap_anim.play("ap_rect_move")
					ap_guide.visible = true
					dj.visible = false
					
				# Singing phase only happens if valid and no other phases
				elif (randf() < singing_phase_chance) and sp_valid == true:
					print("SINGING PHASE!")
					
					# Allows limiting to specific number of singing phases per level (deactivated)
					sp_done = true

					# Sets up SP, timings for it and sets warmup time
					var singing_beats = 36  
					var current_beat_time = beats[beat_index]
					sp_warmup_ends = beats[beat_index + 4]
					sp_start_index = beat_index
					var next_beat_index_in_original = find_next_beat_index(current_beat_time)
					var end_beat_index = min(next_beat_index_in_original + singing_beats, original_beats.size() - 1)
					sp_end_time = original_beats[end_beat_index]
					sp_warmup = true
					
					# SP GUI activates
					dj.visible = false
					ap_rect.visible = true
					ap_text.text = "SING ALONG"
					ap_text.visible = true
					ap_anim.play("ap_rect_move")
					player_sing_label.visible = true
					player_sing_label.text = "0"
					target_sing_label.visible = true
					target_sing_label.text = "0"
					advice_sing_label.visible = true
					advice_sing_label.text = "START SINGING"
					
				# Spawn a rect if not in any special phase and drum energy is high
				elif ap_valid == true: 
					# Choose a random direction 
					var directionOld = directionInit
					directionInit = randi() % 3  # 0=UP, 1=LEFT, 2=RIGHT
					# prevents double duplication where special_beats are already duplicate
					if directionInit == directionOld and current_time in special_beats:
						if directionInit == 0:
							var up_or_down = randi() % 2
							if up_or_down == 0:
								directionInit += 1
							elif up_or_down == 1:
								directionInit += 2
						if directionInit == 0:
							var up_or_down = randi() % 2
							if up_or_down == 0:
								directionInit += 1
							elif up_or_down == 1:
								directionInit -= 1
						if directionInit == 2:
							var up_or_down = randi() % 2
							if up_or_down == 0:
								directionInit -= 1
							elif up_or_down == 1:
								directionInit -= 2
							
					_spawn_rect(directionInit, current_time + 2)
				
				# Move onto next beat and make the DJ bounce in time with the music
				beat_index += 1
				var tween = create_tween()
				tween.tween_property(dj, "scale", Vector2(0.827, 0.827), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(dj, "scale", Vector2(0.802, 0.802), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				
				# Increase the saturation of the background colour as song progresses
				colorBoost += 0.01
				bg.set_shader_parameter("highlightColor", Vector3(0.3, 0.3, colorBoost))
		
		# Process expiration of active rectangles
		_process_active_rects(current_time)
		
		# Process end of attention phase warmup
		if ap_warmup and !in_attention_phase:
			if current_time >= warmup_ends:
				print("attention_phase_warm_up_ended")
				ap_warmup = false
				in_attention_phase = true
				
				ap_timer.visible = true
				
				_hide_all_visible_rects()
	
				# Collect onsets that fall within the attention phase time window
				attention_phase_onsets = []
				attention_phase_hits = 0
	
				for onset in onsets:
					if onset >= current_time and onset <= attention_phase_end_time:
						attention_phase_onsets.append(onset)
				attention_phase_total_onsets = attention_phase_onsets.size()
				
				# Spawn the drum icons
				spawn_sprites(attention_phase_onsets)
				print("Total onsets in attention phase: " + str(attention_phase_total_onsets))
		
		# Process end of singing phase warmup
		if sp_warmup and !in_singing_phase:
			if current_time >= sp_warmup_ends:
				print("singing_phase_warm_up_ended")
				sp_warmup = false
				in_singing_phase = true
				_hide_all_visible_rects()

				# Prepare for singing phase analysis
				sp_score = 0
				sp_beat_index = 0
				sp_analyse.begin_analysis()
				mic_mat.set_shader_parameter("metallic_tint", Vector4(0.8, 0.8, 0.7, 1.0))
				mic_sprite.visible = true
		
		# !! AP MAIN FUNCTIONALITY !! Check for any attention phase input hits during the phase 
		if in_attention_phase and !ap_warmup:
			_process_attention_phase_onsets(current_time)
			var ap_time_update = int(attention_phase_end_time - current_time)
			ap_timer.text = str(ap_time_update)
		
		# Rate player singing only when active and not in warmup
		if in_singing_phase and !sp_warmup:
			_process_singing_phase_frequencies(current_time)

func song_ends() -> void:
	player_data.song_ends()
	if final_press == 0:
		sf_player.play("slide_final")
		final_press += 1

# Find an available rectangle instance for a given direction
func _find_available_rect(direction: int) -> int:
	var rect_array
	
	match direction:
		UP: rect_array = up_rects
		LEFT: rect_array = left_rects
		RIGHT: rect_array = right_rects
	
	# Find the first invisible (unused) rectangle
	for i in range(rect_array.size()):
		if not rect_array[i].visible:
			return i
	
	# If all instances are in use, return -1
	return -1

# Make a newly assigned input an active rect object with visible Sprite and assign timings
func _spawn_rect(direction: int, end_time: float) -> void:
	var instance_index = _find_available_rect(direction)
	
	if instance_index == -1:
		print("WARNING: No available rectangle instances for direction " + str(direction))
		return
	
	# Get the appropriate array of rects
	var rect_array
	var direction_name
	
	match direction:
		UP:
			rect_array = up_rects
			direction_name = "UP"
		LEFT:
			rect_array = left_rects
			direction_name = "LEFT"
		RIGHT:
			rect_array = right_rects
			direction_name = "RIGHT"
	
	# Show the rect
	rect_array[instance_index].visible = true
	
	# Add to active rects list with updated timing windows
	var new_active_rect = ActiveRect.new(direction, instance_index, end_time, perfect_timing_window, good_after_perfect_window)
	active_rects.append(new_active_rect)
	
	# Identify 'special' duplicates and set material to green duplicate material.
	# Loop through all_rects comparing every rectangle with every other rectangle.
	for j in range(active_rects.size()):
		for k in range(j + 1, active_rects.size()):
			rect_a = active_rects[j]
			rect_b = active_rects[k]
			if (rect_a.direction == rect_b.direction) and (rect_a.end_time == rect_b.end_time):
				if rect_a.direction == UP:
					duplicates.append(up_rects[rect_a.instance_index])
					duplicates.append(up_rects[rect_b.instance_index])
					up_rects[rect_a.instance_index].material = dupe_material
					up_rects[rect_b.instance_index].material = dupe_material
				elif rect_a.direction == LEFT:
					duplicates.append(left_rects[rect_a.instance_index])
					duplicates.append(left_rects[rect_b.instance_index])
					left_rects[rect_a.instance_index].material = dupe_material
					left_rects[rect_b.instance_index].material = dupe_material
				elif rect_a.direction == RIGHT:
					duplicates.append(right_rects[rect_a.instance_index])
					duplicates.append(right_rects[rect_b.instance_index])
					right_rects[rect_a.instance_index].material = dupe_material
					right_rects[rect_b.instance_index].material = dupe_material

# Process active rects (check for timeouts)
func _process_active_rects(current_time: float) -> void:
	var i = 0
	while i < active_rects.size():
		var active_rect = active_rects[i]
		
		# Calculate movement progress towards hit zone based on time
		# Animation should complete at perfect_time, not at end_time
		var progress = clamp(remap(current_time, active_rect.end_time - animation_warn - good_after_perfect_window, 
								active_rect.perfect_time, 0, 1), 0, 1)
		
		# Animate based on direction
		match active_rect.direction:
			UP:
				var position = lerp(upSpawny, upEndy, progress)
				up_rects[active_rect.instance_index].modulate.a = progress
				up_rects[active_rect.instance_index].position.y = position
			LEFT:
				var position = lerp(leftSpawny, leftEndy, progress)
				left_rects[active_rect.instance_index].modulate.a = progress
				left_rects[active_rect.instance_index].position.y = position
			RIGHT:
				var position = lerp(rightSpawny, rightEndy, progress)
				right_rects[active_rect.instance_index].modulate.a = progress
				right_rects[active_rect.instance_index].position.y = position
		
		# Check if this rect has timed out
		if current_time >= active_rect.end_time:
			# Hide the rect
			_hide_rect(active_rect.direction, active_rect.instance_index)
			
			# Penalise missed rects and visual feedback
			if not active_rect.hit:
				rebalancing_penalty()
				hit_rating.visible = true
				hit_rating.text = "FAILED"
				hit_rating.material = missed_material
				
				sad_char.visible = true
				sad_eyes.visible = true
				happy_char.visible = false
				flare.visible = false
				necklace.visible = false
				
				# Record maximum differential in player performance
				global_differential = 0.25
				player_data.main_phase_data(global_differential)
				
				#print("Missed a rectangle! -1 point. Score: " + str(score))
			
			# Remove from active rects when done
			active_rects.remove_at(i)
		else:
			i += 1

# Hide a specific rect instance and animate its disappearance
func _hide_rect(direction: int, instance_index: int) -> void:
	match direction:
		UP: 
			# Create animation
			var tween = up_rects[instance_index].create_tween()

			# Store the original scale before animation
			var original_scale = up_rects[instance_index].scale

			# scale up
			tween.tween_property(up_rects[instance_index], "scale", Vector2(0.56, 0.56), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# then scale down and fade out simultaneously
			tween.tween_property(up_rects[instance_index], "scale", Vector2(0, 0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(up_rects[instance_index], "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

			# Handle post-animation actions (reset and deactivation of rect instance)
			tween.connect("finished", func():
				up_rects[instance_index].visible = false
				up_rects[instance_index].scale = original_scale  # Reset to the original scale
				up_rects[instance_index].modulate.a = 1.0  # Reset alpha
				up_rects[instance_index].material = default_material  # Reapply default material
			)
		LEFT:
			# Create animation
			var tween = left_rects[instance_index].create_tween()

			# scale up
			tween.tween_property(left_rects[instance_index], "scale", Vector2(0.46, 0.46), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# then scale down and fade out simultaneously
			tween.tween_property(left_rects[instance_index], "scale", Vector2(0, 0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(left_rects[instance_index], "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

			# Handle post-animation actions (reset and deactivation of rect instance)
			tween.connect("finished", func():
				left_rects[instance_index].visible = false
				left_rects[instance_index].scale = Vector2(0.332, 0.334)
				left_rects[instance_index].modulate.a = 1.0  # Reset alpha
				left_rects[instance_index].material = default_material
			)
		RIGHT:
			# create animation
			var tween = right_rects[instance_index].create_tween()

			# scale up
			tween.tween_property(right_rects[instance_index], "scale", Vector2(1.4, 1.4), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# then scale down and fade out simultaneously
			tween.tween_property(right_rects[instance_index], "scale", Vector2(0, 0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(right_rects[instance_index], "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

			# Handle post-animation actions (reset and deactivation of rect instance)
			tween.connect("finished", func():
				right_rects[instance_index].visible = false
				right_rects[instance_index].scale = Vector2.ONE
				right_rects[instance_index].modulate.a = 1.0  # Reset alpha
				right_rects[instance_index].material = default_material
			)

func _process_attention_phase_onsets(current_time: float) -> void:
	# Remove onsets that are too old (outside the window) and mark as missed
	var i = 0
	while i < attention_phase_onsets.size():
		if current_time > attention_phase_onsets[i] + attention_input_window:
			var missed_onset = attention_phase_onsets[i]
			
			# Colour the corresponding sprite red for miss
			if onset_sprite_map.has(missed_onset) and onset_sprite_map[missed_onset] < drum_sprites.size():
				var sprite_index = onset_sprite_map[missed_onset]
				drum_sprites[sprite_index].material = bad_sing
			
			attention_phase_onsets.remove_at(i)
		# Moves on to next onset if time surpasses 
		elif current_time > attention_phase_onsets[i]:
			var active_onset = attention_phase_onsets[i]
			
			if onset_sprite_map.has(active_onset) and onset_sprite_map[active_onset] < drum_sprites.size():
				var sprite_index = onset_sprite_map[active_onset]
				# Visual feedback - make the next drum sprite pulse briefly
				var tween = create_tween()
				tween.tween_property(drum_sprites[sprite_index], "scale", Vector2(0.05, 0.05), 0.1)
				tween.tween_property(drum_sprites[sprite_index], "scale", Vector2(0.04, 0.04), 0.1)
			i += 1
		else:
			i += 1

func _evaluate_attention_phase_performance() -> void:
	var hit_percentage = 0.0
	if attention_phase_total_onsets > 0:
		hit_percentage = float(attention_phase_hits) / float(attention_phase_total_onsets)
		# calculate and record player performance
		player_data.ap_data(hit_percentage, attention_phase_total_onsets)
	
	print("Attention phase performance: " + str(attention_phase_hits) + "/" + str(attention_phase_total_onsets) + " = " + str(hit_percentage * 100) + "%")
	
	# Timer for how long to show textual feedback after AP ends
	eval_timer.start()
	
	# Calculate score adjustment based on performance and set visual feedback elements like character adjustments
	var score_adjustment = 0
	if hit_percentage >= 0.9:
		score_adjustment = 10
		sad_char.visible = false
		sad_eyes.visible = false
		happy_char.visible = true
		flare.visible = true
		necklace.visible = true
		ap_rating.material = perfect_material
		ap_rating.text = "NICE"
		ap_rating.visible = true
		#print("Excellent rhythm!")
		
	elif hit_percentage >= 0.7:
		score_adjustment = 5
		sad_char.visible = false
		sad_eyes.visible = false
		happy_char.visible = true
		flare.visible = true
		necklace.visible = true
		ap_rating.material = ok_material
		ap_rating.text = "GOOD"
		ap_rating.visible = true
		#print("Good rhythm!")
	elif hit_percentage >= 0.4:
		score_adjustment = 0
		sad_char.visible = true
		sad_eyes.visible = true
		happy_char.visible = false
		flare.visible = false
		necklace.visible = false
		ap_rating.material = ok_material
		ap_rating.text = "UMM..."
		ap_rating.visible = true
		#print("Okay rhythm")
	elif hit_percentage >= 0.2:
		score_adjustment = -5
		sad_char.visible = true
		sad_eyes.visible = true
		happy_char.visible = false
		flare.visible = false
		necklace.visible = false
		ap_rating.material = missed_material
		ap_rating.text = "BAD"
		ap_rating.visible = true
		#print("Poor rhythm")
	else:
		score_adjustment = -10
		sad_char.visible = true
		sad_eyes.visible = true
		happy_char.visible = false
		flare.visible = false
		necklace.visible = false
		ap_rating.material = missed_material
		ap_rating.text = "TERRIBLE"
		ap_rating.visible = true
		#print("Terrible rhythm!")
	
	# Record AP score
	score += score_adjustment
	player_data.score_data(score)
	#print("Score adjusted to: " + str(score))

# AP textual feedback disappears
func _on_eval_timer_timeout():
	ap_rating.visible = false

# PLAYER INPUT LOGIC - arrow keys are mapped to playstation controller inputs
func _input(event):
	if event.is_action_pressed("ui_down"):
		_on_up_arrow_pressed()
	elif event.is_action_pressed("ui_right"):
		_on_right_arrow_pressed()
	elif event.is_action_pressed("ui_left"):
		_on_left_arrow_pressed()

func _on_up_arrow_pressed():
	if game_begun == true:
		if in_attention_phase:
			_check_attention_phase_hit()
		elif active_rects.size() > 0:
			_handle_input(UP)

func _on_right_arrow_pressed():
	# controls for when song ends
	if GlobalVars.track_finished == true:
		final_press += 1
		if final_press >= 4:
			get_tree().change_scene_to_file("res://node_2d.tscn")
			final_press = 0
	
	# main gameplay controls
	if game_begun == true:
		if in_attention_phase:
			_check_attention_phase_hit()
		elif active_rects.size() > 0:
			_handle_input(RIGHT)

func _on_left_arrow_pressed():
	if game_begun == true:
		if in_attention_phase:
			_check_attention_phase_hit()
		elif active_rects.size() > 0:
			_handle_input(LEFT)

# Unified handler for all button inputs
func _handle_input(direction: int) -> void:
	# check if there's any active rect of the given direction
	var matching_rects = []
	
	for i in range(active_rects.size()):
		if active_rects[i].direction == direction and not active_rects[i].hit:
			matching_rects.append(i)
	
	if matching_rects.size() > 0:
		# If multiple matching rects, prioritise the one ending soonest (oldest)
		var earliest_index = matching_rects[0]
		var earliest_end_time = active_rects[earliest_index].end_time
		
		for idx in matching_rects:
			if active_rects[idx].end_time < earliest_end_time:
				earliest_index = idx
				earliest_end_time = active_rects[idx].end_time
		
		# Get current time for input timing evaluation
		var current_time = audio_player.get_playback_position()
		
		# Mark rect as hit
		active_rects[earliest_index].hit = true
		
		# Get direction and instance info
		var dir = active_rects[earliest_index].direction
		var instance = active_rects[earliest_index].instance_index
		
		# Calculate timing precision
		var perfect_time = active_rects[earliest_index].perfect_time
		var perfect_end_time = active_rects[earliest_index].perfect_end_time
		var time_diff = current_time - perfect_time

		# Define an "extremely early" threshold - will not receive points
		var extremely_early_threshold = animation_warn * 0.25

		# Score the hit based on timing
		if abs(time_diff) <= perfect_timing_window:
			# Perfect timing
			# Gets 5 points if score is bad and 0.5 if score is good
			if score <= 0:
				score += 5
			else:
				score += 0.5
			# Pass score to 2dMain for tempo shifting mechanic
			player_data.score_data(score)
			print(score)
			
			# Visual and textual feedback
			hit_rating.visible = true
			hit_rating.text = "PERFECT!"
			hit_rating.material = perfect_material
			flare_anim.play("flare_spiral")
			sad_char.visible = false
			sad_eyes.visible = false
			happy_char.visible = true
			necklace.visible = true
			flare.visible = true
			
			# Record perfect input in player performance file
			global_differential = time_diff
			player_data.main_phase_data(global_differential)
			
		elif time_diff < -extremely_early_threshold:
			# Very early, big penalty
			rebalancing_penalty()
			print(score)
			
			# Visual and textual feedback
			hit_rating.visible = true
			hit_rating.text = "FAILED"
			hit_rating.material = missed_material
			sad_char.visible = true
			sad_eyes.visible = true
			happy_char.visible = false
			flare.visible = false
			necklace.visible = false
			
			# Record player performance
			global_differential = time_diff
			player_data.main_phase_data(global_differential)
			
		else:
			# OK timing
			# 2.5 points of player doing badly, 0.25 if they are doing well
			if score <= 0:
				score += 2.5
			else:
				score += 0.25
				
			# Pass score to 2dMain for tempo shifting mechanic
			player_data.score_data(score)
			print(score)
			
			# Visual and textual feedback 
			hit_rating.visible = true
			hit_rating.text = "OK..."
			hit_rating.material = ok_material
			sad_char.visible = true
			sad_eyes.visible = true
			happy_char.visible = false
			flare.visible = false
			necklace.visible = false
			
			global_differential = time_diff
			player_data.main_phase_data(global_differential)
			
		# Hide the rect
		_hide_rect(dir, instance)
		
		# Remove from active rects
		active_rects.remove_at(earliest_index)
	else:
		# If no matching rect was found for input, penalise
		rebalancing_penalty()
		
		# Visual and textual feedback
		hit_rating.text = "FAILED"
		hit_rating.material = missed_material
		sad_char.visible = true
		sad_eyes.visible = true
		happy_char.visible = false
		flare.visible = false
		necklace.visible = false

func rebalancing_penalty() -> void:
	# 'Rubber bands' poorly performing players to help them catch up
	# Penalises top performing players harshly so the tempo slows and they are not overwhelmed.
	if score >= 20 and score < 50:
		score -= 8
		player_data.score_data(score)
	elif score >= 50:
		score -= 15
		player_data.score_data(score)
	else:
		score -= 2
		player_data.score_data(score)

# Check if any key hit during attention phase aligns with onsets
func _check_attention_phase_hit() -> void:
	var current_time = audio_player.get_playback_position()
	var hit = false
	var hit_onset_time = 0.0
	
	for i in range(attention_phase_onsets.size()):
		var onset_time = attention_phase_onsets[i]
		# Check if input is within timing window of any onset
		if abs(current_time - onset_time) <= attention_input_window:
			# Award points
			attention_phase_hits += 1
			hit_onset_time = onset_time
			attention_phase_onsets.remove_at(i)
			hit = true
			
			# Colour the corresponding drum sprite green for hit
			if onset_sprite_map.has(hit_onset_time) and onset_sprite_map[hit_onset_time] < drum_sprites.size():
				var sprite_index = onset_sprite_map[hit_onset_time]
				drum_sprites[sprite_index].material = good_sing
				
				# Animate drum sprite in response to hit
				var tween = create_tween()
				tween.tween_property(drum_sprites[sprite_index], "scale", Vector2(0.05, 0.05), 0.1)
				tween.tween_property(drum_sprites[sprite_index], "scale", Vector2(0.04, 0.04), 0.1)
				
				print("Attention phase hit! Current hits: " + str(attention_phase_hits))
			break
	
	if not hit:
		print("Attention phase miss!")

# Find the next beat index in the original beats array
func find_next_beat_index(current_time: float) -> int:
	for i in range(original_beats.size()):
		if original_beats[i] >= current_time:
			return i
	# If can't find a future beat, return the last beat index
	return original_beats.size() - 1

func get_attention_phase_chance(tier: int) -> float:
	match tier:
		1: return 0.01  # 1% chance in easiest segment
		2: return 0.01  
		3: return 0.01 
		4: return 0.015 # 1.5% chance
		_: return 0.01  # Default

func get_singing_phase_chance(tier: int) -> float:
	match tier:
		1: return 0.005  # 0.5% chance 
		2: return 0.01  # 1% chance 
		3: return 0.015 # 1.5% chance 
		4: return 0.01 # 1% chance 
		_: return 0.01  # Default

func _hide_all_visible_rects() -> void:
	for i in range(active_rects.size()):
		var rect = active_rects[i]
		_hide_rect(rect.direction, rect.instance_index)
		# Mark as hit to prevent penalty
		rect.hit = true
	
	# Clear the active rects array
	active_rects.clear()

# Spawn drum sprites for drumming event/AP
func spawn_sprites(array):
	# Clear previous sprites if any
	delete_sprites()
	onset_sprite_map.clear()
	
	# Spawn a sprite for each element in the array
	for i in range(array.size()):
		var sprite = Sprite2D.new()
		sprite.texture = drum_tex
		
		# Position each sprite
		sprite.scale = Vector2(0.04, 0.04)
		
		# Set default color (white)
		sprite.modulate = default_color
		
		# Calculate row and column numbers to arrange sprites
		var row = i / 7 
		var col = i % 7  
		
		# Position sprites close together
		var spacing_x = 80 
		var spacing_y = 80
		var base_x = 85
		var base_y = 470
		sprite.position = Vector2(base_x + col * spacing_x, base_y + row * spacing_y)
		
		# Add the sprite to the scene
		add_child(sprite)
		
		# Store reference to the sprite
		drum_sprites.append(sprite)
		
		# Map the onset time to this sprite index
		onset_sprite_map[array[i]] = i

func delete_sprites():
	# Remove all sprites
	for sprite in drum_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	
	# Clear the array
	drum_sprites.clear()

func _process_singing_phase_frequencies(current_time: float) -> void:
	# if not at the end of singing phase
	if in_singing_phase and sp_beat_index < sp_frequencies.size():
		
		# check player singing on every beat 
		var song_time_for_this_note = beats[sp_start_index + sp_beat_index]
		if current_time >= song_time_for_this_note:
			
			var player_freq = sp_analyse.get_current_frequency()
			print("player: " + str(player_freq))
			
			# show player frequency on screen
			player_sing_label.text = str(int(player_freq))
			
			# show target frequency on screen, multiplied according to tempo (which has changed)
			var target_freq = GlobalVars.speed * sp_frequencies[sp_beat_index]
			print("target: " + str(target_freq))
			
			# allow for players to sing at different octaves by first checking for very high pitch
			target_freq = target_freq * 4
			var target_freqs = []
			
			for i in range(6):
				
				target_freqs.append(target_freq)
				
				# 15% tolerance on player frequencies to get points
				var tolerance = 0.15 * target_freq
				
				# get a point for every beat were frequency sung is within tolerance
				if player_freq >= (target_freq - tolerance) and player_freq <= (target_freq + tolerance):
					score += 1
					
					# record player points in player performance stats
					player_data.score_data(score)
					
					# green microphone simple when points gained
					mic_sprite.material = good_sing
					
					# check next octave down in next iteration
					target_freq = target_freq / 2
					if target_freqs.size() < 6:
						for k in range(6 - (i + 1)):
							target_freqs.append(target_freq)
							target_freq = target_freq / 2
					
					break
				
				else:
					# frequency sung by player was not within theshold
					# microhpone goes red
					mic_sprite.material = bad_sing
					# check next octave down in next iteration
					target_freq = target_freq / 2
			
			# find closest octave to player's sung frequency to print this as target freq on-screen
			var best_fit = target_freqs[0]
			for j in range(5):
				if abs(player_freq - target_freqs[j + 1]) < abs(player_freq - best_fit):
					best_fit = target_freqs[j + 1]
			target_sing_label.text = str(int(best_fit))
			
			# evaluate player pitch (frequency) and give textual feedback
			var tolerance2 = 0.15 * best_fit
			if player_freq >= (best_fit - tolerance2) and player_freq <= (best_fit + tolerance2):
				advice_sing_label.text = "PERFECT"
				advice_sing_label.material = good_sing
				sp_score += 1 # 1 point
			elif player_freq <= best_fit:
				advice_sing_label.text = "TOO LOW"
				advice_sing_label.material = bad_sing
				# no points
			elif player_freq >= best_fit:
				advice_sing_label.text = "TOO HIGH"
				advice_sing_label.material = bad_sing
				# no points
			
			# iterate and wait for next beat to check player pitch (freq) again
			sp_beat_index += 1
