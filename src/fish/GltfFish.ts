import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { BLENDSHAPE_COUNT, BLENDSHAPE_NAMES } from '../facecap/blendshapes';
import type { Avatar } from './Avatar';
import { FinWaves, type RigJson } from './finWave';
import type { FishPose } from './pose';

/**
 * A fish (or anything) modelled in Blender and exported as glTF/GLB.
 *
 * Shape keys become morph targets and are matched to Face Cap blendshapes by
 * name (see `matchBlendshape` for the accepted spellings). Named nodes or
 * bones get extra treatment:
 *
 *   Head            head rotation and drift
 *   Jaw             rotated on X by jawOpen (only if there's no jawOpen shape key)
 *   EyeL / EyeR     rotated by gaze (only if there are no eyeLook* shape keys)
 *   Tail            gentle ambient sway
 *
 * See blender/README.md for the modelling and export conventions.
 */
export class GltfFish implements Avatar {
  readonly root = new THREE.Group();
  /** Drift and framing go here so `root` stays free for the ActionPlayer. */
  private readonly body = new THREE.Group();
  private mixer: THREE.AnimationMixer | null = null;
  private readonly clipMap = new Map<string, THREE.AnimationClip>();
  private activeAction: THREE.AnimationAction | null = null;

  private morphs: { mesh: THREE.Mesh; map: Int16Array }[] = [];
  private head: THREE.Object3D | null = null;
  private jaw: THREE.Object3D | null = null;
  private eyeL: THREE.Object3D | null = null;
  private eyeR: THREE.Object3D | null = null;
  private tail: THREE.Object3D | null = null;
  /** Eyelid bones (or objects) named Lid.L / Lid.R: blinks turn them about their own X axis. */
  private lidL: THREE.Object3D | null = null;
  private lidR: THREE.Object3D | null = null;
  private readonly lidRest = new Map<THREE.Object3D, THREE.Quaternion>();
  private readonly lidTurn = new THREE.Quaternion();
  /** Degrees a lid turns at a full blink. Negative turns the other way. */
  lidAngle = 77;
  /** How far closed the lids sit with no blink (0 = as modelled, 0.3 = 30% of a blink). */
  lidNeutral = 0;
  /**
   * Tail bones Tail.1, Tail.2, ... (root to tip). Each swings about its own X
   * axis, on a spring: bone 1 follows how fast the singer turns their head,
   * every next bone follows the one before it, so turns ripple to the tip
   * and overshoot a little. A slow swim sway runs underneath.
   */
  private readonly tailChain: { bone: THREE.Object3D; rest: THREE.Quaternion; angle: number; vel: number }[] = [];
  private lastTurn: number | null = null;
  private turnRate = 0;
  private lastNod: number | null = null;
  private nodRate = 0;
  /**
   * Side (pectoral) fins: bones Pec.L.1, Pec.L.2, ... and Pec.R.* (Pec.X.0 is a still root anchor).
   * Each bone has two springs: flap about its X axis (+ = up) and sweep about its Z axis. Nods lift
   * both fins; on a turn the inside fin flares forward and the outside one tucks back; at rest they
   * scull gently. Each next bone follows the one before it.
   */
  private readonly pecChains: { side: 1 | -1; links: SpringLink2[] }[] = [];
  /** Strength of the tail's reaction to head turns (negative flips the side). */
  finReaction = 1;
  /** Strength of the idle swim sway. */
  finSway = 1;
  private restRotations = new Map<THREE.Object3D, THREE.Euler>();
  private hasJawShape = false;
  private hasGazeShapes = false;
  /** Where the mouth sits in body space when the model has no Jaw node. */
  private readonly mouthOffset = new THREE.Vector3(0, -0.2, 1.0);
  readonly report: string[] = [];

  /** Face Cap blendshape indices that some mesh in the model has a shape key for. */
  get shapeKeys(): ReadonlySet<number> {
    const set = new Set<number>();
    for (const { map } of this.morphs) {
      map.forEach((idx, bs) => {
        if (idx >= 0) set.add(bs);
      });
    }
    return set;
  }

