"""
CoopHockey background music, round two — arena-hockey idioms.

All melodies original. These borrow the *conventions* of rink music (barn
organ, stomp-clap arena rock, goal-horn brass) rather than any actual tune.

Adds a drum kit, which the first batch lacked and which is most of what
makes this style read as hockey.
"""
import numpy as np, subprocess, os

SR = 44100
OUT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)

def adsr(n, a, d, s, r):
    a, d, r = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    sus = max(0, n - a - d - r)
    return np.concatenate([np.linspace(0, 1, a), np.linspace(1, s, d),
                           np.full(sus, s), np.linspace(s, 0, r)])[:n]

try:
    from scipy.signal import lfilter
    def LP(x, c, res=1):
        a = np.exp(-2 * np.pi * c / SR)
        for _ in range(res):
            x = lfilter([1 - a], [1, -a], x)
        return x
    def HP(x, c):
        return x - LP(x, c, 1)
except ImportError:
    def LP(x, c, res=1):
        X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
        return np.fft.irfft(X / (1 + (f / c) ** (2 * res)) ** 0.5, len(x))
    def HP(x, c):
        return x - LP(x, c, 1)

# ------------------------------------------------------------- instruments

def organ(freq, beats, spb, amp=0.2, a=0.012, r=0.10, vib=True):
    """Drawbar-style additive organ — the barn-organ sound."""
    n = int((beats * spb + r) * SR)
    t = np.arange(n) / SR
    # Harmonic ratios and levels roughly after a classic drawbar registration.
    y = np.zeros(n)
    for ratio, lvl in [(1, 1.0), (2, .70), (3, .45), (4, .32),
                       (6, .18), (8, .12)]:
        y += lvl * np.sin(2 * np.pi * freq * ratio * t)
    if vib:                                   # gentle rotary-ish wobble
        y *= 1 + 0.035 * np.sin(2 * np.pi * 5.6 * t)
    y *= adsr(n, a, 0.05, 0.85, r)
    return LP(y, 4200, 1) * amp * 0.30

def power(freq, beats, spb, amp=0.22, drive=3.4, r=0.10):
    """Root + fifth + octave through soft clipping: an arena power chord."""
    n = int((beats * spb + r) * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for mult, lvl in [(1, 1.0), (1.4983, .85), (2, .55)]:
        p = 2 * np.pi * freq * mult * t
        for h in range(1, 9):
            y += lvl * np.sin(p * h) / h
    y = np.tanh(y * drive) / drive
    y *= adsr(n, 0.004, 0.10, 0.72, r)
    return LP(y, 2600, 2) * amp

def brass(freq, beats, spb, amp=0.2, a=0.07, r=0.30):
    """Goal-horn / fanfare voice: saw stack with a filter swell."""
    n = int((beats * spb + r) * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for det in (-0.004, 0.0, 0.005):
        p = 2 * np.pi * freq * (1 + det) * t
        for h in range(1, 14):
            y += np.sin(p * h) / h
    y /= 3
    env = adsr(n, a, 0.18, 0.80, r)
    # Cutoff opens with the envelope — that's what makes brass sound brassy.
    y = LP(y, 900, 1) * (1 - env) + LP(y, 3800, 1) * env
    return y * env * amp * 0.5

def kick(amp=0.62):
    n = int(0.30 * SR); t = np.arange(n) / SR
    f = 118 * np.exp(-t * 26) + 44           # pitch drop
    y = np.sin(2 * np.pi * np.cumsum(f) / SR)
    y *= np.exp(-t * 9.5)
    y += rng.normal(0, 1, n) * np.exp(-t * 200) * 0.25   # beater click
    return np.tanh(y * 1.5) * amp

def snare(amp=0.42):
    n = int(0.22 * SR); t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * 186 * t) + np.sin(2 * np.pi * 278 * t)) * 0.5
    noise = HP(rng.normal(0, 1, n), 1500)
    y = (tone * 0.35 + noise * 0.75) * np.exp(-t * 19)
    return y * amp

