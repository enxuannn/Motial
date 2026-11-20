"""Pre-renders Steady's spoken lines with a warm neural voice (Kokoro-82M, Apache-2.0, voice af_heart).
Every sentence the app can say from a fixed string becomes vo_<key>.m4a; SoundManager plays the clip when it
exists and falls back to the best on-device voice otherwise. Key = first 12 hex of SHA-1 of the normalised sentence
(lowercase, straight quotes, single spaces, no trailing .!?) — SoundManager.voiceKey computes the same."""
import re, os, sys, hashlib, glob, json, subprocess
SRC = sys.argv[1]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)

def norm(s):
    s = s.replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
    s = re.sub(r'\s+', ' ', s).strip().lower()
    return s.rstrip('.!?').strip()

def key(s): return hashlib.sha1(norm(s).encode()).hexdigest()[:12]

def sentences(text):
    out, cur = [], ''
    for i, ch in enumerate(text):
        cur += ch
        if ch in '.!?' and (i + 1 == len(text) or text[i + 1].isspace()):
            if cur.strip(): out.append(cur.strip())
            cur = ''
    if cur.strip(): out.append(cur.strip())
    return out

lit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
interp = re.compile(r'\\\((?:[^()]|\([^()]*\))*\)')
corpus = set()
files = [f for f in glob.glob(SRC + '/**/*.swift', recursive=True)
         if any(p in f for p in ('/Model/', '/Immersive/', 'AnatomyVolumeView', 'MyScansView'))]
for f in files:
    code = open(f).read()
    for m in lit.finditer(code):
        s = m.group(1)
        s = interp.sub('§', s).replace('\\"', '"').replace("\\'", "'")
        if '§' in s and not re.search(r'[.!?]', s): continue
        for sent in sentences(s):
            sent = sent.lstrip(') ,;:·')
            if '§' in sent or not sent: continue
            if re.search(r'et al|J Orthop|Br J|Am J|JAMA|Med\.|Nucleic|doi|;\d|Ther\.|Sports Med|Lancet|BMJ|Rehabil|\(\d{4}\)|\d{4};', sent): continue
            w = sent.split()
            if not re.search(r'[A-Za-z]', sent): continue
            if re.fullmatch(r'[a-z0-9_.\-/:]+', sent): continue          # identifiers, symbols, file names
            if any(t in sent for t in ('http', '.swift', '%', '_')): continue
            if len(w) < 2 and not sent[0].isupper(): continue
            if len(sent) > 400: continue
            corpus.add(sent)

# composites the app builds at runtime
envs = ['Dawn Lake', 'River Valley', 'Golden Meadow', 'Lantern Night', 'Sunset Court']
for e in envs:
    corpus.update([f'{e}.', f'Welcome to {e}.', f'Back to {e}.'])
corpus.update(["I'm Maya.", "I'm Alex.", 'Hi.', 'Welcome to Sport Lab.', 'Hi there.', 'Welcome to Remer.'])
for n in range(1, 6): corpus.update([f'Set {n} done.'])
corpus.add('Session complete.')
# exercise doses as spoken by the session intro (Dosage.text): "3 × 10", "3 × 20 s", "2 rounds"
for sets in range(1, 6):
    corpus.add(f'{sets} rounds.')
    for r in range(2, 31): corpus.add(f'{sets} × {r}.')
    for h in range(5, 65, 5): corpus.add(f'{sets} × {h} s.')
# exercise and drill titles spoken as their own sentence
lib_all = '\n'.join(open(f).read() for f in glob.glob(SRC + '/**/*.swift', recursive=True))
for t in re.findall(r'title: "([^"]+)"', lib_all): corpus.add(t + '.')
corpus.update(['Nice. Now lift your other foot, and catch on your left leg.', 'Nice. Now lift your other foot, and catch on your right leg.'])

# musclesSpoken for every exercise (mirrors Exercise.musclesSpoken)
lib = open(glob.glob(SRC + '/**/ExerciseLibrary.swift', recursive=True)[0]).read()
mus = dict(re.findall(r'static let (\w+) = MuscleInfo\(name: "([^"]+)"', lib))
for ex, names in re.findall(r'"(\w+)": \[((?:\w+(?:, )?)+)\],', lib):
    ns = [mus[n.strip()] for n in names.split(',') if n.strip() in mus]
    if not ns: continue
    lst = ns[0] if len(ns) == 1 else ', '.join(ns[:-1]) + ' and ' + ns[-1]
    corpus.add(f'This works your {lst}.')
for ex, items in re.findall(r'"(\w+)": \[("[^\]]*")\],', lib):
    first = re.findall(r'"([^"]+)"', items)
    if first: corpus.add(f'It helps with: {first[0].lower()}.')

corpus = sorted(corpus, key=len)
print('sentences:', len(corpus))
json.dump({key(s): s for s in corpus}, open(OUT + '/voice_index.json', 'w'), indent=0, ensure_ascii=False)

if '--render' in sys.argv:
    from kokoro_onnx import Kokoro
    import soundfile as sf
    k = Kokoro('tts/kokoro-v1.0.onnx', 'tts/voices-v1.0.bin')
    for i, s in enumerate(corpus):
        name = f'{OUT}/vo_{key(s)}.m4a'
        if os.path.exists(name): continue
        spoken = s.replace('×', ' by ').replace('NurseFirst', 'Nurse First').replace('6262 6262', '6 2 6 2, 6 2 6 2').replace('995', '9 9 5')
        a, sr = k.create(spoken, voice='af_heart', speed=0.95, lang='en-us')
        sf.write('build/tmp/vo.wav', a, sr)
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', 'build/tmp/vo.wav', '-af', 'afade=t=in:d=0.02,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse',
                        '-ac', '1', '-c:a', 'aac', '-b:a', '64k', name], check=True)
        if i % 50 == 0: print(i, s[:60], flush=True)
    print('done')
