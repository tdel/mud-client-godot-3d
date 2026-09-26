"""Génère la musique d'ambiance des cartes forestières : assets/audio/music/forest_ambience.ogg.

Entièrement synthétisée ici (aucun échantillon externe, donc aucune licence à créditer) :
    - une nappe douce (sinus désaccordés) sur une grille de 8 accords en ré majeur ;
    - un voile aigu très discret (quintes/neuvièmes en harmoniques "de verre") ;
    - une harpe/kalimba clairsemée, mélodie pentatonique aléatoire mais déterministe (SEED) ;
    - deux courtes phrases de flûte en bois ;
    - une couche nature : souffle de vent en rafales lentes et chants d'oiseaux épars.

La piste boucle SANS COUTURE : tout est construit sur une ligne de temps circulaire de
LOOP_SECONDS (les notes qui débordent de la fin sont repliées sur le début, les filtres,
l'écho et la réverbe sont appliqués par FFT, donc circulaires eux aussi). Godot la joue en
boucle depuis 0 (voir autoload/ZoneMusic.gd).

Usage (depuis la racine du projet) :
    uv run --with numpy --with scipy --with soundfile python tools/music_gen/build_forest_music.py [--preview]

--preview écrit en plus tools/music_gen/preview/ (ignoré par git) : le mixage, chaque couche
seule et un extrait "raccord de boucle" (10 s de fin + 10 s de début), avec une page
index.html pour tout écouter. Changer SEED donne une autre mélodie / d'autres oiseaux ;
les niveaux relatifs des couches sont dans STEM_DB.
"""

import argparse
import os

import numpy as np
import soundfile as sf

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "assets", "audio", "music", "forest_ambience.ogg")

SEED = 7
LOOP_SECONDS = 150.0
N = int(SR * LOOP_SECONDS)

# Grille d'accords (ré majeur, couleurs lydiennes sur sol) : voicings ouverts, graves posés.
CHORDS = [
    ["D3", "A3", "E4", "F#4", "C#5"],   # Dmaj9
    ["B2", "F#3", "D4", "E4", "A4"],    # Bm11
    ["G2", "D3", "B3", "F#4", "A4"],    # Gmaj9
    ["A2", "E3", "B3", "D4", "E4"],     # Asus4(9)
    ["E3", "B3", "D4", "F#4", "G4"],    # Em9
    ["G2", "D3", "F#3", "C#4", "B4"],   # Gmaj7#11
    ["F#2", "A3", "D4", "E4", "A4"],    # Dadd9/F#
    ["A2", "E3", "A3", "D4", "B4"],     # Asus4(9)
]
CHORD_SECONDS = LOOP_SECONDS / len(CHORDS)
# Densité de la harpe par accord (secondes moyennes entre deux gestes) : des passages qui
# respirent, d'autres un peu plus bavards, pour éviter une texture uniforme sur 2 min 30.
HARP_GAP = [5.5, 4.0, 3.2, 6.0, 4.5, 3.2, 4.0, 6.5]
# Accords (index) où la flûte joue une phrase.
FLUTE_CHORDS = [2, 5]
PENTATONIC = ["D4", "E4", "F#4", "A4", "B4", "D5", "E5", "F#5", "A5", "B5"]

# Niveau RMS de chaque couche dans le mixage (dB, avant normalisation finale).
STEM_DB = {
    "pad": -23.0,
    "shimmer": -38.0,
    "harp": -27.0,
    "flute": -30.0,
    "wind": -37.0,
    "birds": -35.0,
}
MASTER_RMS_DB = -21.0
MASTER_PEAK_DB = -3.0

_rng = np.random.default_rng(SEED)


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

def sec(t):
    return int(round(t * SR))


