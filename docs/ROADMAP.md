# Expansion roadmap and open release gates

**Continuation:** use [the detailed completion plan](CONTINUATION_PLAN.md) for actionable tasks and acceptance gates, and [the new-conversation handoff](NEW_CONVERSATION.md) to resume in another chat. Version 0.2.0 is a partial preview; the original seven-milestone expansion is unfinished. Optional pack installation does not make delivery of those packs optional for this project.

This tracks the approved seven-release expansion. The app remains a local macOS 13+ Apple-silicon utility with a Finder wheel and a Glacier workspace. Implemented features and verification evidence are in [IMPLEMENTATION.md](../IMPLEMENTATION.md); the [generated capability matrix](CAPABILITIES.md) reflects the current registry, not a promise that every embedded feature is supported.

## 1. Foundation and trustworthy jobs

Implemented: shared asset/action/request/manifest/adapter/coordinator/recipe contracts; legacy image compatibility; Xcode app and sandboxed XPC worker; clone/copy snapshots; persistent jobs and pending queue; cancellation; explicit recovery/retry; exclusive manifest publication; content inspection; folder grants; disk-space preflight; configurable modifier and login launch.

Verified on the current Mac: independently built FFmpeg packs execute through the signed sandboxed XPC app; real download interruption/retry, update/rollback, observed child cancellation and pinned removal/reclamation pass. Native download/install/update/rollback/removal and a downloaded-pack conversion pass. See [exact evidence](FFMPEG_CHECKPOINT.md).

Before release: worker/app termination and disk-full fault injection; memory benchmarks; physical Finder drags across screens, Spaces, edges and modifier changes; clean installation and macOS 13 tests. Strengthen progress with engine-level fractions where appropriate. Do not add parallel conversion workers until benchmarks justify them.

## 2. PDF, images and sharing

Implemented: native PDF workspace/page tools/passwords/rendering/text/OCR; image-to-PDF layout; bundled still WebP; transformations/previews; multiple image outputs; GPS checks; bounded measured size search and sharing presets.

Remaining: pinned qpdf structural operations/optimization; broader encrypted/signed/form PDF corpus; full image HDR/profile/animation loss matrix and preview/export parity checks; more page/image geometry and size-constraint fixtures. Keep structural optimization distinct from destructive image-downsampling compression.

## 3. Audio and video

Implemented: native compatible exports, trim/speed/mute/resize/crop/rotate/matching joins/audio extraction/frame export; FFmpeg adapter with actual codec/muxer probing, primary stream-copy checks, advanced filters/normalization/GIF/size targets; native SRT/VTT conversion.

Initial Media 0.1.2 is a published FFmpeg qualification preview with a verified LGPL configuration and full source; it is not the complete Media pack. Remaining: pinned LAME/libopus/libvpx dependencies and the full runtime/corpus/platform delivery gate, user-selectable tracks, text-subtitle extraction and selectable/burned-in subtitles, waveforms/playback trim UI, media metadata verification, HDR/alpha handling, variable-frame-rate/timestamp/synchronization and cancellation corpus. Bitmap-subtitle OCR stays later work.

## 4. Documents, spreadsheets and text

Implemented: independently versioned-tool manifest support; LibreOffice/Pandoc adapters; isolated macro-disabled profiles; all/selected sheet delimited export; explicit text encoding; table preservation; static HTML PDF rendering boundary.

Remaining: independently built signed Documents pack; full editable interchange coverage; rendered page previews and missing-font/content notices; delimiter/encoding/header/date/sheet preview UI; adversarial macros/external links/package limits; reference layout corpus for documents, slides, formulas and sheets. PDF-to-Word reconstruction remains separate. Use upstream LibreOffice/Pandoc models rather than a new complete Office document model.

## 5. Archives and ebooks

Implemented: safe system-libarchive ZIP/TAR/TAR.GZ/7z operations, content preview/selection, portable-permission notices and expansion limits; Calibre conversion adapter and native EPUB container detection.

Remaining: pinned bundled libarchive, RAR fixture corpus/repackaging workflow, EPUB metadata/cover editing and chapter/navigation previews, signed Calibre Ebooks pack and reopen/navigation validation. Only legitimately openable inputs are supported; no DRM removal.

## 6. Recipes and Mac workflows

Implemented: versioned recipes, ordered lossless preparation and multiple exports, editor/import/export, starter recipes, source lineage, preserved relative folders, naming previews, CLI recipe execution, Finder Service, Shortcuts conversion action, opt-in stable-file watchers, drag/copy/reveal/shelf, hash-checked generated-file removal.

Remaining: dedicated Finder Quick Action extension, recipe selection through Finder/wheel/Shortcuts, complete recipe compatibility preflight, cross-entry consistency corpus, batch destination rules UI, safe generated-folder removal, watcher concurrency/output-loop/duplicate failure qualification. Automation remains opt-in and interrupted manual jobs never silently rerun.

## 7. Transcription and advanced scans

Implemented: local OCR, perspective/contrast scan cleanup, streamed searchable-PDF output preserving physical page geometry, whisper.cpp adapter with verified model paths and TXT/SRT/VTT outputs.

Remaining: signed Transcription pack and explicit model download/removal UI, transcript editing and timing review, experimental scanned-table export with an editable preview, representative language/noise/timing/model cancellation corpus. Recognition accuracy must be disclosed and reviewed.

## Distribution and verification throughout

Ship independently useful releases in this order only after their gates pass. Direct download uses Developer ID signing, hardened runtime and notarization, with full engine/model notices and applicable source obligations. The local app now has Developer ID signing, a secure timestamp, hardened runtime, accepted notarization and a stapled ticket that passes Gatekeeper. The remaining product release gates are still pending.

Every milestone needs generated or permission-cleared fixtures, independent reopening, original integrity, actual cardinality and measurements, accurate partial failures, crash/cancellation/grant/disk testing, accessibility/VoiceOver/keyboard and appearance acceptance, macOS 13/current macOS on Apple silicon, and clean offline installation. Unsupported or experimental paths must remain clearly marked. Network access serves explicit downloads and update checks only.

Full document authoring, video timelines, guaranteed editable PDF reconstruction and App Store packaging remain outside the approved initial scope.
