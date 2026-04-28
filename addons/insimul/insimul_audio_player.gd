class_name InsimulAudioPlayer
extends Node
## InsimulAudioPlayer — Streams TTS audio chunks to an AudioStreamPlayer3D.
##
## Buffers incoming audio chunks and plays them sequentially for seamless
## NPC speech playback with spatial audio support.

# ── Signals ──────────────────────────────────────────────────────────────────

signal playback_started()
signal chunk_played(index: int)
signal playback_completed()

# ── Export Variables ──────────────────────────────────────────────────────────

## Number of chunks to buffer before starting playback.
@export var prebuffer_count: int = 2
## Maximum distance at which audio is heard (spatial audio).
@export var max_distance: float = 50.0

# ── State ────────────────────────────────────────────────────────────────────

var _audio_player: AudioStreamPlayer3D = null
var _queue: Array[InsimulTypes.AudioChunk] = []
var _is_playing: bool = false
var _chunks_played: int = 0
var _buffering: bool = true


func _ready() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.max_distance = max_distance
	_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)


# ── Public API ───────────────────────────────────────────────────────────────

## Queue an audio chunk for playback.
func queue_chunk(chunk: InsimulTypes.AudioChunk) -> void:
	_queue.append(chunk)
	if _buffering and _queue.size() >= prebuffer_count:
		_buffering = false
		_play_next()


## Stop all playback and clear the queue.
func stop() -> void:
	_audio_player.stop()
	_queue.clear()
	_is_playing = false
	_buffering = true
	_chunks_played = 0


## Reset for a new conversation.
func reset() -> void:
	stop()


## Whether audio is currently playing.
func is_playing() -> bool:
	return _is_playing


# ── Internal ─────────────────────────────────────────────────────────────────

func _play_next() -> void:
	if _queue.is_empty():
		_is_playing = false
		playback_completed.emit()
		_buffering = true
		_chunks_played = 0
		return

	var chunk := _queue.pop_front() as InsimulTypes.AudioChunk
	var stream := _create_audio_stream(chunk)
	if stream == null:
		# Skip unplayable chunks
		_play_next()
		return

	if not _is_playing:
		_is_playing = true
		playback_started.emit()

	_audio_player.stream = stream
	_audio_player.play()
	_chunks_played += 1
	chunk_played.emit(_chunks_played)


func _on_audio_finished() -> void:
	_play_next()


func _create_audio_stream(chunk: InsimulTypes.AudioChunk) -> AudioStream:
	# Create an AudioStreamWAV from raw PCM data
	# The server sends PCM16 audio; other encodings would need decoding
	match chunk.encoding:
		InsimulTypes.AudioEncoding.PCM:
			return _create_pcm_stream(chunk)
		InsimulTypes.AudioEncoding.MP3:
			return _create_mp3_stream(chunk)
		_:
			# For OPUS or unknown, try as PCM
			return _create_pcm_stream(chunk)


func _create_pcm_stream(chunk: InsimulTypes.AudioChunk) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = chunk.sample_rate
	stream.stereo = false
	stream.data = chunk.data
	return stream


func _create_mp3_stream(chunk: InsimulTypes.AudioChunk) -> AudioStream:
	# Godot 4.x supports AudioStreamMP3
	var stream := AudioStreamMP3.new()
	stream.data = chunk.data
	return stream
