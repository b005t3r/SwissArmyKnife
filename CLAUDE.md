# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`SwissArmyKnife` is a shared Swift Package of video-capture, tracking, and geometry utilities used across a family of sibling projects: `LiveTrackerBinary` (main app) and `GolfBallTracker` (both `import SwissArmyKnife`), plus the `GPUImage3` package (checked out as `../GPUImage3` relative to this repo, product name `GPUImage`) which this package depends on. Despite the generic name, most of the code is specifically video-capture/playback/stabilization/tracking-oriented — consistent with backing golf-swing/ball-tracking and live-streaming apps.

There is no README, no `.cursorrules`, and no CI/linter config in this repo — this CLAUDE.md is the first documentation.

## Build & Test

Never perform an automated build for this project, the user will do that.
Never perform an automated test run for this project, the user will do that.
Never commit anything to the git repository, the user will handle that.

## Working style

- Keep replies to the user short, concise and to the point. The user does not want to read essays.
- Code comments should be minimal, start sentences with a lowercase letter, and avoid fancy symbols (no emojis, em dashes, ellipses).

## Architecture

Everything lives in one flat module (no submodules); the only subfolder is `Utils2D/`. Code is organized as **free functions and extensions on Foundation/CoreVideo/CoreMedia types** rather than instance methods on custom types — a "toolkit" style consistent with the package name.

### Media I/O (AVFoundation)
- `VideoReader` / `AudioReader` — near-identical (no shared base/protocol) implementations: build a sorted PTS index over a track, then maintain a "cached sequential `AVAssetReader`" fast path with fallback to a fresh reader for non-sequential seeks. **A fix in one likely needs mirroring in the other.**
- `VideoRecorder` — wraps `AVAssetWriter`/pixel-buffer-adaptor recording, with a `heuristicBitrate(size:fps:)` helper and GPS-metadata embedding.
- `AVUtils.mux(...)` — remuxes separate video+audio files into one `.mov`.
- `CameraControl` (`#if os(iOS)`) — sits on top of GPUImage's `Camera`, manages capture-format switching and a manual auto-ISO loop for fixed-shutter exposure control.
- `CVPixelBuffer_copy.swift` — plane-by-plane pixel buffer deep copy + pool helpers.

### GPUImage-integration layer (requires `import GPUImage` from `../GPUImage3`)
- `VideoFrameRenderer: ImageSource` — YUV `CVPixelBuffer`→RGB `Texture` via a custom Metal fragment shader.
- `HumanMaskInput: ImageSource` — runs Vision person-segmentation (`HumanMaskGenerator`, internal) and uploads the mask as a Metal texture into the GPUImage graph.
- `FrameOrientation` — central orientation currency bridging GPUImage's `ImageOrientation`, `CGImagePropertyOrientation`, radians, and a 3D "up" vector; used across the mask/render/rotation code.

These four files are the only ones coupled to GPUImage; the rest of the package is dependency-free (Foundation/AVFoundation/CoreLocation/CoreMotion/Vision/simd only).

### Motion / sensor tracking
- `DeviceRotationTracker` + `GyroData` + `VideoData` (`Codable`) — live-samples `CMMotionManager` into a ring buffer, or replays a previously recorded `VideoData` session (per-frame timestamps + gyro quaternions + FOV + shutter speed), exposing slerp-interpolated rotation lookups by timestamp.
- `LocationProvider` — thread-safe `CLLocationManagerDelegate` wrapper.

### 2D geometry — `Utils2D/` (the most architecturally distinct part)
Protocol-oriented and generic rather than concrete-type-based: `Vector2D`, `Size2D`, `Rect2D`, `Polygon2D` protocols (each with an `associatedtype Scalar: BinaryFloatingPoint`) are retroactively adopted by `CGPoint`/`CGSize`/`CGRect`, plus a concrete `CGPolygon` conformer. Nearly all logic lives in `public extension` default implementations on these protocols, so the same math (arithmetic, distance, normalize, rotate, coordinate-space conversion via Vision's `VNImagePointForNormalizedPoint`/`VNNormalizedPointForImagePoint`, point-in-polygon, convex hull, etc.) works generically for any conforming type — not just the Foundation types.

Built on top of that base:
- `PerspectiveRotation2D.swift` — camera-ray math (`makeCameraRay`, `projectToScreen`, `rotateVector`) to reproject a 2D pixel through a 3D camera rotation, used to compensate for device rotation between frames (golf-swing tracking stabilization). Adds `rotate/unrotateViewInPerspective` etc. as further extensions on the same protocols.
- `SplineInterpolator` — keeps a time-sorted history of spline segments, producing smoothly time-interpolated trajectories (e.g. a tracked ball-flight path) across frames, with pruning of old entries.
- `CoordsUtils.swift` — internal, non-public coordinate-conversion helpers; largely superseded by the `Vector2D`/`Rect2D` extension methods above — treat as legacy when working nearby.

### General-purpose / concurrency
- `SafeDispatchQueue` — `DispatchQueue` wrapper using `DispatchSpecificKey`-based re-entrancy detection so `sync {}` won't deadlock if already on that queue. This is the standard thread-safety idiom used throughout (`DeviceRotationTracker`, `LocationProvider`, `VideoRecorder`, `AsyncProcessor`); `Zoom` uses a raw `NSLock` instead.
- `AsyncProcessor<T>` — bounded producer/consumer queue (drops oldest on overflow) with a semaphore-driven worker loop.
- `Zoom` — thread-safe, timestamped keyframe timeline of zoom `(location, level)` state with smoothstep-eased interpolation (`get(at:)`) and keyframe-merging export (`exportTimeline`), for recording and later re-exporting a pan/zoom edit over a video.
- `MathUtils.swift` — `clamp`, `lerp`, easing curve functions (`@inlinable`, generic).
- `Stopwatch` — benchmarking helper with rolling average tick duration.

## Notes for making changes

- iOS-only code is `#if os(iOS)`-gated (`CameraControl.swift`, parts of `DeviceRotationTracker.swift`, `CMTime_Hashable.swift`) since the package also targets macOS/tvOS/Mac Catalyst — keep new platform-specific code similarly gated rather than assuming iOS.
- Some file header doc-comments still reference earlier prototype project names (`GolfBallTracker`, `GPUImageTest`, `StabilizedVideoRecorder`, `LiveTrackerDemo`, etc.) — this code was consolidated here from multiple prior projects; don't treat those references as current.
- No tests exist for this package — if you add non-trivial logic (especially in `Utils2D/`), be aware there's no existing test suite to extend or pattern-match against.
