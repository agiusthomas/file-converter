# Implementation status — 21 October 2026

Continue implementation using [the completion plan](docs/CONTINUATION_PLAN.md). A [ready-to-paste handoff](docs/NEW_CONVERSATION.md) carries the task into a new conversation. The plan separates working built-in features, adapter-only work, unavailable runtime packs and unverified acceptance gates.

## Glacier File Converter 1.0.0

Version 1.0.0 (build 4) is the first official release requested by the user. It includes all prior conversion features, engine management and the recent Finder-wheel fixes from `1d34af8`: independent hover/selection tracking, release fallback when native callbacks are absent, duplicate-submission prevention, Escape/neutral-drop cancellation and direct conversion without opening the workspace.

Glacier branding appears in the sidebar, window, menus, accessibility descriptions, Settings, Finder service and app metadata. The two-line sidebar header preserves its footprint, Settings reads version/build from the bundle, and shared faceted artwork supplies the sidebar, adaptive menu-bar mark and all ten macOS app-icon sizes. Existing interface colors, controls and conversion wheel artwork are preserved.

Build/CI and release packaging use `Glacier File Converter.app` and `Glacier-File-Converter-VERSION` artifact names. The rename preserves bundle/worker identifiers and all storage paths. Previous public versions and their download links remain unchanged. See [release notes](docs/releases/1.0.0.md), [distribution evidence](docs/evidence/app-1.0.0-release.json), and [first renamed update instructions](docs/INSTALLATION.md#update-or-remove).

Branding verification on 21 October 2026 passed the local Release build, strict nested signature check, all 73 existing tests (zero failures/skips), built metadata/icon checks, and minimum-window-size light/dark inspection. The running app displayed existing job history, renamed menus and the bundle-derived Settings version. The original light appearance was restored afterward. The 1.0.0 app and DMG passed fresh Developer ID signing, Apple notarization, stapling and Gatekeeper assessment. Extracted ZIP and read-only mounted DMG app copies match the signed app CDHash. The signed production XPC worker passed real Media conversion/independent decoding, download interruption/retry, update/rollback, tamper rejection, observed-child cancellation and deferred removal; complete results are recorded in the distribution evidence. The official release does not declare the remaining expansion milestones or untested platforms complete.

## Published previews 0.2.0 and 0.2.1

The repository now contains a working expansion across the shared foundation, images/PDF, native media, archives/text, and Mac workflows. Optional engine adapters and a verified-pack lifecycle are implemented. **The seven-milestone plan is not fully complete and no public release gate is declared passed.** Real FFmpeg pack execution and download/lifecycle now pass on the current Mac. Minimum-OS testing, clean offline installation, failure qualification, physical Finder gestures, other runtime packs and advanced features remain open below.

The published 0.2.0 app is preserved locally at `build/preserved-v0.2.0/File Converter.app`; its original DMG/ZIP/checksums are unchanged. It is an arm64, macOS 13+ preview build signed with the locally configured Developer ID Application identity. Release-mode compilation, secure timestamp, hardened runtime, and strict nested signature verification pass with normal macOS keychain access. Apple accepted notarization on 20 October 2026; the stapled app passes Gatekeeper as “Notarized Developer ID”. Download packaging provides `build/File-Converter-0.2.0.dmg`, the alternative ZIP, and `SHA256SUMS.txt`. The DMG includes an Applications shortcut and installation instructions. Machine-local signing identifiers are stored in the ignored `Configuration/Signing.local.plist`, with environment overrides. No private key or password is stored in the repository.

The separately versioned [0.2.1 app preview](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.1) (build 3) is Developer ID signed, newly notarized and stapled, with a hardened sandboxed XPC worker. Its DMG and alternative ZIP have version-specific checksums. [Release evidence](docs/evidence/app-0.2.1-release.json) records distribution verification. This user-requested preview does not declare a milestone or full product release gate passed. Media pack 0.1.2 is a [published, signed/notarized qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2); it is not completion of the Media milestone. [Builds, source hashes, artifact hashes and actual signed-app evidence](docs/FFMPEG_CHECKPOINT.md) are recorded separately.

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

`scripts/build-ffmpeg-runtime.py` independently builds pinned FFmpeg 8.1.1/8.1.2 from official source. The current initial LGPL configuration links six relative FFmpeg dylibs and Apple frameworks, disables networking/device capture and automatic dependency detection, and includes complete corresponding source, exact build/toolchain records and licenses. `scripts/validate-engine-runtime.py` checks every Mach-O architecture, deployment target and dependency path. LAME, libopus and libvpx encoders remain required for the full Media pack.

The real runtime exposed an execution-access failure that the owned signing fixture did not exercise. Publisher-verified immutable packs now live in the production worker's existing read/execute-only Application Scripts directory. The worker receives no write bookmark to engine code, re-verifies signatures/hashes, stages data inside its container, and executes signed children with inherited sandbox rights. No sandbox exception, disabled library validation or relaxed signature check was added. XPC cancellation now waits for the worker's acknowledgement after child termination/cleanup.

Media 0.1.2 (FFmpeg 8.1.2) is published with corresponding source and checksums. Its exact URL/hash/sizes are sealed into the 0.2.1 app's bundled catalog. The native Engines screen offers available/installed/incompatible states, download and installed sizes, license/source disclosures, explicit download/progress/cancellation/retry, local import, update, rollback and safe removal. Idle refresh updates the same coordinator actor and Finder wheel; active queues keep immutable snapshots. Cross-process leases and a store lock defer removal until snapshots release their versions; interrupted removal intent persists. Reinstalling an active version preserves the rollback pointer.

Actual signed-app acceptance passes generated audio/video conversion, independent decoding, original hashes, real-version update/rollback, tamper rejection, cancellation after observing the real child PID, removal while pinned and reclamation after release. A real catalog download was cancelled after 13,771 bytes without changing the active version, then retried/installed successfully. Native UI checks passed download/install, local import, update, rollback, removal, notices, capability refresh without restart and a window-launched conversion using the downloaded pack. UI cancellation was too fast to exercise manually; the production cancellation path passed in the signed-app harness. Documents/Ebooks/Transcription packs and models remain unpublished. See [engine-pack production](docs/ENGINE_PACKS.md), [checkpoint evidence](docs/FFMPEG_CHECKPOINT.md) and [dependency notices](docs/DEPENDENCIES.md).

## Verification

- 73 automated tests, all passing with native media/OCR, supplemental external-tool and native window-server wheel checks enabled. Fixtures are generated locally and contain no user documents.
- Wheel regression tests cover missing native callbacks, duplicate release submission, background conversion and cancellation. Existing image/gesture tests also cover PDF ordering/count/geometry/passwords, text/table/subtitle integrity, WebP decoded alpha, archive paths/nesting/selection, real worker exit without a manifest, cancellation, interrupted recovery, partial publication, pending-queue persistence, recipe lineage, codec claims, unsafe manifests and unsigned-pack rejection.
- Integration tests use native Apple media/OCR services, FFmpeg 8.1.1 and the development Mac’s installed LibreOffice through test-only injected adapters. These tools are not installed as packs or shipped in the app. Real native output settings/geometry, RTF-to-PDF, MP3/WebM and all/selected spreadsheet sheets pass.
- Native UI on the packaged release-mode app: content inspection through XPC; PNG-to-WebP success; invalid-size fields visibly disable preview/export; recipe editor opens and adds steps. The Developer ID build also passed fresh content inspection and PNG-to-JPG export through its production sandboxed worker. Earlier original-image UI checks also passed.
- Release-mode build, bundled worker/app strict Developer ID signature checks, timestamp/hardened runtime, signed-pack lifecycle, and tamper rejection pass. Apple notarization, ticket stapling, and Gatekeeper assessment pass for both the preserved 0.2.0 app/DMG and the new 0.2.1 preview app/DMG; Media 0.1.2 notarization is Accepted. Verified notarization credentials remain in the login Keychain; the repository stores no credential material.
- Prior Glacier light/dark, transparency, contrast and keyboard-wheel checks are retained from the image-only build; the expanded workspace still needs a full accessibility/VoiceOver regression pass.

Physical Finder dragging across displays/Spaces/edges, minimum macOS 13, current macOS on a clean Mac, large-batch memory/responsiveness, disk-full/revoked-grant fault injection, the remaining distribution/failure gates, and each milestone’s representative corpus are still required. No milestone is published merely because these automated tests pass.
