import { BLENDSHAPE_COUNT, BLENDSHAPE_NAMES, BS } from '../facecap/blendshapes';
import type { FaceFrame } from '../facecap/types';
import { createFishPose, POSE_KEYS, type FishPose, type PoseKey } from './pose';

const DEG = Math.PI / 180;

export interface MappingConfig {
  /**
   * true: mirror (the screen faces the tracked person, like a desk test).
   * false: the fish is the person's face seen from the front (the helmet on
   * stage). This decides which side `_L` shapes land on and the sign of yaw.
   */
  mirror: boolean;
  /**
   * Extra sign applied to each head axis on top of the mirror handling, in
   * case a setup needs an axis flipped. Verify on the device.
   */
  headSigns: { pitch: number; yaw: number; roll: number };
  /** Scale applied to head rotation (1 = follow exactly). */
  headGain: number;
  /**
   * Scale applied to head position. The helmet is mounted on the shoulders,
   * so the head moves freely inside it; this turns that into the fish
   * moving around the bowl. Scene units per centimetre at gain 1.
   */
  moveGain: number;
  /** Extra sign per position axis, like headSigns. */
  posSigns: { x: number; y: number; z: number };
  /**
   * Slowly re-learn the resting head pose while tracking, so a shifted
   * helmet or a slightly off-centre phone don't leave the fish leaning.
   * Seconds to converge; 0 disables it (use centerHead() instead).
   */
  autoCenter: number;
  /** Exaggeration of the tracked blendshapes (1 = as tracked, 2 = double). */
  expressionGain: number;
  /** Clamp for head rotation in degrees. */
  headLimitDeg: number;
  /** Max eye rotation in radians. */
  eyeRange: number;
  /** Seconds without packets before the fish starts idling. */
  idleAfter: number;
  /** Smoothing rates in 1/s at smoothing 1. Higher is snappier. */
  rateFast: number;
  rateSlow: number;
  /**
   * Overall smoothing: 0 shows the tracked values raw (snappiest, can look
   * jittery), 1 is the original soft feel. The rates are divided by it.
   */
  smoothing: number;
  /**
   * Pucker wins over funnel: funnel is scaled by (1 - puckerPriority * pucker), so a narrow kiss
   * mouth and an open "O" never pull the mouth inward at full strength together (the sides would
   * cross). 0 = off, 1 = full.
   */
  puckerPriority: number;
  /**
   * The performer's resting face: one raw Face Cap value per blendshape, captured with
   * captureNeutral(). Each value is rescaled to (raw - rest) / (1 - rest) before the gain, so the
   * resting face reads 0 everywhere and a full expression still reaches 1. null = off.
   */
  faceNeutral: Float32Array | null;
}

export const DEFAULT_MAPPING: MappingConfig = {
  faceNeutral: null,
  mirror: false,
  headSigns: { pitch: 1, yaw: 1, roll: 1 },
  headGain: 1,
  moveGain: 1,
  posSigns: { x: 1, y: 1, z: 1 },
  autoCenter: 30,
  expressionGain: 1,
  headLimitDeg: 55,
  eyeRange: 0.45,
  idleAfter: 1.5,
  rateFast: 28,
  rateSlow: 14,
  smoothing: 0.3,
  puckerPriority: 1,
};

/** Keys that need to react quickly (blinks, jaw). */
const FAST_KEYS = new Set<PoseKey>([
  'jawOpen',
  'turn',
  'nod',
  'blinkL',
  'blinkR',
  'tongue',
  'eyeYawL',
  'eyePitchL',
  'eyeYawR',
  'eyePitchR',
]);

const FAST_WEIGHTS = new Set<number>([
  BS.jawOpen,
  BS.eyeBlink_L,
  BS.eyeBlink_R,
  BS.tongueOut,
  BS.eyeLookUp_L,
  BS.eyeLookUp_R,
  BS.eyeLookDown_L,
  BS.eyeLookDown_R,
  BS.eyeLookIn_L,
  BS.eyeLookIn_R,
  BS.eyeLookOut_L,
  BS.eyeLookOut_R,
]);

/** A raw value relative to the performer's resting value: rest reads 0, 1 stays 1. */
export function calibrate(raw: number, rest: number): number {
  return rest >= 0.95 ? raw : Math.max(0, (raw - rest) / (1 - rest));
}

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

