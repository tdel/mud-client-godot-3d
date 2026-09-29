"""Génère les effets sonores du jeu (sorts + interface) dans assets/audio/sfx/.

Chaque son est un petit "mixage" : des enregistrements libres de droits (CC0, voir SOURCES)
superposés à des couches synthétisées ici (cloches, souffles de vent, grondements, nappes),
puis réverbérés, normalisés en niveau et exportés en OGG Vorbis mono (mono = spatialisation
propre par AudioStreamPlayer3D côté Godot).

Usage (depuis la racine du projet) :
    uv run --with numpy --with scipy --with miniaudio --with soundfile --with py7zr \
        python tools/sfx_gen/build_sfx.py [--preview] [--only=<préfixe>]

Les sources sont téléchargées une fois dans tools/sfx_gen/.cache/ (ignoré par git).
--preview écrit en plus tools/sfx_gen/preview/index.html (lecteurs audio pour tout écouter
d'un coup dans un navigateur).

Nommage de sortie :
    spell_<famille>_<phase>.ogg  — famille : voir FAMILIES (Game3D/Sfx.gd font la
                                   correspondance élément de sort -> famille) ;
                                   phase : cast (début d'incantation), launch (libération),
                                   impact (arrivée d'un projectile sur sa cible)
    ui_<nom>.ogg                 — sons d'interface (bus "UI" côté Godot), dont
                                   ui_item_<equip|unequip>_<weapon|armor|jewel>.ogg
                                   et ui_action_denied.ogg (action refusée),
                                   ui_party_<join|leave>.ogg (arrivée / départ d'un membre)
    combat_<nom>.ogg             — sons de combat (bus "SFX") : combat_miss (sort raté,
                                   spatialisé sur la cible), combat_kill (cible abattue)
    event_<nom>.ogg              — événements de progression (bus "SFX", non spatialisés) :
                                   event_level_up (montée de niveau du joueur, ~3,5 s)
"""

import argparse
import base64
import io
import os
import urllib.request
import zipfile

import miniaudio
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

OGA = "https://opengameart.org/sites/default/files/"
## Toutes CC0 (domaine public). Détail des auteurs dans assets/audio/sfx/CREDITS.md.
SOURCES = {
    "rpg80": ("zip", OGA + "80-CC0-RPG-SFX_0.zip"),              # rubberduck
    "water": ("zip", OGA + "water-splash-slime-sfx.zip"),         # rubberduck
    "dark": ("7z", OGA + "dark_magic.7z"),                        # qubodup
    "swoosh": ("7z", OGA + "swoshes.7z"),                         # qubodup
    "magical": ("files", [OGA + "magical_%d.ogg" % i for i in range(1, 8)]),  # JaggedStone
    "kenney_interface": ("zip", "https://github.com/Calinou/kenney-interface-sounds/archive/refs/heads/master.zip"),
    "kenrpg": ("files", [
        "https://gamesounds.xyz/Kenney%27s%20Sound%20Pack/RPG%20Audio/" + n + ".ogg"
        for n in ("bookClose", "bookFlip2", "bookFlip3", "bookPlace1", "drawKnife1", "drawKnife2", "cloth1",
                  "cloth2", "cloth3", "beltHandle1", "handleSmallLeather", "dropLeather", "metalLatch",
                  "metalClick")
    ]),
}

FAMILIES = ["fire", "water", "wind", "holy", "dark", "arcane", "heal", "buff", "physical"]


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

def fetch_sources():
    for name, (kind, url) in SOURCES.items():
        dest = os.path.join(CACHE, name)
        if kind == "files":
            # Fichier par fichier : une source ajoutée à la liste est récupérée même si le
            # dossier du pack existe déjà.
            urls = [u for u in url if not os.path.exists(os.path.join(dest, _file_name(u)))]
        else:
            urls = [] if os.path.isdir(dest) and os.listdir(dest) else [url]
        if not urls:
            continue
        os.makedirs(dest, exist_ok=True)
        print("téléchargement", name)
        for u in urls:
            data = urllib.request.urlopen(u, timeout=120).read()
            if kind == "files":
                open(os.path.join(dest, _file_name(u)), "wb").write(data)
            elif kind == "zip":
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for member in z.namelist():
                        if member.lower().endswith((".ogg", ".wav", ".flac")):
                            open(os.path.join(dest, os.path.basename(member)), "wb").write(z.read(member))
            else:
                import py7zr
                with py7zr.SevenZipFile(io.BytesIO(data)) as z:
                    for member, content in z.readall().items():
                        if member.lower().endswith((".ogg", ".wav", ".flac")):
                            open(os.path.join(dest, os.path.basename(member)), "wb").write(content.read())


def _file_name(url):
    return os.path.basename(url).replace("%27", "'")


def src(path):
    """Charge une source du cache en mono float32 à SR, pic normalisé à 1."""
    d = miniaudio.decode_file(os.path.join(CACHE, path), output_format=miniaudio.SampleFormat.FLOAT32,
                              nchannels=1, sample_rate=SR)
    x = np.frombuffer(d.samples, dtype=np.float32).astype(np.float64)
    return x / max(np.max(np.abs(x)), 1e-9)


# ---------------------------------------------------------------------------
# Outils de mixage
# ---------------------------------------------------------------------------

def sec(t):
    return int(round(t * SR))


def silence(duration):
    return np.zeros(sec(duration))


def mix(*layers, length=None):
    """layers : (signal, décalage_s, gain) ; renvoie la somme."""
    end = max(sec(off) + len(x) for x, off, _ in layers)
    out = np.zeros(max(end, sec(length) if length else 0))
    for x, off, gain in layers:
        o = sec(off)
        out[o:o + len(x)] += x * gain
    return out


def trim(x, start=0.0, end=None):
    return x[sec(start):(sec(end) if end is not None else len(x))]


def from_onset(x, threshold=0.1, lead=0.004):
    """Coupe le silence de tête d'une source (jusqu'à `lead` s avant le premier échantillon
    dépassant `threshold` × crête) : les décalages de mix() tombent alors sur l'attaque réelle."""
    start = int(np.argmax(np.abs(x) > threshold * np.max(np.abs(x))))
    return x[max(0, start - sec(lead)):]


