# Install File Converter

Requires macOS 13 Ventura or later on an Apple-silicon Mac (M1 or newer). Intel Macs are not supported by this build.

## Install

1. Download `File-Converter-0.2.0.dmg` from the [0.2.0 preview release](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.0).
2. Open the DMG and drag **File Converter** onto **Applications**.
3. Eject the File Converter disk image.
4. Open **File Converter** from Applications. Confirm macOS's normal first-open download prompt if shown.

The app and DMG are Developer ID signed and notarized by Apple. No command-line installation, Xcode, or security-setting changes are required. If macOS reports that a download is damaged or its developer cannot be verified, download a fresh copy from the release page; do not disable Gatekeeper.

## First use

- Add files in the main window, choose an available action and output, preview, then convert. Outputs save beside originals unless you choose another destination; existing files receive a numbered name.
- If a destination is unavailable, open **Settings → Output access → Allow a folder…** and choose the folder again.
- Enable the Finder wheel in Settings, then hold **Shift** while dragging files in Finder. You can change the modifier to Option or Control.
- Closing the window keeps the app running in the menu bar. Use its menu to reopen the window or choose **Quit File Converter**.
- Launch at login and watched folders are optional settings.

Built-in conversions work locally. Optional Media, Documents, Ebooks, and Transcription packs are not available for download in this preview; actions requiring them remain unavailable. See the repository's [capability list](https://github.com/agiusthomas/file-converter/blob/main/docs/CAPABILITIES.md) and [known remaining work](https://github.com/agiusthomas/file-converter/blob/main/docs/ROADMAP.md).

## Update or remove

To update, quit File Converter from its menu bar menu, then drag the new app into Applications and confirm replacement. Saved settings and job history remain available.

To remove the app, quit it and move **File Converter.app** from Applications to Trash. Generated files remain in the locations where you saved them.

## Verify a download (optional)

The release includes `SHA256SUMS.txt`. After downloading the DMG and checksum file into the same folder, compare the DMG's SHA-256 checksum with the matching line in that file. The ZIP is an alternative app download: unzip it, move the app to Applications, and follow the same first-use steps.

## Engine preview in the source candidate

The published 0.2.0 app above retains its original empty engine catalog. The current 0.2.1 source candidate (not yet an app release) includes a [Media 0.1.2 qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2). It requires the publisher's Developer ID signed candidate; an unsigned or differently signed source build cannot install the publisher's executable packs.

In that candidate, open **Engines**, review compatibility/sizes/notices, then choose **Download and install**. Installation is explicit and cancellable; a retry keeps the previous active version until verification/activation succeeds. Updates expose a rollback button. Engine changes activate when current queued work finishes, while running jobs retain their runtime versions. **Remove pack** disables future activation and reclaims files after live pins release. Use the license/source disclosure to inspect the complete runtime.

The initial runtime supports the qualified FLAC and H.264/AAC paths; complete MP3/Opus/VP9 dependencies and advanced Media workflows remain required. Minimum macOS 13 execution and clean offline installation are unverified. Documents, Ebooks, Transcription and PDF structure packs remain unpublished. See [exact qualification and limitations](FFMPEG_CHECKPOINT.md). Before removing a candidate app, remove optional packs from Engines if you also want their cached runtime files reclaimed; generated user outputs are unaffected.
