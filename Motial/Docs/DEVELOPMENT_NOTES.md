# Motial (formerly Remer): development notes

**Read this first, then `Motial/README.md` and `Motial/Docs/Steady_Clinical_Evidence_and_Design_Report.pdf`.**
Owner: Xuan (En Xuan), NUS Industrial Design, DID platform "Spatial Computing and AI". Presentation: **29 Oct 2026**, possibly to the Head of Apple. The target is Apple-quality polish.

---

## 1. What the app is
**Remer** is a visionOS (Apple Vision Pro) app for **ankle-sprain rehabilitation**, following clinical guidelines (JOSPT CPG 2021, PEACE & LOVE, MGH protocol, PAASS 2021, International Ankle Consortium). It comes with an iPhone companion app, **Remer Pedal**.

- Xcode project: `Motial/Motial.xcodeproj` (the folder and target are still named Motial; the display name is **Remer**). Bundle ID `sg.edu.nus.did.Motial`. Target visionOS 2. Swift 5, minimal strict concurrency. It uses **folder-synchronised groups**, so any file dropped into `Motial/Motial/` is added to the app automatically.
- Companion: `Motial/Companion/SteadyShin/SteadyShin.xcodeproj` (display name "Remer Pedal", bundle `sg.edu.nus.did.Motial.Shin`, iOS 17).
- Built and tested in Xcode 26.3 with the Apple Vision Pro simulator (visionOS 26.2).

## 2. Non-negotiable rules from the owner (follow these)
1. **The default space is the user's own room** (mixed immersion). Never change the background or the default without asking. Golden Meadow is the default *immersive* scene. **Avoid water-body backgrounds.**
2. **Calm, rehab tone.** No arcade intensity.
3. **Hops and jumps are locked** behind clinician clearance (Stage 4, pain 0–1, confidence ≥4/5).
4. **Always point to real care:** 995 (Singapore emergency) and NurseFirst 6262 6262.
5. **One voice only:** the human-sounding Kokoro-82M "af_heart" pre-rendered clips. **No robotic system TTS fallback.** Every new spoken sentence needs a clip (see §6).
6. **No coach images on menus.** The 3D coach only appears in the training space and previews. Menus use scenery and SF Symbols.
7. **Moodboard:** dawn-blue, lanterns, glowing orbs, Lumi the butterfly guide. Teal accent, gold highlights.
8. **Licences:** use CC0 or CC BY only, credited in Settings. **Never NC/ND.** No copyrighted downloads. **No real-brand trade dress or logos.**
9. **Check every clinical claim against the evidence** before implementing it (the Clinical report in Docs).
10. **Don't overload the UI.** Keep layouts direct and simple, with one main card per scene.
11. **Ankle Alphabet:** you follow the trainer with your **foot**. Vision Pro can't see feet, so each letter is confirmed **by hand** (raise a hand, or look at ✓ Done and pinch). **Do not** use the iPhone pedal for this game.
12. The owner wants to **choose** things themselves when the options really differ (for example tabletop drive vs cockpit drive). Ask before making large irreversible changes.

## 3. Feature map (where the code is)
`Motial/Motial/`
- `SteadyApp.swift`: scenes: main window, anatomy volume, ImmersiveSpaces `session`, `video`, `sportlab`, `courtguide` (Play Smart, progressive immersion) and `welcome`. The session immersion style starts as `.mixed` (room).
- `Model/`
  - `ClinicalEngine.swift`: triage, 4 stages (Protect & Move → Load & Restore → Balance & Strength → Return to Activity), plan, adaptation, hop gating.
  - `ExerciseLibrary.swift`: 21 exercises. `GameKind`: balanceBloom, ballCatch, riverStones, rhythmSteps, lanternGlide, dawnDrive, cockpitDrive, wordGarden.
  - `Models.swift`: `PatientProfile` (includes `goal`, `playSport`). `AppModel.swift`: shared app state (`guideSport`, migrations `remer.roomDefault` and `remer.meadowDefault`).
  - `CourtGuide.swift`: **Play Smart**: `PlaySport` (basketball, badminton, football, running, everyday), the moves for each sport (verdict safe/care/notYet, `opensAt` stage, jump clearance, why, instead, ankle demo pose) and `scenes180`.
  - `SportLibrary.swift`: Sport Lab drills and access rules.