  static async load(url: string): Promise<GltfFish> {
    const [gltf, rig] = await Promise.all([new GLTFLoader().loadAsync(url), GltfFish.loadRig(url)]);
    const fish = new GltfFish();
    fish.adopt(gltf.scene, gltf.animations);
    fish.finWaves = new FinWaves(gltf.scene, rig);
    fish.report.push(
      fish.finWaves.count
        ? `fin waves: ${fish.finWaves.names.join(', ')} (from ${url.replace(/\.glb$/i, '.rig.json')})`
        : 'fin waves: none (no rig.json, or no fins with a FinWave map)',
    );
    return fish;
  }

  /** The exporter writes <model>.rig.json next to the .glb (fin wave settings, bone names). */
  private static async loadRig(url: string): Promise<RigJson | null> {
    try {
      const res = await fetch(url.replace(/\.glb$/i, '.rig.json'), { cache: 'no-cache' });
      return res.ok ? ((await res.json()) as RigJson) : null;
    } catch {
      return null;
    }
  }

  private finWaves: FinWaves | null = null;

  /** Fin ripple strength multiplier (1 = as tuned in Blender). */
  get finWave(): number {
    return this.finWaves?.amount ?? 1;
  }
  set finWave(v: number) {
    if (this.finWaves) this.finWaves.amount = v;
  }

  /** Fin ripple speed multiplier. */
  get finWaveSpeed(): number {
    return this.finWaves?.speed ?? 1;
  }
  set finWaveSpeed(v: number) {
    if (this.finWaves) this.finWaves.speed = v;
  }

  get clips(): string[] {
    return [...this.clipMap.keys()];
  }

  /** Play an authored clip once (a Blender NLA track exported with the model). */
  playClip(name: string): Promise<void> {
    const clip = this.clipMap.get(name);
    if (!clip || !this.mixer) return Promise.resolve();
    const mixer = this.mixer;
    this.activeAction?.stop();
    const action = mixer.clipAction(clip);
    action.reset();
    action.setLoop(THREE.LoopOnce, 1);
    action.clampWhenFinished = false;
    action.play();
    this.activeAction = action;
    return new Promise((resolve) => {
      const onFinished = (e: { action: THREE.AnimationAction }): void => {
        if (e.action !== action) return;
        mixer.removeEventListener('finished', onFinished);
        action.stop();
        if (this.activeAction === action) this.activeAction = null;
        resolve();
      };
      mixer.addEventListener('finished', onFinished);
    });
  }