def fade(x, fade_in=0.0, fade_out=0.0):
    x = x.copy()
    n_in, n_out = min(sec(fade_in), len(x)), min(sec(fade_out), len(x))
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in) ** 2
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out) ** 2
    return x


def pitch(x, factor):
    """Change la hauteur ET la durée (lecture plus rapide/lente, comme un sampler)."""
    return signal.resample(x, max(1, int(len(x) / factor)))


def _filt(x, kind, freq, order=4):
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=4):
    return _filt(x, "lowpass", f, order)


def highpass(x, f, order=4):
    return _filt(x, "highpass", f, order)


def bandpass(x, lo, hi, order=2):
    return _filt(x, "bandpass", [lo, hi], order)


_rng = np.random.default_rng(1234)


def noise(duration):
    return _rng.uniform(-1, 1, sec(duration))


def reverb(x, wet=0.25, decay=1.2, damp=5000.0, pre_delay=0.012):
    """Réverbe de salle simple : convolution par un bruit à décroissance exponentielle."""
    n = sec(decay)
    t = np.arange(n) / SR
    ir = _rng.normal(0, 1, n) * np.exp(-6.9 * t / decay)
    ir = lowpass(ir, damp, 2)
    ir = np.concatenate([np.zeros(sec(pre_delay)), ir])
    ir /= np.sqrt(np.sum(ir ** 2))
    tail = signal.fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return dry * (1 - wet * 0.5) + tail * wet


def env_adsr(n, attack, release_shape=4.0):
    """Enveloppe attaque linéaire + décroissance exponentielle sur n échantillons."""
    t = np.arange(n) / SR
    a = sec(attack)
    e = np.exp(-release_shape * t / max(t[-1], 1e-9))
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def bell(freq, duration, decay=3.0, brightness=1.0):
    """Cloche/carillon : partiels inharmoniques qui s'éteignent d'autant plus vite qu'ils sont aigus."""
    t = np.arange(sec(duration)) / SR
    out = np.zeros_like(t)
    for ratio, amp in ((1.0, 1.0), (2.76, 0.45 * brightness), (5.40, 0.25 * brightness), (8.93, 0.12 * brightness)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-decay * ratio ** 0.7 * t)
    a = sec(0.003)
    out[:a] *= np.linspace(0, 1, a)
    return out


def pluck(freq, duration, decay=4.0):
    """Corde pincée douce (harpe) : fondamentale + harmoniques amorties."""
    t = np.arange(sec(duration)) / SR
    out = np.zeros_like(t)
    for h, amp in ((1, 1.0), (2, 0.5), (3, 0.22), (4, 0.1)):
        out += amp * np.sin(2 * np.pi * freq * h * t) * np.exp(-decay * h ** 0.8 * t)
    a = sec(0.004)
    out[:a] *= np.linspace(0, 1, a)
    return out


def pad(freqs, duration, cutoff=1800.0, attack=0.6):
    """Nappe : dents de scie désaccordées, filtrées, montée lente."""
    t = np.arange(sec(duration)) / SR
    out = np.zeros_like(t)
    for f in freqs:
        for detune in (0.997, 1.003):
            out += signal.sawtooth(2 * np.pi * f * detune * t)
    out = lowpass(out, cutoff, 2)
    return out * env_adsr(len(t), attack, 2.5)


def boom(duration, f0, f1, noise_amount=0.3):
    """Coup sourd : sinus dont la hauteur chute + souffle grave filtré."""
    n = sec(duration)
    t = np.arange(n) / SR
    freq = f1 + (f0 - f1) * np.exp(-t * 9.0)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t * 5.0 / duration)
    rumble = lowpass(noise(duration), 260, 2) * np.exp(-t * 7.0 / duration) * noise_amount * 3
    a = sec(0.004)
    body[:a] *= np.linspace(0, 1, a)
    return body + rumble


def whoosh(duration, f_start, f_end, width=0.6, shape="arch"):
    """Souffle de vent : bruit filtré dont la bande balaie f_start -> f_end (échelle log)."""
    n = sec(duration)
    x = noise(duration + 0.1)
    f, t, z = signal.stft(x, SR, nperseg=1024)
    progress = np.clip(t / duration, 0, 1)
    centers = np.exp(np.log(f_start) + (np.log(f_end) - np.log(f_start)) * progress)
    logf = np.log(np.maximum(f, 1.0))[:, None]
    mask = np.exp(-0.5 * ((logf - np.log(centers)[None, :]) / width) ** 2)
    _, y = signal.istft(z * mask, SR, nperseg=1024)
    y = y[:n]
    p = np.linspace(0, 1, len(y))
    if shape == "arch":
        e = np.sin(np.pi * p) ** 1.5
    elif shape == "rise":
        e = p ** 1.6 * (1 - p ** 12)
    else:  # "fall"
        e = (1 - p) ** 2 * np.minimum(1, p * 30)
    return y * e


def peak1(x):
    return x / max(np.max(np.abs(x)), 1e-9)


def env_ar(duration, attack, release):
    """Enveloppe attaque (courbe rapide, pour du mordant) / plateau / relâchement."""
    e = np.ones(sec(duration))
    a, r = min(sec(attack), len(e)), min(sec(release), len(e))
    if a:
        e[:a] = 1 - (1 - np.linspace(0, 1, a)) ** 2
    if r:
        e[-r:] *= np.linspace(1, 0, r) ** 2
    return e


def glide(duration, tau):
    """Progression 0 -> 1 rapide puis stabilisée (1 - e^(-t/tau)) : l'énergie d'une
    incantation se rassemble dans la première demi-seconde (les casts durent 0,4 à 0,8 s)."""
    return 1 - np.exp(-np.arange(sec(duration)) / SR / tau)


def svf_bp(x, fc, q):
    """Passe-bande résonant (SVF « TPT », gain 1 à la résonance) dont la fréquence centrale
    varie à chaque échantillon : c'est lui qui fait « siffler » et tourner le vent."""
    fc = np.broadcast_to(np.clip(fc, 20.0, SR * 0.45), x.shape)
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / q
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = []
    ic1 = ic2 = 0.0
    for v0, b1, b2, b3 in zip(x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()):
        v3 = v0 - ic2
        v1 = b1 * ic1 + b2 * v3
        v2 = ic2 + b2 * ic1 + b3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out.append(v1)
    return np.array(out) * k


