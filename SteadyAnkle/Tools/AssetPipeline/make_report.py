from reportlab.lib.pagesizes import A4
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image, Table, TableStyle, PageBreak, KeepTogether)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import mm
from PIL import Image as PImage
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping
F='/usr/share/fonts/truetype/dejavu/'
pdfmetrics.registerFont(TTFont('DV', F+'DejaVuSans.ttf')); pdfmetrics.registerFont(TTFont('DV-B', F+'DejaVuSans-Bold.ttf'))
pdfmetrics.registerFont(TTFont('DV-I', F+'DejaVuSans-Oblique.ttf')); pdfmetrics.registerFont(TTFont('DV-BI', F+'DejaVuSans-BoldOblique.ttf'))
addMapping('DV',0,0,'DV'); addMapping('DV',1,0,'DV-B'); addMapping('DV',0,1,'DV-I'); addMapping('DV',1,1,'DV-BI')

OUT = '/home/claude/build/out/'
doc = SimpleDocTemplate(OUT + 'Steady_Clinical_Evidence_and_Design_Report.pdf', pagesize=A4,
                        leftMargin=18 * mm, rightMargin=18 * mm, topMargin=16 * mm, bottomMargin=16 * mm,
                        title='Steady - Clinical Evidence & Design Report', author='Spatial Computing & AI platform team')
ss = getSampleStyleSheet()
TEAL = colors.HexColor('#1f8f94'); INK = colors.HexColor('#1b2430'); GREY = colors.HexColor('#5b6573')
H1 = ParagraphStyle('H1', parent=ss['Heading1'], fontName='DV-B', fontSize=17, textColor=TEAL, spaceBefore=10, spaceAfter=6)
H2 = ParagraphStyle('H2', parent=ss['Heading2'], fontName='DV-B', fontSize=12.5, textColor=INK, spaceBefore=8, spaceAfter=4)
B = ParagraphStyle('B', parent=ss['BodyText'], fontName='DV', fontSize=9.6, leading=13.4, textColor=INK)
S = ParagraphStyle('S', parent=B, fontSize=8.2, leading=11, textColor=GREY)
C = ParagraphStyle('C', parent=B, fontSize=8.4, leading=10.8)
BUL = ParagraphStyle('BUL', parent=B, leftIndent=12, bulletIndent=2)

def p(t, st=B): return Paragraph(t, st)
def bullets(items): return [Paragraph(i, BUL, bulletText='•') for i in items]
def img(path, width_mm):
    w, h = PImage.open(path).size
    W = width_mm * mm
    return Image(path, width=W, height=W * h / w)
def table(rows, widths, header=True):
    data = [[Paragraph(str(c), C) for c in r] for r in rows]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if header else 0)
    st = [('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor('#c9d2dc')), ('VALIGN', (0, 0), (-1, -1), 'TOP'),
          ('LEFTPADDING', (0, 0), (-1, -1), 4), ('RIGHTPADDING', (0, 0), (-1, -1), 4)]
    if header: st += [('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#e3f3f3'))]
    t.setStyle(TableStyle(st)); return t

story = []
# ---------- Cover ----------
story += [Spacer(1, 10 * mm), img(OUT + 'icon/preview.png', 34), Spacer(1, 6 * mm),
          p('<font size=26 color="#1f8f94"><b>Steady</b></font>', B), Spacer(1, 5 * mm),
          p('<font size=15>Ankle sprain rehabilitation for Apple Vision Pro</font>', B), Spacer(1, 3 * mm),
          p('Clinical Evidence &amp; Design Report: medium-fidelity prototype', B),
          p('NUS Division of Industrial Design · Spatial Computing &amp; AI Platform (AY26/27 Sem 1) · Population health &amp; well-being', S),
          Spacer(1, 8 * mm), img(OUT + 'report_poses_rt.png', 172),
          p('The life-size photoreal coach (Sketchfab, CC BY) performs the guideline exercises, driven by the app\'s clinical motion library. Top row: standing, ankle pumps, double heel raise, knee-to-wall. Bottom row: one-leg stance, one-leg catch, one-leg mini squat, forward hop.', S),
          PageBreak()]