  private adopt(scene: THREE.Group, animations: THREE.AnimationClip[]): void {
    this.root.add(this.body);
    this.body.add(scene);

    if (animations.length > 0) {
      this.mixer = new THREE.AnimationMixer(scene);
      for (const clip of animations) {
        // A clip called "swim" or "idle" loops forever underneath everything else (fins
        // sculling to hold the fish in place); it is not offered as a triggerable action.
        if (/^(swim|idle)$/i.test(clip.name)) {
          const loop = this.mixer.clipAction(clip);
          loop.setLoop(THREE.LoopRepeat, Infinity);
          loop.play();
          this.report.push(`idle loop: ${clip.name} (${clip.duration.toFixed(2)} s)`);
          continue;
        }
        this.clipMap.set(clip.name, clip);
      }
      if (this.clipMap.size > 0) this.report.push(`clips: ${[...this.clipMap.keys()].join(', ')}`);
    }

    // Normalise size: fit the model into roughly the same box as the procedural fish.
    const box = new THREE.Box3().setFromObject(scene);
    const size = new THREE.Vector3();
    box.getSize(size);
    const largest = Math.max(size.x, size.y, size.z) || 1;
    const scale = 2.4 / largest;
    scene.scale.setScalar(scale);
    const center = new THREE.Vector3();
    box.getCenter(center);
    scene.position.sub(center.multiplyScalar(scale));
    // Nose is toward +z by convention; put the mouth low on the front face.
    this.mouthOffset.set(0, -size.y * scale * 0.15, size.z * scale * 0.5);

    // A skinned mesh ignores its own node transform (bones place every vertex),
    // so a mesh named "Head" in a rigged model can't be turned by rotating it.
    // Skip those; without a Head bone the whole model turns instead.
    const isSkinned = (obj: THREE.Object3D): boolean =>
      (obj as THREE.SkinnedMesh).isSkinnedMesh === true ||
      obj.children.some((c) => (c as THREE.SkinnedMesh).isSkinnedMesh === true);
    const tailBones: [number, THREE.Object3D][] = [];
    const pecBones: [string, number, THREE.Object3D][] = [];
    scene.traverse((obj) => {
      const name = obj.name.toLowerCase();
      if (!this.head && /^(head|fishhead|face)$/.test(name) && !isSkinned(obj)) this.head = obj;
      if (!this.jaw && /^(jaw|lowerjaw|mouth)$/.test(name) && !isSkinned(obj)) this.jaw = obj;
      if (!this.eyeL && /^(eyel|eye_l|eyeleft|lefteye|eye\.l)$/.test(name)) this.eyeL = obj;
      if (!this.eyeR && /^(eyer|eye_r|eyeright|righteye|eye\.r)$/.test(name)) this.eyeR = obj;
      if (!this.tail && /^(tail|tailfin)$/.test(name)) this.tail = obj;
      // three.js drops the dot from node names ("Lid.L" arrives as "LidL").
      if (!this.lidL && /^lid[._]?l$/.test(name)) this.lidL = obj;
      if (!this.lidR && /^lid[._]?r$/.test(name)) this.lidR = obj;
      const tailMatch = /^tail[._]?(\d+)$/.exec(name);
      if (tailMatch) tailBones.push([Number(tailMatch[1]), obj]);
      const pecMatch = /^pec[._]?([lr])[._]?(\d+)$/.exec(name);
      if (pecMatch && Number(pecMatch[2]) > 0) pecBones.push([pecMatch[1], Number(pecMatch[2]), obj]);

      if (obj instanceof THREE.Mesh && obj.morphTargetDictionary && obj.morphTargetInfluences) {
        const map = new Int16Array(BLENDSHAPE_COUNT).fill(-1);
        let matched = 0;
        for (const [key, index] of Object.entries(obj.morphTargetDictionary)) {
          const bs = matchBlendshape(key);
          if (bs >= 0) {
            map[bs] = index;
            matched++;
          }
        }
        if (matched > 0) {
          this.morphs.push({ mesh: obj, map });
          this.report.push(`${obj.name || 'mesh'}: ${matched} of ${Object.keys(obj.morphTargetDictionary).length} shape keys matched`);
          if (map[BLENDSHAPE_NAMES.indexOf('jawOpen')] >= 0) this.hasJawShape = true;
          if (map[BLENDSHAPE_NAMES.indexOf('eyeLookUp_L')] >= 0) this.hasGazeShapes = true;
        }
      }
    });

    let tris = 0;
    let verts = 0;
    scene.traverse((obj) => {
      if (obj instanceof THREE.Mesh) {
        const g = obj.geometry as THREE.BufferGeometry;
        verts += g.attributes.position?.count ?? 0;
        tris += g.index ? g.index.count / 3 : (g.attributes.position?.count ?? 0) / 3;
      }
    });
    this.report.push(`${Math.round(tris)} triangles, ${verts} vertices (aim for 20-40k triangles)`);

    for (const obj of [this.head, this.jaw, this.eyeL, this.eyeR, this.tail]) {
      if (obj) this.restRotations.set(obj, obj.rotation.clone());
    }
    tailBones.sort((a, b) => a[0] - b[0]);
    for (const [, bone] of tailBones) {
      this.tailChain.push({ bone, rest: bone.quaternion.clone(), angle: 0, vel: 0 });
    }
    if (this.tailChain.length) {
      this.report.push(`tail chain: ${this.tailChain.map((t) => t.bone.name).join(' > ')} (springs on head turns)`);
    }
    for (const sideName of ['l', 'r']) {
      const bones = pecBones.filter((b) => b[0] === sideName).sort((a, b) => a[1] - b[1]);
      if (!bones.length) continue;
      this.pecChains.push({
        side: sideName === 'l' ? 1 : -1,
        links: bones.map(([, , bone]) => ({ bone, rest: bone.quaternion.clone(), flap: 0, flapVel: 0, sweep: 0, sweepVel: 0 })),
      });
      this.report.push(`side fin ${sideName.toUpperCase()}: ${bones.map((b) => b[2].name).join(' > ')} (springs on nods and turns)`);
    }
    for (const lid of [this.lidL, this.lidR]) {
      if (lid) this.lidRest.set(lid, lid.quaternion.clone());
    }
    if (this.lidL || this.lidR) {
      this.report.push(`lids: ${this.lidL?.name ?? '-'}/${this.lidR?.name ?? '-'} (turn about their own X on blink)`);
    }
    if (!this.head) this.head = scene;

    this.report.push(
      `nodes: head=${this.head?.name || '(root)'} jaw=${this.jaw?.name ?? '-'} eyes=${this.eyeL?.name ?? '-'}/${this.eyeR?.name ?? '-'} tail=${this.tail?.name ?? '-'}`,
    );
    if (this.morphs.length === 0) {
      this.report.push('warning: no shape keys matched Face Cap names; only bones/nodes will move');
    }
  }

