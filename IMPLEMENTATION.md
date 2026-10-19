# Implementation status — 19 October 2026

## Working foundation

- Swift Package with `ConverterCore`, native `FileConverter`, command-line `convert-file`, and core tests.
- Ad-hoc signed app bundle built by `scripts/build-app.sh`; no external dependencies.
- Native menu-bar lifecycle with a converter window, Activity, Settings, file picker and file-drop area.
- Global mouse/modifier/drag-pasteboard sampling; Shift before or during a file drag opens a nonactivating wheel. Other utilities should not monitor the same shortcut during testing.
- Native rounded wheel sectors with neutral centre, hover selection, drag destinations, clickable accessibility buttons and keyboard selection.
- Runtime capability registry excludes missing native encoders and identity conversions; mixed selections use shared destinations.
- ImageIO image import/encode, orientation normalization, supported metadata copying, configurable quality, alpha flattening for JPG/BMP and multi-page TIFF/PDF output.
- Serial background conversion actor, cancellable batch queue, partial-error reporting, output notices and Finder reveal.
- Same-volume staging, reopen verification of every image page, and exclusive atomic output publication with collision numbering.
- Folder grant selection and persistent security-scoped bookmarks for save-access recovery.

## Verification

- Debug build passed and the app launched through the native UI interface.
- All 13 core tests passed, including the metadata-option and multi-page TIFF checks.
- Real PNG exports succeeded to JPG, PNG, HEIC, TIFF, AVIF, BMP and PDF on the development Mac. All kept the original file hash intact.
- HEIC/AVIF export succeeded with normal macOS encoder-service access; native app HEIC export was also verified. An additional command sandbox can block those services.
- Native UI: opened image picker, selected PNG, converted to JPG, opened the live wheel, selected HEIC and observed successful saved results in Activity.
- Native UI wheel exposes format buttons to accessibility. The inspected PNG wheel contains JPG/HEIC/TIFF/AVIF/BMP/PDF; PNG is excluded as the input format.
- Automated tests validate Shift-before/during-drag transitions, stale pasteboard suppression, cancelled sessions and wheel geometry. **Physical Finder Shift-drag and drop interception remain manually unverified** because the available input tool does not reliably preserve Shift across a drag.

## Glacier UI refresh

- Shared ice/sapphire and deep-blue/azure palettes follow the Mac's appearance across the workspace and AppKit wheel labels.
- Native macOS 26 Liquid Glass is used for the wheel, navigation selection, wheel status, shortcut key and drop area; native glass button styles distinguish secondary actions from the primary conversion action. Settings and activity use quieter opaque cards.
- The wheel and its illustration share rounded petal artwork. The live artwork is hosted beneath the existing AppKit buttons and returns no hit-test target, preserving native click, keyboard and drag handling. Selection tint remains blue outside the glass container so inactive panels retain readable white labels.
- All newer APIs are availability-guarded; macOS 13–15 use material and bordered-button fallbacks. Building now requires the macOS 26 SDK / Xcode 26+. An older macOS runtime was not available for verification.
- Release build and signature verification passed. All 13 existing core tests passed. Native UI checks covered Convert, Activity and Settings in light/dark appearance; empty and populated selections; minimum window size with scrolling; opaque Reduce Transparency surfaces; Increase Contrast boundaries; and wheel selection with Reduce Motion enabled. Original display preferences were restored afterward.
- Keyboard arrows, Return conversion, Escape dismissal and native wheel-button conversion were verified. A batch of two 6000 × 6000 PNG fixtures converted successfully to HEIC and JPG, alongside a deliberately malformed fixture that displayed a failure without preventing the successful results. These fixtures and outputs are local ignored build artifacts.
- The conversion queue finished before the UI tool captured its running state. Physical Finder Shift-drag, live drop/hover behavior over different desktops, screen-edge/multi-display placement, and older-macOS runtime appearance still need manual checks; their existing interaction logic and geometry were retained.

## Current scope limits

This implements the first image-conversion slice. It does not yet include external encoders/WebP output; video/audio; PDF input and PDF editing; document/EPUB/Office engines; archives/subtitles; editing/redaction/compression tools; file actions and floating shelves; or production distribution.

Image conversion currently runs inside the application process. XPC/worker isolation, memory-pressure handling, job journaling/crash recovery, sandboxed release packaging, login launch, comprehensive accessibility testing, stale/revocable grant management, minimum-OS testing and the remaining milestones are still needed. Metadata conversion is best-effort across different formats; deeper privacy scrubbing needs separate implementation and verification.

## Next implementation sequence

1. Validate physical Finder Shift-drag on this build, including different screens, centre/outside drops, Escape, ordinary drags and mixed selections. Adjust the monitor/drop panel from observed behavior.
2. Isolate the conversion worker, improve persisted output grants and interrupted-job cleanup, and add a capability/status matrix generated from actual engine support.
3. Expand images and PDF tools, including bundled WebP, compression, crop, image-to-PDF aggregation, PDF split/merge/organize and deeper metadata verification.
4. Continue the media and structured-document work packages in [the roadmap](docs/ROADMAP.md).
