#!/usr/bin/env python3
"""결계 수호대 BGM · 효과음 생성기 (외부 음원 없이 직접 작곡·합성).

실행:  python3 tools/make_audio.py        (numpy 필요)
결과:  audio/bgm/*.wav  (끊김 없이 반복되는 배경음악)
       audio/sfx/*.wav  (효과음, 짧은 음악)

곡을 바꾸고 싶으면 아래 SONGS 의 코드 진행/멜로디를 고치고 다시 실행하면 된다.
실제 작곡가 음원으로 바꿀 때는 같은 파일 이름의 .ogg/.wav 를 audio/ 에 넣으면 게임이 그걸 쓴다.
"""
import math
import os
import wave

import numpy as np

SR = 32000
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------------------
# 기본 도구
# ---------------------------------------------------------------------------
def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def n(name):
    """'A4' → 69"""
    if name[1:2] in ("#", "b"):
        key, octv = name[:2], int(name[2:])
    else:
        key, octv = name[:1], int(name[1:])
    return 12 * (octv + 1) + NOTE[key]


def env_adsr(length, a=0.01, d=0.1, s=0.7, r=0.1):
    total = length
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, total - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(1, a_n), endpoint=False),
        np.linspace(1, s, max(1, d_n), endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, max(1, r_n)),
    ])
    return e[:total] if len(e) >= total else np.pad(e, (0, total - len(e)))


def osc(kind, freq, length, duty=0.5, vib=0.0, vib_rate=5.5, detune=0.0):
    t = np.arange(length) / SR
    f = freq * (1.0 + detune)
    phase_inc = f * (1.0 + vib * np.sin(2 * np.pi * vib_rate * t)) / SR
    ph = np.cumsum(phase_inc) % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "tri":
        return 4.0 * np.abs(ph - 0.5) - 1.0
    if kind == "square":
        return np.where(ph < duty, 1.0, -1.0) * 0.6
    if kind == "saw":
        return (2.0 * ph - 1.0) * 0.6
    raise ValueError(kind)


def lowpass(x, cutoff):
    """짧은 FIR 저역 통과 (거친 파형을 부드럽게)"""
    taps = 63
    fc = cutoff / SR
    k = np.arange(taps) - (taps - 1) / 2
    h = np.sinc(2 * fc * k) * np.hamming(taps)
    h /= h.sum()
    return np.convolve(x, h, mode="same")


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(length):
    return rng.uniform(-1, 1, length)


def reverb(x, seconds=1.2, mix=0.22, damp=5000):
    ir_n = int(seconds * SR)
    t = np.arange(ir_n) / SR
    ir = rng.normal(0, 1, ir_n) * np.exp(-t * 4.5 / seconds)
    ir = lowpass(ir, damp)
    ir[0] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    size = 1 << int(math.ceil(math.log2(len(x) + ir_n)))
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return x * (1 - mix) + wet * mix * 0.9


def place(buf, start, sig):
    s = int(start)
    if s >= len(buf):
        return
    e = min(len(buf), s + len(sig))
    buf[s:e] += sig[: e - s]


def normalize(x, peak=0.8):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def soft_clip(x):
    return np.tanh(x * 1.2) / np.tanh(1.2)


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(x, -1, 1)
    pcm = (data * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {os.path.relpath(path, ROOT)}  {len(x) / SR:5.1f}s")


# ---------------------------------------------------------------------------
# 악기
# ---------------------------------------------------------------------------
def inst_lead(freq, dur, vel=1.0, bright=4200):
    ln = int(dur * SR)
    sig = osc("square", freq, ln, duty=0.25, vib=0.004) * 0.55 + osc("saw", freq, ln, detune=0.004) * 0.35
    sig = lowpass(sig, bright)
    return sig * env_adsr(ln, 0.01, 0.12, 0.6, min(0.12, dur * 0.4)) * vel


def inst_bell(freq, dur, vel=1.0):
    ln = int(dur * SR)
    t = np.arange(ln) / SR
    sig = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 6)
    return sig * np.exp(-t * 3.2) * vel * 0.6


def inst_pluck(freq, dur, vel=1.0):
    ln = int(dur * SR)
    t = np.arange(ln) / SR
    sig = osc("tri", freq, ln) * 0.7 + osc("square", freq, ln, duty=0.5) * 0.25
    return lowpass(sig, 3000) * np.exp(-t * 7) * vel


