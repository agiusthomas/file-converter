# Glacier File Converter — completion plan

**Glacier File Converter 1.0.0** (build 4) is the first official release, requested by the user, including the faceted ice icon, unchanged interface colors/layout and recent Finder-wheel/background-conversion fixes. Build output is `build/Glacier File Converter.app`; downloads start with `Glacier-File-Converter-`. Preserve bundle/worker identifiers and existing storage paths; historical release artifacts keep their original names. This official release does not close the unfinished expansion milestones. See [release notes](releases/1.0.0.md).

Updated 20 October 2026. This is the execution plan for finishing the approved seven-milestone expansion. Read it alongside [implementation evidence](../IMPLEMENTATION.md), the [roadmap](ROADMAP.md), and the [new-conversation handoff](NEW_CONVERSATION.md).

## Objective and current truth

Deliver the full local file utility originally requested: conversion, compression, extraction, lightweight preparation, recipes, and Mac workflows. Preserve the existing SwiftUI/AppKit app, Glacier design, Finder wheel, macOS 13+ deployment target, and Apple-silicon support.

**The original plan is not complete.** Versions 0.2.0 and 0.2.1 are partial previews. Its successful signing, notarization, and publication do not establish feature completeness or completion of any milestone's full release gate.

The largest immediate gap is that most optional engine adapters still lack usable production packs. Media 0.1.2 now provides a limited qualification preview; it does not finish the required Media runtime or its acceptance gate. Calling a pack optional describes how users install it; delivering that pack is still required by the approved plan. Do not finish this work with another release whose required features are unavailable because their packs were never delivered.

### Repository and published baseline

- Work in `/Users/thomasagius/Documents/Projects/file-converter`.
- Repository: <https://github.com/agiusthomas/file-converter>, branch `main`.
- Baseline implementation/release commit: `7b9760c6edf89508c0a88f1291974d32a6285e72`. Later planning or implementation commits may follow it; inspect the actual checkout before editing.
- Preserved preview: <https://github.com/agiusthomas/file-converter/releases/tag/v0.2.0>.
- Preserved preview: [0.2.1](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.1), published at the user's explicit request after checkpoint 1. It includes real Media 0.1.2 download/lifecycle support; it does not close any milestone's full acceptance gate. [Release changes/limits](releases/0.2.1.md), [distribution evidence](evidence/app-0.2.1-release.json).
- The preview includes a notarized app, notarized DMG, ZIP, checksums, and installation instructions. Preserve those versioned artifacts; use new versions for changed binaries and packs.
- The 58-test suite passed locally with opt-in native media/OCR and external-engine integration checks. The release commit also passed GitHub's macOS tests, build, and signature checks. These are baseline evidence, not a substitute for the remaining acceptance work.
- Developer ID signing and notarization are configured locally. The ignored `Configuration/Signing.local.plist` references the signing identity and Keychain notarization profile. Use the existing scripts and secure configuration; do not request credentials again unless an actual check fails. Never commit private keys, passwords, local signing settings, or compiler caches.

### What users can and cannot do today

| Area | Current baseline | Outstanding delivery |
| --- | --- | --- |
| Shared jobs | Staged inputs, XPC worker, persistent queue/retry, manifests, exclusive publication and real FFmpeg sandbox execution | Full failure/recovery qualification and responsiveness benchmarks |
| Images/PDF | Native image operations, bundled still WebP, PDF page tools/passwords/OCR/searchable PDF | qpdf structure tools, complete preservation/loss notices and representative parity/corpus checks |
| Audio/video | Native compatible exports, basic preparation and initial signed FFmpeg Media 0.1.2 preview | Complete Media dependencies, track/subtitle controls, playback/waveforms, broader media qualification |
| Office/Markdown | LibreOffice/Pandoc adapters and development integration tests | Signed Documents pack, usable document/sheet previews, font/content notices and full interchange coverage |
| Archives/ebooks | Bounded system-libarchive operations; Calibre adapter | Pinned archive runtime, qualified RAR extraction/repackaging, EPUB editing/navigation, signed Ebooks pack |
| Recipes/Mac | Recipe editor/CLI, Finder Service, Shortcuts conversion, watchers and shelf | Dedicated Quick Action, recipe entry-point parity, destination UI and automation/removal qualification |
| Transcription/scans | Vision OCR/scan processing; whisper.cpp adapter | Signed Transcription pack, model management, editable transcript/timing review, experimental table workflow |
| Distribution | Developer ID app/DMG signing, notarization, installation docs and real Media download/lifecycle | Remaining production packs, clean offline installation and full platform/accessibility/failure acceptance |

