class_name InsimulTypes
extends RefCounted
## Shared type definitions for the Insimul conversation service.
## Mirrors the SSE event protocol used by all Insimul SDKs.


# ── Provider Enums (matching JS SDK and Unreal/Unity plugins) ────────────────

## Where LLM inference runs.
enum ChatProvider {
	SERVER = 0,  ## Insimul server via HTTP/SSE (Gemini LLM)
	LOCAL = 1,   ## Local LLM (GDLlama in-process or Ollama/llama.cpp HTTP)
}

## Where TTS audio is synthesized.
enum TTSProvider {
	SERVER = 0,  ## Server-side TTS (audio streams inline with chat)
	LOCAL = 1,   ## Local TTS (platform native or external)
	NONE = 2,    ## TTS disabled
}

## Where player voice is transcribed.
enum STTProvider {
	SERVER = 0,  ## Server-side STT
	LOCAL = 1,   ## Local STT (platform native or external)
	NONE = 2,    ## STT disabled
}

# ── Core Enums ───────────────────────────────────────────────────────────────

enum AudioEncoding {
	UNSPECIFIED = 0,
	PCM = 1,
	OPUS = 2,
	MP3 = 3,
}

enum ConversationState {
	UNSPECIFIED = 0,
	STARTED = 1,
	ACTIVE = 2,
	PAUSED = 3,
	ENDED = 4,
}


# ── Data Classes ─────────────────────────────────────────────────────────────

class TextChunk:
	var text: String = ""
	var is_final: bool = false
	var language_code: String = ""
	var session_id: String = ""


class AudioChunk:
	var data: PackedByteArray = PackedByteArray()
	var encoding: int = AudioEncoding.UNSPECIFIED
	var sample_rate: int = 16000
	var duration_ms: int = 0


class Viseme:
	var phoneme: String = ""
	var weight: float = 0.0
	var duration_ms: int = 0


class FacialData:
	var visemes: Array = []


class ActionTrigger:
	var action_type: String = ""
	var target_id: String = ""
	var parameters: Dictionary = {}


class HealthCheckResponse:
	var healthy: bool = false
	var version: String = ""
	var services: Dictionary = {}


# ── Dialogue Context (for offline mode) ──────────────────────────────────────

class DialogueTruth:
	var title: String = ""
	var content: String = ""


class DialogueContext:
	var character_id: String = ""
	var character_name: String = ""
	var system_prompt: String = ""
	var greeting: String = ""
	var voice: String = ""
	var truths: Array = []


class ExportedCharacter:
	var character_id: String = ""
	var first_name: String = ""
	var last_name: String = ""
	var gender: String = ""
	var occupation: String = ""
	var birth_year: int = 0
	var is_alive: bool = true
	var openness: float = 0.0
	var conscientiousness: float = 0.0
	var extroversion: float = 0.0
	var agreeableness: float = 0.0
	var neuroticism: float = 0.0


class ExportedWorld:
	var world_name: String = ""
	var world_id: String = ""
	var characters: Array = []
	var dialogue_contexts: Array = []

	func find_dialogue_context(character_id: String) -> DialogueContext:
		for ctx in dialogue_contexts:
			if ctx.character_id == character_id:
				return ctx
		return null

	func find_character(character_id: String) -> ExportedCharacter:
		for c in characters:
			if c.character_id == character_id:
				return c
		return null