def swirl(duration, f0, f1, rate0, rate1, depth=0.6, q=3.0, voices=3, spread=1.6,
          tau=0.45, attack=0.05, release=0.5, am=0.6):
    """Tourbillon : du bruit passé dans plusieurs filtres résonants dont la fréquence
    « tourne » (modulation circulaire) autour d'un centre qui glisse f0 -> f1, la rotation
    accélérant de rate0 à rate1 tours/s. Chaque voix est déphasée et plus forte quand elle
    monte (effet Doppler) : on entend l'air tourner autour du lanceur."""
    p = glide(duration, tau)
    center = np.exp(np.log(f0) + (np.log(f1) - np.log(f0)) * p)
    phase = 2 * np.pi * np.cumsum(rate0 + (rate1 - rate0) * p) / SR
    out = np.zeros(len(p))
    for v in range(voices):
        s = np.sin(phase + 2 * np.pi * v / voices)
        fc = center * spread ** v * 2 ** (depth * s)
        out += svf_bp(noise(duration), fc, q) * (1 - am + am * (0.5 + 0.5 * s)) / (1 + 0.35 * v)
    return peak1(out * env_ar(duration, attack, release))


def hum(duration, f0, f1, rate0=3.0, rate1=8.0, partials=8, tau=0.45, attack=0.04,
        release=0.5, trem=0.45, detune=0.006, cutoff=2400.0):
    """Vrombissement magique : son tonal (dents de scie additives, deux voix désaccordées)
    qui glisse de f0 à f1, avec un trémolo calé sur la rotation du tourbillon."""
    p = glide(duration, tau)
    freq = f0 * (f1 / f0) ** p
    rate = rate0 + (rate1 - rate0) * p
    out = np.zeros(len(p))
    for d in (1 - detune, 1 + detune):
        ph = 2 * np.pi * np.cumsum(freq * d) / SR
        for h in range(1, partials + 1):
            out += np.sin(h * ph + h) / h
    out = lowpass(out, cutoff, 2)
    out *= 1 - trem + trem * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(rate) / SR))
    return peak1(out * env_ar(duration, attack, release))


## Formants (fréquence, largeur de bande, gain) des voyelles chantées ; « a » = « aaah » de
## chœur, « o » plus sombre et rond.
VOWELS = {
    "a": ((800, 90, 1.0), (1150, 100, 0.55), (2900, 140, 0.12), (3900, 160, 0.06)),
    "o": ((450, 70, 1.0), (800, 90, 0.4), (2830, 130, 0.05), (3800, 150, 0.03)),
}


def choir(freqs, duration, vowel="a", attack=0.2, release=0.8, voices=3, vibrato=5.2):
    """Chœur : pour chaque note, quelques voix désaccordées au vibrato indépendant, en synthèse
    additive dont chaque harmonique est pondérée par les formants de la voyelle."""
    t = np.arange(sec(duration)) / SR
    formants = VOWELS[vowel]

    def response(f):
        return sum(g / (1 + ((f - fc) / (bw / 2)) ** 2) for fc, bw, g in formants) + 0.02

    out = np.zeros(len(t))
    for f in freqs:
        for v in range(voices):
            d = 1 + _rng.uniform(-0.004, 0.004)
            rate = vibrato * _rng.uniform(0.85, 1.15)
            vib = 1 + 0.004 * np.sin(2 * np.pi * rate * t + _rng.uniform(0, 6.3)) * np.minimum(1, t / 0.4)
            ph = 2 * np.pi * np.cumsum(f * d * vib) / SR
            for h in range(1, int(5000 / f) + 1):
                out += np.sin(h * ph + _rng.uniform(0, 6.3)) * response(f * h) / h ** 0.6
    # Souffle des voix : un peu de bruit passé dans les mêmes formants.
    breath = sum(bandpass(noise(duration), fc - bw, fc + bw) * g for fc, bw, g in formants)
    out = peak1(out) + peak1(breath) * 0.06
    return peak1(out * env_ar(duration, attack, release))


def sparkle(duration, count, lo, hi, decay=9.0):
    """Scintillement : petites clochettes aiguës semées au hasard (poussière lumineuse)."""
    out = np.zeros(sec(duration) + sec(0.6))
    for _ in range(count):
        b = bell(np.exp(_rng.uniform(np.log(lo), np.log(hi))), 0.6, decay, 0.5) * _rng.uniform(0.4, 1.0)
        o = sec(_rng.uniform(0, duration))
        out[o:o + len(b)] += b
    return peak1(out)


def cathedral(x, wet=0.5, decay=4.0, damp=6500.0):
    """Grande nef : premières réflexions espacées (murs lointains) puis longue queue diffuse
    qui s'installe progressivement (« bloom »)."""
    n = sec(decay)
    t = np.arange(n) / SR
    tail = _rng.normal(0, 1, n) * np.exp(-6.9 * t / decay) * np.minimum(1, t / 0.08)
    tail = lowpass(tail, damp, 2)
    ir = np.concatenate([np.zeros(sec(0.035)), tail])
    for delay, gain in ((0.019, 0.5), (0.031, 0.4), (0.047, 0.35), (0.063, 0.3), (0.089, 0.25)):
        ir[sec(delay)] += gain * np.max(np.abs(tail)) * 0.6
    ir /= np.sqrt(np.sum(ir ** 2))
    tailx = signal.fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(tailx) - len(x))])
    return dry * (1 - wet * 0.5) + tailx * wet


def normalize(x, rms_db, peak_db=-1.0):
    """Cale le niveau RMS de la partie active sur rms_db, sans dépasser peak_db en crête."""
    env = np.abs(x)
    active = x[env > np.max(env) * 0.05]
    rms = np.sqrt(np.mean(active ** 2)) if len(active) else 1e-9
    x = x * (10 ** (rms_db / 20) / rms)
    peak = np.max(np.abs(x))
    limit = 10 ** (peak_db / 20)
    if peak > limit:
        # Limiteur doux : compression tanh au-delà du seuil plutôt qu'un simple gain global,
        # pour ne pas faire tomber tout le son à cause d'une seule crête de transitoire.
        x = np.tanh(x / limit) * limit
    return x