# ---------- 1. Problem ----------
story += [p('1. Pain points this prototype addresses', H1),
          p('Lateral ankle sprains are among the most common musculoskeletal injuries. The problems clinicians face are well documented, and the design follows from them:', B)]
story += bullets([
    '<b>People don\'t finish home programmes.</b> In the landmark home balance-training RCT, only 23% of athletes fully complied and 35% did not comply at all, yet the programme still cut re-sprains from 33% to 22% (RR 0.63, NNT 9) [3].',
    '<b>Recovery is often incomplete.</b> About 40% of people developed chronic ankle instability within 12 months of a first sprain [6].',
    '<b>No feedback at home.</b> Patients can\'t tell whether they are doing balance work "right", and clinicians see no data between visits.',
    '<b>Unsafe progressions.</b> Without guidance, people either do nothing or jump to hopping and sport too early.',
])
story += [p('<b>Design goal:</b> deliver the guideline-recommended programme (structured exercise with balance training, Grade A [1]) in a form people want to repeat, measure it, and adapt it safely to each person\'s ankle. In line with the brief, technology serves the pain point, not the other way round.', B)]

# ---------- 2. Clinical basis ----------
story += [p('2. Clinical basis: guideline recommendation → app feature', H1),
          table([
              ['Recommendation (grade)', 'Source', 'How Steady implements it'],
              ['Structured exercise incl. ROM, neuromuscular & balance training, in clinic and at home (A)', 'JOSPT CPG 2021 [1]', 'Four-stage programme; every session mixes mobility, strength and balance; home use with a 3D coach'],
              ['Progressive weight bearing with external support (A)', '[1]', 'Stage 1-2 seated → supported standing; support within reach is part of the safety check'],
              ['Balance-focused exercise + bracing after a first sprain (A, secondary prevention)', '[1], [5]', 'Balance work in stages 2-4; brace advice for sport; extra balance volume for recurrent sprains'],
              ['Functional treatment preferred over immobilisation; start exercise early', 'BJSM 2018 [2]', 'Stage 1 starts with protected ROM from day 1'],
              ['8-week, 3×/week unsupervised proprioceptive programme reduces recurrences', 'BMJ 2009 [3]', 'Balance stages recommend 3×/week for at least 8 weeks, delivered as games so people keep going'],
              ['PEACE & LOVE: Protect, Elevate, Avoid NSAIDs, Compress, Educate; Load, Optimism, Vascularisation, Exercise', 'BJSM 2020 [4]', 'Education cards; encouragement scripts ("Optimism"); load progressions'],
              ['Ottawa Ankle Rules for possible fracture', 'JAMA 1993 [7]', 'Onboarding red-flag screen blocks exercise and directs to a clinician'],
              ['Apps/video games to augment home programmes: conflicting evidence (D)', '[1]', 'Games deliver the guideline exercises; they do not replace them. Outcomes are tracked for evaluation'],
              ['Phase III: dual-task balance (ball toss), stepping/agility drills; single-leg hops only in phase IV after 25 single-leg heel raises', 'MGH protocol [11]', 'One-Leg Catch (both-feet warm-up, then one leg) and Stepping Stones in stage 3; two-foot hops before single-leg hops; hops, side hops and River Hops locked to stage 4'],
              ['Return to sport: Pain, Ankle impairment, Athlete perception, Sensorimotor control, Sport performance', 'PAASS, BJSM 2021 [12]', 'Hops need clearance + pain 0-1 + ankle confidence 4/5 or higher (daily check-in); otherwise a stepping version is given'],
              ['Chronic ankle instability: previous sprain + giving way / recurrent sprains', 'IAC 2014 [13]', 'Two onboarding taps identify the instability pathway: extra balance volume, longer programme, brace advice'],
              ['VR rehab improved 30 s single-leg stance vs conventional training (5 RCTs, limited)', 'Lin 2021 [14]', 'Supports VR delivery of balance work; claims kept modest, outcomes tracked'],
          ], [62, 28, 84])]