def hz(name):
    base = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = base[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def bus():
    return np.zeros((2, N))


def pan(x, position):
    """Mono -> stéréo à puissance constante, position -1 (gauche) .. 1 (droite)."""
    angle = (position + 1) * np.pi / 4
    return np.vstack([x * np.cos(angle), x * np.sin(angle)])


def place(target, x, t0, position=0.0):
    """Ajoute x (mono ou stéréo) dans target à t0 secondes ; ce qui dépasse la fin de la
    boucle est replié sur son début (ligne de temps circulaire)."""
    if x.ndim == 1:
        x = pan(x, position)
    start = sec(t0) % N
    pos = 0
    while pos < x.shape[1]:
        s = (start + pos) % N
        k = min(x.shape[1] - pos, N - s)
        target[:, s:s + k] += x[:, pos:pos + k]
        pos += k


def circ_filter(x, gain):
    """Filtre fréquentiel circulaire : gain(f) -> amplitude. Préserve la boucle."""
    spectrum = np.fft.rfft(x, axis=-1)
    f = np.fft.rfftfreq(x.shape[-1], 1 / SR)
    return np.fft.irfft(spectrum * gain(f), n=x.shape[-1], axis=-1)


def lp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def smooth_lfo(cycles, depth_seed):
    """Modulation lente, aléatoire mais périodique sur la boucle (somme de sinus dont le
    nombre de cycles par boucle est entier) : valeurs dans 0..1."""
    t = np.arange(N) / N
    rng = np.random.default_rng(depth_seed)
    out = np.zeros(N)
    for k in cycles:
        out += rng.uniform(0.5, 1.0) / k ** 0.5 * np.sin(2 * np.pi * k * t + rng.uniform(0, 2 * np.pi))
    out -= out.min()
    return out / out.max()


def fade_env(n, attack, release):
    e = np.ones(n)
    a, r = min(sec(attack), n), min(sec(release), n)
    if a:
        e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if r:
        e[n - r:] *= np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


def set_rms(x, db):
    return x * 10 ** ((db - rms_db(x)) / 20)


# ---------------------------------------------------------------------------
# Réverbe et écho circulaires
# ---------------------------------------------------------------------------

def reverb(x, decay=4.5, wet=0.5, pre_delay=0.03, seed=1):
    """Réverbe de grand espace ouvert : réponse impulsionnelle bruitée, les aigus s'éteignant
    plus vite que les graves (deux bandes), une réponse différente par canal pour
    l'ampleur stéréo. Convolution circulaire (FFT de la longueur de la boucle)."""
    rng = np.random.default_rng(seed)
    n = sec(decay * 1.3)
    t = np.arange(n) / SR
    out = np.empty_like(x)
    for ch in range(2):
        low = circ_filter(rng.normal(0, 1, n), lp(1800, 2)) * np.exp(-6.9 * t / decay)
        high = circ_filter(rng.normal(0, 1, n), hp(1800, 2)) * np.exp(-6.9 * t / (decay * 0.35))
        ir = low + 0.6 * high
        ir *= np.minimum(1, t / 0.06)  # densité qui se construit (pas de "clac" initial)
        ir = np.concatenate([np.zeros(sec(pre_delay)), ir])
        ir /= np.sqrt(np.sum(ir ** 2))
        padded = np.zeros(N)
        padded[:len(ir)] = ir
        out[ch] = np.fft.irfft(np.fft.rfft(x[ch]) * np.fft.rfft(padded), n=N)
    return x * (1 - wet * 0.5) + out * wet


def echo(x, delays=(0.46, 0.61), feedback=0.35, taps=4, wet=0.3):
    """Écho ping-pong assourdi (délais différents à gauche/à droite), circulaire."""
    out = np.zeros_like(x)
    for ch in range(2):
        d = sec(delays[ch])
        for k in range(1, taps + 1):
            out[ch] += feedback ** (k - 1) * np.roll(x[1 - ch if k % 2 else ch], d * k)
    out = circ_filter(out, lp(2600, 2))
    return x + out * wet


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------

def pad_note(freq, duration):
    """Note de nappe stéréo : harmoniques sinus douces, deux voix légèrement désaccordées
    (battements lents = mouvement) placées de part et d'autre du centre, respiration
    d'amplitude lente."""
    t = np.arange(sec(duration)) / SR
    out = np.zeros((2, len(t)))
    for voice_cents, position in ((-3.0, -0.45), (3.0, 0.45)):
        voice = np.zeros(len(t))
        for h in range(1, 7):
            f = freq * h * 2 ** ((voice_cents + _rng.uniform(-1.0, 1.0)) / 1200)
            if f > 4500:
                continue
            voice += np.sin(2 * np.pi * f * t + _rng.uniform(0, 2 * np.pi)) / h ** 1.8
        voice *= 1 + 0.18 * np.sin(2 * np.pi * t / _rng.uniform(7, 12) + _rng.uniform(0, 2 * np.pi))
        out += pan(voice, position)
    return out


def pluck(freq, duration=5.0, velocity=1.0):
    """Harpe/kalimba : fondamentale longue, harmoniques qui s'éteignent vite, léger partiel
    inharmonique (bois) et un petit transitoire d'attaque."""
    t = np.arange(sec(duration)) / SR
    out = np.zeros_like(t)
    for ratio, amp, decay in ((1, 1.0, 1.0), (2, 0.32, 2.2), (3, 0.10, 3.6), (4.2, 0.05, 6.0)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-decay * t)
    click = _rng.normal(0, 1, len(t)) * np.exp(-t / 0.004) * 0.05
    out += circ_filter(click, lp(3000, 2))
    a = sec(0.004)
    out[:a] *= np.linspace(0, 1, a)
    out *= fade_env(len(t), 0, 0.3)
    return out * velocity


def flute(freq, duration):
    """Flûte en bois : sinus + harmoniques faibles, vibrato qui s'installe, souffle filtré."""
    n = sec(duration)
    t = np.arange(n) / SR
    vibrato = 1 + 0.0045 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.25) / 0.5, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq * vibrato) / SR
    tone = np.sin(phase) + 0.16 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase)
    breath = circ_filter(_rng.normal(0, 1, n), lambda f: np.exp(-0.5 * (np.log(np.maximum(f, 1) / (freq * 1.6)) / 0.35) ** 2))
    breath *= 0.08 + 0.2 * np.exp(-t / 0.08)
    return (tone + breath * 3.0) * fade_env(n, 0.14, 0.4)


