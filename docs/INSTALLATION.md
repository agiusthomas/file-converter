# Install Glacier File Converter

Targets macOS 13 Ventura or later on an Apple-silicon Mac (M1 or newer). Intel Macs are not supported by this build. This release was exercised on macOS 26.5.1; macOS 13 execution and installation on a clean offline Mac remain unverified.

## Install

Download [Glacier File Converter 1.0.1](https://github.com/agiusthomas/file-converter/releases/tag/v1.0.1), the latest patch release. The first official [1.0.0 release](https://github.com/agiusthomas/file-converter/releases/tag/v1.0.0) remains available.

1. Download **Glacier-File-Converter-1.0.1.dmg** from the release page.
2. Open the DMG and drag **Glacier File Converter** onto **Applications**.
3. Eject the Glacier File Converter disk image.
4. Open **Glacier File Converter** from Applications. Confirm macOS's normal first-open download prompt if shown.

The app and DMG are Developer ID signed, notarized by Apple and stapled. No command-line installation, Xcode, or security-setting changes are required. If macOS reports that a download is damaged or its developer cannot be verified, download a fresh copy from the release page; do not disable Gatekeeper.

Older [0.2.1 preview downloads](https://github.com/agiusthomas/file-converter/releases/tag/v0.2.1) remain unchanged as `File-Converter-0.2.1.dmg` and **File Converter.app**. When installing that older preview, use its original app name in the steps above.

## First use

- Add files in the main window, choose an available action and output, preview, then convert. Outputs save beside originals unless you choose another destination; existing files receive a numbered name.
- If a destination is unavailable, open **Settings → Output access → Allow a folder…** and choose the folder again.
- Enable the Finder wheel in Settings, then hold **Shift** while dragging files in Finder. You can change the modifier to Option or Control.
- Sound effects default to Soft Detent at 30% volume. Use **Settings → Sound effects** to mute, adjust volume or preview the wheel and success cues. Success sounds play once per fully successful manual batch; watched folders stay silent.
- Closing the window keeps the app running in the menu bar. Use its menu to reopen the window or choose **Quit Glacier File Converter** (or **Quit File Converter** in 0.2.1).
- Launch at login and watched folders are optional settings.

Built-in conversions work locally. A limited Media runtime is available as an explicit download in **Engines**, described below. Documents, Ebooks, Transcription and PDF structure packs remain unpublished; actions requiring missing packs remain unavailable. The full seven-milestone expansion is unfinished. See the repository's [capability list](https://github.com/agiusthomas/file-converter/blob/main/docs/CAPABILITIES.md) and [known remaining work](https://github.com/agiusthomas/file-converter/blob/main/docs/ROADMAP.md).

## Update or remove

For the first renamed update, quit **File Converter** from its menu bar menu, install **Glacier File Converter.app** in Applications, and remove the old **File Converter.app** copy. The two app filenames differ, so Finder will not automatically replace the old copy. Keep only the new app installed before launching it; reselect it in Login Items if macOS still points to the old filename.

For subsequent updates, quit **Glacier File Converter**, drag the new app into Applications, and confirm replacement. The bundle identifier and all existing storage locations remain unchanged, preserving saved settings, folder permissions, recipes, job history, and installed engines. Do not delete the app's Library data when removing the old application copy.

To remove the app, quit it and move **Glacier File Converter.app** (or **File Converter.app** for an older release) from Applications to Trash. Generated files remain in the locations where you saved them.

## Verify a download (optional)

The 1.0.1 release includes `Glacier-File-Converter-1.0.1-SHA256SUMS.txt`; the existing 0.2.1 preview retains `File-Converter-0.2.1-SHA256SUMS.txt`. After downloading the DMG and checksum file into the same folder, compare the DMG's SHA-256 checksum with the matching line in that file. The ZIP is an alternative app download: unzip it, move the app to Applications, and follow the same first-use steps.

## Media engine preview

Glacier File Converter 1.0.1 retains the [Media 0.1.2 qualification preview](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2), using independently built FFmpeg 8.1.2. It requires the publisher's Developer ID signed app; an unsigned or differently signed source build cannot install the publisher's executable packs. The preserved 0.2.0 app retains its original empty engine catalog and cannot install this newer pack.

Open **Engines**, review compatibility/sizes/notices, then choose **Download and install**. Installation is explicit and cancellable; a retry keeps the previous active version until verification/activation succeeds. Updates expose a rollback button. Engine changes activate when current queued work finishes, while running jobs retain their runtime versions. **Remove pack** disables future activation and reclaims files after live pins release. Use the license/source disclosure to inspect the complete runtime. Once installed, conversions run locally without a network connection.

The initial runtime supports the qualified FLAC and H.264/AAC paths; complete MP3/Opus/VP9 dependencies and advanced Media workflows remain required. See [exact qualification and limitations](https://github.com/agiusthomas/file-converter/blob/main/docs/FFMPEG_CHECKPOINT.md). Before removing the app, remove optional packs from Engines if you also want their cached runtime files reclaimed; generated user outputs are unaffected.