Adapter source, a generated signing fixture, a test using a developer-installed tool, and a user-installable pack are different evidence. Report which one was tested.

## Completion rules

An operation is delivered only when its intended user can select it in the app, supply its options, run it through the production coordinator and worker, reopen the output independently, and see meaningful losses/errors. Where the CLI, wheel, Finder, Shortcuts, or recipes apply, they must use the same behavior and capability checks.

A pack is delivered only when its real runtime is reproducibly assembled, compatible with the supported Mac, signed and verified, downloadable from the app, cancellable during installation, usable offline after installation, and covered by install/update/rollback/removal tests. It must include its notices and any applicable source obligations. An empty catalog or a local-only import does not satisfy download delivery.

Use a status ledger with **not started**, **in progress**, **implemented / unverified**, **verified**, or **blocked with evidence**. Record code, exact runtime versions, fixtures, observed results, and remaining limitations. A skipped test is not a pass. Do not replace working built-in code merely to make the architecture look complete, or silently narrow the approved scope.

Keep processing local. Network access is for explicit engine/model downloads and update checks. Preserve image quality/metadata preferences, source integrity, output naming, macOS 13 availability checks, and one active conversion worker until measurements justify more. Interrupted manual jobs require an explicit retry.

## Execution order

Start with checkpoint 1 below. It is an early engineering proof for the shared architecture, not a reason to publish a later milestone before earlier gates pass. Then finish milestones in the original order. Make concrete code and runtime deliveries, not another planning-only cycle.

### Checkpoint 1 — prove a real production pack

Current status: **verified on the current Mac**. Independent FFmpeg 8.1.1/8.1.2 runtimes execute through the Developer ID signed app and sandboxed XPC worker. Observed-child cancellation, original integrity, independent reopening, real-version update/rollback, tamper rejection, reinstall rollback preservation, pinned removal/reclamation and actual catalog download interruption/retry pass. Media 0.1.2 and the separately notarized app 0.2.1 are published as qualification previews. Native window download/import/update/rollback/removal and downloaded-pack conversion pass. Exact builds, artifacts, observed results and platform/codec limits: [checkpoint evidence](FFMPEG_CHECKPOINT.md), [machine-readable summary](evidence/media-0.1.2-checkpoint.json). This engineering checkpoint does not pass the full milestone 1 or Media release gate.

- [x] Audit `EnginePacks.swift`, `WorkerTransport.swift`, `ExternalEngine.swift`, the bundled catalog, pack builder and worker entitlements. Confirm what the signed app actually grants to an installed executable, its libraries/resources, staged inputs and outputs.
- [x] Build a pinned, relocatable arm64 FFmpeg runtime independently, with an explicit codec/license configuration and all required dependencies/notices. Choose and verify versions against macOS 13; do not assume current upstream binaries meet that target. Do not copy executables out of another installed app or require Homebrew on the user's Mac.
- [x] Validate architecture, deployment target, dynamic-library paths, resource discovery and child-process cancellation for the whole runtime. Sign nested executable code and the pack without circular manifest hashing. Notarize executable pack artifacts as needed for direct distribution.
- [x] Install the real pack into an isolated test store through production verification. Run an audio and a video conversion from the Developer ID signed app through its sandboxed XPC worker, with originals protected. Reopen the outputs and confirm cancellation terminates child processes.
- [x] Test update and rollback between actual runtime versions, tamper rejection, and removal deferred while a job pins a version. Preserve the previous working version after an unsuccessful update.
- [x] Record the exact build, manifest, signatures, fixture results and production path. If sandbox execution fails, fix the worker/access/pack architecture; do not disable sandboxing or signature checks, import another app's runtime, or claim the development CLI proves the app path.

**Checkpoint passes:** a real independently packaged engine, rather than the owned signing acceptance program, works through the installed signed app and production worker.

### Milestone 1 — finish the foundation and pack delivery

Current status: **in progress**. Media artifact publication and the sealed-catalog/native pack lifecycle are implemented and verified on this host. Cross-process runtime leases, deferred reclamation, same-coordinator capability refresh, bounded streamed downloads and cancellation-before-activation are implemented. The unchecked tasks below still require all their listed acceptance work; model management and the remaining production packs are not supplied by this Media preview.