def clap(amp=0.34):
    """Stacked short bursts — the stomp-clap signature."""
    n = int(0.30 * SR); y = np.zeros(n)
    for off, lvl in [(0, .7), (0.011, .9), (0.023, 1.0)]:
        i = int(off * SR); m = n - i
        t = np.arange(m) / SR
        y[i:] += HP(rng.normal(0, 1, m), 1100) * np.exp(-t * 62) * lvl
    t = np.arange(n) / SR
    y += HP(rng.normal(0, 1, n), 900) * np.exp(-t * 13) * 0.30  # room tail
    return y * amp

def hat(open_=False, amp=0.17):
    n = int((0.18 if open_ else 0.055) * SR); t = np.arange(n) / SR
    return HP(rng.normal(0, 1, n), 7000) * np.exp(-t * (11 if open_ else 48)) * amp

class Track:
    def __init__(self, bars, bpm, bpbar=4):
        self.spb = 60.0 / bpm
        self.n = int(round(bars * bpbar * self.spb * SR))
        self.buf = np.zeros((self.n + SR * 4, 2))
    def add(self, sig, at, pan=0.0):
        i = int(round(at * self.spb * SR))
        l = np.clip(1 - max(0, pan), 0, 1) ** .5
        r = np.clip(1 + min(0, pan), 0, 1) ** .5
        e = min(i + len(sig), len(self.buf)); s = sig[:e - i]
        self.buf[i:e, 0] += s * l; self.buf[i:e, 1] += s * r
    def finish(self):
        head, tail = self.buf[:self.n].copy(), self.buf[self.n:]
        head[:len(tail)] += tail
        return head

def render(name, T, peak=0.74):
    y = np.tanh(T.finish() * 1.15) / 1.15
    m = np.max(np.abs(y))
    if m: y = y / m * peak
    g = int(0.015 * SR)
    f = (1 - np.cos(np.linspace(0, np.pi, g))) / 2
    y[:g] *= f[:, None]; y[-g:] *= f[::-1][:, None]
    raw = os.path.join(OUT, name + ".raw")
    (y * 32767).astype("<i2").tofile(raw)
    mp3 = os.path.join(OUT, name + ".mp3")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le",
                    "-ar", str(SR), "-ac", "2", "-i", raw, "-b:a", "160k",
                    mp3], check=True)
    os.remove(raw)
    print(f"{name}.mp3  {os.path.getsize(mp3)/1024:.0f} KB  {len(y)/SR:.1f}s")

# ------------------------------------------------------------ D: BARN ORGAN
# The between-whistles rink organ. Bright F major, bouncy two-feel, with a
# fanfare-style call at the top of each 4-bar phrase. Original melody.
def barn():
    bpm, bars = 118, 8
    T = Track(bars, bpm); spb = T.spb
    # F - Bb - C - F  |  F - Dm - Bb/C - F
    prog = [(41, [53, 57, 60]), (46, [53, 58, 62]),
            (48, [52, 55, 60]), (41, [53, 57, 60]),
            (41, [53, 57, 60]), (38, [53, 57, 62]),
            (48, [53, 58, 62]), (41, [53, 57, 60])]
    call = [65, 65, 67, 69, 69, 67, 65, 62]      # original fanfare figure
    for bar in range(bars):
        root, chord = prog[bar]; b0 = bar * 4
        # Walking two-feel bass: root on 1, fifth on 3.
        T.add(organ(midi(root - 12), 1.7, spb, 0.34, r=0.12), b0, 0)
        T.add(organ(midi(root - 5), 1.7, spb, 0.28, r=0.12), b0 + 2, 0)
        # Comped chords on the offbeats — the bouncy rink feel.
        for i in (1, 3, 5, 7):
            for j, n in enumerate(chord):
                T.add(organ(midi(n), 0.42, spb, 0.115, a=0.008, r=0.08),
                      b0 + i * 0.5, pan=-0.3 + j * 0.3)
        # Fanfare call across bars 0-1 and 4-5 of the phrase.
        if bar % 4 in (0, 1):
            for i in range(4):
                n = call[(bar % 4) * 4 + i]
                T.add(organ(midi(n + 12), 0.85, spb, 0.17, a=0.01, r=0.14),
                      b0 + i, pan=0.15)
        # Kit: simple, loud on 2 and 4 like a crowd clap.
        for i in range(4):
            T.add(kick(0.5), b0 + i)
        T.add(clap(0.30), b0 + 1); T.add(clap(0.30), b0 + 3)
        for i in range(8):
            T.add(hat(i % 4 == 3, 0.13), b0 + i * 0.5, pan=0.25)
    render("bgm_d_barnorgan", T)

