# File Converter

A native, open-source macOS file converter with a Shift-drag conversion wheel, batch image conversion, and local processing. Built with SwiftUI, AppKit, and ImageIO. Licensed under [MIT](LICENSE).

The first build focuses on images. Requires macOS 13+ and Apple silicon; build with Xcode 16+ / Swift 6. Apple silicon is the currently tested platform.

## Run the app

```sh
./scripts/build-app.sh
open "build/File Converter.app"
```

The app stays in the menu bar after its window closes. Choose images in the window, drop images onto the drop area, or hold **Shift while dragging an image in Finder** and drop onto a format in the wheel. Quit other utilities using the same shortcut when testing it. The window's **Open wheel** button also supports click selection and arrow keys / Return / Escape.

Current outputs on the development Mac: **JPG, PNG, HEIC, TIFF, AVIF, BMP, PDF**. Availability comes from the local ImageIO encoders. WebP encoding and other file families are not implemented yet. Multi-frame input can be exported as TIFF or PDF pages; playback timing is not retained. Single-image destinations reject multi-frame input instead of dropping frames silently.

Results are reopened for validation and saved beside their originals. Existing filenames get a number; atomic exclusive publication prevents concurrent jobs from replacing one another. JPG/BMP flatten transparency onto white. Orientation is applied to pixels once, with output orientation normalized. Quality and supported metadata copying are configurable. The current limits are 256 MB input, 100 million total decoded pixels, and 1,000 pages/frames per job.

This is a local development build signed ad hoc. Conversion currently runs in an actor in the app process; worker isolation, crash recovery, App Store packaging and the rest of the conversion catalog remain planned work.

## Build and verify

```sh
./scripts/swift-local.sh test
./scripts/build-app.sh release
```

`swift-local.sh` keeps compiler/package caches inside the workspace and avoids a nested SwiftPM manifest sandbox, for compatibility with restricted development environments. The package has no external dependencies or build plugins.

The tests cover orientation, alpha, metadata selection, multi-page input, malformed data, concurrent output publication, capability intersections, wheel hit testing, and the Shift-before/during-drag state machine. The physical Finder gesture needs a manual check because the current UI automation tool cannot reliably hold Shift across a drag.

## Command-line conversion

```sh
.build/debug/convert-file capabilities
.build/debug/convert-file convert --to jpg /absolute/path/image.png
.build/debug/convert-file convert --to pdf --output /absolute/path/folder image1.png image2.png
```

Each source creates its own output. Use `--quality 0.9` or `--strip-metadata` as needed. `--strip-metadata` omits source properties; it is not a forensic metadata-cleaning service. HEIC/AVIF need access to macOS encoder services, which may be blocked by an additional command sandbox even when the desktop app can encode them.

## Project status

- [Current build and verification](IMPLEMENTATION.md)
- [Architecture and roadmap](docs/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [MIT license](LICENSE)

CI runs the test suite and builds the app on macOS. Broader format support, media tools, document conversion and native file actions are planned; the roadmap is not a claim of implemented support. Development research, third-party application artifacts, personal samples and generated builds are excluded from this source repository.