# ---------- 3. Tailoring ----------
story += [p('3. Tailoring: few questions, safe decisions', H1),
          p('Onboarding takes five short screens (mostly single taps). A 3-tap daily check-in then keeps the plan matched to the ankle. Rules are deterministic and auditable (ClinicalEngine.swift).', B),
          p('3.1 Red flags (exercise blocked until cleared by a clinician)', H2)]
story += bullets(['Ottawa-based: unable to take 4 steps immediately and now; bone tenderness at the posterior edge/tip of either malleolus, base of the 5th metatarsal or navicular.',
                  'Neurovascular signs (numbness, cold/pale/blue foot), deformity, hot swollen calf (DVT), fever or red hot joint.',
                  'Cautions without blocking: suspected high-ankle (syndesmosis) sprain → gentler plan and physio review; age 65+ → support always, hopping disabled; under 18 → supervised use; recurrent sprains or "giving way" → instability pathway.'])
story += [p('3.2 Stages and progression criteria', H2),
          table([
              ['Stage', 'Entry (from onboarding)', 'Main exercises', 'Exit criteria (auto-checked)'],
              ['1 Protect & Move', '< 3 days, rest pain 5+/10, can\'t walk, marked swelling', 'Ankle pumps, alphabet, outer-ankle press (after day 3)', 'Rest pain 3/10 or less'],
              ['2 Load & Restore', 'Limp, or can only stand on one leg with support, or pain 3+/10', 'Knee-to-wall, heel raises, eversion, supported stance, Stepping Stones, Rhythm Steps (slow)', 'Walking normally, 20 s single-leg hold'],
              ['3 Balance & Strength', '~10 s single-leg stand', 'Balance Bloom, One-Leg Catch, head turns, mini squat, single-leg heel raise', '30 s steady hold (steadiness 65+), 25 single-leg heel raises [11], pain 2/10 or less, confidence 3/5+'],
              ['4 Return to Activity', '30 s steady stand, pain 0-1, 2+ weeks', 'Hops, side hops, River Hops only with clearance, pain 0-1 and confidence 4/5+ [11][12]; otherwise Stepping Stones', 'Confident hopping and landing; back to goal'],
          ], [30, 44, 58, 42]),
          Spacer(1, 3 * mm),
          p('3.3 Adapting to the person ("habits and old injuries")', H2)]
story += bullets(['<b>Pain monitoring (traffic light):</b> after every exercise the person rates pain 0-10. 0-3 continue; 4-5 the exercise drops a level next time; 6+ stops the session and never repeats that exercise in the same session.',
                  '<b>Per-exercise learning:</b> two easy, pain-free, steady sessions in a row → level up (dose +reps/+10 s hold). Two pain flags → the exercise is swapped out until symptoms settle.',
                  '<b>Regression:</b> worse swelling with pain 4+, or rest pain 6+, moves the plan back one stage, with a reassuring message.',
                  '<b>History:</b> recurrent sprains or giving way add balance volume and an 8-week, 3×/week recommendation; goals (daily life, running, court sports) decide whether stage 4 and hopping are offered.',
                  '<b>Habits:</b> an exercise the person has skipped 3+ times (more often than done) is moved to the end and marked "Optional today": still offered, never forced, never removed silently.',
                  '<b>Other old injuries (one multi-tap question):</b> knee problems remove single-leg squats; a past fracture or surgery adds a caution and needs clearance for hops; the other ankle sprained adds balance work on both legs; a fall in the past year (World Falls Guidelines [15]) keeps a support within reach, caps levels and switches hopping off.',
                  '<b>Old injuries:</b> a previous sprain plus giving way or re-sprains (IAC criteria [13]) switches on the instability pathway; a suspected high-ankle sprain removes end-range dorsiflexion loading early; age 65+ keeps levels at 2 or below and disables hopping.',
                  '<b>Preferences:</b> 10/15/20-minute sessions and an optional daily reminder support adherence, the main failure point in [3].'])