  mouthPosition(target: THREE.Vector3): THREE.Vector3 {
    // The jaw if the model has one, else the front of the head's bounds.
    if (this.jaw) return this.jaw.getWorldPosition(target);
    this.body.getWorldPosition(target);
    return target.add(this.mouthOffset.clone().applyQuaternion(this.body.getWorldQuaternion(new THREE.Quaternion())));
  }

  update(pose: FishPose, weights: Float32Array, time: number, dt: number): void {
    this.mixer?.update(dt);
    this.finWaves?.update(dt, pose.jawOpen);

    for (const { mesh, map } of this.morphs) {
      const inf = mesh.morphTargetInfluences!;
      for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
        const idx = map[i];
        if (idx >= 0) inf[idx] = weights[i];
      }
    }

    if (this.head) {
      const rest = this.restRotations.get(this.head);
      const e = new THREE.Euler(pose.headPitch, pose.headYaw, pose.headRoll, 'YXZ');
      if (rest) {
        // Turn about the parent's (upright) axes, not the Head's own: a Blender
        // Head is often rotated 90° on X, and turning in its own axes made a
        // head turn roll the fish.
        this.head.quaternion.setFromEuler(e).multiply(new THREE.Quaternion().setFromEuler(rest));
      } else {
        this.head.rotation.copy(e);
      }
    }
    this.body.position.set(pose.headX, pose.headY + Math.sin(time * 0.9) * 0.03, pose.headZ);

