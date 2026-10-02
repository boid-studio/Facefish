import * as THREE from 'three';

/**
 * Procedural actions animate the avatar's root transform, so they work on
 * the placeholder fish and on a Blender model alike. Each returns the root
 * to rest by t = 1.
 *
 * `k` is the strength multiplier from the control panel (1 = authored
 * size). Full turns stay full turns; everything else scales with it.
 */
export interface ProceduralAction {
  /** Seconds. */
  duration: number;
  /** Apply the state for normalised time t in [0, 1] at strength k. */
  apply(root: THREE.Object3D, t: number, k: number): void;
}

const TAU = Math.PI * 2;

function smoothstep(a: number, b: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

function easeInOut(t: number): number {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

/**
 * A lap around the bowl: turn to the side, swim off screen, pass behind in
 * the fog, come back from the other side and turn to face front again.
 */
export const lap: ProceduralAction = {
  duration: 7,
  apply(root, t, k) {
    const R = 2.6;
    const theta = easeInOut(t) * TAU;
    root.position.set(R * Math.sin(theta), Math.sin(theta * 2) * 0.15 * k, -R + R * Math.cos(theta));
    // Face the direction of travel; unwrap so the return blends to 0 cleanly.
    let yaw = Math.PI / 2 + theta;
    if (t > 0.5) yaw -= TAU;
    const w = smoothstep(0, 0.12, t) * (1 - smoothstep(0.88, 1, t));
    root.rotation.set(0, yaw * w, -0.35 * w * Math.min(k, 1.6), 'YXZ');
  },
};

/** A quick barrel roll around the vertical axis, with a hop. */
export const spin: ProceduralAction = {
  duration: 1.2,
  apply(root, t, k) {
    const env = Math.sin(t * Math.PI);
    root.rotation.set(0, easeInOut(t) * TAU, 0, 'YXZ');
    root.position.set(0, env * 0.25 * k, env * 0.2 * (k - 0.5));
  },
};

/** Two emphatic nods, leaning in. */
export const nod: ProceduralAction = {
  duration: 1.0,
  apply(root, t, k) {
    const env = Math.sin(t * Math.PI);
    const s = Math.sin(t * TAU * 2);
    root.rotation.set(s * 0.32 * k * env, 0, 0, 'YXZ');
    root.position.set(0, -Math.max(0, s) * 0.08 * k * env, Math.max(0, s) * 0.25 * k * env);
  },
};

/** A happy side-to-side wiggle that dies out. */
export const wiggle: ProceduralAction = {
  duration: 1.4,
  apply(root, t, k) {
    const env = (1 - t) * Math.sin(Math.min(1, t * 6) * Math.PI * 0.5);
    const s = Math.sin(t * TAU * 3);
    root.rotation.set(0, s * 0.12 * k * env, s * 0.35 * k * env, 'YXZ');
    root.position.set(s * 0.2 * k * env, 0, 0);
  },
};

/** A firm "no": shake the head side to side. */
export const shake: ProceduralAction = {
  duration: 1.1,
  apply(root, t, k) {
    const env = Math.sin(t * Math.PI);
    const s = Math.sin(t * TAU * 3);
    root.rotation.set(0, s * 0.4 * k * env, -s * 0.06 * k * env, 'YXZ');
    root.position.set(s * 0.06 * k * env, 0, 0);
  },
};

/** Two excited hops with a little pitch on the way up. */
export const bounce: ProceduralAction = {
  duration: 1.0,
  apply(root, t, k) {
    const hop = Math.abs(Math.sin(t * TAU));
    const dir = Math.cos(t * TAU) >= 0 ? 1 : -1;
    root.position.set(0, hop * 0.38 * k, 0);
    root.rotation.set(-dir * hop * 0.18 * k, 0, 0, 'YXZ');
  },
};

/** Dart straight at the camera, hang there, and back off. */
export const dash: ProceduralAction = {
  duration: 1.3,
  apply(root, t, k) {
    const inOut = smoothstep(0, 0.28, t) * (1 - smoothstep(0.6, 1, t));
    root.position.set(0, inOut * 0.1 * k, inOut * 0.9 * k);
    root.rotation.set(-inOut * 0.12 * k, 0, 0, 'YXZ');
  },
};

export const PROCEDURAL_ACTIONS: Record<string, ProceduralAction> = {
  lap,
  spin,
  nod,
  wiggle,
  shake,
  bounce,
  dash,
};