# ---------- 4. Spatial ----------
story += [PageBreak(), p('4. Why spatial computing (assessment criterion 1)', H1),
          table([
              ['Spatial affordance', 'What it does for the patient', 'Why a phone or tablet can\'t'],
              ['Life-size 3D coach in the room', 'Demonstrates each exercise at true scale, mirror or side view, with an "X-ray" mode showing the ankle bones and a glowing injured-ligament region', 'A video is flat, small and fixed-angle; depth and the knee-over-toe position are hard to judge'],
              ['Explorable CT-based anatomy (volume)', 'Tap bones, muscles and ligaments; "How a sprain happens" animates inversion and colours the ATFL by strain', 'A 2D diagram can\'t show how the talus rotates under the fibula'],
              ['Head-pose tracking (on-device)', 'Steadiness score during one-leg stands, automatic rep counting for heel raises and squats, hop and step detection, fall-like event detection', 'Needs a separately mounted camera and computer vision, without depth'],
              ['Hand tracking', 'Catch baseballs with a tracked glove while balancing on one leg (dual-task balance, MGH phase III [11]); throws come from changing directions', 'No natural reach-and-catch on a touchscreen'],
              ['Floor-anchored games', 'Stepping stones and dance pads placed on the person\'s real floor', 'Screen games can\'t place targets where the feet go'],
              ['Adjustable immersion (60°, 180°, 360°)', 'Calming scenes for motivation. Standing exercises keep the real floor visible; 360° only when seated', 'Not possible'],
              ['Spatial audio', 'Sounds come from the ball, stone or pad, which helps orientation without looking down', 'Stereo only'],
          ], [40, 74, 60]),
          Spacer(1, 4 * mm), img(OUT + 'prev_anat_lateral.png', 82), p('Ankle anatomy volume: BodyParts3D bones, fibularis muscles, Achilles tendon and landmark-anchored ligaments (ATFL, CFL, PTFL, AITFL, deltoid).', S)]