def inst_bass(freq, dur, vel=1.0, grit=0.0):
    ln = int(dur * SR)
    sig = osc("tri", freq, ln) * 0.8 + osc("saw", freq, ln) * (0.25 + grit)
    sig = lowpass(sig, 900 + grit * 1500)
    return sig * env_adsr(ln, 0.005, 0.08, 0.8, 0.04) * vel


def inst_pad(freqs, dur, vel=1.0):
    ln = int(dur * SR)
    sig = np.zeros(ln)
    for f in freqs:
        for dt in (-0.006, 0.0, 0.006):
            sig += osc("saw", f, ln, detune=dt) * 0.18
    sig = lowpass(sig, 1800)
    return sig * env_adsr(ln, min(0.4, dur * 0.3), 0.3, 0.8, min(0.5, dur * 0.3)) * vel


def inst_brass(freqs, dur, vel=1.0):
    ln = int(dur * SR)
    sig = np.zeros(ln)
    for f in freqs:
        sig += osc("saw", f, ln, vib=0.003) * 0.35 + osc("square", f, ln, duty=0.4) * 0.15
    sig = lowpass(sig, 2600)
    return sig * env_adsr(ln, 0.04, 0.15, 0.75, 0.15) * vel


def drum_kick(vel=1.0):
    ln = int(0.32 * SR)
    t = np.arange(ln) / SR
    f = 50 + 110 * np.exp(-t * 28)
    ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph) * np.exp(-t * 9) * vel


def drum_snare(vel=1.0):
    ln = int(0.22 * SR)
    t = np.arange(ln) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.5
    nz = highpass(noise(ln), 1500) * np.exp(-t * 16)
    return (body + nz * 0.8) * vel


def drum_hat(vel=1.0, open_=False):
    ln = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(ln) / SR
    return highpass(noise(ln), 6000) * np.exp(-t * (14 if open_ else 70)) * 0.45 * vel


def drum_tom(freq=110, vel=1.0):
    ln = int(0.35 * SR)
    t = np.arange(ln) / SR
    f = freq * (1 + 0.6 * np.exp(-t * 20))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * vel


def cymbal(vel=1.0):
    ln = int(1.4 * SR)
    t = np.arange(ln) / SR
    return highpass(noise(ln), 5000) * np.exp(-t * 2.6) * 0.35 * vel


# ---------------------------------------------------------------------------
# 곡 (코드 진행 + 멜로디). 멜로디: "음이름:박자" 공백 구분, R = 쉼표
# ---------------------------------------------------------------------------
CHORDS = {
    "Am": ["A3", "C4", "E4"], "F": ["F3", "A3", "C4"], "C": ["C4", "E4", "G4"], "G": ["G3", "B3", "D4"],
    "E": ["E3", "G#3", "B3"], "Dm": ["D3", "F3", "A3"], "Bb": ["Bb2", "D3", "F3"], "A": ["A2", "C#3", "E3"],
    "Gm": ["G2", "Bb2", "D3"], "Em": ["E3", "G3", "B3"], "D": ["D3", "F#3", "A3"], "B": ["B2", "D#3", "F#3"],
    "Fmaj": ["F3", "A3", "C4"], "Cm": ["C3", "Eb3", "G3"], "Ab": ["Ab2", "C3", "Eb3"], "Eb": ["Eb3", "G3", "Bb3"],
}


def parse_mel(s):
    out = []
    for tok in s.split():
        name, beats = tok.split(":")
        out.append((None if name == "R" else n(name), float(beats)))
    return out