/** Index of the opposite-side shape for every `_L` / `_R` shape (and mouthLeft/Right, jawLeft/Right), else itself. */
const MIRROR_INDEX: number[] = BLENDSHAPE_NAMES.map((name, i) => {
  const other = name.endsWith('_L')
    ? name.slice(0, -2) + '_R'
    : name.endsWith('_R')
      ? name.slice(0, -2) + '_L'
      : name.endsWith('Left')
        ? name.slice(0, -4) + 'Right'
        : name.endsWith('Right')
          ? name.slice(0, -5) + 'Left'
          : null;
  const j = other ? (BLENDSHAPE_NAMES as readonly string[]).indexOf(other) : -1;
  return j >= 0 ? j : i;
});

/**
 * Turns FaceFrames into a smoothed FishPose, falling back to a gentle idle
 * animation whenever the live data stops.
 */
export class FaceToFishMapper {
  readonly pose: FishPose = createFishPose();
  /** Smoothed 52 blendshape weights in Face Cap order, for morph-target avatars. */
  readonly weights = new Float32Array(BLENDSHAPE_COUNT);
  private readonly target: FishPose = createFishPose();
  private readonly targetWeights = new Float32Array(BLENDSHAPE_COUNT);
  private readonly scaled = new Float32Array(BLENDSHAPE_COUNT);
  private lastPacketTime = -Infinity;
  private nextBlink = 2;
  private blinkPhase = 1;
  /** Resting head pose, in Face Cap units (cm, degrees). */
  private readonly neutralPos = { x: 0, y: 0, z: 0 };
  private readonly neutralRot = { x: 0, y: 0, z: 0 };
  private centered = false;
  private lastFrame: FaceFrame | null = null;
  private dtLive = 0;
  private neutralCapture: { samples: Float32Array[]; live: number; waited: number; seconds: number; done: (rest: Float32Array | null) => void } | null = null;

  constructor(public config: MappingConfig = { ...DEFAULT_MAPPING }) {}

  /** Call whenever the decoder receives a packet. */
  notePacket(now: number): void {
    this.lastPacketTime = now;
  }

  get isLive(): boolean {
    return performance.now() - this.lastPacketTime < this.config.idleAfter * 1000;
  }

  /** Take the current head pose as "at rest": fish centred, facing front. */
  centerHead(): void {
    const f = this.lastFrame;
    if (!f) {
      this.centered = false;
      return;
    }
    Object.assign(this.neutralPos, f.headPosition);
    Object.assign(this.neutralRot, f.headRotation);
    this.centered = true;
  }

  /**
   * Record the performer's resting face over `seconds` of live tracking (the median of each value,
   * so a blink in between doesn't count) and use it as faceNeutral. `done` gets the values, or null
   * if no tracking arrived within 5 seconds.
   */
  captureNeutral(seconds: number, done: (rest: Float32Array | null) => void): void {
    this.neutralCapture = { samples: [], live: 0, waited: 0, seconds, done };
  }

  get capturingNeutral(): boolean {
    return this.neutralCapture !== null;
  }

