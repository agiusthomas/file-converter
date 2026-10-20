# Engine-pack producer workflow

The 0.2.1 candidate includes a sealed catalog entry for [Media 0.1.2](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2), a signed/notarized FFmpeg 8.1.2 **qualification preview**. The published 0.2.0 app and its empty catalog remain unchanged. Documents, Ebooks, Transcription and PDF structure packs are still required and unpublished. See [exact runtime evidence and limits](FFMPEG_CHECKPOINT.md).

In the candidate's **Engines** screen, review sizes/compatibility/notices, explicitly download/install, cancel or retry, inspect source/licenses, update, roll back or remove. Idle changes refresh the coordinator and wheel without restarting; existing queues retain immutable runtime pins until they finish. Removal waits for live app/CLI snapshots and then reclaims files. A source build without the publisher's Developer ID cannot install its downloadable executable code; signature checks are never relaxed for development.

## Assemble a runtime

Build an arm64 macOS 13-compatible relocatable runtime independently. Supply its complete libraries/resources, exact engine versions, build flags, license notices and required source offer. Do not copy tools from another installed app. The pack must function without network access and with only staged input/output access. Flatten necessary runtime links during your own packaging; this installer rejects symbolic links.

`examples/media-pack.json` illustrates a producer configuration. All tool, license, and model paths are relative to the payload folder. Include helper executables in `tools` so download installation can restore their executable permission. Declare LibreOffice and Pandoc independently in `engineVersions`. For transcription, `models` maps model names to payload paths; each is hashed like every other file.

For the initial independent FFmpeg runtime (Python 3.12+ and Xcode command line tools on arm64):

```sh
python3 scripts/build-ffmpeg-runtime.py --version 8.1.2 --pack-version NEW_VERSION
python3 scripts/validate-engine-runtime.py build/ffmpeg/8.1.2/payload
```

Use a fresh work/output location for subsequent builds and a new numeric version for changed artifacts. The source archives, SHA-256 pins, exact flags/toolchain, licenses and complete corresponding source are retained. This initial build lacks LAME/Opus/VP9 dependencies and is not the final Media configuration. `sandboxInheritance: true` signs child tools with `app-sandbox` plus `inherit`; dylibs have ordinary hardened-runtime signatures.

```sh
python3 scripts/build-engine-pack.py \
  --config /path/pack.json \
  --payload /path/independent-runtime \
  --output /path/Media-1.0.0.bundle \
  --identity 'Developer ID Application: YOUR IDENTITY' \
  --notary-profile YOUR_STORED_PROFILE
```

The builder signs nested Mach-O code, creates a signed bundle anchor, hashes payload files after signing, writes `Contents/Resources/engine.json`, signs/verifies the outer bundle, and creates a ZIP without AppleDouble resource sidecars. Signed logical installed bytes include the seal/manifest/anchor. Notary submissions must report Accepted; their JSON is retained. Use `--notary-keychain` when the existing secure profile is stored outside the default keychain. Omitting the identity creates an unsigned inspection fixture which production verification deliberately rejects. A build cannot prove correct runtime relocation, license compliance, codec quality, or sandbox operation; run the release corpus against the actual signed pack.

The manifest records schema version, ID, numeric pack version, compatible app/OS, arm64 architecture, tool paths, file checksums, license paths, engine versions, installed bytes, and model paths. The builder prints the ZIP size and SHA-256. Add a release HTTPS URL and those exact fields to `Configuration/EngineCatalog.json`, regenerate the project, then sign a new app release. Catalog entries are sealed into the signed app; unsigned remote catalogs cannot activate executable code.

## Trust and updates

The manager requires an Apple Developer ID Application signature from the app’s own signing team. It checks compatibility, signatures, file hashes, executable paths, licenses, and model declarations before activation. Downloads require the bundled catalog’s exact HTTPS URL, size, hash, and pack identity. Archives pass the same path/link/expansion checks as normal extraction.

Installation copies into a temporary location, verifies again, then selects a versioned immutable bundle with an atomic current pointer. A previous pointer permits rollback. Reusing a version with different manifest/payload content fails; retrying an active version preserves rollback. Downloads stream to disk with the catalog's byte ceiling enforced during receipt, refuse HTTP downgrades, and check compatibility/space/size/hash before extraction and full publisher verification. Cancellation is checked before activation.

The app-owned store is `~/Library/Application Scripts/io.local.file-converter.worker.production.v3/File Converter/Engines`. This stable worker protocol generation has existing static read/execute access there; no write bookmark to code is passed to the worker. Data is staged in the worker container so signed child tools can use inherited sandbox rights without dynamic bookmark access. The worker re-verifies code/hashes and maps validated outputs back to the app's normal exclusive-publication stage. No extra worker entitlement, sandbox exception or disabled library validation was added.

Coordinator and inspection snapshots hold cross-process lease files. A store lock serializes pin/removal decisions and activation. Deactivation retains files; removal persists intent, clears current/previous pointers and deletes only unpinned versioned bundles. Unknown/corrupt lease records fail closed. The window retries deferred reclamation while pins exist; startup also resumes pending removals. XPC cancellation waits for child termination/cleanup acknowledgement before releasing operation pins.

The configured Developer ID and Keychain profile work with normal keychain access; the command sandbox can hide identities/trust. Real independently built FFmpeg packs now pass signed-app/XPC conversion, actual download interruption/retry, version update/rollback, tamper rejection, observed-child cancellation and pinned removal/reclamation on macOS 26.5.1. Native UI installation/import/update/rollback/removal and a downloaded-pack window conversion also pass. Pack 0.1.2 is notarized; app 0.2.0's notarization/Gatekeeper baseline remains preserved. The changed 0.2.1 app is a signed local candidate, not a newly notarized/published release. Minimum-OS/clean offline/failure/corpus/accessibility gates remain open. Never turn off signature checking to make a pack appear installed.

Apple’s [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) govern the public release. FFmpeg’s [build-dependent license requirements](https://ffmpeg.org/legal.html) and every other engine/model’s own terms must accompany its pack.

For CLI isolation, `FILE_CONVERTER_ENGINE_DIRECTORY` selects a separate store without relaxing signatures. Sandboxed app acceptance must keep executable packs under its static helper directory; the harness creates an isolated `Acceptance-*` store there and uses only generated `/private/tmp` fixtures. It never changes the normal active version.

```sh
python3 scripts/qualify-media-pack.py \
  --app 'build/File Converter.app' \
  --pack build/Media-0.1.0.bundle --update build/Media-0.1.2.bundle \
  --download-update --runtime build/ffmpeg/8.1.2/payload \
  --root /private/tmp/NEW_UNIQUE_QUALIFICATION_FOLDER
```

The runner observes a real FFmpeg PID parented by the sandboxed XPC service before cancellation, checks that it exits, and independently probes/fully decodes all completed outputs. This uses neither the development CLI nor injected adapters for app conversions. The bundle anchor is protected by the outer signature and intentionally excluded from payload hashes, avoiding a circular seal.