- `Immersive/`
  - `SessionController.swift`: session state machine, safety check, room scan, STOP orb, games, HUD placement. `setUp()` now runs in a background Task so the space never opens empty.
  - `CourtGuideView.swift`: Play Smart scene:
    - the court (`SportLabController.makeCourt`) with a curved cinema screen
    - a **180° dome** for rendered clips; the card moves to the left during 180° clips
    - `ExplainAnkle`: the AnkleAnatomy model, with the ATFL/CFL drawn between the bones and coloured by strain
  - `Games/`:
    - `LetterGardenGame.swift`: **Ankle Alphabet / Word Garden**: the trainer demonstrates, the letter draws stroke by stroke, then "your turn" is confirmed by hand. Includes word guessing, encouraging phrases and an A–Z collection strip.
    - `CockpitDriveGame.swift`: **Dawn Drive: Cockpit**:
      - seated, first-person, in an open convertible (`RemerCar.usdz`)
      - gauges: speedometer and "toes down" ankle dial
      - start lights, an ease-off guide before gates, a windscreen HUD, streaks and a star result
      - scenery: balloons, wind turbines, flowers, bunting, finish arch
      - comfort rules: straight road, capped speed, no world rotation
    - `DawnDriveGame.swift`: tabletop slot-car version. `LanternGlideGame.swift`: boat glide. `AnklePedal.swift`: `AnklePedal` and `LiveAnkle` ("Your ankle, live").
    - `ShinLink.swift`: Bonjour `_steadyshin._tcp` link to the iPhone pedal.
    - `GameKit.swift`: `RehabGame` protocol, `GameConfig` (seated, reduceMotion, coachAnchor), Palette.
- `Views/`
  - `TodayView.swift`: check-in, session hero, plan grid, then the **Play Smart card** (`CourtSmartsCard` in `SportLabView.swift`, with a sport picker), then the Sport Lab card.
  - `PedalGameViews.swift`: briefing and HUD for pedal games. `GameRecordsView.swift`: "Your drives" dashboard.
- `Audio/`: `SoundManager.swift` (clip-only voice, keyed by SHA-1), `DriveAudio.swift` (engine and wind loops, GameLog).
- `Resources/`
  - `Models/`: coaches, anatomy, RemerCar, RemerWheel, RemerBalloon, RemerWindmill, Birches, Boat, RaceCar, and others.
  - `Videos/`:
    - `video_bb_*`, `video_court_*`: basketball footage
    - `video_bm_*`, `video_fb_*`, `video_run_*`, `video_ev_*`: Mixkit footage for the other sports and everyday life
    - `court180_sprain.mp4` and `court180_safe.mp4`: Blender-rendered 180° clips, left eye, 1280², 24 fps
  - `Voice/`: about 1630 `vo_<sha1-12>.m4a` clips.

## 4. Current state (26 Oct 2026, 12:10)
**Done and tested in the simulator:**
- room default; Ankle Alphabet with word guessing; cockpit with the new car and gauges
- Court Smarts basketball with 180° clips
- the "empty space on first Play now" fix

**Done in code, built successfully, NOT yet visually checked in the simulator:**
- **Play Smart tailored to each sport** (picker on the Today card; content for badminton, football, running and everyday life; 49 new voice clips)
- **New 180° clips v2** (hoop, ball caught by Maya, no body overlap; a joint-distance check shows ≥18 cm apart)
- The Ankle Alphabet hand-confirm flow (raise hand / ✓ Done). The 40 s auto-advance prevents it getting stuck.

**Simulator problem at handover:** Xcode builds succeed, but LLDB fails to attach ("Xcode has killed the LLDB RPC server", "Failed to initialize logging system"). Fix: quit Xcode and Simulator, restart the Mac if needed, then ⌘R. If it still fails, untick **Edit Scheme → Run → Info → Debug executable** and run again.

