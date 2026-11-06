# Exporting the fish from Blender

The app loads `ARFace/Resources/fish.usdz`. It is exported from the working Blender file on the
shared Google Drive with the export scripts on this repo's `web` branch (`blender/export_rest.py`,
`export_fish.py`, `export_usd.py`). Two scripts in `tools/` wrap them, so an export is two short
steps and works the same on any Mac set up as below. The Blender file is never written to.

## Setting up a Mac (once)

1. **Blender**, installed in `/Applications`. We export with Blender 5.2 LTS. Elsewhere, set
   `BLENDER=/path/to/Blender.app/Contents/MacOS/Blender` when exporting.
2. **The repo**, cloned with its branches, so the export scripts on `web` are there:

   ```bash
   git clone https://github.com/boid-studio/Facefish.git
   ```

   A fresh clone has them as `origin/web`, which the export script uses. If it says there is no
   web branch, run `git fetch origin web`.
3. **Google Drive for desktop**, signed in with access to the shared drive `Projekt`, folder
   `Masked Singer-fisken`. The Blender files are in `2. Work/Blender/`; their textures are in
   `2. Work/Textures/` and `2. Work/Blender/textures/`. Make those folders **available offline**
   (right-click in Finder): Blender can only pack a texture that is downloaded.
4. **Xcode**, to build and run the app (see the README). `usdtree`, used to check an export,
   comes with macOS.

## Exporting

1. **Open the latest fish** in Blender (for example `fish_Pelles_Feedback_DL1_LW_tweak.blend`) and
   save it.

2. **Save an export copy, inside Blender.** Go to the Scripting workspace. In its Text Editor choose
   Text › Open, pick `tools/save-export-copy.py` from the repo, and press Run Script (▶ or
   Alt+P). It writes `/tmp/facefish_export.blend`, a copy of what is open with every texture
   packed in. The open file keeps its name and stays saved. (Its report, including any texture it
   couldn't pack, goes to the Terminal if Blender was started from one; otherwise check that
   `/tmp/facefish_export.blend` was written. Claude can run this step through the Blender MCP and
   shows the report.)

   Why a copy: command-line Blender isn't allowed to read files in Google Drive (macOS privacy;
   it fails with "Operation not permitted"), and a plain copy saved elsewhere would lose its
   relative texture paths.

3. **Export**, in Terminal from the repo:

   ```bash
   FACEFISH_SOURCE="fish_Pelles_Feedback_DL1_LW_tweak.blend" tools/export-fish.sh
   ```

   This runs Blender headless on the copy and writes `ARFace/Resources/fish.usdz`. It then checks
   that the parts the app looks for are there (see below), warns about any that are missing, and
   prints the number of blend shapes (41 today: 34 on the head, 5 on the brows, 1 per eyelid).
   `FACEFISH_SOURCE` names the real file instead of the copy; it's optional.

4. **Check it in the app**: build, run on the phone, and look at the fish. Mouth, blink, brows,
   fins, and a blush (the side fins must not cut into the face).

5. **Commit** `ARFace/Resources/fish.usdz`, naming the source `.blend` in the message.

## What the export does

In one Blender session on the copy, nothing saved back:

- rest pose: no animation, shape keys at 0, bones at rest, fin-wave previews off
- shape keys rebuilt on the subdivided meshes (head, brows, eyelids), their modifiers baked in
- hidden objects, reference images, lights and cameras dropped
- every other modifier applied except the armatures (skinning)
- everything grouped under one `Fish` prim, Y up; textures that aren't PNG or JPEG become PNG

USD doesn't allow `.` in names, so `Eye.L` arrives as `Eye_L`, `Tail.1` as `Tail_1` and so on.
The app matches names ignoring `.`, `_` and case.

## Keeping the Blender file export-ready

- **Everything visible is exported.** Hide work in progress (the eye icon in the Outliner) before
  step 2, as the brows were while they were only a plane.
- **Keep the eye and lid turns as object rotations; don't apply them (Ctrl+A).** The app uses each
  exported rotation as the rest pose and turns the eye or lid about its origin, which must stay at
  the eyeball's centre. It also reads the eyes' cross-eyed turn from it, to relax it when the gaze
  goes to the side.
- **Both lids at the same angle**, today 5.2° about X. How far a blink closes from there is set in
  the app: `LidRig.angle` in `ARFace/Avatar/EyeRig.swift` (95.7°, so a lid closes at 100.9° in
  Blender terms). If the lids' rest angle changes, set `angle` to 100.9 minus the new angle.
- **Expressions are shape keys named after ARKit** (`jawOpen`, `browDownLeft`…), on any mesh: the
  app drives every shape key whose name matches, on whichever part it is. Left and right are the
  fish's own; Left moves the fish's left side (+X in Blender).
- **The brows have their Mirror applied** (needed for separate left and right shape keys); edit
  both sides. Solidify and Subdivision stay as live modifiers.
- **Remove test animations** from rigs when done with them. The export drops animation, but the
  viewport shows the animated pose, which can hide what the file really holds.
- **Accessories** (things she can wear, put on and off with the hat button) are objects named
  `accessory_<name>`, e.g. `accessory_mask` (a version number after it is fine: `accessory_mask2`),
  in the head's space. To follow the face, give them the
  head's shape keys (start from a copy of the head). A new one also needs a case in
  `ARFace/Avatar/Accessory.swift`. Their materials must be plain values or image textures:
  procedural nodes (noise, colour ramps) don't export, and the material keeps only the unlinked
  defaults.
- **The blush pose** (the `cover…` constants in `ARFace/Avatar/FinRig.swift`) was solved against the
  head, eyes, lids and lashes. After changes around the eyes or the side fins, check a blush.

## What the app expects

| Part | Used by |
| --- | --- |
| `Head` mesh with ARKit-named shape keys (`jawOpen`, `mouthSmileLeft`…) | `AvatarController` (face) |
| `accessory_brows` mesh with the five ARKit brow shape keys (worn by default) | `AvatarController` (face), the hat button |
| `Eye_L`, `Eye_R` (pivot at the eyeball's centre) | `EyeRig` |
| `Eyelid_L`, `Eyelid_R` with a `lashesClosed` shape key | `LidRig` |
| `TailRig` (`Tail_1`–`Tail_3`) | `FinRig`, the swim body bend |
| `PecRig_L`, `PecRig_R` (`Pec_L_0`–`Pec_L_2`, `Pec_R_0`–`Pec_R_2`) | `FinRig`, the blush |
| `DorsalRig` (`Dorsal_0`–`Dorsal_3`) | `FinRig` |
| `FinWave` UV set on the fins | fin ripple shaders |
| `accessory_<name>` (optional), e.g. `accessory_mask` | the hat button (`Accessory`) |

## Troubleshooting

- **"No /tmp/facefish_export.blend"**: run step 2 first.
- **"could not pack …" in step 2**: that image's file is missing or not downloaded. Fine for the
  reference images (front, side, top and perspective views, `V.png`): they point at files on the
  Mac they were added on and are dropped from the export anyway. For a material texture (in
  `2. Work/Textures/` or `2. Work/Blender/textures/`), make its Drive folder available offline and
  run step 2 again; otherwise it comes out missing.
- **"No web branch with the export scripts"**: run `git fetch origin web`.
- **"Blender not found"**: install Blender in `/Applications`, or set `BLENDER=…`.
- **"WARNING: no … in the export"**: a part was renamed or hidden in Blender; the app won't find it.
- **"Operation not permitted"**: Blender was pointed at the Google Drive file; use the copy.