SONGS = {
    "lobby": {
        "bpm": 96, "bars": ["Am", "F", "C", "G", "Am", "F", "G", "E", "F", "G", "Em", "Am", "F", "G", "C", "E"],
        "mel": ("A4:1.5 C5:0.5 E5:1 D5:1  C5:1.5 A4:0.5 F4:2  G4:1.5 C5:0.5 E5:1 G5:1  F5:1 E5:1 D5:2 "
                "C5:1.5 E5:0.5 A5:1 G5:1  F5:1 E5:1 C5:2  D5:1 E5:1 F5:1 D5:1  B4:2 E5:2 "
                "C5:1 D5:1 E5:1 F5:1  G5:1.5 F5:0.5 E5:1 D5:1  E5:1 B4:1 G4:1 B4:1  C5:2 A4:2 "
                "A4:1 C5:1 F5:1 E5:1  D5:1 B4:1 G4:2  C5:1 E5:1 G5:1 C6:1  B5:2 G#5:2"),
        "style": "hero", "lead": "lead",
    },
    "battle": {
        "bpm": 132, "bars": ["Dm", "Bb", "C", "A", "Dm", "Bb", "Gm", "A", "Dm", "Bb", "C", "A", "Gm", "Bb", "C", "A"],
        "mel": ("D5:0.75 D5:0.25 F5:0.5 A5:0.5 G5:1 F5:1  D5:0.5 F5:0.5 Bb5:1 A5:1 F5:1  G5:0.75 E5:0.25 C5:1 E5:1 G5:1  A5:2 C#5:1 E5:1 "
                "F5:0.5 E5:0.5 D5:1 A4:1 D5:1  F5:0.5 G5:0.5 A5:1 Bb5:1 A5:1  G5:1 D5:1 G5:1 Bb5:1  A5:3 R:1 "
                "D6:0.5 C6:0.5 A5:1 F5:1 D5:1  Bb5:0.5 A5:0.5 F5:1 D5:1 Bb4:1  C5:0.5 E5:0.5 G5:1 C6:1 G5:1  A5:1 E5:1 C#5:1 A4:1 "
                "Bb4:1 D5:1 G5:1 D5:1  Bb4:1 F5:1 Bb5:1 F5:1  C5:1 E5:1 G5:1 C6:1  A5:2 A5:1 R:1"),
        "style": "battle", "lead": "lead",
    },
    "boss": {
        "bpm": 150, "bars": ["Em", "Em", "C", "B", "Em", "Em", "D", "B", "Am", "Em", "C", "B", "Am", "C", "D", "B"],
        "mel": ("E5:1 F5:1 G5:1 F5:1  E5:1 B4:1 E5:2  C5:1 E5:1 G5:1 E5:1  D#5:3 B4:1 "
                "E5:0.5 G5:0.5 B5:1 A5:1 G5:1  F#5:1 E5:1 B4:2  D5:1 F#5:1 A5:1 D6:1  B5:3 R:1 "
                "A5:1 C6:1 B5:1 A5:1  G5:1 E5:1 B4:2  C5:1 E5:1 G5:1 C6:1  B5:2 F#5:2 "
                "A5:1 G5:1 F#5:1 E5:1  G5:1 A5:1 C6:2  D6:1 C6:1 B5:1 A5:1  B5:4"),
        "style": "boss", "lead": "brass",
    },
    "map": {
        "bpm": 84, "bars": ["C", "G", "Am", "F", "C", "G", "F", "G", "Am", "Em", "F", "C", "F", "G", "C", "G"],
        "mel": ("E5:2 D5:1 C5:1  D5:3 G4:1  C5:2 E5:1 A5:1  A5:2 F5:2 "
                "G5:2 E5:1 C5:1  D5:2 B4:2  A4:1 C5:1 F5:1 A5:1  G5:4 "
                "A5:2 G5:1 E5:1  G5:2 B4:2  C5:1 F5:1 A5:1 C6:1  G5:4 "
                "A5:2 F5:1 C5:1  B4:2 D5:2  C5:4  R:2 D5:2"),
        "style": "calm", "lead": "bell",
    },
}


