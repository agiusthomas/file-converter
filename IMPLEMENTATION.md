# Implementation status — 20 October 2026

Continue implementation using [the completion plan](docs/CONTINUATION_PLAN.md). A [ready-to-paste handoff](docs/NEW_CONVERSATION.md) carries the task into a new conversation. The plan separates working built-in features, adapter-only work, unavailable runtime packs and unverified acceptance gates.

## Preview build 0.2.0

The repository now contains a working expansion across the shared foundation, images/PDF, native media, archives/text, and Mac workflows. Optional engine adapters and a verified-pack lifecycle are implemented. **The seven-milestone plan is not fully complete and no public release gate is declared passed.** Signed third-party execution, minimum-OS testing, physical Finder gestures, and several advanced features remain open below.

The generated app is `build/File Converter.app`. It is an arm64, macOS 13+ preview build signed with the locally configured Developer ID Application identity. Release-mode compilation, secure timestamp, hardened runtime, and strict nested signature verification pass with normal macOS keychain access. Apple accepted notarization on 20 October 2026; the stapled app passes Gatekeeper as “Notarized Developer ID”. Download packaging provides `build/File-Converter-0.2.0.dmg`, the alternative ZIP, and `SHA256SUMS.txt`. The DMG includes an Applications shortcut and installation instructions. Machine-local signing identifiers are stored in the ignored `Configuration/Signing.local.plist`, with environment overrides. No private key or password is stored in the repository.

## Implemented behavior

### Shared execution

`ConverterCore` defines content-probed assets, file families, stable actions, container/codec output profiles, typed options, manifests, adapters, persistent jobs, and versioned recipes. The existing image API and legacy CLI image result fields remain available.

The Xcode application embeds a sandboxed XPC conversion worker. The standalone SwiftPM CLI uses a separate worker process. The broker grants workers staged snapshots and output folders; originals are not writable job inputs. Inputs use filesystem clones with copy fallback and source-change detection. One conversion/preview runs at a time per coordinator. Mixed unknown files stay visible and can be archived; family filters help narrow a selection. Inspection is cancellable; previews leave no activity entries and are cancelled before a new conversion starts.

Jobs persist before execution; pending window jobs also persist when enqueued. State changes cover queue, analysis, conversion, validation, publication, and completion. Dead-owner jobs become interrupted and require an explicit retry. Worker exits/disconnects cannot count as successful results. Each XPC connection owns and cancels its worker tasks on invalidation. Ad-hoc development and Developer ID production workers use distinct sandbox containers to avoid identity-change migration prompts. Inspection requests also have a response deadline. Staging cleanup uses the exact owned job path, including preserved source subfolders.

Output manifests include source relationships, measured sizes, dimensions/pages/duration where available, file hashes, engine versions, and notices. The broker checks paths, regular-file/folder status, links, duplicate/overlapping outputs, hashes, and measured bytes before exclusive publication. Completed publications are recorded incrementally; partial failures keep completed outputs. Retry skips already saved image formats or completed recipe exports. It does not resume an engine mid-conversion. A storage failure between filesystem publication and journal persistence still needs fault-injection qualification.

### Images and PDF

- Native ImageIO outputs, plus independently compiled libwebp 1.6.0 still-image encoding.
- Orientation, alpha, metadata, and multi-frame regression coverage retained. Animated input is rejected for destinations without an explicitly supported multi-frame path. TIFF/PDF pages do not preserve animation timing.
- Resize, crop, quarter-turn rotation, background, multiple image outputs, scan cleanup, source/result previews, quality and bounded measured target-size search.
- GPS image-property removal is reopened and checked. This does not remove arbitrary location-bearing text or guarantee forensic sanitization.
- Image descriptors expose profile, bit depth, alpha, GPS presence and frame count. WebP uses sRGB, preserves alpha, and omits source metadata. High-bit-depth/HDR preservation is not guaranteed.
- PDF input/password opening, thumbnails, ordered page selection, removal, reordering, per-page rotation, split/merge, page images at chosen DPI, and aggregate image-to-PDF with size/margin/fit/background.
- Selectable-text extraction, Vision OCR, scan cleanup, and searchable PDF with preserved physical page geometry.
- Password protection is verified; passwords are omitted from persistent jobs and recipes.
- PDF compression explicitly rasterizes/downsamples pages and removes text, links, forms, annotations, and signatures. A separate qpdf structural optimization engine is not yet bundled.

### Media

Native AVFoundation paths export tested H.264/HEVC MP4, AAC M4A, and PCM WAV where the actual input supports them. Trim, speed, mute, matching joins, resize/crop/rotation, audio extraction, and frame export share the same coordinator. Native M4A/WAV honor channel/sample-rate controls; AAC honors bitrate. Native movie audio settings remain automatic and the window explains that limitation. Joins require matching displayed geometry and orientation. Native paths reject extra tracks rather than dropping them silently.

The FFmpeg adapter implements additional codecs, transformations, normalization, GIF export and measured target bitrate. It queries the actual binary’s encoders and muxers before advertising profiles. Stream copy checks primary codec compatibility and explains when re-encoding is necessary. Output duration/geometry and actual byte limits are checked. Primary tracks are exported; track selection, subtitle embedding/extraction, waveform trimming, advanced HDR/alpha handling and the full variable-frame-rate/synchronization corpus remain unfinished.

### Documents, text, archives, ebooks and transcription

