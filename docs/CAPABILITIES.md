# Capability reference

Generated 2026-10-20 from `convert-file capabilities` (schema 1).

This is the registry on the generation Mac. Use `convert-file actions FILE...` for the content-probed intersection for your selection. Native encoders vary by OS; optional media profiles are further filtered against the installed binary’s encoders and muxers. A format name does not guarantee every codec, track, animation, or embedded feature.

Archive engine: libarchive 3.7.4.

| Action | Inputs | Output profiles | Availability |
| --- | --- | --- | --- |
| `image.convert` | image | `jpg`, `png`, `webp`, `heic`, `tiff`, `avif`, `bmp`, `pdf` | Included |
| `image.combine-pdf` | image | `pdf` | Included |
| `pdf.export` | pdf | `png`, `jpg` | Included |
| `pdf.organize` | pdf | `pdf` | Included |
| `pdf.merge` | pdf | `pdf` | Included |
| `pdf.split` | pdf | `pdf` | Included |
| `pdf.text` | pdf | `txt` | Included |
| `pdf.ocr` | pdf, image | `txt`, `searchable-pdf` | Included |
| `pdf.compress` | pdf | `pdf` | Included |
| `pdf.protect` | pdf | `pdf` | Included |
| `media.convert` | audio, video | `mp4-h264`, `mp4-hevc`, `m4a-aac`, `wav` | Included |
| `media.extract-audio` | video | `m4a-aac`, `wav` | Included |
| `media.frame` | video | `png`, `jpg` | Included |
| `media.join` | audio, video | `mp4-h264`, `m4a-aac` | Included |
| `text.convert` | text | `txt`, `html`, `md`, `csv`, `tsv` | Included |
| `subtitle.convert` | subtitle | `srt`, `vtt`, `txt` | Included |
| `document.convert` | document, spreadsheet, presentation, text | `pdf`, `docx`, `odt`, `txt`, `epub`, `csv`, `tsv` | Requires documents pack |
| `archive.create` | image, pdf, audio, video, document, spreadsheet, presentation, text, subtitle, archive, ebook, unknown | `zip`, `tar`, `tar.gz`, `7z` | Included |
| `archive.extract` | archive | `folder` | Included |
| `ebook.convert` | ebook, document, text | `epub`, `azw3`, `mobi`, `txt` | Requires ebooks pack |
| `transcribe` | audio, video | `txt`, `srt`, `vtt` | Requires transcription pack |

Media 0.1.2 is a published FFmpeg qualification preview for the signed 0.2.1 candidate, with FLAC and H.264/AAC proof; this table was generated without an active optional pack. Its full codec/workflow/platform corpus and the other production packs remain required. See [runtime evidence](FFMPEG_CHECKPOINT.md) and [implementation status](../IMPLEMENTATION.md).
