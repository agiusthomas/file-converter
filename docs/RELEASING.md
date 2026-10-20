# Release flow

Use the existing checkout at `/Users/thomasagius/Documents/Projects/file-converter` and remote `agiusthomas/file-converter`. This records the successful [0.2.1 Preview](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.1) flow from 20 October 2026. Read it before preparing another release. Preserve unrelated changes and published artifacts, tags and checksum associations.

## Reuse the secure local setup

`scripts/signing-config.sh` reads the ignored `Configuration/Signing.local.plist`: `identity`, `team`, `notaryProfile`, and optional `notaryKeychain`. Existing `CONVERTER_*` environment overrides take precedence. Credentials remain in Keychain. Reuse this working configuration without requesting private keys/passwords or committing local settings, certificates or caches. Do not print configuration or credential material into logs.

The restricted command environment can report zero signing identities even when Developer ID works. Signing, Apple services, notarization, disk-image operations and GitHub networking worked with normal macOS/Keychain access outside that restriction. Use the environment's approved escalation mechanism when needed; distinguish a sandbox limitation from genuinely missing configuration. Never substitute ad-hoc signing, disable Gatekeeper/library validation, strip quarantine, or weaken the worker sandbox to pass a release check.

## Prepare a fresh version

1. Inspect Git status, fetch the remote, and check for conflicting changes and existing tags/releases. Preserve unrelated changes. Reuse current authorization when the user has already requested pushing/publishing.
2. Give changed app/pack artifacts new versions. Align app version/build in `project.yml`, generated Info plists/Xcode project and `EnginePacks.appVersion`; regenerate the project when required. Keep `io.local.file-converter.worker.production.v3` stable across routine version bumps: it identifies a worker protocol/store, not an app build number.
3. Future source builds produce `build/Glacier File Converter.app`. Preserve any previous unversioned Glacier app under a versioned backup when needed; leave the legacy `build/File Converter.app` and its published artifacts intact. Retain old DMG/ZIP/checksums. Scripts overwrite local artifacts for the current version; do not rebuild a published version to replace its downloads. The original `build/SHA256SUMS.txt` remains associated with 0.2.0; newer releases use version-specific checksum filenames.
4. Update `docs/INSTALLATION.md` **before packaging**; the DMG copies it as `Install Glacier File Converter.txt`. Write release notes under `docs/releases/` and align README, implementation status, continuation plan, handoff and evidence. Distinguish implemented, verified, shipped, experimental and blocked work. Keep unfinished features and qualification gaps explicit. The user requested 1.0.0 as the first official release of the available features; publication/notarization does not complete the separate expansion milestones.
5. Run relevant tests and production acceptance. For 0.2.1, `FILE_CONVERTER_MEDIA_TESTS=1 FILE_CONVERTER_EXTERNAL_TESTS=1 ./scripts/swift-local.sh test` passed 64 tests without skips. Developer-installed tools supplement tests; they do not prove delivered packs. Engine proof uses independently packaged runtimes through the Developer ID signed app's sandboxed XPC worker. Record unavailable platform/manual checks honestly.

## Renamed releases

The first official release is **Glacier File Converter 1.0.0**, build 4, requested by the user. Use the new app name, disk-image title and `Glacier-File-Converter-VERSION` filenames. Future publication requires authorization; use a fresh version for changed artifacts. Do not run the release pipeline to replace an already-published version. Preserve all historical links and assets under their original names.

Keep `io.local.file-converter`, worker service identifiers, existing Library storage paths, preferences and engine versions unchanged. Include the first renamed update steps from `INSTALLATION.md` in the next release notes: quit the old app, install Glacier File Converter, remove the old application copy, and preserve Library data. The installer instructions must accurately state which renamed release has actually shipped before packaging.

## Build, notarize and package

From the project root, with normal Keychain access:

```sh
./scripts/release-app.sh > build/release-NEW_VERSION.log 2>&1
```

The pipeline builds the release app and CLI/worker, signs nested code and the app with Developer ID, a secure timestamp and hardened runtime, and verifies strict nested signatures. It submits an app ZIP, staples the accepted ticket to the app, assesses Gatekeeper, and recreates the ZIP so it contains the stapled app. `scripts/package-dmg.sh` packages that app with an Applications shortcut and installation instructions, signs/notarizes/staples/verifies the DMG, and verifies its disk image. The release script produces:

