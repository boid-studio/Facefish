# Exporting the fish from Blender

The app loads `ARFace/Resources/fish.usdz`. It is exported from the working Blender file
(Google Drive: `Masked Singer-fisken/2. Work/Blender/fish_david_…blend`) with the export scripts on
the `web` branch (`blender/export_rest.py`, `export_fish.py`, `export_usd.py`). Two scripts in
`tools/` wrap them; nothing needs checking out and the Blender file is never written to.

## Steps

1. **Save** the file in Blender.

2. **Save an export copy** from inside Blender: in a Text Editor, open
   `tools/save-export-copy.py` and press Run Script (or ask Claude to run it through the Blender
   MCP). It writes `/tmp/facefish_export.blend` with every texture packed in. The open file keeps
   its name and stays saved.

   Why the copy: command-line Blender isn't allowed to read files in Google Drive (macOS privacy;
   it fails with "Operation not permitted"), and a plain copy saved elsewhere would lose its
   relative texture paths.

3. **Export** from the repo:

   ```bash
   FACEFISH_SOURCE="fish_david_AppliedMirror_keys9 LW edit.blend" tools/export-fish.sh
   ```

   This runs Blender headless on the copy and writes `ARFace/Resources/fish.usdz`. It then checks
   that the parts the app looks for are there (see below) and prints the number of blend shapes
   (36 today). `FACEFISH_SOURCE` is optional; it records the real file name instead of the
   copy's. Set `BLENDER=…` if Blender isn't in `/Applications`.

4. **Check** it in the app: build, run, and look at the fish (mouth, blink, fins, a blush).

5. **Commit** `ARFace/Resources/fish.usdz`, naming the source `.blend` in the message.

## What the export does

In one Blender session on the copy, nothing saved back:

- rest pose: no animation, shape keys at 0, bones at rest, fin-wave previews off
- shape keys rebuilt on the subdivided head, and modifiers on the eyelids baked into theirs
- hidden objects, reference images, lights and cameras dropped
- every other modifier applied except the armatures (skinning)
- everything grouped under one `Fish` prim, Y up; textures that aren't PNG or JPEG become PNG

USD doesn't allow `.` in names, so `Eye.L` arrives as `Eye_L`, `Tail.1` as `Tail_1` and so on.
The app matches names ignoring `.`, `_` and case.

## What the app expects

| Part | Used by |
| --- | --- |
| `Head` mesh with ARKit-named shape keys (`jawOpen`, `mouthSmileLeft`…) | `AvatarController` (face) |
| `Eye_L`, `Eye_R` (pivot at the eyeball's centre) | `EyeRig` |
| `Eyelid_L`, `Eyelid_R` with a `lashesClosed` shape key | `LidRig` |
| `TailRig` (`Tail_1`–`Tail_3`) | `FinRig`, the swim body bend |
| `PecRig_L`, `PecRig_R` (`Pec_L_0`–`Pec_L_2`, `Pec_R_0`–`Pec_R_2`) | `FinRig`, the blush |
| `DorsalRig` (`Dorsal_0`–`Dorsal_3`) | `FinRig` |
| `FinWave` UV set on the fins | fin ripple shaders |

## When the geometry changes

The blush pose (`coverRootTurn` and the other `cover…` constants in `ARFace/Avatar/FinRig.swift`)
was solved against the head, eyeballs, lids and lashes so the side fins cover the eyes without
cutting into the face. Changes to the mouth or body don't affect it; if the eyes, lids, lashes,
cheeks or side fins change, check a blush and ask for the pose to be re-solved if a fin cuts
through.

## Troubleshooting

- **"No /tmp/facefish_export.blend"**: run step 2 first.
- **"could not pack …" in step 2**: that image's file is missing. Fine for reference images
  (they're dropped); a material texture would come out missing.
- **"WARNING: no … in the export"**: a part was renamed or hidden in Blender; the app won't find it.
- **"Operation not permitted"**: Blender was pointed at the Google Drive file; use the copy.