- [ ] Reconcile every shared contract and cardinality with actual actions: one-to-one, many-to-one, one-to-many and multiple terminal outputs. Keep container and codec claims separate; preserve legacy image CLI fields and versioned generic JSON.
- [ ] Complete the engine/model installation UI: available vs installed vs incompatible, download/installed sizes, notices, explicit install, progress, cancellation/retry, activation, update, rollback and safe removal. Refresh capabilities safely while existing jobs keep their pinned runtime versions.
- [ ] Publish verified immutable runtime artifacts, then seal their final URLs, hashes and sizes into the app's trusted catalog. Do not weaken the catalog trust model or advertise a pack before its artifact exists and verifies. Audit the minimum app/OS version and architecture compatibility checks.
- [ ] Exercise interrupted/tampered downloads, truncated archives, low disk space, incompatible packs, interrupted activation, failed updates and rollback. Install/update must be atomic and preserve the current version on failure.
- [ ] Fault-inject worker crashes, app termination, cancellation, source changes, missing/revoked/stale folder access, disk full and publication/journal failures. Completed outputs remain accurate; retries do not duplicate completed exports or overwrite originals.
- [ ] Validate progress stages, cancellable low-priority previews, staged clone/copy cleanup and actual space estimates. Benchmark large batches for memory and UI responsiveness before considering parallel conversion.
- [ ] Validate physical Finder drags across displays, Spaces and screen edges, modifier changes, escape/cancellation, mixed selections and ordinary drags. Confirm launch-at-login and configurable modifiers work on installed builds.

**Gate:** image behavior remains intact; real pack installation/execution works; failure and restart cannot overwrite originals or falsely report success. Record manual checks separately from automated ones.

### Milestone 2 — finish PDF, images and sharing

- [ ] Bundle pinned qpdf structural support as originally planned. Separate structural optimization from raster/downsampling compression in actions, options, notices and documentation.
- [ ] Qualify PDF selection/order/count/geometry, per-page rotation/removal, split/merge, rendering DPI, image-to-PDF page size/margins/fit/background, selectable text, OCR and password opening/protection. Include encrypted, signed, form and annotated PDF fixtures; disclose transformations that invalidate signatures or remove features.
- [ ] Verify image orientation, transparency/background, animation/page/timing handling, HDR/bit depth, profiles, metadata copying and GPS-property removal. Supported animation paths must be explicit; show losses before export.
- [ ] Match source/result previews with actual resize/crop/rotation/export operations. Test multiple requested outputs, per-output recovery, and alpha/color behavior of the bundled WebP encoder.
- [ ] Qualify Smaller file, Email attachment, Compatible image and custom-byte-limit presets using measured outputs. A bounded search must explain an unreachable limit and offer revised constraints; it must not report success above the limit.

**Gate:** independent PDF/image reopening confirms page order/count, geometry, text and declared preservation; previews agree with exports; size claims match actual bytes.

### Milestone 3 — finish audio/video and subtitles

- [ ] Deliver the verified downloadable Media pack and publish a capability matrix generated from its actual encoders, decoders, muxers and formats. Qualify WAV/AIFF/FLAC/MP3/AAC-M4A/Opus and tested MOV/MP4/MKV/AVI/WebM input paths; advertise only tested combinations.
- [ ] Finish playback previews and waveforms for audio trim selection; sample-rate/channel/bitrate controls, audio extraction and loudness normalization must affect the exported result.
- [ ] Implement selectable audio/video/subtitle tracks with languages and defaults visible. Avoid silent track loss; expose codec/container compatibility and stream-copy vs re-encode decisions before execution.
- [ ] Finish compatible H.264/AAC MP4, supported HEVC/WebM profiles, trim/crop/resize/rotation/mute/speed, compatible joins, frame extraction and GIF export. Validate HDR, alpha and color changes, including unsupported-path notices.
- [ ] Add supported text-subtitle extraction, selectable subtitle muxing and burned-in subtitles; verify SRT/VTT conversion and offsets. Bitmap subtitle OCR remains deferred as in the original plan.
- [ ] Qualify target-size compression against measured final sizes, duration/timestamps/rotation, variable frame rate, A/V synchronization, joins, track selection and cancellation on a representative corpus.

**Gate:** actual shipped codec/license configuration matches claims; fixtures verify duration, timestamps, synchronization, tracks and cancellation, with no silent unsupported losses.

### Milestone 4 — finish documents, spreadsheets and text

