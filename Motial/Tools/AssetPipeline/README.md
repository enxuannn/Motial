# Asset pipeline (Blender 5 as a Python module)

`pip install bpy==5.2.3 usd-core trimesh numpy-stl scipy pillow`, then download the BodyParts3D STL files (https://github.com/Kevin-Mattheus-Moerman/BodyParts3D) and set `STL` in `common.py`.

1. `prep_body.py` decimates the CT skin into body.blend
2. `build_anatomy.py` builds AnkleAnatomy.usdz and anatomy_landmarks.json
3. `build_coach.py` builds Coach.usdz (rig, clothing, 15 clips × 2 sides) and coach_clips.json
4. `build_props.py` builds Stones.usdz and Lotus.usdz
5. `paint_panoramas.py` creates the four 360° environments
6. `synth_audio.py` creates the sound effects, ambiences and music
7. `render_*.py` renders previews, and `make_report.py` builds the PDF report

Edit the pose functions in `build_coach.py` (C_* functions) to add or refine exercises, then re-run steps 3 and 7.