- `build/Glacier-File-Converter-VERSION.dmg`
- `build/Glacier-File-Converter-VERSION.zip`
- `build/Glacier-File-Converter-VERSION-SHA256SUMS.txt`

Require **Accepted** for both notarization submissions and retain their IDs/statuses. Require successful staple validation, strict signatures, Gatekeeper's **Notarized Developer ID** assessment and disk-image verification. The script exiting successfully does not establish feature acceptance.

Verify final checksums from `build/`. Extract the final ZIP and read-only mount the DMG; check each contained app's nested signatures, ticket, Gatekeeper assessment, version/build and CDHash. Check the DMG shortcut/instructions. Compare the final app CDHash with the build used for signed-app acceptance; repeat affected acceptance if signed code/resources differ. Verify original artifacts still match their checksums.

Record public evidence under `docs/evidence/`: versions/source references, artifact names/byte sizes/SHA-256, publisher team, app CDHash, notary IDs/statuses, tests and qualification limits. Keep raw local logs under ignored `build/`. Examples: [0.2.1 distribution evidence](evidence/app-0.2.1-release.json) and [Media acceptance](FFMPEG_CHECKPOINT.md).

## Push, stage, check CI, publish

Commit the implementation, notes and evidence, then push the intended branch without force. Capture the full pushed SHA. Watch GitHub's workflow for **that exact SHA**, rather than a previous successful run. Require the macOS tests, release build and strict signature check to pass before publication. `gh run watch RUN_ID --exit-status` worked; retain the run URL in the release notes.

This template stages a draft while CI runs. Substitute a fresh numeric version and actual notes path:

```sh
release_version="NEXT_VERSION"
release_tag="v$release_version"
release_commit="$(git rev-parse HEAD)"
gh release create "$release_tag" \
  "build/Glacier-File-Converter-$release_version.dmg" \
  "build/Glacier-File-Converter-$release_version.zip" \
  "build/Glacier-File-Converter-$release_version-SHA256SUMS.txt" \
  --repo agiusthomas/file-converter --target "$release_commit" \
  --title "Glacier File Converter $release_version" \
  --notes-file "docs/releases/$release_version.md" \
  --draft --prerelease=false --latest=false
```

Inspect the draft with `gh release view`: tag name, target SHA, draft/prerelease flags and exact asset set. Compare GitHub's asset digests/byte sizes with local evidence. Draft URLs may contain `untagged-...`; the final tag URL is established on publication. Reuse a matching interrupted draft; do not create duplicates or replace published assets.

After the exact commit's CI succeeds, publish the prepared official release:

```sh
gh release edit "$release_tag" --repo agiusthomas/file-converter \
  --draft=false --prerelease=false --latest=true
```

Verify the release is public, is marked as the latest official release (not a prerelease), and has the intended final download URLs/digests/sizes. Fetch its tag and confirm it resolves to the exact tested/pushed commit. Check the working tree/remote branch and previous published artifacts/checksums. Report the release URL, pushed commit, checks and remaining qualification limits. Documentation-only follow-up notes do not need another app release.

## Packs have separate immutable releases

Follow [the pack producer workflow](ENGINE_PACKS.md). Build pinned relocatable runtimes independently; include notices, applicable complete corresponding source and build records; audit deployment/dependencies; sign nested code/pack; notarize; and prove signed-app execution/cancellation/lifecycle. Publish ZIP/source/checksums under a new pack version. Seal its exact URL/hash/sizes/platform/publisher metadata into the catalog of a **new signed app version**. Neither a signing fixture nor a developer-installed engine proves a production pack.

## Successful reference

- App source/tag: `63be4ebb260313a708d13ac698891e0a7f5cafb1`, `v0.2.1`, app 0.2.1 build 3.
- [Exact-commit GitHub verification](https://github.com/agiusthomas/file-converter/actions/runs/39440457668): tests, release build and strict signature check passed.
- App notary ID: `4e0bd767-6727-4d47-97aa-953bbbadb0de`; DMG: `460374fe-d9b1-4ff1-a9a6-8e9e8dfe0778`; both Accepted, stapled and Gatekeeper verified.
- Release app and packaged copies matched acceptance CDHash `3a6ab6b66659f3139e4db768b75c46feed847515`.
- [Media 0.1.2 qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2) is a separate immutable release. Original 0.2.0 downloads/checksums were preserved and compared with GitHub digests.
- Tested host: macOS 26.5.1 arm64. macOS 13 execution, clean offline second-host installation and other milestone gates remained unverified when the user explicitly requested publication of 0.2.1.
