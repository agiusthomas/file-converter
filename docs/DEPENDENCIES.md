# Conversion dependencies

## Bundled libwebp

- Upstream: https://chromium.googlesource.com/webm/libwebp/
- Version: 1.6.0, unmodified C sources under `Sources/WebPBridge/libwebp`.
- Release: https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
- SHA-256: `e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`
- License: BSD-style; retain upstream COPYING, PATENTS, and AUTHORS in source and distributed notices.
- Built independently by SwiftPM/Xcode; no installed application executable is reused.
- Uses the encoder, decoder, DSP, utilities, and SharpYUV sources. Container mux/demux sources and upstream build tools are excluded.

## System libraries

Apple's ImageIO, PDFKit, Vision, AVFoundation, CoreText, AppKit, and Security frameworks are provided by macOS. ArchiveBridge loads the system libarchive ABI at runtime; capabilities are tested against the available system version. It does not claim a pinned bundled libarchive build.

## Optional engine packs

The adapters support separately signed Media (FFmpeg), Documents (LibreOffice/Pandoc), Ebooks (Calibre), and Transcription (whisper.cpp/model) runtimes. No third-party application binaries are copied into this repository. Media 0.1.2 is a published FFmpeg 8.1.2 qualification preview and appears in the 0.2.1 candidate's sealed catalog; the other packs remain unpublished. Pack manifests must declare exact engine versions, supported architecture/OS, tool paths, SHA-256 hashes, and license/source notices before activation.

FFmpeg's license depends on its build configuration. LibreOffice, Pandoc, Calibre, whisper.cpp, models, and transitive libraries retain their own licenses; the application's MIT license does not replace those terms.

## Media runtime qualification preview

[Media 0.1.2](https://github.com/agiusthomas/file-converter/releases/tag/engine-media-v0.1.2) independently compiles FFmpeg 8.1.2 for arm64/macOS 13.0 deployment, with LGPL-2.1-or-later configuration and six relative shared libraries. GPL/nonfree/version3 and automatic dependency detection are disabled; Apple VideoToolbox/AudioToolbox are enabled. No Homebrew libraries or third-party app binaries are used. Complete upstream source, exact build/toolchain record, producer script, COPYING.LGPLv2.1, LICENSE.md and CREDITS travel in the payload. The same official source archive is attached to the runtime release.

Source SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`. Source URL: <https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz>. Networking/device capture are disabled. LAME, Opus and VP9 libraries are not part of this initial build; their pinned source, notices and qualification remain required. See [runtime evidence and limits](FFMPEG_CHECKPOINT.md).
