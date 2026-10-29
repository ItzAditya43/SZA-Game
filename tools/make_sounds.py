#!/usr/bin/env python3
"""Synthesises every sound the game uses into assets/audio/ (16-bit mono WAV).

    python3 tools/make_sounds.py

Made from noise, filters and envelopes, so they are this project's own work
(no licence to track). Loops are built to wrap seamlessly (crossfaded ends).
Deterministic: the same script gives the same files.
"""
from pathlib import Path
import wave
import numpy as np
from scipy.signal import butter, lfilter

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def noise(seconds):
    return rng.standard_normal(int(seconds * RATE))


def band(x, lo, hi, order=2):
    nyq = RATE / 2
    if lo <= 0:
        b, a = butter(order, hi / nyq, "low")
    elif hi >= nyq:
        b, a = butter(order, lo / nyq, "high")
    else:
        b, a = butter(order, [lo / nyq, hi / nyq], "band")
    return lfilter(b, a, x)


def env(n, attack, decay):
    x = np.arange(n) / RATE
    e = np.minimum(1.0, x / max(attack, 1e-4)) * np.exp(-np.maximum(0, x - attack) / max(decay, 1e-4))
    return e


def place(track, sound, at):
    i = int(at * RATE)
    j = min(len(track), i + len(sound))
    if i < len(track):
        track[i:j] += sound[: j - i]


def loopable(x, fade=1.0):
    """Crossfade the tail into the head so the clip loops without a click."""
    n = int(fade * RATE)
    head, tail = x[:n].copy(), x[-n:]
    ramp = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


def save(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def wind(seconds, level=1.0):
    gust = band(noise(seconds), 0, 0.4, 1)
    gust = 0.5 + 0.5 * gust / (np.max(np.abs(gust)) + 1e-9)
    return band(noise(seconds), 150, 900) * gust * level


def crow():
    d = 0.35
    x = t(d)
    f = 520 + 120 * np.sin(2 * np.pi * 9 * x)
    tone = np.sign(np.sin(2 * np.pi * np.cumsum(f) / RATE)) * 0.4 + band(noise(d), 600, 2400) * 0.6
    return band(tone, 400, 2600) * env(len(x), 0.02, 0.12)


def bark():
    d = 0.22
    x = t(d)
    f = 380 * np.exp(-x * 4)
    tone = np.sin(2 * np.pi * np.cumsum(f) / RATE) + 0.5 * band(noise(d), 300, 1500)
    return tone * env(len(x), 0.01, 0.07)


def cricket():
    d = 0.6
    x = t(d)
    carrier = np.sin(2 * np.pi * 4200 * x)
    pulses = (np.sin(2 * np.pi * 28 * x) > 0.3).astype(float)
    return carrier * pulses * env(len(x), 0.05, 0.3)


def ambient_day():
    d = 30
    track = wind(d, 0.5)
    for at in rng.uniform(0, d - 1, 9):
        place(track, crow() * rng.uniform(0.2, 0.5), at)
    for at in rng.uniform(0, d - 1, 3):
        for k in range(rng.integers(2, 4)):
            place(track, bark() * 0.25, at + k * 0.35)
    save("amb_day", loopable(track), 0.6)


def ambient_night():
    d = 30
    track = wind(d, 0.35)
    for at in np.arange(0, d - 1, 0.45):
        place(track, cricket() * rng.uniform(0.05, 0.18), at + rng.uniform(0, 0.2))
    for at in rng.uniform(0, d - 3, 2):
        x = t(2.5)
        howl = np.sin(2 * np.pi * np.cumsum(500 + 180 * np.sin(np.pi * x / 2.5)) / RATE)
        place(track, band(howl, 300, 1200) * env(len(x), 0.6, 1.0) * 0.12, at)
    save("amb_night", loopable(track), 0.55)


def ambient_rain():
    d = 20
    hiss = band(noise(d), 800, 8000) * 0.6 + band(noise(d), 200, 800) * 0.4
    drops = np.zeros(int(d * RATE))
    for at in rng.uniform(0, d - 0.1, 900):
        place(drops, band(noise(0.03), 1500, 6000) * env(int(0.03 * RATE), 0.001, 0.008), at)
    save("amb_rain", loopable(hiss + drops * 0.8), 0.7)


def ambient_heat():
    d = 20
    x = t(d)
    buzz = band(noise(d), 3500, 6500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.08 * x)) * (0.75 + 0.25 * np.sin(2 * np.pi * 60 * x))
    save("amb_heat", loopable(buzz + wind(d, 0.2)), 0.45)


