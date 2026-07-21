# Design Implementation

Marauders follows the supplied Monument Guide specification and HTML references.

- Palette: sandstone `#FEF9EF`, terracotta `#6D2325`, muted gold `#775A19`, and status teal `#004544`.
- Shape: 12-24 point continuous corners, pill statuses, and circular AR controls.
- Depth: tonal surfaces and native thin/ultra-thin materials instead of heavy shadows.
- Navigation: ticket-oriented app tabs and the reference Map, Scan, Info tour bar.
- Maps: the three supplied PNG maps are bundled locally. Hotspots use normalized coordinates so map interactions scale across iPhone sizes.
- Typography: rounded system headings approximate Plus Jakarta Sans without requiring a separately licensed font bundle; body text uses the native system face for Dynamic Type support.

The implementation was derived from the supplied Monument Guide design specification, HTML references, and map images. API credentials are supplied through an ignored local configuration file and are never committed.

## Backend Contract Integration

- `TourPackage`, `Monument`, `Routes`, `Route`, `Checkpoint`, `MapPosition`, `GPS`, and `Nugget` match the deployed Codable contract.
- `PackageStore` atomically installs ZIP files to Application Support, decodes `tour.json`, filters partial audio/target content, and preserves the last valid installation if an update fails.
- `NuggetAudioPlayer` applies 0.3-second recognition entry and 1.5-second loss exit holds before local playback changes.
- `VisitedNugget` is the SwiftData source of truth for persisted map and recap progress.
- `ARImageTrackingView` creates reference images from the installed package and maps recognition names back to nuggets.
- `BrowseModeView` is the camera-independent P0 path and shares engagement, playback, reveal, and progress behavior with AR.
- `NuggetRevealCard` uses the curated package target JPG when available and a stable placeholder otherwise; the live camera frame is used only for the 150 ms shutter response.
- Simultaneous AR targets are ranked by distance with hold-duration and current-target stickiness to avoid flicker.
- Camera-driven playback is suppressed while a live question is recording, in flight, or speaking, then resumes from the currently tracked target.
- `AzureAnswerEngine` is the only online tour feature, always uses the deployed Azure base, and applies `X-App-Key` only to `/ask`.
- Optional package ambient audio loops beneath the tour and uses independent narration/Q&A ducking reasons.
- Checkpoint intro audio plays once when a checkpoint is explicitly entered from the map, Info screen, or GPS arrival.
- `LocationService` performs radius checks on-device and does not use GPS for indoor checkpoints.

The iOS 27 FoundationModels recap remains intentionally stubbed because the installed SDK is iOS 26. The `AnswerEngine` abstraction is ready for that implementation when the toolchain is available.
