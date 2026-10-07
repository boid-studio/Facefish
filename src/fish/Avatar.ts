import type * as THREE from 'three';
import type { FishPose } from './pose';

/**
 * Anything that can be driven by the mapper. The procedural `Fish` and the
 * Blender-made `GltfFish` both implement this, so `main.ts` doesn't care
 * which one is on screen.
 *
 * `root` is reserved for the ActionPlayer (laps, spins); avatars animate
 * their own children and leave the root's transform alone.
 */
export interface Avatar {
  readonly root: THREE.Object3D;
  /**
   * @param pose    reduced, smoothed parameters (head, jaw, eyes, ...)
   * @param weights smoothed 52 Face Cap blendshape weights, for morph targets
   * @param time    seconds, for ambient motion
   * @param dt      seconds since the last frame
   */
  update(pose: FishPose, weights: Float32Array, time: number, dt: number): void;
  /** Names of authored animation clips, if any. */
  readonly clips?: string[];
  /** Play a clip once; resolves when it finishes. */
  playClip?(name: string): Promise<void>;
  /** Degrees an eyelid bone (Lid.L / Lid.R) turns at a full blink, for models that have them. */
  lidAngle?: number;
  /** How far closed the lids sit with no blink (0..1 of a full blink). */
  lidNeutral?: number;
  /** Strength of the tail's spring reaction to head turns (Tail.1, Tail.2, ... bones). */
  finReaction?: number;
  /** Strength of the tail's idle swim sway. */
  finSway?: number;
  /** Fin ripple strength multiplier (fins with a FinWave map; 1 = as tuned in Blender). */
  finWave?: number;
  /** Fin ripple speed multiplier. */
  finWaveSpeed?: number;
  /** Face Cap blendshape indices the model has shape keys for (morph-target avatars only). */
  readonly shapeKeys?: ReadonlySet<number>;
  /** World position of the mouth, for bubbles. Writes into and returns `target`. */
  mouthPosition?(target: THREE.Vector3): THREE.Vector3;
}
