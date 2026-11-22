extends RefCounted

## Real clipped strokes avoid relying on a repeated texture in viewport baking.
static func engrave(polygon: Array, gap: float, color: Color, alpha: float) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var extent := bounds.size.length() + 20.0
	var direction := Vector2(0.7, -0.714)
	var normal := Vector2(-direction.y, direction.x)
	var center := bounds.get_center()
	var offset := -extent
	var index := 0
	while offset <= extent:
		var origin := center + normal * offset
		var segments := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([origin - direction * extent, origin + direction * extent]), PackedVector2Array(polygon))
		for segment in segments:
			if segment.size() > 1:
				InkR.poly(Array(segment), 0.8 if index % 3 else 1.25, color, alpha * (0.65 if index % 4 == 0 else 1.0), 0.55)
		offset += gap
		index += 1

## Wrapped paragraphs shared by the painted screens; coordinates stay inside safe area.
static func paragraph(canvas: CanvasItem, font: Font, text: String, rect: Rect2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var paragraph := TextParagraph.new()
	paragraph.alignment = alignment
	paragraph.width = rect.size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(text, font, font_size)
	while paragraph.get_size().y > rect.size.y and font_size > 18:
		font_size -= 1
		paragraph.clear()
		paragraph.add_string(text, font, font_size)
	paragraph.draw(canvas.get_canvas_item(), rect.position, color)