def bird_chirps():
    """Petits cris descendants répétés (mésange/rouge-gorge stylisés)."""
    parts = []
    f_hi, f_lo = _rng.uniform(4600, 5600), _rng.uniform(3000, 3800)
    for _ in range(_rng.integers(2, 6)):
        d = _rng.uniform(0.06, 0.11)
        t = np.arange(sec(d)) / SR
        f = f_lo * (f_hi / f_lo) ** (1 - t / d)
        parts.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 2)
        parts.append(np.zeros(sec(_rng.uniform(0.08, 0.16))))
    return np.concatenate(parts)


def bird_trill():
    """Trille rapide (fauvette stylisée) : porteuse aiguë modulée en fréquence."""
    d = _rng.uniform(0.6, 1.1)
    t = np.arange(sec(d)) / SR
    carrier = _rng.uniform(3600, 4600) * (1 - 0.08 * t / d)
    f = carrier + _rng.uniform(300, 550) * np.sin(2 * np.pi * _rng.uniform(18, 26) * t)
    env = np.sin(np.pi * t / d) ** 1.5 * np.minimum(1, t / (d * 0.3))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env


def bird_whistle():
    """Sifflement mélodieux (merle/loriot stylisé) : 2 à 4 notes glissées."""
    parts = []
    base = _rng.uniform(1900, 2900)
    for _ in range(_rng.integers(2, 5)):
        d = _rng.uniform(0.16, 0.32)
        t = np.arange(sec(d)) / SR
        f0 = base * _rng.choice([0.84, 0.94, 1.0, 1.12, 1.26])
        f = f0 * (1 + _rng.uniform(-0.15, 0.15) * t / d)
        phase = 2 * np.pi * np.cumsum(f) / SR
        parts.append((np.sin(phase) + 0.12 * np.sin(2 * phase)) * np.sin(np.pi * t / d) ** 1.2)
        parts.append(np.zeros(sec(_rng.uniform(0.05, 0.12))))
    return np.concatenate(parts)


# ---------------------------------------------------------------------------
# Couches
# ---------------------------------------------------------------------------

def chord_window(i, overlap=5.0):
    """(début, durée) de l'accord i élargi de `overlap` de chaque côté (fondus croisés)."""
    return i * CHORD_SECONDS - overlap, CHORD_SECONDS + 2 * overlap


def layer_pad():
    out = bus()
    overlap = 5.0
    for i, chord in enumerate(CHORDS):
        start, duration = chord_window(i, overlap)
        n = sec(duration)
        # Fondu croisé à puissance constante avec l'accord voisin.
        env = np.ones(n)
        k = sec(2 * overlap)
        env[:k] = np.sin(np.linspace(0, np.pi / 2, k))
        env[-k:] = np.cos(np.linspace(0, np.pi / 2, k))
        chord_sum = np.zeros((2, n))
        for j, name in enumerate(chord):
            # Les graves un peu plus présents, les notes hautes en retrait.
            chord_sum += pad_note(hz(name), duration) * (1.0 if j < 2 else 0.6)
        place(out, chord_sum * env, start)
    # Passe-haut : les basses restent suggérées, la nappe ne doit pas "peser".
    return circ_filter(out, lambda f: lp(1400, 1)(f) * hp(90, 1)(f))


