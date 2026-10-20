# Real FFmpeg pack qualification

20 October 2026. Checkpoint 1 is **verified on the current Mac**. This is not completion of a milestone or the full Media pack. Published app 0.2.0 remains unchanged. The new app preview is 0.2.1 (build 3).

## Independently built runtime

`scripts/build-ffmpeg-runtime.py` downloads checksum-pinned official source, compiles arm64 with a macOS 13.0 deployment target using Apple Clang, and assembles a symlink-free runtime. No installed application or Homebrew runtime is copied. `--disable-autodetect` prevents build-machine codec dependencies. FFmpeg networking, device capture, GPL, nonfree and version3 features are disabled; VideoToolbox and AudioToolbox are explicitly enabled. The pack includes the complete unmodified source archive, build script, exact compiler/configuration record, LGPL license and upstream notices.

| FFmpeg | Official source SHA-256 |
| --- | --- |
| 8.1.1 | `b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3` |
| 8.1.2 | `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c` |

Both runtimes have passed `scripts/validate-engine-runtime.py`: arm64 only, every Mach-O deployment target 13.0, all six FFmpeg shared libraries present at relative `@rpath` locations, and only Apple system dependencies outside the pack. This is a deployment/load-command audit, **not execution on macOS 13**. Qualification host: macOS 26.5.1, Xcode 26.5, Apple Clang 21.0.0.

| Local artifact | Runtime | ZIP bytes | ZIP SHA-256 | Apple notarization |
| --- | --- | --- | --- | --- |
| Media 0.1.0 | FFmpeg 8.1.1 | 21868381 | `814a73de39bdac36596df51b38e55e46cab06caac8186725639ff4e899ca4312` | Accepted, `c97a6f07-8ce8-4533-81b4-9bb8c30dcee1` |
| Media 0.1.1 | FFmpeg 8.1.2 | 21870879 | `2b3bc10572a99c21c105d93fd379d69279ec14a18293c38611c68301496f8697` | Accepted, `de75aea9-6916-411e-8d9c-d7f58391f209` |
| Media 0.1.2 | FFmpeg 8.1.2 | 21870879 | `419e2db4491978df9773ef5b7ee70edf1aeb4b2f51265065566e931052791dbb` | Accepted, `84e39575-7094-489b-82f5-63900b703e38` |

Artifacts and build/signing/notarization logs are retained under ignored `build/`. Media 0.1.2 is now a [published/downloadable qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2), with the matching source archive and checksums. The exact artifact URL, SHA-256, sizes, platform limits and publisher team are sealed into the 0.2.1 app catalog. Media 0.1.0/0.1.1 remain local acceptance artifacts. 0.1.0 and 0.1.1 undercount signed installed bytes; 0.1.2 fixes this with an exact signed logical size of 33,491,160 bytes. Versions are immutable; do not replace earlier ZIPs under their existing version.

These initial LGPL runtimes provide native FFmpeg codecs and Apple hardware encoders, but do **not** include LAME, libopus or libvpx. MP3/Opus/VP9 WebM encoding and its pinned dependencies, notices and corpus remain required for the complete Media milestone. Actual encoder/muxer probing hides absent profiles.

## Production sandbox architecture

The real runtime exposed a failure that the owned signing fixture never exercised: a bookmark permits reading installed code, but does not grant process execution. Copying mode-0755 tools into the worker container also failed the executable-access check on this host. No signature or sandbox check was removed.

The app now installs immutable, publisher-verified engines under `~/Library/Application Scripts/<production-worker-service>/File Converter/Engines`. macOS already gives that worker static read/execute access to its own Application Scripts directory; the worker cannot write it. The envelope deliberately supplies **no write bookmark to engine code**. The worker re-verifies bundle/team/tool signatures and every payload hash before use.

Incoming job data is cloned/copied to a private worker-container workspace because child processes do not inherit dynamic bookmark extensions. The child inherits the worker sandbox, reads its statically accessible signed code/libraries, and reads/writes only container-staged data. The worker copies validated outputs back to the coordinator's stage and remaps source lineage before normal exclusive publication. Cancellation terminates the child before workspace cleanup. No new worker entitlement, temporary sandbox exception, disabled library validation, network entitlement, quarantine removal or private sandbox API was added.

`scripts/build-engine-pack.py` signs FFmpeg and ffprobe with `app-sandbox` plus `inherit`; dylibs retain ordinary hardened-runtime signatures. The signed anchor remains outside manifest payload hashes, avoiding a signature/hash cycle. Notary submission must explicitly report Accepted; its JSON record is retained.

## Actual-app acceptance