- Native text encodings and line endings, CSV/TSV quoting/newlines/textual leading zeros, and validated SRT/VTT timing conversion.
- LibreOffice adapter uses an isolated profile with macros and external-link updates disabled. DOCX/ODT/RTF/PPTX/ODP/XLSX/ODS are detected through content/package structure. OpenDocument detection reads its embedded mimetype even when the extension is wrong.
- Spreadsheet CSV/TSV exports produce a collision-free folder containing every sheet or an explicitly selected sheet; displayed values are used and formula/format losses are disclosed. Real two-sheet regression fixtures verify no silent omission.
- Markdown/HTML adapters use Pandoc where required. PDF rendering reconstructs an attribute-free static HTML subset before local rendering; scripts, remote resources, CSS and embedded objects are omitted. Package and text bounds apply. Full Office font/layout fidelity, conversion corpus and external-resource/macro adversarial qualification remain open.
- System libarchive handles tested ZIP/TAR/TAR.GZ/7z creation/extraction and member selection. Paths, duplicate/case conflicts, links, special files, expansion and member counts are bounded. Nested snapshots and archives preserve relative paths across macOS path aliases. System RAR reading has not passed a representative fixture corpus. A pinned bundled libarchive is not supplied.
- Calibre ebook-conversion and whisper.cpp transcription/model adapters exist behind missing packs. Their production execution is unverified. Native EPUB metadata/cover/navigation editing, transcript review editing, explicit model-download UI and experimental scanned-table export remain unfinished. DRM removal is not implemented.

### Mac workflows

Glacier appearance, native wheel and macOS 13 availability guards remain. The wheel uses the common usable actions for inspected selections. The workspace exposes unavailable optional actions with their pack requirements. Shift/Option/Control wheel settings, launch-at-login, stale/revocable output grants, batch naming previews and source-subfolder preservation are implemented.

Recipes support ordered processing, lossless-intermediate validation, multiple terminal exports, source lineage, a window editor, JSON import/export and CLI execution. Opt-in watchers skip startup baselines, wait for stable file size/time, filter extensions and write into a non-recursive `Converted` subfolder. Activity provides drag-out/copy/reveal/shelf and hash-checked Trash for individual generated files. Generated folders must be removed through Finder. Owned preview/Shortcuts staging expires after seven days.

A Finder Services entry opens files in the workspace; a dedicated Finder Quick Action extension is still pending. The Shortcuts conversion action is implemented, but recipe selection through the wheel/Shortcuts and full cross-entry consistency testing are pending.

## Engine packs and distribution

Pack manifests record app/OS/architecture compatibility, versions, hashes, tools, models, installed bytes and licenses. The manager requires Apple Developer ID Application signatures from the app publisher, verifies contents, installs immutable versions atomically, retains a rollback pointer, and defers deletion of old versions. Running jobs pin their pack locations and record their versions. Downloads must match the app’s signed bundled HTTPS catalog, size, checksum and identity before activation.

`scripts/build-engine-pack.py` assembles independently built runtimes with a signed bundle anchor, nested-code signing, hashes, notices, archive metadata and optional notarization. Unsigned fixtures remain unusable. A generated Developer ID signed pack passes production verification, isolated installation/update/rollback/deactivation, and tamper rejection. The test pack contains an owned acceptance program and is not an activated conversion engine. `scripts/release-app.sh` builds/signs, submits for notarization, staples and assesses the app when valid credentials are supplied.

The configured Developer ID was previously hidden by the command sandbox; signing outside that sandbox succeeds. The trusted download catalog is intentionally empty. No engines or models have been published. Signed pack lifecycle passes the generated acceptance fixture. Actual engine-runtime execution, interrupted/tampered downloads, relocation, sandboxed external tools and clean offline installation remain release gates. See [engine-pack production](docs/ENGINE_PACKS.md) and [dependency notices](docs/DEPENDENCIES.md).

## Verification

- 58 automated tests in the final suite, including seven opt-in native/external integration tests. Fixtures are generated locally and contain no user documents.
- Existing image/gesture tests plus PDF ordering/count/geometry/passwords, text/table/subtitle integrity, WebP decoded alpha, archive paths/nesting/selection, real worker exit without a manifest, cancellation, interrupted recovery, partial publication, pending-queue persistence, recipe lineage, codec claims, unsafe manifests and unsigned-pack rejection.
- Integration tests use native Apple media/OCR services, FFmpeg 8.1.1 and the development Mac’s installed LibreOffice through test-only injected adapters. These tools are not installed as packs or shipped in the app. Real native output settings/geometry, RTF-to-PDF, MP3/WebM and all/selected spreadsheet sheets pass.
- Native UI on the packaged release-mode app: content inspection through XPC; PNG-to-WebP success; invalid-size fields visibly disable preview/export; recipe editor opens and adds steps. The Developer ID build also passed fresh content inspection and PNG-to-JPG export through its production sandboxed worker. Earlier original-image UI checks also passed.
- Release-mode build, bundled worker/app strict Developer ID signature checks, timestamp/hardened runtime, signed-pack lifecycle, and tamper rejection pass. Apple notarization, ticket stapling, and Gatekeeper assessment pass. The verified notarization credentials are stored in the login Keychain; the repository stores no credential material.
- Prior Glacier light/dark, transparency, contrast and keyboard-wheel checks are retained from the image-only build; the expanded workspace still needs a full accessibility/VoiceOver regression pass.

Physical Finder dragging across displays/Spaces/edges, minimum macOS 13, current macOS on a clean Mac, large-batch memory/responsiveness, disk-full/revoked-grant fault injection, signed external-engine execution, and each milestone’s representative corpus are still required. No milestone is published merely because these automated tests pass.
