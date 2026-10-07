"""Turn a recorded Face Cap take into keyframes on the fish, the way the app moves it.

Record in the app (press r, or the Record button in the panel); the relay saves
recordings/take-YYYYMMDD-HHMMSS.json. Then, with your fish file open in Blender:

    Scripting workspace → Open → blender/import_take.py → Run Script

That imports the newest take. To pick one, set TAKE below, or run headless:

    Blender -b blender/<fish>.blend -P blender/import_take.py -- recordings/take-....json

What gets keyframed (each as its own action named after the take, so takes don't overwrite each other):
  - Head shape keys whose names match Face Cap's (jawOpen, mouthFunnel, eyeBlink_L, ...)
  - Eye.L / Eye.R turning (gaze), around the true up and sideways axes
  - Lid.L / Lid.R bones in EyelidRig: blink closes them by LID_ANGLE degrees, about their own X
  - the Head object turning with your head (HEAD = False to leave it still)
Values are raw from Face Cap times GAIN (the app's Expression setting), clamped to 0..1,
resampled to the scene's frame rate. Nothing is saved; save the file yourself if you want to keep it.
"""
import glob
import json
import math
import os
import sys

import bpy
import numpy as np
from bpy_extras import anim_utils
from mathutils import Euler, Matrix

# ---- settings (match the app's control panel)
TAKE = None          # path to a take .json; None = newest in recordings/
GAIN = 1.3           # Expression
CALIBRATE = True     # Face calibration: subtract the resting face stored with the take (Center face in the app)
PUCKER_PRIORITY = 1.0  # Pucker priority: a pucker turns funnel down (funnel *= 1 - priority * pucker)
MIRROR = False       # Mirror switch: True swaps left and right like a mirror
LID_ANGLE = 77.0     # Lid close angle, degrees (the lids are modelled ~23 degrees down; 77 more closes them)
LID_REST = 0.0       # Lid rest: how far closed the lids sit with no blink (0 = as modelled)
EYE_RANGE = 0.45     # radians an eye turns at a full look
HEAD = True          # turn the Head object with the singer's head
HEAD_GAIN = 1.0
HEAD_LIMIT = 55.0    # degrees
START_FRAME = 1

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else bpy.path.abspath("//")
ROOT = os.path.dirname(HERE) if os.path.basename(HERE) == "blender" else os.path.dirname(bpy.path.abspath("//"))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if argv:
    TAKE = argv[0]
if TAKE is None:
    takes = sorted(glob.glob(os.path.join(ROOT, "recordings", "take-*.json")))
    if not takes:
        raise RuntimeError(f"no takes in {os.path.join(ROOT, 'recordings')}; record one in the app first (press r)")
    TAKE = takes[-1]
if not os.path.isabs(TAKE):
    TAKE = os.path.join(ROOT, TAKE)

with open(TAKE) as f:
    doc = json.load(f)
NAMES = doc["names"]
IDX = {n: i for i, n in enumerate(NAMES)}
frames = doc["frames"]
T = np.array([fr["t"] for fr in frames])
W = np.array([fr["w"] for fr in frames])
HR = np.array([fr["hr"] for fr in frames])
take_name = doc.get("name", os.path.splitext(os.path.basename(TAKE))[0])

scene = bpy.context.scene
fps = scene.render.fps / scene.render.fps_base
n_frames = int(math.floor(T[-1] * fps)) + 1
times = np.arange(n_frames) / fps
blender_frames = START_FRAME + np.arange(n_frames)


def resample(col):
    return np.interp(times, T, col)


w_raw = np.stack([resample(W[:, i]) for i in range(len(NAMES))], axis=1)
NEUTRAL = doc.get("neutral")
if CALIBRATE and NEUTRAL:
    rest = np.array(NEUTRAL, dtype=float)
    rest = np.where(rest >= 0.95, 0.0, rest)          # like the app: a stuck value isn't rescaled
    w_raw = np.maximum(0.0, (w_raw - rest) / (1 - rest))
w = np.clip(w_raw * GAIN, 0, 1)
w[:, NAMES.index("mouthFunnel")] *= 1 - min(1.0, max(0.0, PUCKER_PRIORITY)) * w[:, NAMES.index("mouthPucker")]


def swap(name):
    for a, b in (("_L", "_R"), ("_R", "_L"), ("Left", "Right"), ("Right", "Left")):
        if name.endswith(a):
            return name[: -len(a)] + b
    return name


def model(name):
    """Weight driving the model's shape `name` (mirrored like the app when MIRROR)."""
    return w[:, IDX[swap(name) if MIRROR else name]]


def screen_pair(left, right):
    """The app's pair(): values for the screen-left and screen-right eye."""
    return (w[:, IDX[left]], w[:, IDX[right]]) if MIRROR else (w[:, IDX[right]], w[:, IDX[left]])


def normalise(key):
    k = key.strip().lower()
    for side in ("l", "r"):
        for sep in (".", "-", " "):
            if k.endswith(sep + side):
                k = k[:-2] + "_" + side
    if k.endswith("left"):
        k = k[:-4] + "_l"
    if k.endswith("right"):
        k = k[:-5] + "_r"
    return k


NORM = {normalise(n): n for n in NAMES}


def new_action(id_block, id_type, label):
    act = bpy.data.actions.new(f"{take_name} {label}")
    slot = act.slots.new(id_type=id_type, name=label)
    cb = anim_utils.action_ensure_channelbag_for_slot(act, slot)
    ad = id_block.animation_data or id_block.animation_data_create()
    ad.action = act
    ad.action_slot = slot
    return cb