    if (this.jaw && !this.hasJawShape) {
      const rest = this.restRotations.get(this.jaw)!;
      this.jaw.rotation.set(rest.x + pose.jawOpen * 0.5, rest.y, rest.z);
    }
    if (!this.hasGazeShapes) {
      // pose.*L is the eye on the LEFT OF THE SCREEN. The fish faces the viewer,
      // so that is its right eye (Eye.R), and the screen-right eye is Eye.L.
      if (this.eyeL) {
        const rest = this.restRotations.get(this.eyeL)!;
        this.eyeL.rotation.set(rest.x + pose.eyePitchR, rest.y + pose.eyeYawR, rest.z);
      }
      if (this.eyeR) {
        const rest = this.restRotations.get(this.eyeR)!;
        this.eyeR.rotation.set(rest.x + pose.eyePitchL, rest.y + pose.eyeYawL, rest.z);
      }
    }
    // Lids: a blink turns each lid about its own X axis by up to lidAngle; a
    // squint closes it part way, wide eyes open it a little past the modelled lid.
    // With no blink the lid sits lidNeutral of the way closed.
    // `weights` are already mirrored, smoothed and gained, so _L is the fish's left.
    for (const [lid, blink, squint, wide] of [
      [this.lidL, BS_BLINK_L, BS_SQUINT_L, BS_WIDE_L],
      [this.lidR, BS_BLINK_R, BS_SQUINT_R, BS_WIDE_R],
    ] as const) {
      if (!lid) continue;
      const amount = Math.max(-0.3, Math.min(1, weights[blink] + 0.35 * weights[squint] - 0.25 * weights[wide]));
      this.lidTurn.setFromAxisAngle(X_AXIS, THREE.MathUtils.degToRad(this.lidAngle * lidClosed(amount, this.lidNeutral)));
      lid.quaternion.copy(this.lidRest.get(lid)!).multiply(this.lidTurn);
    }
    this.updateRates(pose, dt);
    this.updateTail(pose, time, dt);
    this.updateSideFins(pose, time, dt);
    if (this.tail) {
      const rest = this.restRotations.get(this.tail)!;
      const energy = 0.6 + pose.jawOpen * 1.2;
      this.tail.rotation.set(rest.x, rest.y + Math.sin(time * 4.2) * 0.3 * energy, rest.z);
    }
  }

  /** How fast the singer turns and nods their head (rad/s), lightly smoothed. Drives the fin springs. */
  private updateRates(pose: FishPose, dt: number): void {
    if (dt <= 0) return;
    if (this.lastTurn === null) this.lastTurn = pose.turn;
    if (this.lastNod === null) this.lastNod = pose.nod;
    const k = 1 - Math.exp(-dt * 18);
    this.turnRate += ((pose.turn - this.lastTurn) / dt - this.turnRate) * k;
    this.nodRate += ((pose.nod - this.lastNod) / dt - this.nodRate) * k;
    this.lastTurn = pose.turn;
    this.lastNod = pose.nod;
  }

  private updateSideFins(pose: FishPose, time: number, dt: number): void {
    if (this.pecChains.length === 0 || dt <= 0) return;

    const k = this.finReaction;
    const flapTarget = THREE.MathUtils.clamp(this.nodRate * 0.3 * k, -0.6, 0.6); // head dips -> fins lift
    const stiffness = 55;
    const damping = 2 * 0.35 * Math.sqrt(stiffness);
    const steps = Math.max(1, Math.ceil(dt / (1 / 120)));
    const h = dt / steps;
    const energy = 0.6 + Math.min(1, pose.jawOpen) * 1.2;
    for (const chain of this.pecChains) {
      // Turning toward this fin's side (turnRate > 0 is toward the fish's left): it flares
      // forward like a brake; the other fin tucks back. "Forward" is -Z on the left fin, +Z on the right.
      const forward = THREE.MathUtils.clamp(chain.side * this.turnRate * 0.3 * k, -0.6, 0.6);
      const sweepTarget = -chain.side * forward;
      for (let s = 0; s < steps; s++) {
        let tf = flapTarget;
        let ts = sweepTarget;
        for (const l of chain.links) {
          l.flapVel += (stiffness * (tf - l.flap) - damping * l.flapVel) * h;
          l.flap += l.flapVel * h;
          l.sweepVel += (stiffness * (ts - l.sweep) - damping * l.sweepVel) * h;
          l.sweep += l.sweepVel * h;
          tf = l.flap;
          ts = l.sweep;
        }
      }
      // Gentle sculling at rest: flap with a little feathering, the right fin a bit behind the left.
      const phase = chain.side === 1 ? 0 : 0.5;
      chain.links.forEach((l, i) => {
        const a = time * 5.6 + phase - i * 0.7;
        const flap = l.flap + 0.14 * this.finSway * energy * Math.sin(a);
        const sweep = l.sweep - chain.side * 0.08 * this.finSway * energy * Math.sin(a + 1.2);
        this.lidTurn.setFromAxisAngle(X_AXIS, flap);
        this.finTurn.setFromAxisAngle(Z_AXIS, sweep);
        l.bone.quaternion.copy(l.rest).multiply(this.lidTurn).multiply(this.finTurn);
      });
    }
  }

  private readonly finTurn = new THREE.Quaternion();

  private updateTail(pose: FishPose, time: number, dt: number): void {
    if (this.tailChain.length === 0 || dt <= 0) return;

    // Bone 1 lags behind the turn: it bends toward the side the head turns
    // to (a positive bone turn swings the tail to the fish's right), up to ~45°.
    const target0 = THREE.MathUtils.clamp(-this.turnRate * 0.35 * this.finReaction, -0.8, 0.8);
    const stiffness = 70;
    const damping = 2 * 0.32 * Math.sqrt(stiffness); // under-damped: a small overshoot
    const steps = Math.max(1, Math.ceil(dt / (1 / 120)));
    const h = dt / steps;
    for (let s = 0; s < steps; s++) {
      let target = target0;
      for (const link of this.tailChain) {
        const acc = stiffness * (target - link.angle) - damping * link.vel;
        link.vel += acc * h;
        link.angle += link.vel * h;
        target = link.angle; // the next bone follows this one
      }
    }

    // Swim sway, a travelling wave along the chain; livelier while singing.
    const energy = 0.6 + Math.min(1, pose.jawOpen) * 1.2;
    this.tailChain.forEach((link, i) => {
      const sway = 0.1 * this.finSway * energy * Math.sin(time * 4.2 - i * 0.9);
      this.lidTurn.setFromAxisAngle(X_AXIS, link.angle + sway);
      link.bone.quaternion.copy(link.rest).multiply(this.lidTurn);
    });
  }
}

