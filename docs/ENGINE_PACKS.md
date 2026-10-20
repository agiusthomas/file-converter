# Engine-pack producer workflow

No public engine catalog or signed runtime is included in this development build. The native app works offline without optional packs. Install/verify/rollback/deactivate exist in the CLI; the window imports signed local bundles. A restart activates a fresh engine snapshot. Existing jobs retain immutable versioned paths.

## Assemble a runtime

Build an arm64 macOS 13-compatible relocatable runtime independently. Supply its complete libraries/resources, exact engine versions, build flags, license notices and required source offer. Do not copy tools from another installed app. The pack must function without network access and with only staged input/output access. Flatten necessary runtime links during your own packaging; this installer rejects symbolic links.

`examples/media-pack.json` illustrates a producer configuration. All tool, license, and model paths are relative to the payload folder. Include helper executables in `tools` so download installation can restore their executable permission. Declare LibreOffice and Pandoc independently in `engineVersions`. For transcription, `models` maps model names to payload paths; each is hashed like every other file.

```sh
python3 scripts/build-engine-pack.py \
  --config /path/pack.json \
  --payload /path/independent-runtime \
  --output /path/Media-1.0.0.bundle \
  --identity 'Developer ID Application: YOUR IDENTITY' \
  --notary-profile YOUR_STORED_PROFILE
```

The builder signs nested Mach-O code, creates a signed bundle anchor, hashes payload files after signing, writes `Contents/Resources/engine.json`, signs/verifies the outer bundle, and creates a ZIP without AppleDouble resource sidecars. Omitting the identity creates an unsigned inspection fixture which production verification deliberately rejects. A build cannot prove correct runtime relocation, license compliance, codec quality, or sandbox operation; run the release corpus against the actual signed pack.

The manifest records schema version, ID, numeric pack version, compatible app/OS, arm64 architecture, tool paths, file checksums, license paths, engine versions, installed bytes, and model paths. The builder prints the ZIP size and SHA-256. Add a release HTTPS URL and those exact fields to `Configuration/EngineCatalog.json`, regenerate the project, then sign a new app release. Catalog entries are sealed into the signed app; unsigned remote catalogs cannot activate executable code.

## Trust and updates

The manager requires an Apple Developer ID Application signature from the app’s own signing team. It checks compatibility, signatures, file hashes, executable paths, licenses, and model declarations before activation. Downloads require the bundled catalog’s exact HTTPS URL, size, hash, and pack identity. Archives pass the same path/link/expansion checks as normal extraction.

Installation copies into a temporary location, verifies again, then selects a versioned immutable bundle with an atomic current pointer. A previous pointer permits rollback. Reusing an existing version with different payload hashes fails. Deactivation removes the pointer; files are retained so existing engine snapshots remain usable. Automatic garbage collection of retired versions is not implemented.

The local Developer ID Application identity is configured and has successfully signed the app and helpers. Signing requires normal keychain access; the command sandbox can hide identities and certificate trust. A generated signed acceptance pack now passes verification, isolated install/update/rollback/deactivation, and tamper rejection. App notarization and stapled-ticket Gatekeeper assessment also pass. Pack notarization, actual sandboxed third-party execution, download interruption and the real-runtime corpus remain open release gates. Never turn off signature checking to make a development pack appear installed.

Apple’s [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) govern the public release. FFmpeg’s [build-dependent license requirements](https://ffmpeg.org/legal.html) and every other engine/model’s own terms must accompany its pack.

For isolated acceptance runs, `FILE_CONVERTER_ENGINE_DIRECTORY` selects a separate engine store without relaxing any signature checks. The generated test pack is never installed in the normal app engine directory. The bundle anchor is protected by the outer code signature; it is intentionally excluded from payload hashes because its signature seals the manifest itself.
