class_name PopupDismiss


static func outside_press(viewport: Viewport, event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return false
	var dismissed := false
	for window in viewport.get_embedded_subwindows():
		var popup := window as Popup
		if popup != null and popup.visible and not Rect2(popup.position, popup.size).has_point(button.position):
			popup.hide()
			dismissed = true
	return dismissed
