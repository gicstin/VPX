extends RefCounted


class TrackedPanel extends FloatPanel:
	var writes := 0

	func _apply_opacity() -> void:
		writes += 1
		super._apply_opacity()


class ReferencePanel extends TrackedPanel:
	func _process(delta: float) -> void:
		if not visible:
			return
		var rate := FADE_IN_RATE if target_opacity > opacity else FADE_OUT_RATE
		opacity = lerpf(opacity, target_opacity, 1.0 - exp(-delta * rate))
		if absf(opacity - target_opacity) < FADE_SNAP:
			opacity = target_opacity
		_apply_opacity()
		if opacity <= 0.0 and target_opacity <= 0.0:
			visible = false
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


class ReferenceVisualizer extends "res://scripts/music_visualizer.gd":
	func _smooth_levels(delta: float) -> void:
		for i in BANDS:
			var blend := 1.0 - exp(-delta * (60.0 if targets[i] > levels[i] else 10.0))
			levels[i] = lerpf(levels[i], targets[i], blend)


class ReferencePlayer extends "res://scripts/player.gd":
	func _process(delta: float) -> void:
		for task in source_tasks.duplicate():
			if WorkerThreadPool.is_task_completed(task):
				WorkerThreadPool.wait_for_task_completion(task)
				source_tasks.erase(task)
		if not discarded_streams.is_empty():
			discarded_streams = discarded_streams.filter(func(video: FFmpegVideoStream) -> bool: return video.get_open_status() == 1)
		retired_streams = retired_streams.filter(func(video: FFmpegVideoStream) -> bool: return not video.get_playback().is_io_stopped())
		if image_loader != null:
			_poll_image()
		elif not prefetched.is_empty():
			_poll_prefetch()
		if not discarded_loaders.is_empty():
			discarded_loaders = discarded_loaders.filter(func(loader: VPXPanorama) -> bool: return not loader.is_decoded())
		if paused and playback != null and not current_path.is_empty():
			playback.pump_paused(delta)
		_monitor_stream(delta)
		_update_radio_metadata(delta)
		_update_sleep(delta)
		if current_path.is_empty() or paused or not is_playing():
			return
		if loop_b > loop_a and loop_a >= 0.0 and stream_position >= loop_b:
			seek_to(loop_a)
		save_timer += delta
		if save_timer >= POSITION_SAVE_INTERVAL:
			save_timer = 0.0
			remember_position()


class ReferenceTracks extends "res://scripts/media_tracks.gd":
	func _process(_delta: float) -> void:
		for task in subtitle_tasks.duplicate():
			if WorkerThreadPool.is_task_completed(task):
				WorkerThreadPool.wait_for_task_completion(task)
				subtitle_tasks.erase(task)


class ReferenceScreen extends "res://scripts/screen.gd":
	func _process(delta: float) -> void:
		material.set_shader_parameter("visualizer_media_dim", 1.0 - Settings.visualizer_background_dim if player.is_visualizer_overlay_active() else 1.0)
		_update_zoom(delta)
		if Settings.projection != Settings.ProjectionMode.FLAT and is_instance_valid(view_origin):
			global_position = view_origin.global_position
		if player.is_image():
			visible = true
			if bound_image != player.image:
				_bind_image(player.image, player.image_info)
			return
		if bound_image != null:
			bound_image = null
			material.set_shader_parameter("picture_source", 0)
			refresh()
		var playback := player.playback
		var texture := player.get_video_texture()
		var has_video := playback != null and texture != null and texture.get_height() > 0
		var immersive_music := player.is_immersive_visualizer_active() and not player.is_visualizer_overlay_active()
		visible = has_video and not hidden_by_layer and not immersive_music
		if not has_video:
			return
		var state: Dictionary = playback.get_frame_state()
		var serial := int(state.get("serial", 0))
		refreshes_since_frame += 1
		if playback != bound_playback or serial != bound_serial:
			if playback == bound_playback and not player.paused:
				Log.note_cadence(refreshes_since_frame)
			refreshes_since_frame = 0
			_bind_frame(playback, int(state.get("set", 0)))
			_track_video_frame(playback, float(state.get("time_msec", 0.0)))
			bound_playback = playback
			bound_serial = serial
			if _geometry_key() != geometry_key:
				refresh()
		probe.tick(delta, bound_serial >= 0)
		material.set_shader_parameter("frame_seed", float(bound_serial % 997) * 0.618)


