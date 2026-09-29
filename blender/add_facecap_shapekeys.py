"""
Add the 52 Face Cap / ARKit shape keys to the active mesh, in Face Cap order
and with Face Cap's exact names. Run from Blender's Text Editor or Scripting
workspace with the fish head mesh selected. Existing keys are left alone.

Sculpt each key afterwards; empty keys are harmless (the app just won't
see any change for them).
"""
import bpy

FACECAP_SHAPES = [
    "browInnerUp", "browDown_L", "browDown_R", "browOuterUp_L", "browOuterUp_R",
    "eyeLookUp_L", "eyeLookUp_R", "eyeLookDown_L", "eyeLookDown_R",
    "eyeLookIn_L", "eyeLookIn_R", "eyeLookOut_L", "eyeLookOut_R",
    "eyeBlink_L", "eyeBlink_R", "eyeSquint_L", "eyeSquint_R", "eyeWide_L", "eyeWide_R",
    "cheekPuff", "cheekSquint_L", "cheekSquint_R", "noseSneer_L", "noseSneer_R",
    "jawOpen", "jawForward", "jawLeft", "jawRight",
    "mouthFunnel", "mouthPucker", "mouthLeft", "mouthRight",
    "mouthRollUpper", "mouthRollLower", "mouthShrugUpper", "mouthShrugLower", "mouthClose",
    "mouthSmile_L", "mouthSmile_R", "mouthFrown_L", "mouthFrown_R",
    "mouthDimple_L", "mouthDimple_R", "mouthUpperUp_L", "mouthUpperUp_R",
    "mouthLowerDown_L", "mouthLowerDown_R", "mouthPress_L", "mouthPress_R",
    "mouthStretch_L", "mouthStretch_R", "tongueOut",
]

# The ones that matter most for a fish; do these first if you're short on time.
RECOMMENDED = {
    "jawOpen", "eyeBlink_L", "eyeBlink_R", "eyeWide_L", "eyeWide_R",
    "mouthSmile_L", "mouthSmile_R", "mouthFrown_L", "mouthFrown_R",
    "mouthPucker", "mouthFunnel", "browInnerUp", "browDown_L", "browDown_R",
    "browOuterUp_L", "browOuterUp_R", "cheekPuff", "tongueOut",
    "eyeLookUp_L", "eyeLookUp_R", "eyeLookDown_L", "eyeLookDown_R",
    "eyeLookIn_L", "eyeLookIn_R", "eyeLookOut_L", "eyeLookOut_R",
}


def main():
    obj = bpy.context.active_object
    if obj is None or obj.type != "MESH":
        raise RuntimeError("Select the fish mesh first.")

    if obj.data.shape_keys is None:
        obj.shape_key_add(name="Basis", from_mix=False)

    existing = {k.name for k in obj.data.shape_keys.key_blocks}
    added = 0
    for name in FACECAP_SHAPES:
        if name in existing:
            continue
        key = obj.shape_key_add(name=name, from_mix=False)
        key.value = 0.0
        added += 1

    print(f"[facecap] {added} shape keys added to '{obj.name}' "
          f"({len(FACECAP_SHAPES) - added} already existed).")
    print("[facecap] Recommended to sculpt first: " + ", ".join(sorted(RECOMMENDED)))


if __name__ == "__main__":
    main()
