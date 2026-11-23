extends SceneTree

const Audit := preload("res://tools/content_audit.gd")


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var audit := Audit.new()
	audit.inspect()
	if not audit.errors.is_empty():
		for error in audit.errors:
			printerr(error)
		quit(1)
		return
	var temporary := Audit.MANIFEST + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		printerr("manifest: не удалось открыть " + temporary)
		quit(1)
		return
	file.store_string(JSON.stringify(audit.manifest, "  ") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, Audit.MANIFEST) != OK:
		printerr("manifest: не удалось заменить " + Audit.MANIFEST)
		quit(1)
		return
	print("CONTENT_MANIFEST_RESULT=OK")
	quit()