def finish(x, rms_db, tail_fade=0.08):
    x = x - np.mean(x)
    x = highpass(x, 35, 2)
    # Coupe la queue silencieuse (réverbe éteinte) pour ne pas stocker de silence.
    env = np.abs(x)
    above = np.where(env > np.max(env) * 0.003)[0]
    if len(above):
        x = x[:min(len(x), above[-1] + sec(0.05))]
    return normalize(fade(x, 0.0, tail_fade), rms_db)


# Niveaux cibles (dB RMS de la partie active) : le lancement et l'impact portent, l'incantation
# reste en retrait (elle dure et se répète), l'interface est discrète.
CAST_DB, LAUNCH_DB, IMPACT_DB = -19.0, -17.0, -16.0


# ---------------------------------------------------------------------------
# Recettes des sorts
# ---------------------------------------------------------------------------

def notes(*names):
    base = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    out = []
    for n in names:
        semis = base[n[0]] + (1 if "#" in n else 0) + 12 * (int(n[-1]) - 4)
        out.append(440.0 * 2 ** (semis / 12))
    return out


def spells():
    s = {}

    # Incantations façon Lineage 2 : une bouffée d'énergie immédiate (un cast ne dure que 0,4
    # à 0,8 s, il doit « claquer » dès le clic) puis un tourbillon propre à l'élément qui monte
    # et accélère ; Game3D l'efface à la libération, relayé par le son de lancement. Les sorts
    # de soutien (soin, renforcement) tournent dans une grande nef : chœur, cloches, longue
    # réverbération.
    CAST = 2.0

    def gust(f_hi, f_lo, duration=0.35):
        """Bouffée d'attaque : souffle qui part à fond et retombe aussitôt."""
        return peak1(whoosh(duration, f_hi, f_lo, 0.5, "fall"))

    def arp(names, step, duration=1.4, decay=2.5, brightness=0.8):
        return [(bell(f, duration, decay, brightness), step * i, 1.0) for i, f in enumerate(notes(*names))]

    def scaled(layers, gain):
        return [(x, off, g * gain) for x, off, g in layers]

    # --- Feu : vortex rugissant et crépitant, souffle enflammé, explosion -------------
    s["fire_cast"] = reverb(mix(
        (swirl(CAST, 220, 700, 2.0, 6.0, depth=0.7, q=1.4, spread=1.8), 0.0, 0.9),
        (hum(CAST, 55, 82, 2.0, 6.0, partials=10, cutoff=900), 0.0, 0.35),
        (from_onset(src("rpg80/spell_fire_05.ogg")), 0.0, 0.8),
        (trim(src("rpg80/spell_fire_03.ogg"), 0.2, 1.8), 0.15, 0.4),
        (boom(0.35, 110, 45, 0.6), 0.0, 0.6),
        (gust(2500, 400), 0.0, 0.5),
    ), 0.2, 1.1)
    s["fire_launch"] = reverb(mix(
        (src("rpg80/spell_fire_06.ogg"), 0.0, 1.0),
        (lowpass(src("swoosh/swosh-05.flac"), 2200), 0.0, 0.7),
        (swirl(0.8, 700, 250, 7.0, 2.0, depth=0.7, q=1.4, attack=0.005, release=0.7), 0.0, 0.5),
        (boom(0.45, 100, 42, 0.4), 0.0, 0.7),
    ), 0.15, 0.9)
    s["fire_impact"] = reverb(mix(
        (boom(0.8, 120, 38, 0.45), 0.0, 1.0),
        (pitch(src("rpg80/spell_fire_06.ogg"), 0.8), 0.0, 0.8),
        (fade(trim(src("rpg80/spell_fire_03.ogg"), 0.4), 0.05, 0.4), 0.12, 0.45),
    ), 0.2, 1.3)

    # --- Eau : tourbillon liquide et bulles, jet d'eau, grosse éclaboussure ----------
    s["water_cast"] = reverb(mix(
        (swirl(CAST, 350, 1000, 2.5, 7.0, depth=0.8, q=7.0, spread=1.5), 0.0, 0.8),
        (swirl(CAST, 150, 300, 2.0, 5.0, depth=0.5, q=1.5, voices=2), 0.0, 0.4),
        (gust(2200, 500), 0.0, 0.5),
        (from_onset(src("water/bubble_02.ogg")), 0.03, 0.7),
        (from_onset(src("water/bubble_01.ogg")), 0.20, 0.5),
        (pitch(from_onset(src("water/bubble_02.ogg")), 1.3), 0.38, 0.55),
        (pitch(from_onset(src("water/bubble_03.ogg")), 0.8), 0.60, 0.35),
        (lowpass(src("magical/magical_1.ogg"), 3000), 0.0, 0.3),
    ), 0.3, 1.3)
    s["water_launch"] = reverb(mix(
        (src("swoosh/swosh-13.flac"), 0.0, 0.6),
        (src("water/splash_13.ogg"), 0.0, 1.0),
        (src("water/bubble_03.ogg"), 0.05, 0.4),
        (swirl(0.7, 900, 350, 8.0, 3.0, depth=0.8, q=6.0, attack=0.005, release=0.6), 0.0, 0.45),
        (boom(0.3, 95, 50, 0.3), 0.0, 0.4),
    ), 0.2, 1.0)
    s["water_impact"] = reverb(mix(
        (src("water/splash_05.ogg"), 0.0, 1.0),
        (src("water/splash_02.ogg"), 0.03, 0.6),
        (boom(0.35, 90, 50, 0.1), 0.0, 0.3),
    ), 0.18, 1.0)

    # --- Vent : tourbillon sifflant qui accélère, trait d'air tranchant, bourrasque ---
    s["wind_cast"] = reverb(mix(
        (swirl(CAST, 450, 1300, 3.0, 8.5, depth=0.75, q=4.5, spread=1.7), 0.0, 1.0),
        (swirl(CAST, 160, 320, 2.0, 5.0, depth=0.5, q=1.2, voices=2, spread=1.5), 0.0, 0.55),
        (gust(3200, 700, 0.3), 0.0, 0.6),
        (hum(CAST, 392, 587, 3.0, 8.5, partials=4, cutoff=2500, trem=0.6), 0.0, 0.1),
    ), 0.25, 1.4)
    s["wind_launch"] = reverb(mix(
        (peak1(whoosh(0.4, 350, 4500, 0.4, "arch")), 0.0, 0.9),
        (src("swoosh/swosh-16.flac"), 0.0, 0.8),
        (swirl(0.9, 1400, 600, 9.0, 3.0, depth=0.8, q=4.0, attack=0.005, release=0.8), 0.0, 0.6),
        (boom(0.3, 100, 45, 0.7), 0.0, 0.45),
    ), 0.18, 1.0)
    s["wind_impact"] = reverb(mix(
        (swirl(1.0, 1800, 450, 10.0, 3.0, depth=0.8, q=3.0, tau=0.35, attack=0.004, release=0.9), 0.0, 0.9),
        (src("swoosh/swosh-19.flac"), 0.0, 0.8),
        (pitch(src("swoosh/swosh-04.flac"), 1.2), 0.07, 0.6),
        (boom(0.4, 100, 45, 0.5), 0.0, 0.55),
    ), 0.2, 1.1)

    # --- Sacré (attaque) : tourbillon lumineux + chœur, éclat de cloches, frappe ------
    s["holy_cast"] = cathedral(mix(
        (swirl(CAST, 1100, 3000, 3.0, 8.5, depth=0.7, q=4.5), 0.0, 0.7),
        (choir(notes("E4", "B4", "E5"), CAST, "a", 0.08, 0.7), 0.0, 0.55),
        (hum(CAST, 165, 247, 3.0, 8.5, cutoff=2000), 0.0, 0.25),
        *scaled(arp(("E5", "B5", "E6", "G#6"), 0.07), 0.3),
        (gust(4000, 1200, 0.3), 0.0, 0.45),
    ), 0.4, 2.5)
    s["holy_launch"] = cathedral(mix(
        *[(bell(f, 1.2, 3.0), 0.0, 0.45) for f in notes("E6", "B6", "E7")],
        (highpass(src("swoosh/swosh-17.flac"), 1500), 0.0, 0.6),
        (peak1(whoosh(0.35, 800, 6000, 0.4, "arch")), 0.0, 0.6),
        (choir(notes("E5", "B5", "E6"), 0.9, "a", 0.01, 0.8), 0.0, 0.4),
        (boom(0.3, 130, 60, 0.3), 0.0, 0.4),
    ), 0.4, 2.8)
    s["holy_impact"] = reverb(mix(
        (bell(notes("E5")[0], 1.2, 3.5), 0.0, 0.8),
        (bell(notes("B6")[0], 0.8, 4.0), 0.0, 0.5),
        (fade(highpass(noise(0.25), 3000), 0.0, 0.22), 0.0, 0.4),
        (boom(0.3, 140, 70, 0.0), 0.0, 0.3),
    ), 0.35, 1.5)

    # --- Ténèbres / malédictions : vortex grave et grondement, souffle maléfique, choc
    s["dark_cast"] = reverb(mix(
        (swirl(CAST, 140, 450, 1.8, 5.0, depth=0.7, q=2.5, spread=1.7), 0.0, 0.8),
        (hum(CAST, 55, 49, 1.5, 4.0, partials=12, cutoff=1200, detune=0.012), 0.0, 0.45),
        (fade(pitch(trim(src("dark/fout-03.flac"), 0.3, 2.6), 0.85), 0.03, 0.5), 0.0, 0.8),
        (boom(0.4, 80, 35, 0.6), 0.0, 0.55),
        (gust(1800, 300), 0.0, 0.4),
    ), 0.3, 1.5, 3500)
    s["dark_launch"] = reverb(mix(
        (pitch(src("dark/fout-02.flac"), 0.9), 0.0, 1.0),
        (swirl(0.8, 450, 150, 6.0, 2.0, depth=0.7, q=2.5, attack=0.005, release=0.7), 0.0, 0.45),
        (boom(0.4, 85, 38, 0.5), 0.0, 0.5),
    ), 0.3, 1.3, 4000)
    s["dark_impact"] = reverb(mix(
        (pitch(src("dark/fout-02.flac"), 0.7), 0.0, 1.0),
        (boom(0.7, 75, 32, 0.4), 0.0, 0.7),
    ), 0.3, 1.4, 3500)

    # --- Arcane (sort non classé) : tourbillon + vrombissement, éclat, impact ---------
    s["arcane_cast"] = reverb(mix(
        (swirl(CAST, 700, 1900, 3.0, 8.0, depth=0.7, q=4.0), 0.0, 0.6),
        (hum(CAST, 220, 330, 3.0, 8.0, partials=6), 0.0, 0.3),
        (fade(trim(src("magical/magical_4.ogg"), 0.0, 2.0), 0.0, 0.4), 0.0, 0.7),
        (gust(3000, 800), 0.0, 0.45),
    ), 0.3, 1.4)
    s["arcane_launch"] = reverb(mix(
        (src("rpg80/spell_01.ogg"), 0.0, 1.0),
        (src("magical/magical_2.ogg"), 0.05, 0.45),
    ), 0.25, 1.2)
    s["arcane_impact"] = reverb(mix(
        (src("rpg80/spell_02.ogg"), 0.0, 1.0),
        (src("magical/magical_6.ogg"), 0.02, 0.5),
    ), 0.25, 1.2)

    # --- Soin : tourbillon aérien dans une cathédrale (chœur, poussière de cloches), puis
    #     l'accord s'épanouit et s'élève --------------------------------------------------
    s["heal_cast"] = cathedral(mix(
        (swirl(CAST, 1500, 3800, 2.5, 6.5, depth=0.65, q=5.0, spread=1.45, attack=0.08, release=0.7), 0.0, 0.6),
        (choir(notes("C4", "G4", "C5", "E5"), CAST, "a", 0.06, 0.8), 0.0, 0.75),
        (peak1(pad(notes("C3", "G3"), CAST, 800, 0.2)), 0.0, 0.2),
        (sparkle(1.8, 16, 2000, 6000), 0.05, 0.3),
        (peak1(bell(notes("C6")[0], 1.5, 2.5, 0.6)), 0.0, 0.3),
        (peak1(whoosh(0.4, 1200, 5000, 0.5, "arch")), 0.0, 0.25),
    ), 0.55, 3.8)
    s["heal_launch"] = cathedral(mix(
        (choir(notes("C4", "E4", "G4", "C5", "G5"), 2.6, "a", 0.04, 2.0), 0.0, 0.75),
        (choir(notes("E5", "G5", "C6"), 2.2, "a", 0.08, 1.6), 0.06, 0.3),
        *scaled(arp(("C6", "E6", "G6", "C7", "E7"), 0.05, 1.6, 2.2, 0.6), 0.3),
        (swirl(1.8, 2200, 6500, 6.0, 2.0, depth=0.6, q=5.0, tau=0.6, attack=0.01, release=1.3), 0.0, 0.45),
        (sparkle(1.4, 20, 2500, 8000), 0.05, 0.3),
        (pitch(src("magical/magical_3.ogg"), 1.2), 0.0, 0.25),
    ), 0.6, 4.5)

    # --- Renforcement : même nef, chœur plus sombre sur un bourdon grave, puis accord
    #     triomphant et arpège de cloches -------------------------------------------------
    s["buff_cast"] = cathedral(mix(
        (swirl(CAST, 700, 1800, 2.5, 7.0, depth=0.65, q=4.5), 0.0, 0.6),
        (choir(notes("A3", "E4", "A4", "C#5"), CAST, "o", 0.05, 0.8), 0.0, 0.7),
        (hum(CAST, 110, 110, 2.5, 7.0, partials=10, cutoff=1500), 0.0, 0.3),
        (sparkle(1.6, 8, 1500, 4000), 0.1, 0.2),
        (gust(2500, 700), 0.0, 0.6),
    ), 0.45, 3.2)
    s["buff_launch"] = cathedral(mix(
        *scaled(arp(("A5", "C#6", "E6", "A6", "C#7"), 0.045, 0.9, 3.5, 0.7), 0.4),
        (choir(notes("A4", "C#5", "E5", "A5"), 1.6, "a", 0.02, 1.2), 0.0, 0.55),
        (swirl(1.2, 1500, 4500, 7.0, 2.5, attack=0.005, release=1.0), 0.0, 0.45),
        (src("rpg80/item_gem_04.ogg"), 0.05, 0.35),
        (boom(0.35, 110, 55, 0.2), 0.0, 0.35),
    ), 0.5, 3.2)

    # --- Physique (Power Strike...) : arme qu'on apprête, frappe lame + métal ---------
    s["physical_cast"] = mix(
        (src("kenrpg/drawKnife1.ogg"), 0.0, 1.0),
        (src("kenrpg/cloth1.ogg"), 0.15, 0.6),
    )
    s["physical_launch"] = reverb(mix(
        (src("swoosh/swosh-08.flac"), 0.0, 1.0),
        (src("rpg80/blade_03.ogg"), 0.08, 0.9),
        (src("rpg80/metal_03.ogg"), 0.10, 0.45),
    ), 0.12, 0.8)

    out = {}
    for name, x in s.items():
        phase = name.split("_")[1]
        out["spell_" + name] = finish(x, {"cast": CAST_DB, "launch": LAUNCH_DB, "impact": IMPACT_DB}[phase])
    return out


# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

def ui():
    k = "kenney_interface/"
    r = "kenrpg/"
    return {
        # Ouverture : une seule page qu'on tourne, légère — froissement de papier sans son
        # clic de doigt ni son bruit de manipulation grave, plus un filet d'air.
        "ui_window_open": finish(reverb(mix(
            (fade(bandpass(from_onset(src(r + "bookFlip2.ogg")), 350, 7500), 0.012, 0.08), 0.0, 1.0),
            (whoosh(0.32, 1400, 4200, 0.45, "arch"), 0.02, 0.18),
        ), 0.1, 0.4), -28.0, 0.05),
        # Fermeture : les pages se rabattent (souffle de papier bref) puis le livre se referme
        # en douceur — bruit sourd feutré, sans le claquement aigu de la source.
        "ui_window_close": finish(reverb(mix(
            (fade(lowpass(from_onset(src(r + "bookFlip3.ogg")), 5500), 0.01, 0.06), 0.0, 0.35),
            (lowpass(from_onset(src(r + "bookPlace1.ogg")), 2200), 0.07, 1.0),
            (boom(0.2, 150, 75, 0.1), 0.07, 0.35),
        ), 0.12, 0.45), -27.0, 0.05),
        # Fin de recharge : "tic" très léger, à peine cristallin.
        "ui_cooldown_ready": finish(mix(
            (src(k + "tick_001.wav"), 0.0, 1.0),
            (fade(pitch(src(k + "glass_002.wav"), 1.5), 0.0, 0.06), 0.0, 0.3),
        ), -30.0, 0.02),
        # Action refusée (skill en recharge, déjà en train d'incanter...) : "bang" sourd et
        # bref, comme un coup contre une porte fermée — un bonk de bois étouffé sur un petit
        # coup grave, sans rien d'aigu ni d'agressif (il peut être répété vite).
        "ui_action_denied": finish(reverb(mix(
            (boom(0.16, 260, 130, 0.05), 0.0, 0.5),
            (fade(lowpass(from_onset(src("rpg80/wood_02.ogg")), 2600), 0.0, 0.08), 0.0, 1.0),
            (bandpass(from_onset(src(k + "bong_001.wav")), 250, 1600), 0.0, 0.4),
        ), 0.08, 0.3), -27.0, 0.04),
        **equipment(),
    }


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

