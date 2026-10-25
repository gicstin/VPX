# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [0.0.9] - 2026-10-25

### Added

- Add a square Cover mode with hover playback, volume, favourites and an expand action; add title-side favourites in the expanded float.
- Add a desktop-only floating mini player with artwork, video view, playback and volume controls, pin-on-top, and restoration of the full window.
- Add contextual tooltips for playback, library, settings, bookmarks, viewing profiles, keyboard and visualizer controls, with current actions for toggles.
- Adjust volume in 5% steps by hovering volume controls and using the mouse wheel or VR thumbstick; right-click to toggle mute, including the mini player.
- Add three 3D music worlds, Valley of Sources, Sound Cathedral and Deep Current, with a steady ground and horizon, sounds placed where they sit in the mix, and support in desktop mode.
- Analyse local music tracks in the background for beats, bars, sections, build-ups and drops so music scenes anticipate drops and land on the beat, with results cached for instant replay.
- Limit music scene flashes to at most three per second.

### Fixed

- Route mini music player and visualizer-picker tooltip text directly to the custom renderer so Godot cannot create native tooltip windows for those controls.
- Match the music mini player's visualizer-list button to its open state, restore consistent starred-filter backgrounds and icons, close the picker on collapse, and keep track-title tooltips current.

## [0.0.8] - 2026-10-24

### Added

- Double-click a Library item or click its play badge to start playback right away.
- Add a dice toggle beside the immersive visualizer favourite filter; previous and next shuffle the full list or filtered favourites without repeats, with dice icons and shared history across desktop and VR.
- Add Play count sorting with most-played videos and audio first, plus an Unplayed filter that combines with search, media filters and favourites and persists per Library tab.
- Restore desktop window size, position, monitor, maximized and fullscreen state after restart, fitting saved bounds to available screens.
- Restore open Library tabs, active tab, folders, filters, view modes and scroll positions after restart.
- Add browser-style Library tabs with independent folders, filters, view modes and scroll positions, plus new-tab, close-tab and tab-switching shortcuts.
- Show bookmark names when hovering yellow timeline pins and seek to their exact timestamps when clicked.
- Show watched icons and view counts for videos, and listened icons and listen counts for audio, once playback reaches 90% of the duration, including after seeking.
- Add a saved folder favourites filter that combines with search and media-type filters, including subfolders in Flat view and updating when favourites change.

### Fixed

- Hide playback speed controls for live sources and keep streams at normal speed, including after playing a file at another speed.
- Show the release version throughout the app and remove obsolete build numbering from packaging.

## [0.0.7] - 2026-10-24

### Fixed

- Enable HTTPS, TLS, secure RTMP, SRT and DASH in Linux builds, and verify bundled network protocols, encrypted playback and redirects before packaging.
- Open SFTP media through the desktop share backend instead of passing links to FFmpeg builds without SFTP support.

## [0.0.6] - 2026-10-22

### Fixed

- Include Ogg streams advertised as FLAC or Opus in their codec filters and quality badges instead of relying only on the directory's container label.

### Changed

- Batch visualizer spectral-history copies, reduce channel-history and stereo-analysis work, and skip remote playback-status polling without connected clients, with byte-equivalence, TCP and performance tests.
- Reduce settled panel updates, repeated screen shader writes, spectrum smoothing work, playback cleanup allocations and empty library-search processing, with performance and regression tests.

### Added

- Add a discovery quality filter for bitrate presets and audio codecs, including FLAC, MP3, AAC, Opus and Ogg.
- Show codec and bitrate quality badges on online-source cards and list rows, including discovered and saved radio stations.
- Add online radio discovery with popular and trending stations, station search, genre, country and language filters, one-click playback, saved stations and direct stream links.


## [0.0.5] - 2026-10-21

### Added

- Mark currently playing files and online sources with a play icon on gallery grid thumbnails, including background music, without polling or extra file reads.
- Add one-click Off, Subtle, Balanced and Vivid visualizer mixes directly to the desktop and VR mini player while music plays over images or panoramas.
- Restore immersive sound visualizer overlays over videos, images and panoramas, with saved visual opacity, backdrop dimming, atmosphere controls and Subtle, Balanced and Vivid mixes.

### Changed

