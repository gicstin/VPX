extends RefCounted


class ReferenceField extends ResonanceField:
	func _update_history(delta: float) -> void:
		var previous := channel_levels.duplicate()
		for channel in 2:
			for domain in 3:
				var speed := 45.0 if channel_targets[channel][domain] > channel_levels[channel][domain] else 14.0
				channel_levels[channel][domain] = lerpf(channel_levels[channel][domain], channel_targets[channel][domain], 1.0 - exp(-delta * speed))
		if not has_audio:
			return
		history_elapsed += delta
		var wrote := false
		while history_elapsed >= 1.0 / HISTORY_RATE:
			history_elapsed -= 1.0 / HISTORY_RATE
			for channel in 2:
				var energy: Vector3 = previous[channel].lerp(channel_levels[channel], clampf(1.0 - history_elapsed / maxf(delta, 0.00001), 0.0, 1.0))
				history_image.set_pixel(history_position, channel, Color(energy.x, energy.y, energy.z, maxf(energy.x, maxf(energy.y, energy.z))))
			history_position = (history_position + 1) % HISTORY_SAMPLES
			wrote = true
		if wrote:
			history_texture.update(history_image)

	func _update_spectral_history(delta: float) -> void:
		if not has_audio:
			return
		spectral_history_duration = minf(4.2, spectral_history_duration + delta)
		spectral_history_elapsed += delta
		var wrote := false
		while spectral_history_elapsed >= 1.0 / SPECTRAL_HISTORY_RATE:
			spectral_history_elapsed -= 1.0 / SPECTRAL_HISTORY_RATE
			for channel in 2:
				for band in BANDS:
					spectral_history_image.set_pixel(band, channel * HISTORY_SAMPLES + spectral_history_position, Color(spectrum_levels[channel * BANDS + band], 0, 0, 0))
			spectral_history_position = (spectral_history_position + 1) % HISTORY_SAMPLES
			wrote = true
		if wrote:
			spectral_history_texture.update(spectral_history_image)


class ReferenceStereo extends StereoImage:
	func update(delta: float) -> void:
		scope_elapsed += delta
		scope_delta += delta
		var attack := 1.0 - exp(-delta * 35.0)
		var release := 1.0 - exp(-delta * 9.0)
		var steer := 1.0 - exp(-delta * 10.0)
		var sum := Vector2.ZERO
		for band in BANDS:
			left_levels[band] = lerpf(left_levels[band], left_targets[band], attack if left_targets[band] > left_levels[band] else release)
			right_levels[band] = lerpf(right_levels[band], right_targets[band], attack if right_targets[band] > right_levels[band] else release)
			levels[band] = maxf(left_levels[band], right_levels[band])
			var left := _power(left_levels[band])
			var right := _power(right_levels[band])
			if left + right > 0.000001:
				pans[band] = lerpf(pans[band], 0.0 if mono else _expand((right - left) / (right + left)), steer * clampf(levels[band] * 3.0, 0.2, 1.0))
			sum += Vector2(left_levels[band], right_levels[band]) / BANDS
		channel_balance = sum
		for slot in slots:
			slot.level = lerpf(slot.level, slot.target, 1.0 - exp(-delta * (20.0 if slot.target > slot.level else 5.0)))
			slot.burst.z = minf(9.0, slot.burst.z + delta)
			slot.flash *= exp(-delta * 8.0)
			if slot.alive:
				slot.age += delta
			elif slot.level < 0.01:
				slot.level = 0.0
		if active:
			var ticks := band_ring.due(delta)
			correlation_ring.elapsed = band_ring.elapsed
			field_ring.elapsed = band_ring.elapsed
			source_ring.elapsed = band_ring.elapsed
			for tick in ticks:
				_identify()
				_write_rows()
			if ticks > 0:
				correlation_ring.texture.update(correlation_ring.image)
				band_ring.texture.update(band_ring.image)
				field_ring.texture.update(field_ring.image)
				source_ring.texture.update(source_ring.image)
		_publish()

	func _write_rows() -> void:
		var energy := PackedFloat32Array()
		energy.resize(PAN_BINS)
		var tone := PackedFloat32Array()
		tone.resize(PAN_BINS)
		var side := 0.0
		var total := 0.0
		var pan_sum := 0.0
		for band in BANDS:
			var left := sqrt(_power(left_levels[band]))
			var right := sqrt(_power(right_levels[band]))
			side += absf(right - left)
			total += right + left
			var weight := _weight(levels[band])
			band_ring.row[band] = Color(pans[band], levels[band], left_levels[band], right_levels[band])
			if weight <= 0.0:
				continue
			pan_sum += pans[band] * weight
			var centre := (pans[band] * 0.5 + 0.5) * (PAN_BINS - 1)
			for bin in range(maxi(0, int(centre) - 6), mini(PAN_BINS - 1, int(centre) + 7) + 1):
				var spread := (bin - centre) / 2.2
				var share := exp(-spread * spread) * weight
				energy[bin] += share
				tone[bin] += share * band / float(BANDS - 1)
		width = lerpf(width, side / maxf(total, 0.000001), 0.25)
		var weights := 0.0
		for band in BANDS:
			weights += _weight(levels[band])
		balance = lerpf(balance, pan_sum / weights if weights > 0.0 else 0.0, 0.2)
		for bin in PAN_BINS:
			field_ring.row[bin] = Color(energy[bin], tone[bin] / energy[bin] if energy[bin] > 0.0 else 0.5, 0.0, width)
		for i in SLOTS:
			var slot := slots[i]
			source_ring.row[i] = Color(slot.pan, slot.band, slot.level, slot.hue)
		correlation_ring.row[0] = Color(correlation, maxf(channel_balance.x, channel_balance.y), 0.0, 0.0)
		correlation_ring.write()
		band_ring.write()
		field_ring.write()
		source_ring.write()


class TrackedRemote extends "res://scripts/remote_control.gd":
	var status_calls := 0

	func _status() -> Dictionary:
		status_calls += 1
		return super._status()


class ReferenceRemote extends TrackedRemote:
	func _process(delta: float) -> void:
		if server == null:
			return
		while server.is_connection_available():
			var client := server.take_connection()
			client.set_no_delay(true)
			clients.append(client)
			buffers.append(PackedByteArray())
			Log.info("remote control: client %s connected" % client.get_connected_host())
			clients_changed.emit(clients.size())
			_send(client, _status())
		for i in range(clients.size() - 1, -1, -1):
			var client := clients[i]
			client.poll()
			if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				clients.remove_at(i)
				buffers.remove_at(i)
				outgoing.erase(client)
				Log.info("remote control: client disconnected")
				clients_changed.emit(clients.size())
				continue
			var available := client.get_available_bytes()
			if available > 0:
				var chunk := client.get_data(available)
				if chunk[0] == OK:
					buffers[i].append_array(chunk[1])
					_drain(i)
		status_timer += delta
		var status := _status()
		var text := "%s|%s|%s" % [status.get("path", ""), status.get("playerState", -1), status.get("playbackSpeed", 1.0)]
		var now := Time.get_ticks_msec()
		var expected := sent_time + (float(now - sent_msec) / 1000.0 * Settings.playback_speed if int(status.get("playerState", STATE_PAUSED)) == STATE_PLAYING else 0.0)
		var jumped := absf(float(status.get("currentTime", 0.0)) - expected) > 0.75
		if status_timer >= STATUS_INTERVAL or text != last_status or jumped:
			status_timer = 0.0
			last_status = text
			sent_time = float(status.get("currentTime", 0.0))
			sent_msec = now
			for client in clients:
				_send(client, status)
		for client in clients:
			_flush(client)