def combat():
    return {
        # Sort raté (bus SFX, spatialisé sur la cible, à la place de spell_*_impact) : le
        # projectile frôle la cible et file plus loin — souffle qui passe et retombe (effet
        # Doppler : balayage aigu -> grave) et petite "pluie" d'étincelles qui s'éteint, sans
        # aucun coup sourd, pour qu'on entende tout de suite que rien n'a porté.
        "combat_miss": finish(reverb(mix(
            (highpass(pitch(src("swoosh/swosh-13.flac"), 0.8), 400), 0.0, 0.8),
            (whoosh(0.38, 3200, 600, 0.45, "arch"), 0.02, 0.45),
            (highpass(sparkle(0.35, 5, 2400, 4200, 14.0), 1800), 0.12, 0.12),
        ), 0.12, 0.5), -21.0, 0.06),
        # Cible abattue (bus SFX, non spatialisé) : petite fanfare de deux notes de cloche
        # montantes (quarte) sur un coup grave feutré — distincte de tous les impacts de sorts,
        # joue juste après le dernier coup.
        "combat_kill": finish(reverb(mix(
            (boom(0.3, 110, 55, 0.1), 0.0, 0.45),
            (bell(notes("E6")[0], 0.9, 4.0, 0.7), 0.0, 0.5),
            (bell(notes("A6")[0], 1.1, 3.5, 0.7), 0.09, 0.6),
            (pluck(notes("A5")[0], 0.8, 3.0), 0.09, 0.3),
        ), 0.25, 1.1), -24.0, 0.1),
    }