# ---------- 5. Games ----------
story += [p('5. Game design: lessons from successful VR fitness titles', H1),
          p('The games apply design principles from commercially successful titles. No assets or IP from them are used.', B),
          table([
              ['Principle (inspiration)', 'Steady game', 'Exercise delivered'],
              ['Clear targets, rhythmic timing, rich hit feedback (Beat Saber)', 'Rhythm Steps: lean, step or hop (by stage) onto front/left/right pads on the beat; Perfect/Great/Good. Each hit makes the chosen world react: ripples on Dawn Lake, droplets in River Valley, flowers growing in Golden Meadow, shooting stars in Aurora Night, each with its own sound. Bundled tracks or the person\'s own songs (automatic tempo detection)', 'Agility, weight shift; hop variant only in stage 4 with clearance. No backward steps'],
              ['Coach voice, scenic places, music (Supernatural)', 'Voice coach, four original 360° scenes with matching soundscapes', 'All exercises'],
              ['Exercise disguised as adventure with gradual progression (Ring Fit Adventure)', 'River Stones: cross a river on stepping stones (walk version in stages 2-3, single-leg hops in stage 4); "stick the landing" bonus', 'Controlled stepping → hop-and-hold landing control'],
              ['Calm biofeedback', 'Balance Bloom: a lotus opens and fireflies rise as sway falls', 'Single-leg stance (proprioception)'],
              ['Reactive ball toss (clinic drill: physio throws from changing directions)', 'One-Leg Catch, baseball style: a glove follows your tracked hand; first throws on both feet, then one leg; level 1 straight on, level 2 three directions, level 3 five directions and heights', 'Dual-task, reactive single-leg balance (MGH phase III [11])'],
              ['Agility ladder with levels (lateral and quarter-turn hops)', 'River Stones levels: straight, zig-zag, side-step crossing; hop version: two-foot warm-up, forward, zig-zag, quarter-turn hops with arrows', 'Stepping → double-leg → single-leg hops → change of direction (MGH III→IV [11])'],
              ['Balance platform game (weight shift while holding rails)', 'Rhythm Steps weight-shift mode in stage 2: feet planted, lean to the beat holding a support', 'Progressive weight bearing with support (Grade A [1])'],
          ], [52, 78, 44]),
          p('Encouragement follows LOVE\'s "Optimism": positive milestone feedback, never punitive. A miss gets "Next one\'s yours", a splash gets "hop back and try again". There are streaks but no penalties. Messages are matched to the stage (reassurance in stage 1, confidence building in stage 4) and to sprain history.', B),
          p('<b>Clinical reference videos reviewed:</b> (1) ReBalance Physiotherapy, single-leg reactive ball toss on a slat board; (2) Fitness Pain Free, "Lateral Ankle Sprain, Phase 3": lateral hops and quarter-turn hops on an agility ladder, shuttles, heel-float single-leg balance; (3) Kaizo Health, weight-shift balance platform with a ski game, hands on rails. Each was mapped to a game above. Its stage was then set by the MGH protocol rather than the video\'s own label, so hops stay behind the stage 4 criteria.', B),
          img(OUT + 'glove_ball_preview.png', 70), p('Baseball glove and ball used in One-Leg Catch (Sketchfab, CC BY 4.0; brand markings removed).', S)]

# ---------- 6. Safety ----------
story += [p('6. Safety &amp; user experience', H1)]
story += bullets(['<b>Always-visible STOP orb</b> follows the person gently in the lower right of their view; one tap stops audio, games and the coach, then gives clear advice (sit, hold support, when to seek care).',
                  '<b>Automatic stop</b> on fall-like head motion (rapid drop or head height below 62% of standing height), with a hop-aware threshold.',
                  '<b>Pre-session safety check:</b> clear floor, sturdy support within reach, non-slip footing, current pain (8+/10 blocks standing work).',
                  '<b>Immersion limits:</b> standing work never hides the real floor; 360° is reserved for seated exercises.',
                  '<b>Cybersickness:</b> no artificial locomotion; the world never moves the person; sessions are short with rests.',
                  '<b>Clean menus:</b> the 3D coach appears only in the training space and exercise preview, never as cut-outs on menu cards; cards use scenery and SF Symbols so the Today screen stays calm and readable.',
                  '<b>HIG &amp; accessibility:</b> glass windows, ornaments, large targets (60 pt+), VoiceOver labels, voice and text cues together, reduced-motion friendly, readable pain scales with traffic-light colour plus numbers.'])

# ---------- 7. Apple platform ----------
story += [p('7. Apple platform, privacy and launch readiness', H1)]
story += bullets(['<b>Privacy by design:</b> no accounts, ads, analytics or third-party SDKs. Data stays on the device in Application Support with Data Protection (complete file protection). The clinician PDF is generated locally and shared only by the user.',
                  '<b>Privacy manifest</b> (PrivacyInfo.xcprivacy): no tracking, no collected data types; file-timestamp API reason declared. Usage strings explain hand-tracking and world-sensing use.',
                  '<b>App Review 1.4.1 (medical apps):</b> the app reminds users to consult a clinician, discloses the steadiness methodology (head-sway RMS) and labels it experimental rather than claiming accuracy [8]. Before submission, validate it against a force plate or the clinical single-leg stance test, or keep it as a non-diagnostic training score.',
                  '<b>App Review 5.1.1 / 5.1.3:</b> a public privacy policy URL is required in App Store Connect. Health data is never used for advertising or shared, and isn\'t stored in iCloud.',
                  '<b>Regulation:</b> software intended to monitor or treat injury can be a medical device under Singapore\'s Health Products Act (HSA). Before a commercial launch, confirm the classification with HSA, or position the app strictly as clinician-prescribed exercise guidance and education, and keep claims within that scope.',
                  '<b>IP:</b> under the NUS IP Policy, coursework IP may belong to the University. Check with the platform leader before any commercial release.'])