`scripts/qualify-media-pack.py` launches the **signed app bundle**, whose opt-in `--engine-acceptance` entry point uses `JobCoordinator`, `XPCWorkerTransport`, production pack verification, staging and publication. The embedded CLI and test-injected adapters are not used for conversions. Only fixture generation and independent full output decoding use the unsigned, independently compiled runtime.

Generated fixtures: two-second 44.1 kHz mono sine WAV, two-second 320×180 MPEG-4/AAC video, and a 120-second 1280×720 cancellation video. The harness tests tamper rejection, failed-update preservation, conversions, an actual FFmpeg-version update, rollback, deactivation with a pinned coordinator, source hashes and cancellation. The external runner must observe a real FFmpeg child parented by the app's XPC worker before requesting cancellation, confirm that PID exits, then independently probe and decode outputs.

**Verified:** the signed-app harness passes audio/video conversion, independently probed/fully decoded outputs, unchanged original hashes, real runtime-version updates/rollback, tamper rejection, reinstall preserving rollback, observed FFmpeg child cancellation, deferred removal while pinned, and reclamation after release. Cancellation returns only after the worker acknowledges child termination/cleanup.

- `/private/tmp/file-converter-media-acceptance-06`: FFmpeg 8.1.1 → 8.1.2 update and original observed-child proof.
- `/private/tmp/file-converter-media-acceptance-07`: exact Media 0.1.2 audio/video/cancellation and safe removal; a second real version is used to exercise rollback.
- `/private/tmp/file-converter-media-download-08`: actual sealed-catalog HTTPS download cancelled after **13,771 received bytes**, active runtime unchanged, then successful retry/install of 0.1.2. Updated FLAC and H.264/AAC outputs independently reopen/decode. Real-version rollback, tamper rejection, cancellation and reclamation also pass.
- `/private/tmp/file-converter-media-final-09`: repeated signed-catalog download/cancellation/retry and full lifecycle proof after publisher-team compatibility metadata; cancelled after 1,369 received bytes.
- `/private/tmp/file-converter-media-root-guard-10`: real-pack positive path after rejecting symbolic-link bundle roots. Final lease-directory safety guards and peak-copy space accounting pass the 64-test suite.
- `/private/tmp/file-converter-media-verified-11`: frozen signed build, catalog download cancellation after 7,734 received bytes, retry/install, independent audio/video decoding, actual child cancellation, rollback and pin-safe reclamation all pass. Exact app CDHash is retained in the evidence summary.
- Native signed window: available/installed sizes and notices; explicit download/install; license/source/version disclosure; local import of Media 0.1.0; download update to 0.1.2; rollback to 0.1.0; removal and actual file reclamation; refreshed capabilities without restart. A window-launched job `534A0130-20E8-4B7C-8DDA-0D9E64DF3DFE` used downloaded Media 0.1.2 and independently decoded as H.264/AAC, 2.020 seconds, with its original hash unchanged. UI cancellation could not be triggered before this fast download completed; do not count that attempted click as a manual pass. The signed-app byte-observed cancellation test passed.
- 64 tests pass with all seven opt-in native/OCR/development-engine tests enabled. Development-installed-tool regressions supplement the separately verified real-pack path; they do not replace it.

[Machine-readable evidence](evidence/media-0.1.2-checkpoint.json) retains fixture/output hashes, runtime versions, notarization ID, actual child/parent PIDs, output codec/duration results and the limitations. Failed runs are retained as failures: initial execution access denied, container-copy execution still denied, and a harness GIF title mismatch rejected preflight before engine launch. Those runs are never counted as passes.

## Still required

- Full LAME/Opus/VP9 dependency configuration and Media format/track/subtitle/playback/corpus gates.
- Remaining milestone 1 malformed/oversized/truncated download, interrupted activation, low-space/worker/app crash/grant/publication recovery and responsiveness qualification. Implemented guards and existing unit tests do not complete that full matrix.
- macOS 13 execution and clean offline installation on suitable hosts. This session has only macOS 26.5.1; deployment/load-command validation cannot replace those tests.
- Full physical Finder gesture and VoiceOver/appearance acceptance.
- Other production runtime/model packs and all remaining milestones in `CONTINUATION_PLAN.md`.

The [0.2.1 app preview](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.1) is separately Developer ID signed, notarized, stapled and published at the user's request; [distribution evidence](evidence/app-0.2.1-release.json) is separate from these runtime acceptance results. Publication does not close the remaining milestone gates. Published 0.2.0 app/DMG/ZIP/checksums remain preserved. Media 0.1.2 is a public qualification preview with an explicit limited codec and platform qualification scope.

Sources: [FFmpeg releases](https://ffmpeg.org/releases/), [FFmpeg build-dependent license guidance](https://ffmpeg.org/legal.html), [Apple sandbox file and process access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox). The helper-directory access was also inspected in this host's unmodified Apple sandbox profile; no profile is edited or bundled by this project.
