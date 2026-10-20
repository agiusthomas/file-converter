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

The adapters support separately signed Media (FFmpeg), Documents (LibreOffice/Pandoc), Ebooks (Calibre), and Transcription (whisper.cpp/model) runtimes. No third-party application binaries are copied into this repository. No public pack download catalog has been published yet. Pack manifests must declare exact engine versions, supported architecture/OS, tool paths, SHA-256 hashes, and license/source notices before activation.

FFmpeg's license depends on its build configuration. LibreOffice, Pandoc, Calibre, whisper.cpp, models, and transitive libraries retain their own licenses; the application's MIT license does not replace those terms.