def layer_shimmer():
    """Voile aigu : les deux notes hautes de chaque accord une octave au-dessus, en sinus
    purs à trémolo lent — un air "de verre" très discret."""
    out = bus()
    for i, chord in enumerate(CHORDS):
        start, duration = chord_window(i, 6.0)
        n = sec(duration)
        t = np.arange(n) / SR
        env = np.sin(np.pi * t / duration) ** 2
        for name, position in zip(chord[-2:], (-0.6, 0.6)):
            f = hz(name) * 2
            trem = 0.6 + 0.4 * np.sin(2 * np.pi * t / _rng.uniform(3, 6) + _rng.uniform(0, 6.3))
            place(out, np.sin(2 * np.pi * f * t) * trem * env, start, position)
    return out


def layer_harp():
    out = bus()
    index = 3
    for i, chord in enumerate(CHORDS):
        chord_pcs = {name[:-1] for name in chord}
        t = i * CHORD_SECONDS + _rng.uniform(0.5, 2.0)
        end = (i + 1) * CHORD_SECONDS - 1.0
        while t < end:
            # Le geste commence sur une note de l'accord proche de la position courante.
            candidates = [k for k, name in enumerate(PENTATONIC) if name[:-1] in chord_pcs]
            if candidates:
                index = min(candidates, key=lambda k: abs(k - index) + _rng.uniform(0, 1.5))
            gesture = _rng.choice(["single", "arp", "fall"], p=[0.45, 0.35, 0.20])
            if gesture == "single":
                steps = [0]
            elif gesture == "arp":
                steps = [0] + [int(s) for s in _rng.choice([1, 2], size=_rng.integers(2, 4))]
            else:
                steps = [0, -1]
            dt = _rng.uniform(0.28, 0.42)
            for n_step, step in enumerate(steps):
                index = int(np.clip(index + step, 0, len(PENTATONIC) - 1))
                velocity = _rng.uniform(0.55, 0.9) * (0.85 if n_step else 1.0)
                place(out, pluck(hz(PENTATONIC[index]), velocity=velocity),
                      t + n_step * dt + _rng.uniform(-0.02, 0.02), _rng.uniform(-0.45, 0.45))
            t += len(steps) * dt + _rng.uniform(0.6, 1.4) * HARP_GAP[i]
    return out


def layer_flute():
    out = bus()
    for i in FLUTE_CHORDS:
        chord_pcs = {name[:-1] for name in CHORDS[i]}
        t = i * CHORD_SECONDS + _rng.uniform(2.5, 4.5)
        durations = [1.4, 0.7, 0.7, 1.6, 2.8]
        index = int(_rng.integers(5, 8))
        position = _rng.uniform(-0.3, 0.3)
        for k, d in enumerate(durations):
            if k:
                index = int(np.clip(index + _rng.choice([-2, -1, 1, 2]), 5, 9))
            if k == len(durations) - 1:
                # Finit sur une note de l'accord (résolution).
                tones = [j for j in range(5, 10) if PENTATONIC[j][:-1] in chord_pcs] or [index]
                index = min(tones, key=lambda j: abs(j - index))
            place(out, flute(hz(PENTATONIC[index]), d + 0.08) * 0.9, t, position)
            t += d
    return out


def layer_wind():
    """Vent : bruit rose filtré en bande large, rafales lentes, bruissement de feuilles
    plus aigu qui suit les rafales."""
    gust = 0.25 + 0.75 * smooth_lfo(range(3, 18, 2), SEED + 11) ** 1.5
    out = np.empty((2, N))
    for ch in range(2):
        body = circ_filter(_rng.normal(0, 1, N),
                           lambda f: np.exp(-0.5 * (np.log(np.maximum(f, 1) / 420) / 0.9) ** 2))
        leaves = circ_filter(_rng.normal(0, 1, N),
                             lambda f: np.exp(-0.5 * (np.log(np.maximum(f, 1) / 3500) / 0.5) ** 2))
        out[ch] = body * gust + 0.25 * leaves * gust ** 2.5
    return out


