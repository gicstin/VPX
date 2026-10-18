# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.2] - 2026-10-18

### Added

- Ten immersive studio visualisation presets for stereo spectrum, phase, channel history, frequency panning, transients and L/R spectral differences, mid/side waveforms, correlation history and pan trails, with scene previews.
- Rename bookmarks and reuse previous names across media, with desktop and VR text entry.
- Scene thumbnails and a visual music scene picker in desktop and VR music controls and settings.

### Changed

- Move studio visualisation guides into wrapped dropdown hover information boxes and remove permanent labels from the visual scenes.
- Make the scene dropdown taller and scale previews to the full card width while preserving their aspect ratio.
- Expand the mini-player scene dropdown to its full content width, rename its off action to Disable Visualisation and keep preview captions readable on bright accent colours.
- Combine immersive music enablement and scene selection in one compact button, with previews only in the dropdown and a pinned Disabled entry.
- Cycle music scenes with F / Shift+F and VR format shortcuts during audio playback, with the current scene shown in shortcut feedback.

### Removed

- Immersive music visualiser overlays over photos and panoramas, including their setting.

### Fixed

- Preserve album-cover proportions in the collapsed music player and regenerate stretched cached audio thumbnails.
- Keep the immersive selector visible in the music mini player over photos and panoramas; selecting a scene replaces the image while music continues.
- Keep saved subtitle sizes editable and restore them only when changing format.
- Preserve language and forced subtitle suffixes, Subs-folder subtitles and nested subtitle discovery through rename, undo and recovery.
- Match external subtitles at media-name boundaries instead of attaching files belonging to another movie with a shared prefix.
- Update renamed photo paths and cached source state so cancellation cannot restore a removed filename.
- Bind background music track controls and restore saved track choices and delays while photos remain displayed.
- Honor end-of-track sleep before repeat or next-track actions for music playing over photos.
- Restore the selected embedded subtitle by stream ID and external subtitles by file path.
- Keep stereo visual histories and oscilloscope gain consistent across frame rates.
- Use shared stereo levels and loudness for native and fallback visual analysis while retaining native surround directions.
- Apply visual timing to spectrum, loudness and waveform history consistently, with advance limited to available output latency.
- Report and control background music through the remote API while photos remain displayed.
- Keep immersive and compact music visualisers driven by music levels independently of playback volume, mute and sleep fade, including fallback spectrum and oscilloscope analysis.
- Restore live fallback spectrum analysis after installing the waveform capture effect.
- Keep mounted-share file checks, media preparation, image discovery and subtitle loading off the playback UI thread.
- Preserve a requested media replacement when the previous track finishes during opening.
- Apply remote open commands with their requested start time and pause state, including transport updates during opening.
- Keep remote-control clients from blocking playback with bounded, nonblocking status writes.
- Stop playlist navigation safely when empty or unavailable folders exhaust the available entries.
- Retry stalled background music from its original source and options after browsing photos.
- Apply decoder-mode changes consistently while preserving explicit command-line and environment overrides.
- Keep network stream opening, cancellation and shutdown responsive with asynchronous connection setup and bounded, cancellable decoder I/O.
- Detect stalled video and background music from decoded media progress, restore playback after temporary stalls, and offer recovery when a connection stops responding.

## [0.0.1] - 2026-10-18

Initial public release.

### Added

- Windows and Linux x86_64 packages with OpenXR VR support and desktop mode.
- Video playback with hardware decoding, automatic software fallback, 10-bit video and HDR tone mapping.
- Flat and curved cinema screens, video-lit cinema room and passthrough.
- 2D, side-by-side and over-under 3D, Apple spatial video, 180° / 360°, fisheye, EAC and cubemap video and photos.
- Audio playback with music over photos, head-tracked audio, dialogue boost, volume levelling and night mode.
- Fully immersive VR music visualiser, audio-reactive 3D scenes and adjustable quality, intensity, depth sensitivity, motion and timing.
- Media library with thumbnails, grid and list views, subfolder browsing, search, favourites, recent files and saved playback positions.
- Local files, network shares, DLNA media servers and web-video playback through an optional helper.
- Embedded and external subtitles, chapters, bookmarks, A–B looping and seek previews.
- Pitch-corrected 0.5–2× playback speed, shuffle, repeat and sleep timer.
- Picture, projection and stereo controls with per-file settings, zoom, horizon levelling and named viewing profiles.
- Customisable VR controller shortcuts, recentering, settings search, on-screen keyboard and adjustable interface and text sizes.
- Settings backup and restore, format-based file renaming with undo, and playback recovery controls.