## 4b. Changes on 26 Oct 2026 (afternoon, second session)
- **LLDB fix applied:** Edit Scheme → Run → Info → *Debug executable* is now **off**. The app runs; Xcode can't stop on crashes until it's switched back on.
- **Play Smart card (Today):** five white sport buttons (invisible labels) → one segmented control (`PlaySport.shortTitle`, "Everyday"); card 270 → 340 pt so "Watch and learn" isn't cut off.
- **Court scenes as live 3D (gap 3):** `Resources/Models/Court3D.usdz` (15 MB, both scenes on one 24 fps timeline: sprain 0–158, safe 170–290; `Clip180.frames`). `CourtGuideScene` plays it life-size on Sunset Court (real stereo, walk-around parallax) and drives x-ray/ligament glow in code; falls back to the 180° video if the file is missing. Built by `Tools/AssetPipeline/bake_court3d.py` (also in `AssetScripts/`), which reuses `vr180.py`. Ball/hoop colours are set in code (`paintProps`).
- **First-time headset onboarding (gap 5):** Welcome tour now starts with "Look, then pinch" (a glowing practice orb; pinching it advances). STOP step teaches pause/exit and the tour STOP orb responds to a pinch. Room step teaches the Digital Crown. Settings → "Show the welcome again". 13 new Kokoro clips.
- **Not yet confirmed on screen:** all of the above. The build was at step 39/52 with no errors when the Mac disconnected.
- **Simulator note:** synthetic drags/swipes from computer use don't scroll windows or Home pages; clicks work. Ask the owner to scroll.

