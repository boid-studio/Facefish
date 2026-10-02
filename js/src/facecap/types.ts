import { BLENDSHAPE_COUNT } from './blendshapes';

/**
 * One decoded snapshot of Face Cap live data. Angles are in degrees as sent
 * by Face Cap; the fish mapping converts to radians and handles mirroring.
 */
export interface FaceFrame {
  /** 52 blendshape weights in Face Cap index order, each 0..1. */
  weights: Float32Array;
  /** Head position in metres (ARKit space). */
  headPosition: { x: number; y: number; z: number };
  /** Head rotation as Euler degrees (x, y, z). */
  headRotation: { x: number; y: number; z: number };
  /** Head rotation as a quaternion, when Face Cap sends `/HRQ`. */
  headQuaternion: { x: number; y: number; z: number; w: number } | null;
  /** Left / right eye rotation (x, y) as sent by Face Cap. */
  eyeLeft: { x: number; y: number };
  eyeRight: { x: number; y: number };
  /** Wall-clock time of the last update (performance.now()). */
  timestamp: number;
}

export function createFaceFrame(): FaceFrame {
  return {
    weights: new Float32Array(BLENDSHAPE_COUNT),
    headPosition: { x: 0, y: 0, z: 0 },
    headRotation: { x: 0, y: 0, z: 0 },
    headQuaternion: null,
    eyeLeft: { x: 0, y: 0 },
    eyeRight: { x: 0, y: 0 },
    timestamp: 0,
  };
}

export function copyFaceFrame(from: FaceFrame, to: FaceFrame): void {
  to.weights.set(from.weights);
  to.headPosition.x = from.headPosition.x;
  to.headPosition.y = from.headPosition.y;
  to.headPosition.z = from.headPosition.z;
  to.headRotation.x = from.headRotation.x;
  to.headRotation.y = from.headRotation.y;
  to.headRotation.z = from.headRotation.z;
  to.headQuaternion = from.headQuaternion ? { ...from.headQuaternion } : null;
  to.eyeLeft.x = from.eyeLeft.x;
  to.eyeLeft.y = from.eyeLeft.y;
  to.eyeRight.x = from.eyeRight.x;
  to.eyeRight.y = from.eyeRight.y;
  to.timestamp = from.timestamp;
}
