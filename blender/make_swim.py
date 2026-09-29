"""Create the looping "swim" animation on the fish rig: fins sculling to hold the fish in place.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter8.blend -P blender/make_swim.py

Writes an Action "swim" on the Rig and pushes it to an NLA track of the same name, which the
exporter turns into a glTF clip. The app plays a clip called "swim" (or "idle") on a loop all the
time, underneath face tracking and the body actions. The tail is left out on purpose: the app
sways the Tail bone itself, harder while the singer sings.

Edit freely in Blender afterwards (Dope Sheet > Action Editor); keep the first and last frame equal
so the loop is seamless.
"""
import math

import bpy

FPS = 30
CYCLE = 1.2          # seconds per stroke
STEP = 2             # key every 2 frames

scene = bpy.context.scene
scene.render.fps = FPS
rig = bpy.data.objects["Rig"]
frames = int(round(CYCLE * FPS))

# (bone, [(euler axis, amplitude in radians, phase in cycles)])
MOTION = {
    # pectoral fins scull: sweep forward/back and feather up/down, a little out of phase
    "Fin.L": [(0, 0.38, 0.00), (2, 0.20, 0.25)],
    "Fin.R": [(0, 0.38, 0.08), (2, -0.20, 0.33)],
    # pelvic fins (fish_starter7/8) flutter against the pectorals
    "Pelvic.L": [(0, 0.26, 0.50), (2, 0.10, 0.75)],
    "Pelvic.R": [(0, 0.26, 0.58), (2, -0.10, 0.83)],
    # the small anal fin (fish_starter9) ripples
    "Anal": [(2, 0.12, 0.55), (0, 0.08, 0.8)],
    # dorsal fin ripples side to side, slowly lagging the stroke
    "Dorsal": [(2, 0.09, 0.15), (0, 0.04, 0.40)],
}
MOTION = {b: ch for b, ch in MOTION.items() if b in bpy.data.objects["Rig"].pose.bones}

rig.animation_data_create()
ad = rig.animation_data
old = bpy.data.actions.get("swim")
if old:
    bpy.data.actions.remove(old)
for t in list(ad.nla_tracks):
    if t.name == "swim":
        ad.nla_tracks.remove(t)
action = bpy.data.actions.new("swim")
action.use_fake_user = True
ad.action = action

for pb in rig.pose.bones:
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (0, 0, 0)
    pb.location = (0, 0, 0)

for f in range(0, frames + 1, STEP):
    t = f / frames
    for bone, channels in MOTION.items():
        pb = rig.pose.bones[bone]
        rot = [0.0, 0.0, 0.0]
        for axis, amp, phase in channels:
            rot[axis] += amp * math.sin(2 * math.pi * (t + phase))
        pb.rotation_euler = rot
        pb.keyframe_insert("rotation_euler", frame=f)

# smooth, seamless loop
for fc in action.fcurves if hasattr(action, "fcurves") else []:
    for kp in fc.keyframe_points:
        kp.interpolation = "BEZIER"
        kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
    mod = fc.modifiers.new("CYCLES")

ad.action = None
track = ad.nla_tracks.new()
track.name = "swim"
strip = track.strips.new("swim", 0, action)
strip.action_frame_start, strip.action_frame_end = 0, frames
scene.frame_start, scene.frame_end = 0, frames
# preview in the viewport: keep the strip playing
for pb in rig.pose.bones:
    pb.rotation_euler = (0, 0, 0)
bpy.ops.wm.save_mainfile()
print("SWIM", {"frames": frames, "fps": FPS, "bones": list(MOTION), "tracks": [t.name for t in ad.nla_tracks]})