def events():
    """Événements de progression (bus "SFX", non spatialisés, voir Sfx.play_event)."""
    rise = 0.75  # instant où l'énergie éclate (accord de cloches + chœur)

    def cascade(names, step, gain_end=0.35):
        """Poussière dorée qui retombe : clochettes descendantes, légèrement irrégulières."""
        freqs = notes(*names)
        return [(bell(f, 0.9, 5.0, 0.5), step * i + _rng.uniform(0, step * 0.4),
                 1.0 + (gain_end - 1.0) * i / (len(freqs) - 1))
                for i, f in enumerate(freqs)]

    def scaled(layers, gain, offset=0.0):
        return [(x, off + offset, g * gain) for x, off, g in layers]

    # Montée de niveau, façon Lineage 2 : une colonne d'énergie monte du sol (tourbillon qui
    # s'élève et accélère, harpe qui gravit l'accord de ré majeur), éclate en un accord de
    # cloches lumineux sur un coup grave, puis un chœur s'épanouit dans une grande nef pendant
    # qu'une poussière dorée retombe en scintillant. ~3,5 s au total, distinct du soin (do
    # majeur, pas d'éclat) et du renforcement (la majeur, sans montée).
    x = cathedral(mix(
        # Montée
        (swirl(rise + 0.3, 600, 4200, 2.0, 9.0, depth=0.6, q=4.5, tau=0.5, attack=0.25, release=0.3), 0.0, 0.45),
        (hum(rise + 0.2, notes("D3")[0], notes("D4")[0], 3.0, 10.0, tau=0.5, attack=0.3, release=0.25, cutoff=1800), 0.0, 0.3),
        (peak1(whoosh(rise, 500, 5000, 0.5, "rise")), 0.0, 0.35),
        *scaled([(pluck(f, 1.2, 3.0), 0.085 * i, 0.55 + 0.05 * i)
                 for i, f in enumerate(notes("D4", "F#4", "A4", "D5", "F#5", "A5", "D6"))], 0.5, 0.1),
        # Éclat
        (boom(0.6, 150, notes("D2")[0], 0.25), rise, 0.55),
        *[(bell(f, 2.4, 1.6, 0.9), rise, g)
          for f, g in zip(notes("D6", "F#6", "A6", "D7"), (0.5, 0.35, 0.35, 0.3))],
        (peak1(from_onset(src("rpg80/item_gem_04.ogg"))), rise, 0.3),
        (peak1(whoosh(0.5, 5000, 1500, 0.5, "fall")), rise, 0.25),
        # Épanouissement
        (choir(notes("D4", "F#4", "A4", "D5", "A5"), 2.5, "a", 0.05, 1.7), rise, 0.8),
        (choir(notes("F#5", "A5", "D6"), 2.1, "a", 0.15, 1.5), rise + 0.1, 0.3),
        (peak1(pad(notes("D3", "A3"), 2.6, 900, 0.1)), rise, 0.2),
        *scaled(cascade(("F#7", "D7", "A6", "F#6", "D6", "A5", "F#5", "D5"), 0.11), 0.22, rise + 0.08),
        (highpass(sparkle(1.8, 26, 2500, 8000), 1800), rise + 0.05, 0.2),
    ), 0.5, 3.2)
    # Queue de réverbe bornée : le son ne doit pas dépasser ~4 s.
    x = fade(trim(x, 0.0, 4.0), 0.0, 1.0)
    return {"event_level_up": finish(x, -20.0, 0.1)}


def party():
    """Groupe (bus "UI", voir Game3D._on_party_message). Évalué en dernier dans main() : ses
    tirages aléatoires ne décalent pas ceux des autres recettes, dont les fichiers restent
    identiques."""
    return {
        # Un joueur rejoint le groupe : petit carillon sympathique qui monte (harpe en arpège
        # de do majeur, sol -> do -> mi, puis deux cloches claires et une pincée d'étincelles).
        "ui_party_join": finish(reverb(mix(
            (pluck(notes("G5")[0], 0.9, 3.5), 0.0, 0.5),
            (pluck(notes("C6")[0], 0.9, 3.5), 0.07, 0.55),
            (pluck(notes("E6")[0], 1.0, 3.2), 0.14, 0.6),
            (bell(notes("G6")[0], 1.2, 3.2, 0.6), 0.21, 0.45),
            (bell(notes("C7")[0], 1.0, 3.6, 0.5), 0.21, 0.22),
            (highpass(sparkle(0.45, 8, 3000, 7000), 2000), 0.2, 0.12),
        ), 0.25, 1.2), -25.0, 0.1),
        # Un joueur part, est exclu, ou le groupe se dissout : même timbre, mais qui redescend
        # doucement (mi -> si -> sol -> ré, la dernière note assourdie), sans étincelles.
        "ui_party_leave": finish(reverb(mix(
            (bell(notes("E6")[0], 0.8, 4.0, 0.5), 0.0, 0.4),
            (pluck(notes("B5")[0], 0.8, 3.5), 0.0, 0.35),
            (pluck(notes("G5")[0], 0.9, 3.2), 0.12, 0.5),
            (lowpass(pluck(notes("D5")[0], 1.1, 2.8), 3000), 0.24, 0.55),
            (peak1(whoosh(0.35, 2400, 700, 0.5, "fall")), 0.0, 0.06),
        ), 0.22, 1.0), -27.0, 0.1),
    }


