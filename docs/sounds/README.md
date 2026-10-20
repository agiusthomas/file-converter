# Glacier sound previews

**Soft Detent** is the active set: a muted opening, dial-like selection ticks, and a short two-note success cue. Settings provides a sound toggle, volume (30% by default), and a preview button. App volume follows the Mac's output volume and mute setting.

These original synthesized sounds are included under the repository's MIT license. They have no downloaded samples or runtime dependencies. Regenerate all assets and previews with `python3 scripts/generate-sound-assets.py`.

Each preview plays opening → five option ticks → success at its original level, before the app's volume adjustment:

- [Soft Detent](previews/soft-detent.wav)
- [Glacier Glass](previews/glacier-glass.wav)
- [Warm Minimal](previews/warm-minimal.wav)

The active cues live in `Sources/FileConverter/Resources/Sounds/soft-detent`. The other complete sets are preserved in `alternatives/glacier-glass` and `alternatives/warm-minimal` here, alongside the previews, for a later switch after auditioning the app. Only the active set is bundled.

The wheel plays opening only once it appears and ticks only on a changed, non-neutral option. Ticks are limited to one per 60 ms and suppressed for the first 80 ms after opening. Suppressed ticks are discarded. Dismissing the wheel stops its opening/tick cues. A new cue replaces the previous one without an audio queue.

Success plays once per fully successful manual batch (wheel, main window, retry, or recipe), after its outputs are published. Independently submitted batches receive independent confirmations. Failed/cancelled batches, previews, loaded history, watched folders, CLI and Shortcuts stay silent. Sound failures never prevent conversion.
