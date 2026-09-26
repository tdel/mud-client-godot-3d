"""Synthétise le clapotis en boucle de la fontaine (assets/audio/sfx/env_fountain_loop.ogg).

Trois couches : chute d'eau continue (bruit rose filtré en bande, légèrement modulé),
grondement grave du bassin (bruit brun passe-bas) et gouttes/bulles (courts "plocs" sinus
à fréquence montante, amortis). Le dernier 1,5 s est fondu dans le début : boucle sans
couture. Mono (spatialisé par AudioStreamPlayer3D côté Godot).

Usage (depuis la racine du projet) :
    uv run --with numpy --with scipy --with soundfile python tools/env_gen/build_fountain_sound.py
"""

import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
LOOP = 8.0
FADE = 1.5
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "env_fountain_loop.ogg")


def pink(n, rng):
    white = rng.standard_normal(n)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, white)


def main():
    rng = np.random.default_rng(7)
    n = int(SR * (LOOP + FADE))
    t = np.arange(n) / SR

    stream = pink(n, rng)
    sos = signal.butter(4, [350, 7000], btype="band", fs=SR, output="sos")
    stream = signal.sosfilt(sos, stream)
    stream *= 1.0 + 0.18 * np.sin(2 * np.pi * 0.23 * t) + 0.1 * np.sin(2 * np.pi * 0.61 * t + 1.0)
    stream /= np.abs(stream).max()

    rumble = np.cumsum(rng.standard_normal(n))
    rumble -= signal.sosfilt(signal.butter(1, 20, btype="low", fs=SR, output="sos"), rumble)
    rumble = signal.sosfilt(signal.butter(4, 380, btype="low", fs=SR, output="sos"), rumble)
    rumble /= np.abs(rumble).max()

    drops = np.zeros(n)
    count = int((LOOP + FADE) * 55)
    for start in rng.uniform(0, LOOP + FADE - 0.1, count):
        dur = rng.uniform(0.015, 0.06)
        m = int(dur * SR)
        tt = np.arange(m) / SR
        f0 = rng.uniform(700, 2600)
        freq = f0 * (1 + tt / dur * rng.uniform(0.3, 1.2))
        ploc = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-tt / (dur * 0.3))
        i = int(start * SR)
        drops[i:i + m] += ploc * rng.uniform(0.2, 1.0)
    drops /= np.abs(drops).max()

    mix = 0.55 * stream + 0.35 * rumble + 0.22 * drops

    loop_n = int(LOOP * SR)
    fade_n = int(FADE * SR)
    out = mix[:loop_n].copy()
    ramp = np.linspace(0, 1, fade_n)
    out[:fade_n] = out[:fade_n] * ramp + mix[loop_n:loop_n + fade_n] * (1 - ramp)
    out /= np.abs(out).max()
    out *= 0.7
    sf.write(OUT, out.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    print("écrit", OUT)


if __name__ == "__main__":
    main()
