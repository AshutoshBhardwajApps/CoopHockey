"""
CoopHockey background music generator.

Produces CoopHockey/COOPbackground.mp3 — "Faceoff": driving hard rock with
a goal-horn swell, 138 BPM, Am-G-F-G.

Original composition. It borrows the conventions of arena hockey music
(four-on-the-floor kit, palm-muted eighths, goal-horn brass) rather than
any actual track, so there is nothing to license.

24 bars in three 8-bar phrases with genuine shape — full, breakdown-and-
build, full — so it runs ~42s before repeating instead of ~14s. Note tails
that overrun the end are folded back onto the start, so it loops seamlessly
under AVAudioPlayer's numberOfLoops = -1.

    python3 tools/bgm_generator.py            # writes the mp3 in place
    python3 tools/bgm_generator.py --preview  # writes to /tmp instead
"""
import numpy as np, subprocess, os, sys

SR = 44100
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(7)          # fixed: regenerating is reproducible

BPM, BARS = 138, 24

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
except ImportError:
    def LP(x, c, res=1):
        X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
        return np.fft.irfft(X / (1 + (f / c) ** (2 * res)) ** 0.5, len(x))

def HP(x, c):
    return x - LP(x, c, 1)

# ------------------------------------------------------------- instruments

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
    """Goal-horn voice: saw stack whose cutoff opens with the envelope."""
    n = int((beats * spb + r) * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for det in (-0.004, 0.0, 0.005):
        p = 2 * np.pi * freq * (1 + det) * t
        for h in range(1, 14):
            y += np.sin(p * h) / h
    y /= 3
    env = adsr(n, a, 0.18, 0.80, r)
    y = LP(y, 900, 1) * (1 - env) + LP(y, 3800, 1) * env
    return y * env * amp * 0.5

def kick(amp=0.62):
    n = int(0.30 * SR); t = np.arange(n) / SR
    f = 118 * np.exp(-t * 26) + 44
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9.5)
    y += rng.normal(0, 1, n) * np.exp(-t * 200) * 0.25
    return np.tanh(y * 1.5) * amp

def snare(amp=0.42):
    n = int(0.22 * SR); t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * 186 * t) + np.sin(2 * np.pi * 278 * t)) * 0.5
    return (tone * 0.35 + HP(rng.normal(0, 1, n), 1500) * 0.75) \
        * np.exp(-t * 19) * amp

def hat(open_=False, amp=0.17):
    n = int((0.18 if open_ else 0.055) * SR); t = np.arange(n) / SR
    return HP(rng.normal(0, 1, n), 7000) \
        * np.exp(-t * (11 if open_ else 48)) * amp

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
        head[:len(tail)] += tail       # decays cross the loop seam
        return head

# ------------------------------------------------------------ arrangement

# Am - G - F - G, with the last bar of each phrase dropping to D for a turn.
PROG = [45, 43, 41, 43, 45, 43, 41, 38]
RIFF_A = [57, 57, 60, 57, 64, 62, 60, 57]   # phrases 1 and 2
RIFF_B = [57, 60, 64, 60, 65, 64, 62, 60]   # phrase 3 — opens it up

def bar_plan(bar):
    """What plays in this bar. Three 8-bar phrases: full, break/build, full."""
    phrase, pos = bar // 8, bar % 8
    if phrase == 1 and pos in (0, 1):
        return dict(kit="none",  riff="none",    horn=False)
    if phrase == 1 and pos in (2, 3):
        return dict(kit="half",  riff="quarter", horn=False)
    if phrase == 1:
        return dict(kit="full",  riff="eighth",  horn=(pos == 4))
    return dict(kit="full", riff="eighth", horn=(pos == 0))

def build():
    T = Track(BARS, BPM); spb = T.spb
    for bar in range(BARS):
        root = PROG[bar % 8]
        b0 = bar * 4
        plan = bar_plan(bar)
        phrase = bar // 8
        riff = RIFF_B if phrase == 2 else RIFF_A

        # --- kit
        if plan["kit"] == "full":
            for i in range(4):
                T.add(kick(0.60), b0 + i)
            T.add(snare(0.40), b0 + 1); T.add(snare(0.40), b0 + 3)
            for i in range(8):
                T.add(hat(i == 7, 0.12), b0 + i * 0.5, pan=0.3)
        elif plan["kit"] == "half":
            T.add(kick(0.58), b0); T.add(kick(0.58), b0 + 2)
            T.add(snare(0.34), b0 + 3)
            for i in range(4):
                T.add(hat(False, 0.10), b0 + i, pan=0.3)
        else:                                   # breakdown: air, open hats
            T.add(hat(True, 0.12), b0, pan=0.3)
            T.add(hat(True, 0.10), b0 + 2, pan=0.3)

        # --- chugging root
        if plan["riff"] == "eighth":
            for i in range(8):
                T.add(power(midi(root - 12), 0.24, spb, 0.20,
                            drive=4.2, r=0.06), b0 + i * 0.5, pan=-0.25)
        elif plan["riff"] == "quarter":
            for i in range(4):
                T.add(power(midi(root - 12), 0.5, spb, 0.18,
                            drive=3.8, r=0.08), b0 + i, pan=-0.25)
        else:
            # Breakdown holds one long chord instead of chugging.
            T.add(power(midi(root - 12), 3.6, spb, 0.17,
                        drive=2.4, r=0.4), b0, pan=-0.2)

        # --- riff
        if plan["riff"] == "eighth":
            for i, n in enumerate(riff):
                oct_ = 12 if (bar % 2 and phrase != 1) else 0
                T.add(power(midi(n + oct_), 0.4, spb, 0.135, drive=2.6),
                      b0 + i * 0.5, pan=0.25)
        elif plan["riff"] == "quarter":
            for i in range(4):
                T.add(power(midi(riff[i * 2] + 12), 0.8, spb, 0.12,
                            drive=2.2), b0 + i, pan=0.25)

        # --- goal horn
        if plan["horn"]:
            for n, p in [(57, -0.3), (64, 0.0), (69, 0.3)]:
                T.add(brass(midi(n), 3.6, spb, 0.16, a=0.25, r=0.5),
                      b0, pan=p)

        # --- fills: end of each phrase, and a bigger one wrapping to the top
        if bar % 8 == 7:
            hits = [3.0, 3.25, 3.5, 3.75] if bar == BARS - 1 else [3.5, 3.75]
            for j, beat in enumerate(hits):
                T.add(snare(0.30 + 0.05 * j), b0 + beat,
                      pan=-0.3 + 0.2 * j)
    return T

def render(path, T, peak=0.74):
    y = np.tanh(T.finish() * 1.15) / 1.15
    m = np.max(np.abs(y))
    if m: y = y / m * peak
    g = int(0.015 * SR)
    f = (1 - np.cos(np.linspace(0, np.pi, g))) / 2
    y[:g] *= f[:, None]; y[-g:] *= f[::-1][:, None]
    raw = path + ".raw"
    (y * 32767).astype("<i2").tofile(raw)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le",
                    "-ar", str(SR), "-ac", "2", "-i", raw,
                    "-b:a", "160k", path], check=True)
    os.remove(raw)
    print(f"{path}\n  {os.path.getsize(path)/1024:.0f} KB  {len(y)/SR:.1f}s  "
          f"{BARS} bars @ {BPM} BPM")

if __name__ == "__main__":
    dest = ("/tmp/COOPbackground_preview.mp3" if "--preview" in sys.argv
            else os.path.join(REPO, "CoopHockey", "COOPbackground.mp3"))
    render(dest, build())
