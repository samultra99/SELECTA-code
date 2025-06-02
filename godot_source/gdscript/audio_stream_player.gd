extends AudioStreamPlayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
# Find the parent (Node2D) and connect the signal
	var parent_node = get_parent()
	if parent_node.has_signal("file_path_selected"):
		parent_node.file_path_selected.connect(Callable(self, "_on_file_path_selected"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_file_path_selected(path: String) -> void:
	print("Received audio path: ", path)
	var audio_stream = load_audio_file(path)
	if audio_stream:
		stream = audio_stream
		play()
	else:
		print("Failed to load audio")

func load_audio_file(path: String) -> AudioStream:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Failed to open file: ", path)
		return null

	var extension = path.get_extension().to_lower()

	if extension == "wav":
		var audio_stream = AudioStreamWAV.new()
		audio_stream.data = file.get_buffer(file.get_length())
		return audio_stream

	elif extension == "mp3" or extension == "flac":
		print("Support for %s may require custom plugins or GDExtensions." % extension)
		return null

	print("Unsupported audio format: ", extension)
	return null
