# Singing Analysis class by Samuel Shipp
# Takes microhpone input continously, runs FFT, outputs dominant frequency at runtime

extends Node

# mic capture bus and variables
var bus_idx = AudioServer.get_bus_index("MicCapture")
var SAMPLE_RATE := AudioServer.get_mix_rate()
var capture = AudioEffectCapture.new()
var mic_player = AudioStreamPlayer.new()

# prepare for fft
const FFT_SIZE = 1024  
const MIN_HZ := 80.0
const MAX_HZ := 1100.0
var stereo_samples := PackedVector2Array()
var mono := PackedFloat32Array()
var windowed := PackedFloat32Array()
# precompute window + bin limits
var hann_window := PackedFloat32Array()

# frequency bins
var min_bin := 0
var max_bin := 0
var current_frequency := 0.0

var analysing = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# not activated yet, mic capture is an 'effect' in Godot
	AudioServer.add_bus_effect(bus_idx, capture)
	AudioServer.set_bus_mute(bus_idx, true)
	
	# resize intermediary buffers
	mono.resize(FFT_SIZE)
	windowed.resize(FFT_SIZE)
	
	# precompute Hann window once
	hann_window.resize(FFT_SIZE)
	for i in range(FFT_SIZE):
		hann_window[i] = 0.5 * (1.0 - cos(2.0 * PI * float(i) / float(FFT_SIZE - 1)))
	
	# compute human-voice bin limits for fft
	min_bin = int(MIN_HZ * FFT_SIZE / SAMPLE_RATE)
	max_bin = int(MAX_HZ * FFT_SIZE / SAMPLE_RATE)
	min_bin = clamp(min_bin, 1, FFT_SIZE/2 - 1)
	max_bin = clamp(max_bin, 1, FFT_SIZE/2 - 1)

func begin_analysis() -> void:
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "MicCapture"
	add_child(mic_player)
	mic_player.play()
	analysing = true

func stop_analysis() -> void:
	mic_player.stop()
	capture.clear_buffer()
	remove_child(mic_player)
	analysing = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func process_singing() -> float:
	var available = capture.get_frames_available()
	
	# if we're more than 2 buffers behind, drop one buffer then record into buffer until size limit reached
	if available > FFT_SIZE * 2:
		capture.get_buffer(FFT_SIZE)  
		available = capture.get_frames_available()
	
	# record into buffer until size limit reached
	if available >= FFT_SIZE:
		# Get the actual buffer data
		stereo_samples = capture.get_buffer(FFT_SIZE)
		
		for i in range(FFT_SIZE):
			mono[i] = (stereo_samples[i].x + stereo_samples[i].y) * 0.5
			# Apply the precomputed Hann window
			windowed[i] = mono[i] * hann_window[i]
		
		# run the FFT 
		var spectrum: Array = FFT.fft(Array(windowed))
		
		# pull real & imag parts
		var reals: Array = FFT.reals(spectrum)
		var imags: Array = FFT.imags(spectrum)
		
		# only search between human voice bins for dominant frequency (max freq bin)
		var max_bin_idx = min_bin
		var max_val = sqrt(reals[min_bin] * reals[min_bin] + imags[min_bin] * imags[min_bin])
		for k in range(min_bin + 1, max_bin):
			var mag = sqrt(reals[k] * reals[k] + imags[k] * imags[k])
			if mag > max_val:
				max_val = mag
				max_bin_idx = k
		
		# convert bin to Hz
		var freq = float(max_bin_idx) * SAMPLE_RATE / float(FFT_SIZE)
		return freq
	
	return current_frequency  # Return the previous frequency if we don't have enough samples

# pass current frequency to other classes
func get_current_frequency() -> float:
	if analysing:
		if mic_player.is_playing():
			current_frequency = process_singing()
	return current_frequency