def layer_birds():
    out = bus()
    t = _rng.uniform(1, 4)
    while t < LOOP_SECONDS:
        kind = _rng.choice([bird_chirps, bird_trill, bird_whistle], p=[0.4, 0.25, 0.35])
        call = kind()
        distance = _rng.uniform(0, 1)
        gain = 1.0 - 0.7 * distance
        position = _rng.uniform(-0.8, 0.8)
        # Au loin : moins d'aigus.
        call = circ_filter(call, lp(9000 - 5000 * distance, 1))
        place(out, call * gain, t, position)
        if kind is bird_whistle and _rng.uniform() < 0.4:
            # Un congénère répond de l'autre côté, plus loin.
            place(out, circ_filter(call, lp(4000, 1)) * gain * 0.5, t + _rng.uniform(1.2, 2.2), -position)
        t += _rng.uniform(5.0, 11.0)
    return circ_filter(out, hp(1500, 2))


# ---------------------------------------------------------------------------

def build():
    stems = {
        "pad": layer_pad(),
        "shimmer": layer_shimmer(),
        "harp": layer_harp(),
        "flute": layer_flute(),
        "wind": layer_wind(),
        "birds": layer_birds(),
    }
    stems = {name: set_rms(x, STEM_DB[name]) for name, x in stems.items()}
    # Sons "d'espace" : les instruments partagent un écho puis une grande réverbe ; les
    # oiseaux sont plus mouillés (ils chantent au loin dans les arbres).
    music = stems["pad"] + stems["shimmer"] + echo(stems["harp"]) + stems["flute"]
    mix = reverb(music, decay=4.5, wet=0.55, seed=SEED)
    mix += reverb(stems["birds"], decay=3.0, wet=0.8, seed=SEED + 1) + stems["wind"]
    mix = circ_filter(mix, hp(35, 2))
    mix = set_rms(mix, MASTER_RMS_DB)
    limit = 10 ** (MASTER_PEAK_DB / 20)
    mix = np.tanh(mix / limit) * limit
    return mix, stems


def write_ogg(path, x):
    # Par blocs d'une seconde : libsndfile plante (sans message) quand on lui passe plusieurs
    # minutes de Vorbis en un seul write.
    frames = x.T.astype(np.float32)
    with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(frames), SR):
            f.write(frames[i:i + SR])


def write_preview(mix, stems):
    preview = os.path.join(HERE, "preview")
    os.makedirs(preview, exist_ok=True)
    # Sans ça l'éditeur Godot importerait ces .ogg d'écoute comme des ressources du projet.
    open(os.path.join(preview, ".gdignore"), "w").close()
    files = []
    seam = np.concatenate([mix[:, -sec(10):], mix[:, :sec(10)]], axis=1)
    for name, x in [("raccord_boucle", seam)] + sorted(stems.items()):
        # Couches seules remontées au niveau du mixage pour être audibles.
        y = x if name == "raccord_boucle" else set_rms(x, MASTER_RMS_DB)
        y = np.clip(y, -1, 1)
        write_ogg(os.path.join(preview, name + ".ogg"), y)
        files.append(name + ".ogg")
    rows = ['<tr><td>mixage complet</td><td><audio controls loop src="../../../assets/audio/music/forest_ambience.ogg"></audio></td></tr>']
    rows += [f'<tr><td>{os.path.splitext(f)[0]}</td><td><audio controls src="{f}"></audio></td></tr>' for f in files]
    html = ("<!doctype html><meta charset=utf-8><title>Forest music preview</title>"
            "<style>body{font-family:Tahoma,sans-serif;background:#111;color:#ddd}td{padding:3px 10px}</style>"
            "<p>« raccord_boucle » = 10 s de fin puis 10 s de début : la jonction (à 10 s) doit être inaudible.</p>"
            "<table>" + "".join(rows) + "</table>")
    path = os.path.join(preview, "index.html")
    open(path, "w", encoding="utf-8").write(html)
    print("aperçu :", path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    mix, stems = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_ogg(OUT, mix)
    for name, x in stems.items():
        print(f"  {name:8s} {rms_db(x):6.1f} dB RMS")
    print(f"{OUT}  {LOOP_SECONDS:.0f}s  {rms_db(mix):.1f} dB RMS  pic {20 * np.log10(np.max(np.abs(mix))):.1f} dB")
    if args.preview:
        write_preview(mix, stems)


if __name__ == "__main__":
    main()
