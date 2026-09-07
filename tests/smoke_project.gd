extends SceneTree

# Mechanical smoke test only. This proves that the project parses, the main scene
# can be instantiated and its _ready() path can execute in a headless desktop
# environment. It does NOT validate any iPhone capability.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("SMOKE_FAIL: main scene could not be loaded")
		quit(1)
		return

	var instance := packed.instantiate()
	if instance == null:
		push_error("SMOKE_FAIL: main scene could not be instantiated")
		quit(1)
		return

	get_root().add_child(instance)
	await process_frame
	await process_frame

	if not is_instance_valid(instance):
		push_error("SMOKE_FAIL: main scene became invalid")
		quit(1)
		return

	print("SMOKE_PASS: project parsed and main scene instantiated")
	quit(0)
