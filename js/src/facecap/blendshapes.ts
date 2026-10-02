/**
 * Face Cap blendshape indices, in the exact order Face Cap live mode sends
 * them on the `/W` OSC address (int index, float value).
 *
 * Naming follows Face Cap: `_L` / `_R` mark symmetrical shapes, while
 * `Left` / `Right` inside a name is a direction for non-symmetrical shapes.
 */
export const BLENDSHAPE_NAMES = [
  'browInnerUp',
  'browDown_L',
  'browDown_R',
  'browOuterUp_L',
  'browOuterUp_R',
  'eyeLookUp_L',
  'eyeLookUp_R',
  'eyeLookDown_L',
  'eyeLookDown_R',
  'eyeLookIn_L',
  'eyeLookIn_R',
  'eyeLookOut_L',
  'eyeLookOut_R',
  'eyeBlink_L',
  'eyeBlink_R',
  'eyeSquint_L',
  'eyeSquint_R',
  'eyeWide_L',
  'eyeWide_R',
  'cheekPuff',
  'cheekSquint_L',
  'cheekSquint_R',
  'noseSneer_L',
  'noseSneer_R',
  'jawOpen',
  'jawForward',
  'jawLeft',
  'jawRight',
  'mouthFunnel',
  'mouthPucker',
  'mouthLeft',
  'mouthRight',
  'mouthRollUpper',
  'mouthRollLower',
  'mouthShrugUpper',
  'mouthShrugLower',
  'mouthClose',
  'mouthSmile_L',
  'mouthSmile_R',
  'mouthFrown_L',
  'mouthFrown_R',
  'mouthDimple_L',
  'mouthDimple_R',
  'mouthUpperUp_L',
  'mouthUpperUp_R',
  'mouthLowerDown_L',
  'mouthLowerDown_R',
  'mouthPress_L',
  'mouthPress_R',
  'mouthStretch_L',
  'mouthStretch_R',
  'tongueOut',
] as const;

export type BlendshapeName = (typeof BLENDSHAPE_NAMES)[number];

export const BLENDSHAPE_COUNT = BLENDSHAPE_NAMES.length;

/** Index lookup by name, e.g. `BS.jawOpen === 24`. */
export const BS = Object.fromEntries(
  BLENDSHAPE_NAMES.map((name, i) => [name, i]),
) as Record<BlendshapeName, number>;
