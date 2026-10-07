/**
 * The fish's animation parameters. The mapping layer turns a FaceFrame (or
 * idle behaviour) into a target FishPose; the Fish mesh only ever reads a
 * pose, so the model and the tracking data stay decoupled.
 */
export interface FishPose {
  /** 0 = closed, 1 = fully open. */
  jawOpen: number;
  /** -1 = frown, 0 = neutral, 1 = smile. */
  mouthCorner: number;
  /** 0..1 pucker / funnel. */
  pucker: number;
  /** 0..1 horizontal stretch of the corners (wide vowels). */
  mouthStretch: number;
  /** -1 = jaw to fish's left (screen -x), 1 = right. */
  jawSide: number;
  tongue: number;
  cheekPuff: number;

  blinkL: number;
  blinkR: number;
  wideL: number;
  wideR: number;
  /** Radians. Yaw positive turns the pupil toward +x, pitch positive looks down. */
  eyeYawL: number;
  eyePitchL: number;
  eyeYawR: number;
  eyePitchR: number;

  /** -1 = down, 1 = up. */
  browL: number;
  browR: number;
  browInner: number;

  /** Head rotation in radians, already mirrored for an avatar facing the user. */
  headPitch: number;
  headYaw: number;
  headRoll: number;
  /** Head offset in scene units: where the singer's head is inside the helmet. */
  headX: number;
  headY: number;
  /** Positive = toward the viewer. */
  headZ: number;
  /**
   * The singer's head turn in radians, relative to rest and mirrored like
   * headYaw, but NOT scaled by the Head turn setting: fins and tail react to
   * it even when the fish itself doesn't turn.
   */
  turn: number;
  /** The singer's head nod in radians (positive = down), relative to rest, NOT scaled by Head turn. */
  nod: number;

  /** 1 while tracking data is live, 0 while idling. */
  signal: number;
}

export function createFishPose(): FishPose {
  return {
    jawOpen: 0,
    mouthCorner: 0,
    pucker: 0,
    mouthStretch: 0,
    jawSide: 0,
    tongue: 0,
    cheekPuff: 0,
    blinkL: 0,
    blinkR: 0,
    wideL: 0,
    wideR: 0,
    eyeYawL: 0,
    eyePitchL: 0,
    eyeYawR: 0,
    eyePitchR: 0,
    browL: 0,
    browR: 0,
    browInner: 0,
    headPitch: 0,
    headYaw: 0,
    headRoll: 0,
    headX: 0,
    headY: 0,
    headZ: 0,
    turn: 0,
    nod: 0,
    signal: 0,
  };
}

export type PoseKey = keyof FishPose;
export const POSE_KEYS = Object.keys(createFishPose()) as PoseKey[];