# ------------------------------------------------------------- E: STOMP
# Arena stomp-clap: boom-boom-clap, power chords, built for a crowd to
# shout over. Em - C - G - D, the anthem progression.
def stomp():
    bpm, bars = 100, 8
    T = Track(bars, bpm); spb = T.spb
    prog = [40, 36, 43, 38, 40, 36, 43, 38]
    hook = [[64, 67, 71, 67], [60, 64, 67, 64],
            [59, 62, 67, 62], [57, 62, 66, 62]]
    for bar in range(bars):
        root = prog[bar]; b0 = bar * 4
        # STOMP STOMP CLAP — kick on 1 and the & of 1, clap on 2 and 4.
        T.add(kick(0.66), b0); T.add(kick(0.60), b0 + 0.5)
        T.add(clap(0.40), b0 + 1)
        T.add(kick(0.62), b0 + 2); T.add(kick(0.56), b0 + 2.5)
        T.add(clap(0.40), b0 + 3)
        T.add(snare(0.22), b0 + 3.5) if bar % 4 == 3 else None
        # Power chords: whole-bar sustain, plus a push into the next bar.
        T.add(power(midi(root), 3.3, spb, 0.24), b0, pan=-0.2)
        T.add(power(midi(root), 3.3, spb, 0.24, drive=3.0), b0, pan=0.2)
        T.add(power(midi(root), 0.45, spb, 0.18), b0 + 3.5)
        # Hook, an octave up, only on the back half so it has some shape.
        if bar % 2 == 1:
            for i, n in enumerate(hook[bar % 4]):
                T.add(brass(midi(n), 0.9, spb, 0.15, a=0.03, r=0.2),
                      b0 + i, pan=0.2 if i % 2 else -0.2)
        for i in range(8):
            T.add(hat(False, 0.11), b0 + i * 0.5, pan=-0.3)
    render("bgm_e_stomp", T)

# ------------------------------------------------------------ F: FACEOFF
# Driving hard rock with a goal-horn swell at the top of each phrase.
# Fastest and most aggressive of the six — closest to a whistle-to-whistle
# broadcast bed. Am - G - F - G.
def faceoff():
    bpm, bars = 138, 8
    T = Track(bars, bpm); spb = T.spb
    prog = [45, 43, 41, 43, 45, 43, 41, 38]
    riff = [57, 57, 60, 57, 64, 62, 60, 57]
    for bar in range(bars):
        root = prog[bar]; b0 = bar * 4
        # Four on the floor with a driving eighth-note riff over it.
        for i in range(4):
            T.add(kick(0.60), b0 + i)
        T.add(snare(0.40), b0 + 1); T.add(snare(0.40), b0 + 3)
        for i in range(8):
            T.add(hat(i == 7, 0.12), b0 + i * 0.5, pan=0.3)
        # Palm-muted-feel eighths on the root.
        for i in range(8):
            T.add(power(midi(root - 12), 0.24, spb, 0.20, drive=4.2, r=0.06),
                  b0 + i * 0.5, pan=-0.25)
        # Riff, doubled an octave up on alternating bars for lift.
        for i, n in enumerate(riff):
            oct_ = 12 if bar % 2 else 0
            T.add(power(midi(n + oct_), 0.4, spb, 0.135, drive=2.6),
                  b0 + i * 0.5, pan=0.25)
        # Goal-horn swell opening each 4-bar phrase.
        if bar % 4 == 0:
            for n, p in [(57, -0.3), (64, 0.0), (69, 0.3)]:
                T.add(brass(midi(n), 3.6, spb, 0.16, a=0.25, r=0.5), b0, pan=p)
    render("bgm_f_faceoff", T)

if __name__ == "__main__":
    barn(); stomp(); faceoff()