def skill_learning():
    """Compétence apprise auprès du maître des compétences (bus "UI", voir
    Game3D "SkillLearned"). Évalué après party() : ses tirages aléatoires ne décalent pas
    ceux des recettes existantes."""
    return {
        # Révélation : accord de chœur qui s'ouvre (ré majeur), arpège de cloches qui monte
        # vers l'aigu et poussière d'étincelles, dans une réverbe de temple.
        "ui_skill_learn": finish(cathedral(mix(
            (choir(notes("D4", "F#4", "A4"), 1.3, "o", attack=0.15, release=0.7), 0.0, 0.28),
            (bell(notes("A5")[0], 1.0, 3.8, 0.6), 0.05, 0.35),
            (bell(notes("D6")[0], 1.0, 3.8, 0.6), 0.13, 0.35),
            (bell(notes("F#6")[0], 1.1, 3.6, 0.55), 0.21, 0.32),
            (bell(notes("A6")[0], 1.2, 3.4, 0.5), 0.29, 0.3),
            (highpass(sparkle(0.7, 14, 3500, 8000), 2500), 0.25, 0.14),
        ), 0.35, 2.2), -24.0, 0.15),
    }


def equipment():
    """Équiper / retirer un objet, par famille (voir Sfx.EQUIP_FAMILY) : comme dans L2, une
    arme se dégaine avec un tintement métallique, une armure bruisse (cuir, boucle), un bijou
    tinte comme une petite pierre précieuse. Retirer = même matière, plus bref et plus doux."""
    r = "kenrpg/"
    ring = bell(notes("E7")[0], 0.5, 7.0, 0.5)
    s = {
        # Arme : lame qui glisse hors du fourreau puis se cale (clic de garde + résonance).
        "equip_weapon": reverb(mix(
            (fade(lowpass(from_onset(src(r + "drawKnife1.ogg")), 8000), 0.01, 0.08), 0.0, 0.7),
            (from_onset(src(r + "metalLatch.ogg")), 0.13, 0.8),
            (ring, 0.13, 0.08),
        ), 0.12, 0.6),
        "unequip_weapon": reverb(mix(
            (fade(lowpass(pitch(from_onset(src(r + "drawKnife2.ogg")), 0.9), 5000), 0.02, 0.1), 0.0, 0.5),
            (lowpass(from_onset(src(r + "metalClick.ogg")), 6000), 0.16, 0.6),
        ), 0.1, 0.5),
        # Armure : bruissement de tissu/cuir, boucle de ceinture et pièce qui se pose.
        "equip_armor": reverb(mix(
            (lowpass(from_onset(src(r + "cloth3.ogg")), 7000), 0.0, 0.7),
            (from_onset(src(r + "beltHandle1.ogg")), 0.08, 0.6),
            (lowpass(from_onset(src(r + "dropLeather.ogg")), 2500), 0.05, 0.45),
        ), 0.1, 0.5),
        "unequip_armor": reverb(mix(
            (lowpass(from_onset(src(r + "cloth2.ogg")), 5000), 0.0, 0.7),
            (lowpass(from_onset(src(r + "handleSmallLeather.ogg")), 6000), 0.05, 0.6),
        ), 0.1, 0.45),
        # Bijou : pierre qui tinte, petite note cristalline.
        "equip_jewel": reverb(mix(
            (from_onset(src("rpg80/item_gem_01.ogg")), 0.0, 0.8),
            (bell(notes("B6")[0], 0.6, 6.5, 0.6), 0.01, 0.22),
            (bell(notes("E7")[0], 0.5, 7.5, 0.4), 0.06, 0.13),
        ), 0.25, 0.9),
        "unequip_jewel": reverb(mix(
            (lowpass(pitch(from_onset(src("rpg80/item_gem_02.ogg")), 0.9), 7000), 0.0, 0.8),
            (bell(notes("G#6")[0], 0.5, 7.0, 0.5), 0.01, 0.13),
        ), 0.2, 0.7),
    }
    return {"ui_item_" + name: finish(x, -26.0 if name.startswith("equip") else -28.0, 0.04)
            for name, x in s.items()}


# ---------------------------------------------------------------------------

def write_preview(paths):
    preview = os.path.join(HERE, "preview")
    os.makedirs(preview, exist_ok=True)
    rows = []
    for p in paths:
        b64 = base64.b64encode(open(p, "rb").read()).decode()
        name = os.path.splitext(os.path.basename(p))[0]
        rows.append(f'<tr><td>{name}</td><td><audio controls preload="none" src="data:audio/ogg;base64,{b64}"></audio></td></tr>')
    html = ("<!doctype html><meta charset=utf-8><title>SFX preview</title>"
            "<style>body{font-family:Tahoma,sans-serif;background:#111;color:#ddd}td{padding:3px 10px}</style>"
            "<table>" + "".join(rows) + "</table>")
    path = os.path.join(preview, "index.html")
    open(path, "w", encoding="utf-8").write(html)
    print("aperçu :", path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--only", default="", help="n'écrit que les sons dont le nom commence par ce préfixe")
    args = parser.parse_args()
    fetch_sources()
    os.makedirs(OUT, exist_ok=True)
    sounds = {**spells(), **ui(), **combat(), **events(), **party(), **skill_learning()}
    written = []
    for name, x in sorted(sounds.items()):
        if not name.startswith(args.only):
            continue
        path = os.path.join(OUT, name + ".ogg")
        sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
        written.append(path)
        print(f"{name:28s} {len(x) / SR:5.2f}s  pic {20 * np.log10(np.max(np.abs(x))):6.1f} dB")
    if args.preview:
        write_preview(written)


if __name__ == "__main__":
    main()
