#!/usr/bin/env python3
"""Regenerate Glacier's original UI cues and comparison previews (stdlib only)."""
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_RATE = 32000


def tone(frequency, duration, decay, amplitude, warm=False):
    samples = []
    for index in range(round(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        value = math.sin(2 * math.pi * frequency * time)
        if warm:
            value += 0.18 * math.sin(4 * math.pi * frequency * time)
        envelope = ((1 - math.exp(-time / 0.003)) * math.exp(-time / decay)
                    * min(1, max(0, (duration - time) / 0.025)))
        samples.append(amplitude * envelope * value)
    return samples


def mix(parts):
    samples = [0.0] * max(round(start * SAMPLE_RATE) + len(part) for start, part in parts)
    for start, part in parts:
        offset = round(start * SAMPLE_RATE)
        for index, value in enumerate(part):
            samples[offset + index] += value
    return samples


def detent(rng, frequency=950, amplitude=0.11):
    samples = []
    previous = 0
    for index in range(round(SAMPLE_RATE * 0.065)):
        time = index / SAMPLE_RATE
        previous = 0.72 * previous + 0.28 * rng.uniform(-1, 1)
        samples.append(amplitude * (1 - math.exp(-time / 0.0008)) * math.exp(-time / 0.009)
                       * (math.sin(2 * math.pi * frequency * time) * 0.65 + previous * 0.65)
                       * min(1, (0.065 - time) / 0.008))
    return samples


def write(path, samples):
    assert all(math.isfinite(value) and abs(value) < 0.3 for value in samples)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        stream.writeframes(struct.pack("<" + "h" * len(samples), *(round(value * 32767) for value in samples)))


def main():
    rng = random.Random(14)
    sets = {
        "glacier-glass": (
            mix([(0, tone(784, .22, .055, .065)), (.014, tone(1568, .24, .07, .022))]),
            mix([(0, tone(1397, .065, .012, .085)), (0, tone(2794, .05, .008, .012))]),
            mix([(0, tone(1046.5, .38, .11, .09)), (.095, tone(1568, .48, .14, .08)),
                 (.095, tone(2093, .4, .09, .014))])),
        "soft-detent": (
            mix([(0, detent(rng, 550, .10)), (.028, tone(370, .13, .03, .045))]),
            detent(rng),
            mix([(0, tone(740, .24, .07, .105)), (.09, tone(1109, .34, .10, .085))])),
        "warm-minimal": (
            tone(440, .20, .045, .09, True),
            tone(660, .070, .013, .09, True),
            mix([(0, tone(523.25, .34, .10, .08, True)), (.095, tone(783.99, .43, .12, .085, True))]))
    }
    for name, (opening, tick, success) in sets.items():
        directory = (ROOT / "Sources/FileConverter/Resources/Sounds" if name == "soft-detent"
                     else ROOT / "docs/sounds/alternatives") / name
        for cue, samples in [("opening", opening), ("tick", tick), ("success", success)]:
            write(directory / (cue + ".wav"), samples)
        preview = mix([(.15, opening)] + [(.78 + index * .24, tick) for index in range(5)]
                      + [(2.38, success), (3.3, [0])])
        write(ROOT / "docs/sounds/previews" / (name + ".wav"), preview)


if __name__ == "__main__":
    main()