- Skip settled spectrum smoothing and unchanged texture uploads, reduce audio-capture and oscilloscope work, and speed up panorama face parsing, with reference-equivalence and performance checks.
- Reduce music-player refresh work and visualizer analysis cost by caching unchanged picker and favourite state, reusing audio timing, and avoiding redundant directional calculations.
- Batch oscilloscope shading and cache visualizer colour gradients while preserving waveform appearance, resizing and palette updates.
- Reduce library grid idle work, cache date and size sort keys, and group panorama visibility decisions per cube set, with repeatable performance and regression checks.
- Collapse the mini player by clicking its album-art area, with an audio-icon fallback when artwork is missing, replacing the dedicated collapse button.

### Fixed

- Smooth 360° visualizer joins by closing waveform and spectral ribbon endpoints, matching loop colours and making sky patterns continuous across longitude seams.
- Fade the mini player as one composited panel so idle buttons, icons and labels retain consistent contrast.
- Remove the thick inset around collapsed album art and clip artwork to rounded corners in both music-player sizes.
- Make Next and Previous cycle through memorised online sources, preserving navigation order while opened-link history updates.
- Restore button clicks and the normal pointer after pasting through a text field's right-click menu, and after dismissing that menu.
- Preserve music and online-radio album art proportions in a square thumbnail in the main player bar.
- Notify the desktop UI viewport when the mouse enters or leaves, restoring mouse motion over virtual keyboard keys and clearing stale hover when the menu closes.

## [0.0.4] - 2026-10-20

### Added

- Live station metadata and album art in the music player, including now-playing updates and standard stream tags.
- Persistent opened-link history in Network, with duplicate links moved to the top when reopened.
- Play online radio and direct audio streams, including extensionless URLs, with station names and live playback controls.
- Independent visualizer zoom for desktop and VR, with scene-picker controls and keyboard, mouse and controller shortcuts.
- Repeatable rendered preset calibration compares music response, loudness range, highlight clipping and motion before selecting stronger defaults.
- Four native 3D adaptations of Geiss MilkDrop presets from projectM’s classic collection: Swirl 1, Starfish 1, Nautilus and Cosmic Dust 2, with audio response and picker previews.

### Changed

- Reduce idle music-player opacity to 30% while retaining full opacity on hover and during interaction.
- Consolidate the compact music visualizer toggle under immersive visualizer Controls, freeing header space in desktop and VR music players.
- Collapse visualizer settings behind a compact Controls toggle, giving scene previews the full gallery height by default.
- Apply measured response profiles automatically for immersive music presets while retaining global intensity, sensitivity and motion controls.

### Fixed

- Normalize live-radio timestamps and buffer network audio to prevent silence after broadcast timestamp jumps and avoid skipping audio after stalls.
- Stop inactive VR controllers from stealing desktop pointer hover and clicks on the link-entry Done button.

## [0.0.3] - 2026-10-19

### Added

- Star music visualizer presets and remember favorites and the compact global Starred only button beside Disable Visualisation, including filtered forward, backward and automatic scene changes.
- Announce published GitHub releases in Discord through a release-triggered workflow, including release changelogs and download links.
- Choose whether music grabs move the scene with spatial audio or move audio alone, with existing desktop and VR behavior retained by default.

### Changed

- Reduce all music visualisation previews to 160×90 and use lossy texture compression to shrink the packaged thumbnail atlas while retaining full-size picker cards.

### Fixed

- Release VR slider drags outside panels and retain pointer capture across panels and tracking loss.
- Cancel and replace network-share connections immediately, with helper deadlines and stale-result protection.
- Keep favourites, recent locations, drive discovery and folder navigation responsive during unavailable filesystem reads, preserving unavailable saved entries.
- Keep ISO inspection and mounting responsive, with cancellable progress, helper timeouts and stale-result protection.
- Keep file pickers responsive during slow directory reads, path checks and cancellation.
- Contain settings import/export keyboard focus and shortcuts, and close the picker with one Escape.
- Commit keyboard timeline changes without duplicate drag seeks or seeks into replacement media.
- Offer software decoding recovery for damaged local videos instead of reporting a network connection failure.
- Keep sidebar tab highlights evenly inset and fully rounded when collapsed or expanded, with centered collapsed icons and no left-only accent border.
- Allow Grip + A / X to toggle music favourites during visualization, matching the shortcut help.
- Use direct Spectrum and Oscilloscope buttons for compact music display selection so both styles can be selected inside the VR panel.
- Keep the music visual selector open after choosing a scene so users can finish selecting before closing it.
- Remove the duplicate Music scene entry from VR shortcut help when the active shortcut already cycles music scenes.
- Size the expanded navigation sidebar to fit its labels at larger text sizes, preventing Search settings from clipping.

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