- [ ] Deliver independently versioned, pinned LibreOffice and Pandoc runtimes in the Documents pack, with complete relocatable libraries/resources, licenses and macOS 13 validation. Repeat the real signed-app/XPC/offline proof for both tools.
- [ ] Complete and qualify DOCX/ODT/RTF to PDF and editable interchange, PPTX/ODP to PDF, XLSX/ODS to PDF and delimited outputs, Markdown to/from HTML/DOCX/EPUB, rich text to plain text, and explicit text encoding/line-ending conversion.
- [ ] Add document/page previews, missing-font and unsupported-content notices. Compare common documents with reference renders; record acceptable differences and failures rather than promising exact Office fidelity.
- [ ] Add sheet selection and delimiter/encoding/header/date/leading-zero previews. Export one delimited output per selected sheet and explain formula-to-value and formatting losses. Never silently omit sheets.
- [ ] Audit macro suppression, external links/resources, isolated profiles, bounded package parsing and controlled local HTML/Markdown PDF rendering. Test adversarial fixtures and verify no external fetching or macro execution from the installed app.

**Gate:** a user can install the Documents pack and convert representative documents offline with previews/notices; layouts are reviewed, all selected sheets are present, and prohibited execution/fetching tests pass.

### Milestone 5 — finish archives and ebooks

- [ ] Replace the unpinned system archive dependency with qualified bundled libarchive support as planned. Deliver ZIP/TAR/TAR.GZ and tested 7z creation/extraction, RAR reading and extraction/repackaging to supported writable formats.
- [ ] Verify archive content preview, selected-member extraction, folder structure, permissions/metadata notices, member count/expanded size limits, path traversal, absolute paths, unsafe links, duplicate/case conflicts and special files. Reopen created archives independently.
- [ ] Add EPUB inspection, metadata/cover editing and chapter/navigation previews; document-to-EPUB uses the Documents pack.
- [ ] Deliver a pinned downloadable Calibre Ebooks pack for tested EPUB/AZW3/MOBI interchange. Verify its signed sandboxed execution, relocatability, offline operation, metadata/navigation and output reopening. Disclose layout changes.
- [ ] Keep DRM removal outside scope; support only files the engine can legitimately open.

**Gate:** archive outputs contain the expected members without escape or unbounded expansion; RAR has representative fixtures; ebooks reopen with valid navigation and declared content coverage.

### Milestone 6 — finish recipes and Mac workflows

- [ ] Finish recipe preflight across ordered steps, branching/terminal exports, intermediate formats, typed options and input/output cardinality. Avoid repeated lossy encoding; errors identify the incompatible step before execution.
- [ ] Qualify screenshot-sharing, compressed-recording, scan-cleanup and Office-to-PDF starter recipes using the real installed engines.
- [ ] Implement a dedicated Finder Quick Action extension and recipe selection through the wheel, Finder and Shortcuts; retain CLI recipe execution through the coordinator. Existing Finder Services alone do not fulfill the extension requirement.
- [ ] Complete batch naming/destination previews, destination rules and preserved relative source folders. Confirm aggregate outputs use the first input's folder by default.
- [ ] Qualify opt-in watchers for pause/resume, filters, stable-file detection, duplicate suppression, concurrent change handling and output-loop prevention. Interrupted manual jobs must not silently rerun.
- [ ] Complete drag-out/copy/shelf behavior and safe removal of generated folders as well as files, checking recorded identity/content before removal. Originals remain intact.

**Gate:** the same recipe yields equivalent validated outputs through the window, wheel, Finder, Shortcuts, CLI and watched folders, with entry-point differences explicitly justified and tested.

### Milestone 7 — finish transcription and advanced scans

- [ ] Deliver a signed pinned whisper.cpp Transcription pack and explicit model download/selection/removal UI, recording model versions, sizes, checksums, licenses and compatible runtime versions. Do not bundle a model without its required notices or silently download it.
- [ ] Support audio/video transcription with language selection and TXT/SRT/VTT exports. Add editable transcript and timing review before final export; preserve the relationship between reviewed text and exported subtitles.
- [ ] Qualify runtime/model installation, update/removal, offline operation, representative language/noise/timing accuracy, progress, resource limits and cancellation.
- [ ] Finish scan straightening, rotation and contrast cleanup; verify searchable text placement preserves page geometry through mixed page sizes and rotations.
- [ ] Implement experimental scanned-table export with an editable preview and clear accuracy limits. Label it experimental without treating that label as a substitute for implementing the workflow.

**Gate:** real downloaded runtime/models operate offline, transcripts and subtitle timing pass representative review, searchable PDF geometry is preserved, and the experimental table workflow is usable and clearly disclosed.

## Acceptance and release discipline

Apply these checks to every completed milestone, not only at the end:

