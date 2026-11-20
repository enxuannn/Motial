# Steady: Ankle Sprain Rehab for Apple Vision Pro

A medium-fidelity visionOS prototype that delivers guideline-based ankle sprain rehabilitation with:

- a life-size photoreal 3D coach (choose a photoreal model or a real-person 3D scan), with optional real-person 180° video demos
- explorable CT-based ankle anatomy
- head- and hand-tracked balance games
- safety-first tailoring

## Open and run

1. You need a Mac with Apple Silicon and **Xcode 16 or newer** (visionOS 2 SDK). The project targets visionOS 2.0, so it also builds with Xcode 26.
2. Double-click `Motial.xcodeproj`.
3. Select the **Motial** target, open *Signing & Capabilities* and choose your team. Change the bundle ID if needed (default `sg.edu.nus.did.Motial`).
4. Pick a run destination:
   - **Apple Vision Pro** (recommended). Head and hand tracking, balance scoring and the games need the real device.
   - **Apple Vision Pro simulator**. Fine for the UI, coach, anatomy and environments. There's no hand tracking, so in Catch you look at a ball and pinch instead.
5. Press **Run** (⌘R).

The project uses Xcode's *folder-synchronised groups*, so any file you drop into `Motial/` is added to the app automatically. If you see build errors, see **Troubleshooting** below.

## What's inside

```
Motial/
  SteadyApp.swift              App entry: main window, 3D anatomy volume, immersive training space
  Model/                       Clinical engine (triage, stages, plan, adaptation), exercise & evidence library, persistence
  Views/                       Onboarding (5 short screens), Today, Exercise detail, Learn, 3D Anatomy, Progress, Settings
  Immersive/                   Session controller (state machine + STOP), coach rig, environment (60°/180°/360°), motion tracking
  Immersive/Games/             Balance Bloom, One-Leg Catch, River Stones, Rhythm Steps
  Audio/                       Music, ambience, spatial SFX, voice coach, beat detection for the person's own songs
  Report/                      On-device clinician PDF
  Resources/                   Coach.usdz, AnkleAnatomy.usdz, Stones.usdz, Lotus.usdz, panoramas, audio, JSON data
  Assets.xcassets              Layered visionOS app icon, accent colour
  PrivacyInfo.xcprivacy        Privacy manifest
Info.plist                     Hand-tracking / world-sensing usage strings, scene manifest
Docs/                          Clinical Evidence & Design Report (PDF), preview renders
```

## Demo script (about 3 minutes)

1. **Onboarding:** right ankle, 3–14 days, first sprain. Safety: none. Today: pain 2, walks with a limp, single-leg only with support. Result: **Stage 2 · Load & Restore**.
2. **Learn → Open 3D ankle:** tap the ATFL, then press **How a sprain happens** to watch the ligament turn red as it stretches.
3. **Today → Start session:** complete the safety check, then watch the coach. Toggle **See the ankle** for X-ray mode.
4. Run **Stepping Stones** or **Rhythm Steps**, and press the red **STOP** orb at any time.
5. **Progress:** create the clinician PDF.

To show Stage 3 games (Balance Bloom, One-Leg Catch), use **Settings → Clinician: set stage manually → 3**. For Stage 4 hops, also switch on **Clinician has cleared hopping**, then do a check-in with pain 0–1 and confidence 🙂 or 💪 (hops are gated on clearance, pain and confidence, following the MGH phase IV criteria and the PAASS return-to-sport framework; otherwise Stepping Stones is offered instead).

## Tailoring rules added after the evidence re-check (Oct 2026)

- **Hops last:** single-leg hops, side hops and River Hops only in Stage 4, with clinician clearance, pain 0–1/10 and ankle confidence 4/5 or higher (MGH protocol phase IV; PAASS 2021).
- **Stage 3 → 4:** 30 s steady single-leg stand, 25 single-leg heel raises (MGH), pain 2/10 or less and confidence 3/5 or higher.
- **Old injuries:** previous sprain plus giving way or re-sprains (International Ankle Consortium 2014) turns on the instability pathway: extra balance volume and a 3×/week, 8-week plan.
- **Habits:** exercises skipped 3+ times (more than done) move to the end as "Optional today". Nothing is forced or silently removed.
- **Interface:** the 3D coach appears only in the training space and the exercise preview. Menu cards use scenery and SF Symbols, the plan is an adaptive grid (no sideways carousel), and the check-in sits first because it changes the plan.