/**
 * Map a shape key name to a Face Cap blendshape index, or -1. Accepts the
 * Face Cap spelling (`eyeBlink_L`), the ARKit spelling (`eyeBlinkLeft`),
 * Blender-style suffixes (`eyeBlink.L`, `eyeBlink-L`), and ignores case.
 */
export function matchBlendshape(key: string): number {
  const norm = normalise(key);
  const hit = NORMALISED.get(norm);
  return hit === undefined ? -1 : hit;
}

function normalise(key: string): string {
  // Blender-style suffixes: "eyeBlink.L", "eyeBlink-L", "eyeBlink L" → "eyeblink_l".
  return key.trim().toLowerCase().replace(/[.\-\s]+([lr])$/, '_$1');
}

/**
 * How far closed a lid is (1 = full blink, 0 = as modelled) for a blink amount in -0.3..1:
 * 0 sits at `neutral`, 1 closes fully, -0.3 (wide eyes) opens to 0.3 past the modelled lid.
 */
export function lidClosed(amount: number, neutral: number): number {
  return amount >= 0 ? neutral + (1 - neutral) * amount : neutral + (amount * (neutral + 0.3)) / 0.3;
}

const X_AXIS = new THREE.Vector3(1, 0, 0);
const Z_AXIS = new THREE.Vector3(0, 0, 1);

/** One bone of a side fin: two springs (flap about X, sweep about Z). */
interface SpringLink2 {
  bone: THREE.Object3D;
  rest: THREE.Quaternion;
  flap: number;
  flapVel: number;
  sweep: number;
  sweepVel: number;
}
const BS_BLINK_L = BLENDSHAPE_NAMES.indexOf('eyeBlink_L');
const BS_BLINK_R = BLENDSHAPE_NAMES.indexOf('eyeBlink_R');
const BS_SQUINT_L = BLENDSHAPE_NAMES.indexOf('eyeSquint_L');
const BS_SQUINT_R = BLENDSHAPE_NAMES.indexOf('eyeSquint_R');
const BS_WIDE_L = BLENDSHAPE_NAMES.indexOf('eyeWide_L');
const BS_WIDE_R = BLENDSHAPE_NAMES.indexOf('eyeWide_R');

const NORMALISED = new Map<string, number>();
BLENDSHAPE_NAMES.forEach((name, i) => {
  NORMALISED.set(normalise(name), i);
  // ARKit spelling: eyeBlink_L → eyeBlinkLeft.
  if (name.endsWith('_L')) NORMALISED.set(normalise(name.slice(0, -2) + 'Left'), i);
  if (name.endsWith('_R')) NORMALISED.set(normalise(name.slice(0, -2) + 'Right'), i);
});