def gunshot():
    d = 1.6
    crack = band(noise(d), 200, 4000) * env(int(d * RATE), 0.001, 0.05)
    boom = band(noise(d), 40, 300) * env(int(d * RATE), 0.005, 0.35)
    echo = np.zeros_like(boom)
    place(echo, boom * 0.4, 0.18)
    save("sfx_gunshot", band(crack * 0.6 + boom + echo, 0, 2500), 0.9)


def door():
    d = 1.4
    track = np.zeros(int(d * RATE))
    for at, level in [(0.0, 1.0), (0.35, 0.8), (0.7, 1.0)]:
        hit = band(noise(0.25), 80, 900) * env(int(0.25 * RATE), 0.002, 0.06)
        place(track, hit * level, at)
    creak = np.sin(2 * np.pi * np.cumsum(220 + 90 * t(0.4)) / RATE) * env(int(0.4 * RATE), 0.05, 0.2) * 0.3
    place(track, creak, 0.95)
    save("sfx_door", track, 0.85)


def hammer():
    d = 1.2
    track = np.zeros(int(d * RATE))
    for k in range(3):
        x = t(0.18)
        ping = np.sin(2 * np.pi * 1800 * x) * 0.3 + band(noise(0.18), 500, 3000)
        place(track, ping * env(len(x), 0.001, 0.03), k * 0.38)
    save("sfx_hammer", track, 0.7)


def generator():
    d = 4
    x = t(d)
    hum = sum(np.sin(2 * np.pi * f * x) / (i + 1) for i, f in enumerate([55, 110, 165, 220]))
    chug = 0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 25 * x))
    save("sfx_generator", loopable(hum * chug + band(noise(d), 100, 800) * 0.3, 0.3), 0.6)


def fire():
    d = 6
    roar = band(noise(d), 60, 400) * 0.5
    crackle = np.zeros(int(d * RATE))
    for at in rng.uniform(0, d - 0.05, 160):
        place(crackle, band(noise(0.02), 1500, 7000) * env(int(0.02 * RATE), 0.001, 0.004) * rng.uniform(0.3, 1), at)
    save("sfx_fire", loopable(roar + crackle, 0.5), 0.7)


def attack():
    d = 2.0
    track = np.zeros(int(d * RATE))
    for at in rng.uniform(0, 1.6, 7):
        place(track, band(noise(0.2), 50, 400) * env(int(0.2 * RATE), 0.003, 0.07), at)
    x = t(1.2)
    groan = band(np.sign(np.sin(2 * np.pi * np.cumsum(140 + 30 * np.sin(2 * np.pi * 3 * x)) / RATE)), 100, 900)
    place(track, groan * env(len(x), 0.2, 0.5) * 0.3, 0.3)
    save("sfx_attack", track, 0.85)


def ui_click():
    x = t(0.05)
    save("ui_click", np.sin(2 * np.pi * 1400 * x) * env(len(x), 0.001, 0.012), 0.5)


def chime(name, notes, step, peak):
    track = np.zeros(int((len(notes) * step + 0.5) * RATE))
    for i, f in enumerate(notes):
        x = t(0.5)
        tone = (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * 2 * f * x)) * env(len(x), 0.005, 0.18)
        place(track, tone, i * step)
    save(name, track, peak)


if __name__ == "__main__":
    ambient_day()
    ambient_night()
    ambient_rain()
    ambient_heat()
    gunshot()
    door()
    hammer()
    generator()
    fire()
    attack()
    ui_click()
    chime("ui_info", [660], 0.1, 0.35)
    chime("ui_caution", [660, 520], 0.13, 0.45)
    chime("ui_urgent", [880, 660, 880], 0.11, 0.55)
    print("wrote", len(list(OUT.glob("*.wav"))), "sounds to", OUT)
