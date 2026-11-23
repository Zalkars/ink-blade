extends SceneTree

const Audit := preload("res://tools/content_audit.gd")


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--root")
	var overlay := args[index + 1] if index >= 0 and index + 1 < args.size() else ""
	if index >= 0 and (overlay.is_empty() or not DirAccess.dir_exists_absolute(overlay)):
		printerr("validator: --root должен указывать на каталог с фикстурой")
		quit(1)
		return
	var audit := Audit.new()
	audit.inspect(overlay)
	var saved := LevelData.read_json(audit._resolve(Audit.MANIFEST))
	var expected: Variant = JSON.parse_string(JSON.stringify(audit.manifest))
	if saved != expected:
		audit.errors.append(Audit.MANIFEST + ": устаревший манифест")
	for error in audit.errors:
		printerr(error)
	print("CONTENT_VALIDATE_RESULT=%s" % ("OK" if audit.errors.is_empty() else "FAIL"))
	quit(0 if audit.errors.is_empty() else 1)