# ---------- 8. Assets ----------
story += [p('8. 3D, audio and visual assets', H1),
          table([
              ['Asset', 'Source & licence', 'Processing'],
              ['Coach "Maya" (photoreal)', '"Female fitness Model - Ai Generated + Rigged" by XCoder07, Sketchfab, CC BY 4.0', 'Decimated (205k → 95k tris), bind pose baked, retargeted: 15 exercise clips × 2 sides'],
              ['Coach "Alex" (real-person 3D scan)', '"Human 3D model scanned with iPhone X" by in3D, Sketchfab, CC BY 4.0', 'Retargeted with the same motion library'],
              ['Ankle bones inside the coach (X-ray view)', 'BodyParts3D, (c) DBCLS, CC BY-SA 2.1 JP', 'Fitted to each coach\'s knee, ankle and toe joints and skinned rigidly'],
              ['Ankle anatomy (33 structures)', 'BodyParts3D, CC BY-SA 2.1 JP', 'Clipped, decimated, grouped Leg/Foot with pivot at the ankle axis; ligament landmarks computed from bone geometry'],
              ['Environments (4 × 360° panoramas)', 'Original, procedurally painted', '4096×2048 equirectangular; 60°/180° arcs and 360° sphere generated in RealityKit'],
              ['Stepping stones, lotus', 'Original (Blender)', 'USDZ'],
              ['Sound effects, ambiences, 3 music tracks', 'Original, synthesised', 'WAV (effects), AAC (loops)'],
              ['Baseball glove (One-Leg Catch)', '"Baseball Glove" by m.lando, Sketchfab, CC BY 4.0', 'Scaled to 29 cm, texture 1024 px, brand markings removed by inpainting'],
              ['Baseball', '"Baseball" by Virtua Con, Sketchfab, CC BY 4.0', 'Scaled to 7.4 cm, textures 512 px'],
              ['App icon (3-layer visionOS)', 'Original', 'Front / Middle / Back solid image stack'],
          ], [44, 60, 70]),
          p('Sketchfab and BlenderKit models can be added later. The coach file is replaceable as long as clip timing is kept (coach_clips.json). Check each model\'s licence (CC BY or CC0 for commercial use).', S),
          Spacer(1, 3 * mm), img(OUT + 'sheet_env.jpg', 150), p('The four original environments: Dawn Lake, River Valley, Golden Meadow and Aurora Night.', S)]

# ---------- 9. Validation ----------
story += [p('9. Limitations and validation plan', H1)]
story += bullets(['The coaches are photoreal 3D people animated by the app\'s clinical motion library (keyframed, not motion-captured). For a real-person guide, each exercise accepts a <b>clinician-recorded 180°/360° or spatial video</b> (Insta360 X4/X5, GoPro MAX, Canon EOS VR, or iPhone 15 Pro and later), played fully immersive on visionOS 26. Free online 180° rehab footage that may legally be reused does not exist, so we recommend filming our partner physiotherapist.',
                  'The steadiness score is experimental. Head-sway RMS relates to force-plate sway in validation work [8], but magnitudes differ.',
                  'Rules need review by a physiotherapist before patient use. All thresholds are in one file (ClinicalEngine.swift).',
                  '<b>Proposed user study (Week 10-11):</b> 5-8 participants with a recent or recurrent sprain, plus 2 clinicians. Measures: SUS usability, a session-adherence proxy, CAIT/FAAM at baseline, comfort and sickness questionnaire, and clinician rating of exercise fidelity from the coach vs a standard leaflet.'])

