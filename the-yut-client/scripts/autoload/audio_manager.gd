extends Node

# Placeholder audio manager — will be connected to real audio assets later

func play_sfx(sfx_name: String) -> void:
	print("[Audio] SFX: ", sfx_name)

func play_bgm() -> void:
	print("[Audio] BGM started")

func stop_bgm() -> void:
	print("[Audio] BGM stopped")