def add_curve(cb, path, index, values):
    fc = cb.fcurves.new(path, index=index)
    fc.keyframe_points.add(len(values))
    co = np.empty(len(values) * 2)
    co[0::2] = blender_frames
    co[1::2] = values
    fc.keyframe_points.foreach_set("co", co)
    for kp in fc.keyframe_points:
        kp.interpolation = "LINEAR"
    fc.update()


report = {"take": os.path.relpath(TAKE, ROOT), "seconds": round(float(T[-1]), 2), "frames": n_frames, "fps": fps,
          "calibrated": bool(CALIBRATE and NEUTRAL)}

# ---- shape keys
head = bpy.data.objects["Head"]
keys = head.data.shape_keys
used, ignored = [], []
if keys:
    cb = new_action(keys, "KEY", "shapes")
    for kb in keys.key_blocks[1:]:
        name = NORM.get(normalise(kb.name))
        if name is None:
            ignored.append(kb.name)
            continue
        add_curve(cb, f'key_blocks["{kb.name}"].value', 0, model(name))
        used.append(kb.name)
report["shape_keys"] = used
report["shape_keys_not_face_cap"] = ignored

# ---- eyes: yaw about world up (+Z), pitch about world sideways (+X), like the app
inL, inR = screen_pair("eyeLookIn_L", "eyeLookIn_R")
outL, outR = screen_pair("eyeLookOut_L", "eyeLookOut_R")
upL, upR = screen_pair("eyeLookUp_L", "eyeLookUp_R")
downL, downR = screen_pair("eyeLookDown_L", "eyeLookDown_R")
# inL/outL/... are the eye on the LEFT OF THE SCREEN; facing the viewer, that is the fish's right eye
gaze = {
    "Eye.R": ((inL - outL) * EYE_RANGE, (downL - upL) * EYE_RANGE),
    "Eye.L": ((outR - inR) * EYE_RANGE, (downR - upR) * EYE_RANGE),
}
for name, (yaw, pitch) in gaze.items():
    eye = bpy.data.objects.get(name)
    if eye is None:
        continue
    eye.rotation_mode = "XYZ"
    P = eye.parent.matrix_world.to_3x3().normalized() if eye.parent else Matrix.Identity(3)
    Pinv = P.inverted()
    L0 = eye.matrix_basis.to_3x3().normalized()
    rot = np.zeros((n_frames, 3))
    prev = eye.rotation_euler.copy()
    for i in range(n_frames):
        R = Matrix.Rotation(yaw[i], 3, "Z") @ Matrix.Rotation(pitch[i], 3, "X")
        e = (Pinv @ R @ P @ L0).to_euler("XYZ", prev)
        rot[i] = e[:]
        prev = e
    cb = new_action(eye, "OBJECT", name)
    for k in range(3):
        add_curve(cb, "rotation_euler", k, rot[:, k])
    report.setdefault("eyes", []).append(name)

# ---- lids
rig = bpy.data.objects.get("EyelidRig")
if rig is not None:
    cb = None
    for bone, side in (("Lid.L", "L"), ("Lid.R", "R")):
        pb = rig.pose.bones.get(bone)
        if pb is None:
            continue
        cb = cb or new_action(rig, "OBJECT", "lids")
        amount = np.clip(model(f"eyeBlink_{side}") + 0.35 * model(f"eyeSquint_{side}") - 0.25 * model(f"eyeWide_{side}"), -0.3, 1)
        pb.rotation_mode = "XYZ"
        closed = np.where(amount >= 0, LID_REST + (1 - LID_REST) * amount, LID_REST + amount * (LID_REST + 0.3) / 0.3)
        add_curve(cb, f'pose.bones["{bone}"].rotation_euler', 0, np.radians(LID_ANGLE * closed))
        report.setdefault("lids", []).append(bone)

# ---- head turning, relative to the start of the take
if HEAD:
    hr = np.stack([resample(HR[:, k]) for k in range(3)], axis=1)
    rest_n = max(1, int(0.5 * fps))
    neutral = hr[:rest_n].mean(axis=0)
    d = np.clip(hr - neutral, -HEAD_LIMIT, HEAD_LIMIT) * HEAD_GAIN
    sgn = -1 if MIRROR else 1
    pitch, yaw, roll = np.radians(d[:, 0]), np.radians(d[:, 1]) * sgn, np.radians(d[:, 2]) * sgn
    head.rotation_mode = "XYZ"
    M0 = head.matrix_basis.to_3x3().normalized()
    rot = np.zeros((n_frames, 3))
    prev = head.rotation_euler.copy()
    for i in range(n_frames):
        # app: Euler(pitch, yaw, roll, 'YXZ') about up / sideways / toward the viewer (Blender -Y)
        R = Matrix.Rotation(yaw[i], 3, "Z") @ Matrix.Rotation(pitch[i], 3, "X") @ Matrix.Rotation(-roll[i], 3, "Y")
        e = (R @ M0).to_euler("XYZ", prev)
        rot[i] = e[:]
        prev = e
    cb = new_action(head, "OBJECT", "head")
    for k in range(3):
        add_curve(cb, "rotation_euler", k, rot[:, k])
    report["head"] = True

scene.frame_start = START_FRAME
scene.frame_end = START_FRAME + n_frames - 1
scene.frame_set(START_FRAME)
print("TAKE", report)
result = report