# ---------- References ----------
story += [p('References', H1)]
refs = [
    'Martin RL, Davenport TE, Fraser JJ, et al. Ankle Stability and Movement Coordination Impairments: Lateral Ankle Ligament Sprains Revision 2021. J Orthop Sports Phys Ther. 2021;51(4):CPG1-CPG80. doi:10.2519/jospt.2021.0302',
    'Vuurberg G, Hoorntje A, Wink LM, et al. Diagnosis, treatment and prevention of ankle sprains: update of an evidence-based clinical guideline. Br J Sports Med. 2018;52(15):956.',
    'Hupperets MDW, Verhagen EALM, van Mechelen W. Effect of unsupervised home based proprioceptive training on recurrences of ankle sprain: randomised controlled trial. BMJ. 2009;339:b2684.',
    'Dubois B, Esculier JF. Soft-tissue injuries simply need PEACE and LOVE. Br J Sports Med. 2020;54(2):72-73.',
    'Doherty C, Bleakley C, Delahunt E, Holden S. Treatment and prevention of acute and recurrent ankle sprain: an overview of systematic reviews with meta-analysis. Br J Sports Med. 2017;51(2):113-125.',
    'Doherty C, Bleakley C, Hertel J, et al. Recovery from a first-time lateral ankle sprain and the predictors of chronic ankle instability: a prospective cohort analysis. Am J Sports Med. 2016;44(4):995-1003.',
    'Stiell IG, Greenberg GH, McKnight RD, et al. Decision rules for the use of radiography in acute ankle injuries. JAMA. 1993;269(9):1127-1132.',
    'Sylcott B, Lin CC, Williams K, Hinderaker M. Investigating the use of virtual reality headsets for postural control assessment: instrument validation study. JMIR Rehabil Assist Technol. 2021;8(4):e24950.',
    'Mitsuhashi N, Fujieda K, Tamura T, et al. BodyParts3D: 3D structure database for anatomical concepts. Nucleic Acids Res. 2009;37:D782-D785.',
    'Apple. App Review Guidelines (1.4.1, 5.1.1, 5.1.3) and Human Interface Guidelines for visionOS. developer.apple.com',
    'Mass General Brigham Sports Physical Therapy. Rehabilitation Protocol for Ankle Sprain (phases I-IV).',
    'Smith MD, Vicenzino B, Bahr R, et al. Return to sport decisions after an acute lateral ankle sprain injury: introducing the PAASS framework. Br J Sports Med. 2021;55(22):1270-1276.',
    'Gribble PA, Delahunt E, Bleakley C, et al. Selection criteria for patients with chronic ankle instability: a position statement of the International Ankle Consortium. J Athl Train. 2014;49(1):121-127.',
    'Lin H, Han K, Ruan B. Effect of virtual reality on functional ankle instability rehabilitation: a systematic review. J Healthc Eng. 2021:7363403.',
    'Montero-Odasso M, van der Velde N, Martin FC, et al. World guidelines for falls prevention and management for older adults: a global initiative. Age Ageing. 2022;51(9):afac205.',
]
for i, r in enumerate(refs, 1): story.append(p(f'[{i}] {r}', S))
story += [Spacer(1, 4 * mm), p('Steady provides exercise guidance and education. It doesn\'t diagnose, and it doesn\'t replace care from a doctor or physiotherapist.', S)]

def footer(c, d):
    c.saveState(); c.setFont('DV', 7.5); c.setFillColor(GREY)
    c.drawString(18 * mm, 9 * mm, 'Steady · Clinical Evidence & Design Report · medium-fidelity prototype')
    c.drawRightString(A4[0] - 18 * mm, 9 * mm, f'{d.page}'); c.restoreState()
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print('ok')
