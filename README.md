# File Converter

Development continuation: [completion plan](docs/CONTINUATION_PLAN.md) · [new-conversation handoff](docs/NEW_CONVERSATION.md). The full seven-milestone expansion remains unfinished.

A native macOS utility for local conversion, compression, PDF page tools, archives, text, and media. Keep originals intact, prepare files in the Glacier workspace, or hold a configurable modifier while dragging files in Finder to open the quick-action wheel.

Requires **macOS 13+ on Apple silicon**. Licensed under [MIT](LICENSE), with [third-party notices](docs/DEPENDENCIES.md).

## Install

Download the signed and notarized **[0.2.1 preview DMG](https://github.com/agiusthomas/file-converter/releases/download/v0.2.1/File-Converter-0.2.1.dmg)**, open it, drag **File Converter** to **Applications**, eject the disk image, and open the app from Applications. No Xcode or command-line tools are needed to use it.

See [installation, first-use, update, and removal instructions](docs/INSTALLATION.md). The 0.2.1 preview includes built-in conversions and a [downloadable Media runtime qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2). The preserved 0.2.0 app cannot install that newer pack. Read the [0.2.1 changes and limitations](docs/releases/0.2.1.md) before installing.

## Run

For source builds, use **Xcode 26+**. The project retains SwiftUI/AppKit and SwiftPM, with an Xcode app target embedding a sandboxed conversion worker.

```sh
./scripts/build-app.sh
open "build/File Converter.app"
```

The app stays in the menu bar after its window closes. Add or drop files, choose an available action and output, preview the result, then run it. Results save beside originals unless you select a destination. Aggregations use the first source’s folder. Existing names receive a number. Activity records verified outputs, notices, errors, and interrupted work; retries are explicit.

Included development capabilities:

- Images: native formats plus bundled still WebP encoding, crop/rotate/resize/background, multiple outputs, GPS-property removal, and measured size limits.
- PDF: page thumbnails/order/rotation/removal, merge/split, page images, image-to-PDF, text extraction, passwords, local OCR, searchable PDF, and explicitly destructive image-downsampling compression.
- Native audio/video: compatible MP4 H.264/HEVC, M4A AAC, WAV PCM, trim, resize/crop/rotate, mute/speed, matching joins, audio extraction, and frame export. Actual input/export support depends on macOS.
- ZIP, TAR, TAR.GZ and tested 7z creation/extraction through system libarchive, safe-member checks, and selective extraction. RAR reading depends on the system library and has not passed a RAR fixture corpus.
- Plain text encodings/line endings, CSV/TSV preserving textual cell values, and SRT/VTT timing conversion.
- Saved recipes with ordered processing and multiple exports, opt-in stable-file watchers, result shelf/drag-out/copy, Services integration, and a Shortcuts conversion action.

Optional adapters cover FFmpeg media, LibreOffice/Pandoc documents and spreadsheets, Calibre ebooks, and whisper.cpp transcription. **Media 0.1.2 (FFmpeg 8.1.2) is published as a qualification preview for the signed 0.2.1 app preview.** Its native Engines screen supports explicit download/progress/cancel/retry, notices, update, rollback and deferred removal. The broader codec dependencies, Documents/Ebooks/Transcription packs and their acceptance gates remain unfinished. Missing-pack actions remain discoverable; the wheel offers installed usable actions. The app does not import executable tools from other installed applications. All installed conversions run locally; network use is limited to explicit pack downloads.

Version 0.2.1 is a **Developer ID signed and notarized preview**, with hardened runtime and a secure timestamp. Its stapled ticket passes Gatekeeper assessment. The full expansion has open work and release gates, including minimum-OS testing, clean offline installation, fault qualification and physical Finder gestures. Real signed FFmpeg execution/download/lifecycle now pass on the development Mac; see [the exact checkpoint evidence](docs/FFMPEG_CHECKPOINT.md). Preview distribution does not declare those gates complete. See [implementation status](IMPLEMENTATION.md), [capabilities](docs/CAPABILITIES.md), and [remaining milestones](docs/ROADMAP.md).

## Verify

```sh
./scripts/swift-local.sh test
FILE_CONVERTER_MEDIA_TESTS=1 ./scripts/swift-local.sh test
./scripts/build-app.sh release
```

The media/OCR integration tests need normal access to macOS encoder and recognition services. Optional development-engine tests additionally use `FILE_CONVERTER_EXTERNAL_TESTS=1`; they skip when their explicitly configured tools are absent. These tests inject adapters only in the test target and do not bypass production signature verification. The suite generates its fixtures.

`scripts/swift-local.sh` keeps package/compiler caches in the workspace. Bundled libwebp builds from pinned C source; no package downloads or build plugins are required. The generated Xcode project is checked in; regenerate it from `project.yml` with XcodeGen when adding app sources or resources.

## CLI

```sh
.build/debug/convert-file capabilities
.build/debug/convert-file inspect /path/file.pdf
.build/debug/convert-file actions /path/file.pdf
.build/debug/convert-file convert --to jpg --quality 0.9 /path/image.png
.build/debug/convert-file run --action pdf.export --to png --pages 3,1,2 --dpi 144 /path/file.pdf
.build/debug/convert-file run --action archive.create --to zip /path/first /path/second
.build/debug/convert-file run --action subtitle.convert --to vtt --offset 1.5 /path/captions.srt
.build/debug/convert-file recipe run /path/recipe.json /path/input.png
.build/debug/convert-file jobs --recover
```

Generic requests accept `--options OPTIONS.json` for typed options. Inspection, capability, generic output manifests, recipes, and history use versioned JSON; legacy image `convert` retains its original result fields. The standalone development CLI uses a separate worker process. Desktop parsing and conversion use the sandboxed XPC service. Passwords are excluded from persisted jobs and exported recipes. Metadata copying/removal is format-specific; removing GPS properties does not erase arbitrary location-bearing text.

Build distributable engines with [the pack producer workflow](docs/ENGINE_PACKS.md). Production app packaging uses `scripts/release-app.sh` with a Developer ID identity and stored notarization profile. Scripts also read the ignored `Configuration/Signing.local.plist` for `identity`, `team`, and optional `notaryProfile` / `notaryKeychain` identifiers; explicit `CONVERTER_*` environment variables take precedence. No passwords or private keys belong in this file or repository. Signing and trust checks require normal macOS keychain access; a restricted command sandbox may hide configured identities.