def render_song(name, spec, cycles=2):
    bpm = spec["bpm"]
    beat = 60.0 / bpm
    bars = spec["bars"]
    bar_len = 4 * beat
    loop_len = int(round(len(bars) * bar_len * SR))
    total = loop_len * cycles
    mix = {k: np.zeros(total) for k in ("pad", "bass", "lead", "drum", "arp")}
    mel = parse_mel(spec["mel"])
    style = spec["style"]
    for c in range(cycles):
        base = c * loop_len
        for bi, ch in enumerate(bars):
            t0 = base + bi * bar_len * SR
            notes = [n(x) for x in CHORDS[ch]]
            root = notes[0] - 12
            # 패드
            vel_pad = {"hero": 0.55, "battle": 0.35, "boss": 0.4, "calm": 0.6}[style]
            place(mix["pad"], t0, inst_pad([midi(x) for x in notes], bar_len, vel_pad))
            # 베이스
            if style == "calm":
                place(mix["bass"], t0, inst_bass(midi(root), bar_len * 0.5, 0.7))
                place(mix["bass"], t0 + 2 * beat * SR, inst_bass(midi(root + 7), bar_len * 0.5, 0.6))
            elif style == "hero":
                for k, off in enumerate([0, 0, 7, 12]):
                    place(mix["bass"], t0 + k * beat * SR, inst_bass(midi(root + off), beat * 0.9, 0.8))
            elif style == "battle":
                for k in range(8):
                    off = 12 if k % 2 else 0
                    place(mix["bass"], t0 + k * 0.5 * beat * SR, inst_bass(midi(root + off), beat * 0.45, 0.85, grit=0.2))
            else:
                for k in range(16):
                    off = [0, 0, 12, 0, 1, 0, 12, 0, 0, 0, 12, 0, 3, 0, 12, 1][k]
                    place(mix["bass"], t0 + k * 0.25 * beat * SR, inst_bass(midi(root + off), beat * 0.24, 0.9, grit=0.45))
            # 아르페지오
            if style in ("hero", "calm", "battle"):
                steps = 8 if style != "battle" else 16
                pat = notes + [notes[1] + 12, notes[2] + 12] if style == "calm" else notes + [notes[0] + 12]
                for k in range(steps):
                    dur = bar_len / steps
                    nn = pat[k % len(pat)] + 12
                    v = 0.35 if style != "battle" else 0.22
                    place(mix["arp"], t0 + k * dur * SR, inst_pluck(midi(nn), dur * 1.6, v))
            # 드럼
            if style == "hero":
                for k in range(4):
                    place(mix["drum"], t0 + k * beat * SR, drum_kick(0.8 if k in (0, 2) else 0.0))
                    if k in (1, 3):
                        place(mix["drum"], t0 + k * beat * SR, drum_snare(0.45))
                    place(mix["drum"], t0 + (k + 0.5) * beat * SR, drum_hat(0.5))
                if bi % 4 == 0:
                    place(mix["drum"], t0, cymbal(0.5))
            elif style == "battle":
                for k in range(8):
                    tt = t0 + k * 0.5 * beat * SR
                    if k in (0, 3, 4):
                        place(mix["drum"], tt, drum_kick(1.0))
                    if k in (2, 6):
                        place(mix["drum"], tt, drum_snare(0.8))
                    place(mix["drum"], tt, drum_hat(0.6 if k % 2 else 0.35))
                if bi % 4 == 0:
                    place(mix["drum"], t0, cymbal(0.7))
                if bi % 4 == 3:
                    for k in range(4):
                        place(mix["drum"], t0 + (3 + k * 0.25) * beat * SR, drum_snare(0.4 + 0.15 * k))
            elif style == "boss":
                for k in range(16):
                    tt = t0 + k * 0.25 * beat * SR
                    if k in (0, 3, 6, 8, 11, 14):
                        place(mix["drum"], tt, drum_kick(1.0))
                    if k in (4, 12):
                        place(mix["drum"], tt, drum_snare(0.9))
                    if k % 2 == 0:
                        place(mix["drum"], tt, drum_hat(0.5))
                if bi % 2 == 1:
                    for k, f in enumerate([160, 130, 100, 80]):
                        place(mix["drum"], t0 + (3 + k * 0.25) * beat * SR, drum_tom(f, 0.7))
                if bi % 4 == 0:
                    place(mix["drum"], t0, cymbal(0.8))
        # 멜로디
        tpos = 0.0
        for note, beats in mel:
            if note is not None:
                s = base + tpos * beat * SR
                dur = beats * beat
                lead = spec["lead"]
                if lead == "bell":
                    place(mix["lead"], s, inst_bell(midi(note), dur * 1.8, 0.9))
                elif lead == "brass":
                    place(mix["lead"], s, inst_brass([midi(note), midi(note - 12)], dur * 0.95, 0.75))
                else:
                    place(mix["lead"], s, inst_lead(midi(note), dur * 0.95, 0.7))
            tpos += beats
    levels = {
        "hero": {"pad": 0.5, "bass": 0.55, "lead": 0.55, "drum": 0.5, "arp": 0.35},
        "battle": {"pad": 0.35, "bass": 0.6, "lead": 0.55, "drum": 0.65, "arp": 0.3},
        "boss": {"pad": 0.35, "bass": 0.7, "lead": 0.6, "drum": 0.7, "arp": 0.0},
        "calm": {"pad": 0.6, "bass": 0.45, "lead": 0.6, "drum": 0.0, "arp": 0.4},
    }[style]
    out = sum(mix[k] * levels[k] for k in mix)
    out = reverb(out, 1.6 if style == "calm" else 1.1, 0.28 if style in ("calm", "hero") else 0.18)
    out = soft_clip(normalize(out, 0.9))
    # 두 바퀴를 만든 뒤 두 번째 바퀴만 사용 → 잔향이 앞으로 이어져 끊김 없이 반복
    return normalize(out[loop_len: 2 * loop_len], 0.72)