## 4c. Changes on 26 Oct 2026 (evening, after the owner's first headset test)
Owner feedback and what was done:
- **Racing game missing**: the plan alternated pedal games by day, and the cockpit drive was only added on Dawn Drive days. `ClinicalEngine.plan` now always offers `dawn_drive_cockpit` (2nd item) while it fits the stage (1–2).
- **Start button**: pedal-game briefings (`PedalBriefing`) now have one big "Start the drive / glide" button at the top (demo when no iPhone).
- **Too many onboarding questions**: `OnboardingView` is 3 screens: ankle + when; pain + walking (one-leg question only if walking normally); a one-tap safety check ("None of these" / "Yes, some apply", Ottawa rules + red flags + "65+ or a fall"). History, giving way, age, goal, name, clinician-guided moved to Settings › My recovery.
- **Lumi not landing on the hand**: hand tracking already existed, but the trigger was too strict and it overwrote Lumi's mode. `ButterflyGuide` now has `seekHand` (wider reach in the "Meet Lumi" step), follows the hand, keeps her mode for afterwards and calls `onLandedOnHand` (chime + "Lumi landed on your hand…"; hint after 9 s). Session thresholds unchanged.
- **Basketball not working**: Court3D.usdz had NO animation (the glTF/USD imports reset Blender's frame range before export). `bake_court3d.py` now restores the range right before export; re-baked (players, roots and ball animate). Sport Lab "Balanced Set Shot" used the calf-raise clip and the ball appeared from nowhere: new `set_shot` clip; the coach faces the hoop, holds the ball at her chest and releases it at 0.45 s (`shot` points in the clips JSON); clip restarts every rep cycle.
- **Coach speaking animation**: `Tools/AssetPipeline/coach_talk_shot.py` adds a `Jaw` bone (lower face weighted) and clips `talk`, `seated_talk`, `set_shot` (both sides) to CoachFitness/CoachScan. `CoachRig` plays talk while `SoundManager.isVoicePlaying` and the requested clip is idle/seated_idle (0.6 s hold-over between sentences).
- **Welcome tour silent titles**: titles without a full stop were merged with the next sentence (no clip). Titles are now spoken as their own sentence.
- **Low-res court / racing backgrounds**: Sport Lab now uses the real 3D court (`Court.usdz`, Klieg3D, rim on `rimCentre`, made by `bake_court_only.py`) instead of the painted panorama + box hoop; Play Smart keeps its court (in Court3D) as the setting for every scene, players/ball only in live 3D. Both courts are under Poly Haven "Belfast Sunset (Pure Sky)" 8K, cropped to -8°..90° (`env_court_sky.jpg`, `EnvironmentBuilder.patch(imageElMin:)`), lit by `env_court_light.jpg`. Racing sky is the full 8K Bloem Field Sunrise cropped to -30°..90° (was 6K), lit by `env_drive_light.jpg`. 4K road/grass textures were NOT downloaded (browser blocked the second download); the old 1K tiles remain.
- 9 new voice clips (Lumi hand lines, "This is …, the first exercise in your plan").
- Not built yet when the session ended (the Mac was locked). Build, then check: plan shows Dawn Drive: Cockpit; onboarding 3 steps; welcome tour Lumi step on the headset; Play Smart live 3D players move and ball flies; Sport Lab Set Shot; coach mouth moves while talking.
- Settings credits still need the owner's basketball model author.

## 5. Next steps / open items
1. Run and visually check:
   - Play Smart for each sport, especially that the card layout fits
   - the 180° v2 clips
   - Ankle Alphabet's "Your turn" step and the ✓ Done button
2. Badminton footage is weak: Mixkit only has 2 casual rally clips, reused for all moves. Better footage would help (filmed by the owner, or another CC0/CC BY source).
3. The 180° clips are mono in-app. True stereo files (`court180_*_SBS.mp4`, side-by-side 2560×1280) are in `Extras/`. Converting them with Apple Immersive Video Utility on the Mac would give real depth.
4. Cockpit: the car loads a few seconds into the drive. Possibly preload it before the countdown. The side gauge-shaped panels in the car model may look cluttered.
5. iPhone Remer Pedal screenshots for the user-flow board were never captured.
6. Optionally update the pitch deck (`Extras/Steady_Pitch_Deck.pptx` is from before the rename).

## 6. How to add or regenerate assets
- **Voice (required for any new spoken line):** `AssetScripts/render_voice_kokoro.py <lines.txt> <outdir>`. It needs `kokoro_onnx`, `kokoro-v1.0.onnx` and `voices-v1.0.bin` (from the kokoro-onnx GitHub releases), plus ffmpeg. Each sentence becomes `vo_<first 12 hex of sha1(normalised sentence)>.m4a`. Normalising means: lowercase, straight quotes, single spaces, trailing .!? removed. `SoundManager.voiceKey` uses the same rule. Drop the files into `Resources/Voice/`. In DEBUG builds, a missing clip prints `[Remer] voice clip missing: …`. The full corpus builder is `Tools/make_voice.py` / `AssetScripts/make_voice_corpus.py`.
- **Sound effects:** `AssetScripts/make_sfx.py <outdir>` (numpy + soundfile; procedural, licence-free).
- **180° Blender renders:** `pip install bpy==5.2.3`.
  - Inputs: `CoachFitness.usdz`, `CoachScan.usdz`, `coach_*_clips.json` and `env_sunset_court.jpg` from Resources, in the same folder as the scripts (paths in the scripts point to a local build folder; change them).
  - Preview: `python3 vr180.py -- sprain preview`.
  - Background plate: `python3 vr180.py -- sprain render 1280 24 --bg`.
  - Frames: `runall.sh`, then `encode.sh`. About 20 s per frame on 2 CPU cores.
  - `overlap.py <variant>` measures the closest distance between the two bodies.
  - The scene uses the app's own coaches (Maya and Alex), a procedural hoop and ball, an x-ray body fade and ankle glow.
- **Footage:** Mixkit Stock Video Free License. Downloads only worked through the in-app browser (fetch → blob), not curl (blocked by the proxy).
- **3D models:** Sketchfab, CC BY only. Credits are in `Views/SettingsView.swift`. Current credits:
  - Cuy3 by paraje3d
  - Racing Steering Wheel by GAMICO
  - Hot Air Balloon - Low Poly by Styro
  - Windmill, Low-Poly by FLAREMEDIA
  - Stylized Low Poly Rowboat by Muyaya Concept
  - 3D Cartoon Toy Race Car by Skill Artist
  - Birch Trees Pack by Vova Truestory
  - coaches by XCoder07 and in3D
  - anatomy from BodyParts3D (CC BY-SA 2.1 JP)
  - Poly Haven HDRIs and textures (CC0)

## 7. Clinical and comfort design rules already implemented
- **Cockpit:** seated only, a stationary car frame, straight road, lane changes instead of turns, top speed 5 m/s (3 with Reduce Motion), acceleration ≤1.2 m/s², fade in and out, runs of about a minute (Apple HIG Motion; cybersickness evidence).
- **Gates** teach slow, controlled toes-up release, the eccentric control used in heel-raise lowering.
- **Play Smart verdicts** are gated by stage, and jumps also by physio clearance. Evidence comments are in `CourtGuide.swift` (McKay 2001 for basketball; Fahlström 1998 and Phomsoupha 2015 for badminton; Woods 2003 for football; JOSPT CPG 2021).
- **Sprain mechanism shown:** inversion plus plantarflexion loads the ATFL first, then the CFL.

## 8. Folder contents of this zip
- `Motial/`: the complete Xcode project (app, companion, Docs, Tools). **This is all you need to build.**
- `AssetScripts/`: scripts used to make the voice, sound effects and 180° renders.
- `Extras/`:
  - stereo SBS 180° clips
  - Remer_user_flow_VisionPro.png
  - the original project handover PDF
  - the old pitch deck
  - preview screenshots