  private stepNeutralCapture(frame: FaceFrame, live: boolean, dt: number): void {
    const cap = this.neutralCapture;
    if (!cap) return;
    cap.waited += dt;
    if (live) {
      cap.live += dt;
      cap.samples.push(Float32Array.from(frame.weights));
    }
    if (cap.live < cap.seconds && cap.waited < cap.seconds + 5) return;
    this.neutralCapture = null;
    if (cap.samples.length < 5) {
      cap.done(null);
      return;
    }
    const rest = new Float32Array(BLENDSHAPE_COUNT);
    const column = new Float32Array(cap.samples.length);
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      cap.samples.forEach((s, j) => (column[j] = s[i]));
      column.sort();
      rest[i] = column[column.length >> 1];
    }
    this.config.faceNeutral = rest;
    cap.done(rest);
  }

  /**
   * Advance the pose by `dt` seconds toward the frame (if live) or the idle
   * behaviour. `time` is a monotonic clock in seconds for idle motion.
   */
  update(frame: FaceFrame, dt: number, time: number): FishPose {
    const live = this.isLive;
    this.lastFrame = frame;
    this.dtLive = dt;
    this.stepNeutralCapture(frame, live, dt);
    if (live) this.fromFrame(frame);
    else this.idle(time, dt);
    this.target.signal = live ? 1 : 0;

    const s = this.config.smoothing;
    const kFast = s <= 0 ? 1 : 1 - Math.exp((-dt * this.config.rateFast) / s);
    const kSlow = s <= 0 ? 1 : 1 - Math.exp((-dt * this.config.rateSlow) / s);
    for (const key of POSE_KEYS) {
      const k = FAST_KEYS.has(key) ? kFast : kSlow;
      this.pose[key] += (this.target[key] - this.pose[key]) * k;
    }
    // Morph-target avatars: while tracking, every shape follows at the fast
    // rate, so vowels (funnel, pucker, smile) keep up with the jaw. The idle
    // animation keeps the softer split.
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      const k = live || FAST_WEIGHTS.has(i) ? kFast : kSlow;
      this.weights[i] += (this.targetWeights[i] - this.weights[i]) * k;
    }
    return this.pose;
  }

  private fromFrame(frame: FaceFrame): void {
    const t = this.target;
    const c = this.config;
    // Exaggerate (or tone down) every tracked shape before mapping, so the
    // procedural fish and morph-target avatars get the same boost.
    const w = this.scaled;
    const g = c.expressionGain;
    const rest = c.faceNeutral;
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      const raw = rest ? calibrate(frame.weights[i], rest[i]) : frame.weights[i];
      w[i] = clamp(raw * g, 0, 1);
    }
    // Morph-target avatars sculpt `_L` on their own left. Seen from the front
    // that is where the singer's left lands; in a mirror it is the other side.
    if (c.mirror) {
      for (let i = 0; i < BLENDSHAPE_COUNT; i++) this.targetWeights[i] = w[MIRROR_INDEX[i]];
    } else {
      this.targetWeights.set(w);
    }
    const tw = this.targetWeights;
    tw[BS.mouthFunnel] *= 1 - clamp(c.puckerPriority, 0, 1) * tw[BS.mouthPucker];

    // Which tracked side lands on screen-left? In a mirror the person's left
    // is on screen-left. Seen from the front (helmet), their right is.
    const pair = (l: number, r: number): [number, number] => (c.mirror ? [w[l], w[r]] : [w[r], w[l]]);
    // Mirror: person's right appears on screen-right (+x). Front view: person's
    // left is on screen-right.
    const side = c.mirror ? 1 : -1;

    // Mouth. mouthClose is ARKit's "lips together while the jaw is down"
    // (humming, "m"), so it pulls the visible opening back toward closed.
    const jaw = Math.max(w[BS.jawOpen], w[BS.mouthFunnel] * 0.5);
    t.jawOpen = jaw * (1 - w[BS.mouthClose] * 0.85);
    const smile = (w[BS.mouthSmile_L] + w[BS.mouthSmile_R]) * 0.5;
    const frown = (w[BS.mouthFrown_L] + w[BS.mouthFrown_R]) * 0.5;
    t.mouthCorner = clamp(smile - frown, -1, 1);
    // Wide vowels ("ee") stretch the corners without smiling.
    t.mouthStretch = (w[BS.mouthStretch_L] + w[BS.mouthStretch_R]) * 0.5;
    t.jawSide = clamp(w[BS.jawRight] + w[BS.mouthRight] - w[BS.jawLeft] - w[BS.mouthLeft], -1, 1) * side;
    t.tongue = w[BS.tongueOut];
    t.cheekPuff = w[BS.cheekPuff];

    // Eyes. pose.*L is the screen-left eye.
    [t.blinkL, t.blinkR] = pair(BS.eyeBlink_L, BS.eyeBlink_R);
    [t.wideL, t.wideR] = pair(BS.eyeWide_L, BS.eyeWide_R);
    const [inL, inR] = pair(BS.eyeLookIn_L, BS.eyeLookIn_R);
    const [outL, outR] = pair(BS.eyeLookOut_L, BS.eyeLookOut_R);
    const [upL, upR] = pair(BS.eyeLookUp_L, BS.eyeLookUp_R);
    const [downL, downR] = pair(BS.eyeLookDown_L, BS.eyeLookDown_R);
    // The screen-left eye looking "out" always means toward -x, whichever
    // real eye it is, because "out" is away from the nose on either side.
    t.eyeYawL = (inL - outL) * c.eyeRange;
    t.eyeYawR = (outR - inR) * c.eyeRange;
    t.eyePitchL = (downL - upL) * c.eyeRange;
    t.eyePitchR = (downR - upR) * c.eyeRange;

    // Brows
    const [bdL, bdR] = pair(BS.browDown_L, BS.browDown_R);
    const [boL, boR] = pair(BS.browOuterUp_L, BS.browOuterUp_R);
    t.browL = clamp(boL + w[BS.browInnerUp] * 0.5 - bdL, -1, 1);
    t.browR = clamp(boR + w[BS.browInnerUp] * 0.5 - bdR, -1, 1);
    t.browInner = w[BS.browInnerUp];

    // Head, relative to the resting pose. Face Cap sends rotation in
    // degrees and position in centimetres from the phone.
    const p = frame.headPosition;
    const r = frame.headRotation;
    if (!this.centered) this.centerHead();
    if (c.autoCenter > 0) {
      // Slow drift toward the current pose, so the rest position follows
      // the singer without eating deliberate turns and leans.
      const k = 1 - Math.exp(-this.dtLive / c.autoCenter);
      this.neutralPos.x += (p.x - this.neutralPos.x) * k;
      this.neutralPos.y += (p.y - this.neutralPos.y) * k;
      this.neutralPos.z += (p.z - this.neutralPos.z) * k;
      this.neutralRot.x += (r.x - this.neutralRot.x) * k;
      this.neutralRot.y += (r.y - this.neutralRot.y) * k;
      this.neutralRot.z += (r.z - this.neutralRot.z) * k;
    }
    const lim = c.headLimitDeg;
    const yawSign = c.headSigns.yaw * (c.mirror ? -1 : 1);
    const rollSign = c.headSigns.roll * (c.mirror ? -1 : 1);
    t.headPitch = clamp(r.x - this.neutralRot.x, -lim, lim) * DEG * c.headGain * c.headSigns.pitch;
    t.headYaw = clamp(r.y - this.neutralRot.y, -lim, lim) * DEG * c.headGain * yawSign;
    t.headRoll = clamp(r.z - this.neutralRot.z, -lim, lim) * DEG * c.headGain * rollSign;
    t.turn = clamp(r.y - this.neutralRot.y, -lim, lim) * DEG * yawSign;
    t.nod = clamp(r.x - this.neutralRot.x, -lim, lim) * DEG * c.headSigns.pitch;

    // Position: up to ±20 cm of head travel becomes fish travel in the bowl.
    // ARKit's camera looks down -z, so moving toward the phone raises z;
    // that becomes the fish coming toward the viewer.
    const unit = 0.05 * c.moveGain;
    t.headX = clamp(p.x - this.neutralPos.x, -20, 20) * unit * side * c.posSigns.x;
    t.headY = clamp(p.y - this.neutralPos.y, -20, 20) * unit * c.posSigns.y;
    t.headZ = clamp(p.z - this.neutralPos.z, -20, 20) * unit * c.posSigns.z;
  }

  private idle(time: number, dt: number): void {
    const t = this.target;

    // Occasional blinks.
    this.nextBlink -= dt;
    if (this.nextBlink <= 0) {
      this.nextBlink = 2.5 + Math.random() * 3;
      this.blinkPhase = 0;
    }
    this.blinkPhase = Math.min(1, this.blinkPhase + dt * 5);
    const blink = Math.sin(this.blinkPhase * Math.PI);
    t.blinkL = blink;
    t.blinkR = blink;
    t.wideL = 0;
    t.wideR = 0;

    // Fish mouthing the water.
    t.jawOpen = 0.12 + 0.1 * (0.5 + 0.5 * Math.sin(time * 2.1));
    t.mouthCorner = 0.15;
    t.mouthStretch = 0;
    t.pucker = 0.1;
    t.jawSide = 0;
    t.tongue = 0;
    t.cheekPuff = 0;

    // Wandering gaze and gentle drift.
    const gazeYaw = 0.25 * Math.sin(time * 0.45);
    const gazePitch = 0.12 * Math.sin(time * 0.7 + 1);
    t.eyeYawL = t.eyeYawR = gazeYaw;
    t.eyePitchL = t.eyePitchR = gazePitch;
    t.browL = t.browR = 0.1 * Math.sin(time * 0.3);
    t.browInner = 0;
    t.headYaw = 10 * DEG * Math.sin(time * 0.5);
    t.turn = t.headYaw;
    t.nod = t.headPitch;
    t.headPitch = 4 * DEG * Math.sin(time * 0.8 + 2);
    t.headRoll = 4 * DEG * Math.sin(time * 0.35 + 1);
    t.headX = 0.05 * Math.sin(time * 0.4);
    t.headY = 0.04 * Math.sin(time * 0.9);
    t.headZ = 0;

    // Same behaviour expressed as raw blendshapes for morph-target avatars.
    const tw = this.targetWeights;
    tw.fill(0);
    tw[BS.eyeBlink_L] = tw[BS.eyeBlink_R] = blink;
    tw[BS.jawOpen] = t.jawOpen;
    tw[BS.mouthSmile_L] = tw[BS.mouthSmile_R] = t.mouthCorner;
    tw[BS.mouthPucker] = t.pucker;
    tw[BS.eyeLookOut_L] = tw[BS.eyeLookIn_R] = Math.max(0, -gazeYaw);
    tw[BS.eyeLookIn_L] = tw[BS.eyeLookOut_R] = Math.max(0, gazeYaw);
    tw[BS.eyeLookDown_L] = tw[BS.eyeLookDown_R] = Math.max(0, gazePitch);
    tw[BS.eyeLookUp_L] = tw[BS.eyeLookUp_R] = Math.max(0, -gazePitch);
  }
}