# ---------------------------------------------------------------------------
# 효과음
# ---------------------------------------------------------------------------
def seq(notes, step, instr, vel=1.0, tail=0.4):
    total = int((len(notes) * step + tail) * SR)
    buf = np.zeros(total)
    for i, nn in enumerate(notes):
        if nn is None:
            continue
        place(buf, i * step * SR, instr(midi(nn), step + tail, vel))
    return buf


def sweep(f0, f1, dur, kind="sine", curve=2.0):
    ln = int(dur * SR)
    t = np.linspace(0, 1, ln)
    f = f0 + (f1 - f0) * t ** curve
    ph = np.cumsum(f) / SR
    base = np.sin(2 * np.pi * ph) if kind == "sine" else (np.where((ph % 1) < 0.5, 1.0, -1.0) * 0.6)
    return base


def make_sfx():
    out = {}
    L = lambda s: n(s)
    # 버튼 클릭: 짧고 둥근 톡
    ln = int(0.05 * SR); t = np.arange(ln) / SR
    out["click"] = np.sin(2 * np.pi * 1500 * t) * np.exp(-t * 90) * 0.7
    # 소환: 마법 휘익 + 반짝
    s = sweep(300, 1400, 0.28, curve=1.5) * np.linspace(1, 0, int(0.28 * SR)) * 0.5
    sp = seq([L("E6"), L("B6")], 0.06, inst_bell, 0.6, 0.25)
    b = np.zeros(int(0.45 * SR)); place(b, 0, s); place(b, 0.12 * SR, sp); out["summon"] = reverb(b, 0.6, 0.25)
    # 합성: 위로 올라가는 3음 + 반짝
    out["merge"] = reverb(seq([L("C5"), L("E5"), L("G5"), L("C6")], 0.06, inst_pluck, 0.9, 0.3), 0.6, 0.25)
    # 희귀·영웅 획득: 벨 아르페지오
    out["rare"] = reverb(seq([L("C5"), L("E5"), L("G5"), L("C6"), L("E6")], 0.07, inst_bell, 0.9, 0.6), 1.0, 0.3)
    # 전설·신화: 팡파레
    fan = np.zeros(int(1.6 * SR))
    place(fan, 0, inst_brass([midi(L("C4")), midi(L("G4")), midi(L("C5"))], 0.25, 0.8))
    place(fan, 0.25 * SR, inst_brass([midi(L("E4")), midi(L("B4")), midi(L("E5"))], 0.25, 0.8))
    place(fan, 0.5 * SR, inst_brass([midi(L("G4")), midi(L("D5")), midi(L("G5"))], 0.9, 0.9))
    place(fan, 0.5 * SR, cymbal(0.6))
    place(fan, 0.5 * SR, seq([L("G6"), L("C7"), L("E7")], 0.05, inst_bell, 0.5, 0.6))
    out["legend"] = reverb(fan, 1.2, 0.3)
    # 동전
    out["coin"] = seq([L("B6"), L("E7")], 0.05, inst_bell, 0.7, 0.2)
    # 실패·꽝
    out["fail"] = seq([L("E4"), L("C4"), L("Ab3")], 0.11, lambda f, d, v: inst_lead(f, d, v, 1600), 0.8, 0.15)
    # 라운드 시작: 북 + 금관 짧게
    r = np.zeros(int(0.9 * SR)); place(r, 0, drum_tom(120, 0.9)); place(r, 0.1 * SR, drum_tom(90, 0.9))
    place(r, 0.2 * SR, inst_brass([midi(L("A3")), midi(L("E4")), midi(L("A4"))], 0.5, 0.7)); out["round"] = reverb(r, 0.8, 0.2)
    # 보스 등장: 낮은 포효 + 경고 금관
    ln = int(1.4 * SR); t = np.arange(ln) / SR
    growl = lowpass(noise(ln), 400) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t)) * np.exp(-t * 1.8)
    bb = np.zeros(ln); place(bb, 0, growl * 1.2); place(bb, 0, drum_kick(1.0))
    place(bb, 0.25 * SR, inst_brass([midi(L("E3")), midi(L("F3")), midi(L("B3"))], 0.9, 0.8))
    out["boss"] = reverb(bb, 1.0, 0.25)
    # 경보 (한도 임박, 위기)
    al = np.zeros(int(0.7 * SR))
    for k in range(2):
        place(al, k * 0.33 * SR, sweep(700, 1000, 0.3, "square", 1.0) * 0.4 * np.linspace(1, 0.6, int(0.3 * SR)))
    out["alarm"] = al
    # 심장 박동
    hb = np.zeros(int(0.6 * SR)); place(hb, 0, drum_kick(0.9) * 0.9); place(hb, 0.18 * SR, drum_kick(0.6) * 0.7)
    out["heart"] = lowpass(hb, 300)
    # 째깍 (카운트다운)
    ln = int(0.06 * SR); t = np.arange(ln) / SR
    out["tick"] = (np.sin(2 * np.pi * 2000 * t) * 0.5 + highpass(noise(ln), 4000) * 0.3) * np.exp(-t * 80)
    out["tick_boss"] = seq([L("E6"), L("B5")], 0.05, lambda f, d, v: inst_lead(f, d, v, 5000), 0.7, 0.05)
    # 피버
    fv = seq([L("C5"), L("E5"), L("G5"), L("C6"), L("E6"), L("G6")], 0.045, lambda f, d, v: inst_lead(f, d, v, 6000), 0.8, 0.25)
    out["fever"] = reverb(fv, 0.7, 0.25)
    # 타격음 (공격이 맞을 때, 아주 짧게)
    ln = int(0.07 * SR); t = np.arange(ln) / SR
    out["hit"] = (lowpass(noise(ln), 2500) * 0.6 + np.sin(2 * np.pi * 160 * t) * 0.6) * np.exp(-t * 55)
    # 폭발 (메테오, 화염 폭발)
    ln = int(0.9 * SR); t = np.arange(ln) / SR
    ex = lowpass(noise(ln), 1200) * np.exp(-t * 4.5) + np.sin(2 * np.pi * np.cumsum(60 + 80 * np.exp(-t * 10)) / SR) * np.exp(-t * 6)
    out["boom"] = reverb(ex * 0.8, 0.9, 0.2)
    # 번개
    ln = int(0.5 * SR); t = np.arange(ln) / SR
    zap = highpass(noise(ln), 2500) * (np.sin(2 * np.pi * 60 * t) > 0) * np.exp(-t * 8)
    out["zap"] = zap * 0.7
    # 얼음
    out["ice"] = reverb(seq([L("A6"), L("E7"), L("A7")], 0.035, inst_bell, 0.6, 0.3), 0.8, 0.35)
    # 보상 받기 (반짝 + 동전)
    rw = np.zeros(int(0.9 * SR)); place(rw, 0, seq([L("G5"), L("C6"), L("E6"), L("G6")], 0.06, inst_bell, 0.8, 0.5))
    place(rw, 0.25 * SR, out["coin"] * 0.8); out["reward"] = reverb(rw, 0.8, 0.25)
    # 승리 (짧은 음악)
    win = np.zeros(int(3.2 * SR))
    for i, (ch, t0, d) in enumerate([("C", 0, 0.3), ("F", 0.3, 0.3), ("G", 0.6, 0.3), ("C", 0.9, 1.6)]):
        notes = [n(x) + 12 for x in CHORDS[ch]]
        place(win, t0 * SR, inst_brass([midi(x) for x in notes], d, 0.8))
        place(win, t0 * SR, drum_tom(140 - i * 15, 0.7))
    place(win, 0.9 * SR, cymbal(0.8))
    place(win, 0.9 * SR, seq([L("C6"), L("E6"), L("G6"), L("C7")], 0.08, inst_bell, 0.6, 1.0))
    out["win"] = reverb(win, 1.4, 0.3)
    # 패배 (짧은 음악)
    lose = np.zeros(int(3.0 * SR))
    for i, (nn, t0) in enumerate([("E4", 0), ("D4", 0.45), ("C4", 0.9), ("B3", 1.35)]):
        place(lose, t0 * SR, inst_lead(midi(n(nn)), 0.6 if i < 3 else 1.4, 0.7, 1800))
    place(lose, 0, inst_pad([midi(n(x)) for x in CHORDS["Am"]], 2.8, 0.5))
    out["lose"] = reverb(lose, 1.6, 0.35)
    return out


def main():
    print("BGM:")
    for name, spec in SONGS.items():
        write(os.path.join(ROOT, "bgm", name + ".wav"), render_song(name, spec))
    print("SFX:")
    for name, x in make_sfx().items():
        write(os.path.join(ROOT, "sfx", name + ".wav"), normalize(x, 0.85 if name not in ("click", "tick", "hit") else 0.6))


if __name__ == "__main__":
    main()