| Category | Required evidence |
| --- | --- |
| Integrity | Original hashes unchanged; exclusive naming; expected output cardinality/source lineage; independent reopening; accurate partial publication |
| Recovery | Worker crash, app termination, cancellation, disk full, source changes, unavailable/revoked grants, interrupted install/download and cleanup |
| Formats | Image orientation/alpha/animation/profile; PDF pages/text/encryption; media timing/tracks/sync; Office fonts/tables/formulas/sheets; archive paths/expansion; ebook navigation; transcript timing |
| Distribution | Fresh installation, missing/incompatible/tampered packs, interrupted updates, rollback, model removal, no build-machine dependency and offline conversions |
| Experience | Keyboard and VoiceOver, Reduce Motion/Transparency, light/dark appearance, large batches, real Finder gestures and useful before-export loss notices |
| Platforms | Minimum macOS 13 and current macOS on Apple silicon; availability guards; whole runtime/dependency deployment compatibility |

Maintain generated or permission-cleared fixtures, automated regression coverage, a manual acceptance checklist and a runtime/feature evidence matrix. Use source-built/independently packaged engines for production proof; development-installed engines can supplement tests but cannot stand in for shipped packs.

Do not silently raise the minimum OS, weaken trust checks, remove a planned feature, or replace local processing with a service to close a blocker. Record the blocker and its evidence; seek a decision only when a genuine scope/platform change or external access is required. A manual check unavailable on the current Mac remains unverified.

Keep [IMPLEMENTATION.md](../IMPLEMENTATION.md), [ROADMAP.md](ROADMAP.md), the generated [capabilities](CAPABILITIES.md), user-facing availability, and release notes aligned. Report implemented, verified, shipped, experimental and blocked separately. Use new artifact versions for changes, preserve published version/checksum associations, and update installation instructions when the user flow changes. Signing/notarization alone never closes a feature gate.

Full document authoring, video timelines, guaranteed editable PDF-to-Word reconstruction, bitmap-subtitle OCR, DRM removal and App Store packaging retain their original deferred/out-of-scope status. Everything else listed above remains required.

## Current execution ledger

| Work | Status | Evidence / remaining gate |
| --- | --- | --- |
| Checkpoint 1 | verified | Real FFmpeg 8.1.1/8.1.2, signed XPC conversion/cancellation/lifecycle and actual network download; [evidence](FFMPEG_CHECKPOINT.md) |
| Milestone 1 | in progress | Native pack lifecycle verified; contract audit, fault injection, restart/activation failures, large batches and physical/accessibility/platform acceptance remain |
| Minimum macOS 13 / clean offline host qualification | blocked with evidence | Available host is macOS 26.5.1; Mach-O target audit passes 13.0 but is not execution. No macOS 13 or clean second Mac is available in this session. This blocks the release gate, not independent implementation |
| Milestone 2 remaining work | not started | Baseline native PDF/images retained; qpdf and broader preservation/corpus work still required |
| Milestone 3 remaining work | in progress | Initial real runtime exists; LAME/Opus/VP9, full codecs/tracks/subtitles/playback/corpus and platform delivery remain required |
| Milestone 4 remaining work | not started | LibreOffice/Pandoc production packs, previews, interchange and security corpus remain required |
| Milestone 5 remaining work | not started | Pinned archive runtime, RAR/EPUB workflows and Calibre pack remain required |
| Milestone 6 remaining work | not started | Dedicated Finder extension, recipe entry-point parity, destination/watchers/folder removal qualification remain required |
| Milestone 7 remaining work | not started | whisper.cpp/model delivery, transcript review and experimental scanned-table workflow remain required |

Next concrete work: complete milestone 1's fault/activation/download failure matrix and responsiveness/entry-point qualification. Execute macOS 13 and clean offline checks on suitable hosts before declaring a full release gate passed; the user-requested official 1.0.0 release retains these explicit qualification gaps. Continue the remaining milestones in the stated order. Do not repeat checkpoint 1 as another fixture-only or planning-only cycle.

## First-session deliverables and handoff

Checkpoint 1 and the initial Media download/lifecycle implementation now have real signed-app evidence. Resume the unchecked milestone 1 gates, retaining these working packs and tests; do not replace them with an adapter, CLI-only fixture or new plan. If a concrete blocker prevents that proof, document exactly what failed and continue independent authorized work.

At the end of each session, update the status ledger and give: commits/files changed, actual pack/artifact versions, tests and manual checks completed, unresolved failures, and the next concrete task. Keep the full scope visible until all required delivery and acceptance work is complete.
