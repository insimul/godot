class_name InsimulMicrophone
extends Node
## InsimulMicrophone — Wraps Godot's AudioEffectCapture for microphone input.
##
## Records audio from the microphone and provides it as a PackedByteArray
## suitable for sending to the Insimul conversation service.

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted when recording starts.
signal recording_started()
## Emitted when recording stops, with the captured audio data.
signal recording_stopped(audio_data: PackedByteArray)

# ── Export Variables ──────────────────────────────────────────────────────────

## Audio bus name for the microphone input. Must have an AudioEffectCapture.
@export var audio_bus_name: String = "Microphone"
## Sample rate for recording (must match AudioEffectCapture bus sample rate).
@export var sample_rate: int = 16000

# ── State ────────────────────────────────────────────────────────────────────

var _is_recording: bool = false
var _audio_effect_capture: AudioEffectCapture = null
var _recorded_frames: PackedVector2Array = PackedVector2Array()
var _mic_player: AudioStreamPlayer = null


func _ready() -> void:
	_setup_microphone()


# ── Public API ───────────────────────────────────────────────────────────────

## Start recording audio from the microphone.
func start_recording() -> void:
	if _is_recording:
		return
	if _audio_effect_capture == null:
		push_error("InsimulMicrophone: AudioEffectCapture not found on bus '%s'." % audio_bus_name)
		return
	_recorded_frames = PackedVector2Array()
	_audio_effect_capture.clear_buffer()
	_is_recording = true
	# Start the mic player so audio flows through the bus
	if _mic_player != null and not _mic_player.playing:
		_mic_player.play()
	recording_started.emit()


## Stop recording and return the captured audio as PCM16 bytes.
func stop_recording() -> PackedByteArray:
	if not _is_recording:
		return PackedByteArray()
	_is_recording = false
	# Capture any remaining frames
	_capture_available_frames()
	if _mic_player != null:
		_mic_player.stop()
	var pcm_data := _frames_to_pcm16(_recorded_frames)
	recording_stopped.emit(pcm_data)
	return pcm_data


## Whether the microphone is currently recording.
func is_recording() -> bool:
	return _is_recording


func _process(_delta: float) -> void:
	if _is_recording:
		_capture_available_frames()


# ── Internal ─────────────────────────────────────────────────────────────────

func _setup_microphone() -> void:
	# Find or create the microphone audio bus
	var bus_idx := AudioServer.get_bus_index(audio_bus_name)
	if bus_idx == -1:
		# Create the bus
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, audio_bus_name)
		AudioServer.set_bus_mute(bus_idx, true)  # Don't play mic back to speakers
		# Add capture effect
		var capture := AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus_idx, capture)
		_audio_effect_capture = capture
	else:
		# Find existing capture effect
		for i in range(AudioServer.get_bus_effect_count(bus_idx)):
			var effect := AudioServer.get_bus_effect(bus_idx, i)
			if effect is AudioEffectCapture:
				_audio_effect_capture = effect as AudioEffectCapture
				break
		if _audio_effect_capture == null:
			var capture := AudioEffectCapture.new()
			AudioServer.add_bus_effect(bus_idx, capture)
			_audio_effect_capture = capture

	# Create an AudioStreamPlayer with AudioStreamMicrophone
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = audio_bus_name
	add_child(_mic_player)


func _capture_available_frames() -> void:
	if _audio_effect_capture == null:
		return
	var frames_available := _audio_effect_capture.get_frames_available()
	if frames_available > 0:
		var frames := _audio_effect_capture.get_buffer(frames_available)
		_recorded_frames.append_array(frames)


func _frames_to_pcm16(frames: PackedVector2Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 2)  # 16-bit mono = 2 bytes per sample
	for i in range(frames.size()):
		# Mix stereo to mono and convert to 16-bit integer
		var sample := (frames[i].x + frames[i].y) * 0.5
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, int_sample)
	return pcm
