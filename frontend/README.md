# Marauders

Marauders is an offline-first SwiftUI monument companion that turns demo District bookings into interactive map, AR, and voice-guided tours.

The core tour is local-first and works offline after installation. Live Q&A uses the deployed Azure backend and requires a locally supplied app key.

See the [workspace README](../README.md) for the system architecture diagram and how this app talks to the [backend](../backend/README.md).

## Features

- Demo phone and OTP authentication (`123456`), plus a local Google demo sign-in
- Three tour bookings: Taj Mahal, National War Memorial, and Zomato Farmhouse
- Downloadable ZIP tour packages decoded from the deployed backend contract
- Local illustrated maps driven by package checkpoint order and normalized coordinates
- ARKit image tracking that resolves printed targets to local audio nuggets
- Camera-free Browse Mode that exposes the same nuggets, playback, reveal cards, and progress semantics
- Curated target-image reveal cards with shutter feedback and a live-camera thumbnail
- Debounced offline audio playback that tolerates brief target occlusion
- Persistent SwiftData progress for checkpoint state and secrets-found counts
- Package-driven language selection, on-device GPS checkpoint resolution, and live voice Q&A
- Optional ambient soundtrack with narration/Q&A ducking and checkpoint intro playback
- Responsive native SwiftUI layouts and Dynamic Type-compatible text
- Mock authentication and tickets with real packaged tour content

## Requirements

- Xcode 26 or later
- iOS 18 or later
- A physical ARKit-capable iPhone is required for image-tracking verification

## Demo Access

1. Enter any 10-digit Indian phone number.
2. Use OTP `123456`.
3. Alternatively, select **Continue with Google** to use the local demo account.

Authentication and tickets are mock implementations. Taj Mahal monument content and audio are loaded from the deployed backend package contract.

## Backend Configuration

The app uses `https://marauders-backend.azurewebsites.net` as the single source for package downloads, health checks, and live Q&A. Supply only the app key locally:

```sh
MARAUDERS_APP_KEY=your-hand-carried-key \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Marauders.xcodeproj -scheme Marauders \
  -destination 'generic/platform=iOS' build
```

`Secrets.xcconfig.example` documents the equivalent local Xcode value. `Secrets.xcconfig` is ignored by Git. Package and health endpoints are open; only `/ask` receives `X-App-Key`.

## Offline Package

`Marauders/Resources/Packages/taj_mahal.zip` is bundled for deterministic demos. It contains:

```text
tour.json
audio/*.mp3
targets/*.jpg
```

The real Azure package is bundled for first-launch offline use. Installation is atomic and upgrade-aware. Missing localized audio is filtered per nugget; nuggets with no playable audio and checkpoints with no playable nuggets are omitted instead of failing the tour. Missing AR targets fall back to Browse Mode and an image placeholder. The core map, AR recognition, audio playback, and progress flow make no network calls.

## Build

Open `Marauders.xcodeproj` in Xcode and run the `Marauders` scheme, or use:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Marauders.xcodeproj -scheme Marauders \
  -destination 'generic/platform=iOS Simulator' build
```

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Marauders.xcodeproj -scheme Marauders \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test
```

## Architecture

Feature modules live under `Marauders/Features`; shared theme, exact backend models, navigation, package storage, location, Q&A, and session services live under `Marauders/Core`.

```text
Marauders/
├── App/                 App entry point and root flow
├── Core/                Design system, models, navigation, and services
├── Features/            Authentication, bookings, maps, audio, camera, profile
├── Resources/           Asset catalog, bundled maps, localization, and audio
MaraudersTests/          Swift Testing unit tests
MaraudersUITests/        XCTest UI flows
Documentation/           Design implementation notes
```

## Camera and AR

The Scan tab uses `ARImageTrackingConfiguration`. Package target JPGs become `ARReferenceImage` instances at runtime; recognition selects the strongest stable target and drives the debounced local audio state machine. A 150 ms frozen-frame flash confirms recognition, then the bundled reference image becomes the full-quality reveal card while the live camera shrinks to a corner thumbnail.

Browse Mode is always available from the map and camera fallback states. It uses the same package nuggets and audio player as AR, and only marks a nugget visited after the user taps it and playback starts. This makes the complete tour available when camera permission is denied, AR initialization fails, or no printed target is available.

The microphone records a 16 kHz mono M4A question, POSTs it to `/ask`, and plays the returned base64 audio without blocking the UI. Camera-triggered audio is suppressed from permission request through spoken-answer completion, so an answer remains bound to its original checkpoint and cannot be interrupted by a new target. Missing configuration and network failures surface retryable messages.

## Verification

The app builds with the installed Xcode 26 and iOS 26 SDK. The requested iOS 27 SDK is not currently installed, so `FoundationModelsAnswerEngine` is a protocol-compatible stub; the primary Azure engine is complete. Tests cover contract JSON decoding, package installation/path validation, localization fallback, audio timing, authentication, and the bundled tour launch flow.