## Swapping in other 3D models (Sketchfab / BlenderKit)

- **Coach:** run `Tools/AssetPipeline/retarget_coach.py <model.glb> <height_m> 70` on any rigged humanoid (Mixamo, Sketchfab, Character Creator or SMPL-style rig). It maps the bones automatically, bakes the bind pose, fits the ankle bones for X-ray view, and exports a USDZ plus clip JSON with the full exercise motion library. Then add it as a new `CoachModel` case.
- **Props:** any USDZ can replace `Stones.usdz` or `Lotus.usdz` if it keeps the entity names (`Stone_A/B/C`, `LotusPetals`, `LotusCore`).
- Check the licence first: CC0 or CC BY is fine for commercial release. Avoid NC and ND licences. Add credits in *Settings → Credits*.

## Real-person videos (180° / 360° / spatial)

Record each exercise with a 180° or 360° camera that Vision Pro supports (Insta360 X4/X5/X6, GoPro MAX/MAX2, Canon EOS VR lens) or as iPhone spatial video (iPhone 15 Pro and later). In the app, open the exercise, tap **Add video**, then tap **Watch immersive** to watch the person life-size around you. On visionOS 26 the app uses RealityKit's native 180°/360° projection. Filming tips: put the camera at chest height 1.5–2 m from the person, use a plain background and even light, show each exercise from front and side, and keep the camera still to avoid motion sickness. To bundle a video for everyone, add it to `Resources/` as `video_<exerciseID>.mov` (for example `video_single_leg_stance.mov`).

## Troubleshooting

- **"No such module" or SDK errors:** install the visionOS platform in *Xcode → Settings → Components*.
- **Swift 6 concurrency errors:** the target uses Swift 5 mode with minimal concurrency checking. Keep *Swift Language Version = 5*.
- **The coach doesn't animate:** open `Coach.usdz` in Reality Composer Pro and check that one animation is present. Re-export with `Tools/AssetPipeline/build_coach.py` if needed.

## Before an App Store submission

- Add a public privacy-policy URL and fill in App Privacy (*No data collected*).
- Have a physiotherapist review the thresholds in `Model/ClinicalEngine.swift`.
- Keep the steadiness score labelled as non-diagnostic, or validate it (App Review 1.4.1).
- Check the medical-device classification with HSA (Singapore) before commercial release, and check NUS IP policy with the platform leader.

Steady provides exercise guidance and education. It doesn't diagnose, and it doesn't replace care from a doctor or physiotherapist.


## Games updated from the three clinical reference videos (Oct 2026)

| Video | What it shows | What Steady does |
|---|---|---|
| ReBalance Physiotherapy, ball toss on a slat board | Physio throws from changing directions while the patient balances on one leg (reactive balance) | **One-Leg Catch** is now baseball style: a real glove (Sketchfab, CC BY) follows your tracked hand and real baseballs are pitched. Set 1 starts with warm-up catches on both feet, then you lift the other foot. Level 1 throws come straight on, level 2 from three directions, level 3 from five directions and heights. Only one-leg catches score. |
| Fitness Pain Free, "Lateral Ankle Sprain Phase 3" | Agility ladder: lateral hops, quarter-turn hops, shuttles | **River Stones** has levels. Stepping (stages 2–3): straight, zig-zag, side-step crossing. Hopping (stage 4, cleared): two-foot warm-up, forward hops, zig-zag hops, quarter-turn hops (land facing the arrow). Placed by the MGH protocol: two-foot hops before single-leg, direction changes last. |
| Kaizo Health, balance platform with a ski game | Weight shifting while holding rails, with game feedback | **Rhythm Steps** stage-2 weight-shift mode: feet planted, lean to the beat holding a support. Step mode in stage 3, hop mode only when hops are cleared. Each hit makes your chosen world react with its own sound (lake ripples, river droplets, meadow flowers, aurora shooting stars). Your own songs still work. |

**Other old injuries** (one multi-tap question in onboarding, editable in Settings): knee problems remove single-leg squats; a past ankle fracture or surgery adds a caution and needs clearance for hops; a sprain on the other ankle adds balance on both legs; a fall in the past year keeps a support within reach, caps levels at 2 and switches hopping off (World Falls Guidelines 2022).

**Evidence correction:** the claim that Hupperets 2009 included ball catching could not be confirmed from the paper, so One-Leg Catch now cites the MGH phase III "ball toss with decreased base of support".
