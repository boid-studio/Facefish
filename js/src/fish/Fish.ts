import * as THREE from 'three';
import type { Avatar } from './Avatar';
import type { FishPose } from './pose';

/**
 * A procedural cartoon fish that faces the camera (+z) and is driven by a
 * FishPose. Everything is built from primitives so no asset pipeline is
 * needed; swap this class for a glTF-based one later if you get a model.
 */
export class Fish implements Avatar {
  readonly root = new THREE.Group();

  private readonly head = new THREE.Group();
  private readonly body: THREE.Mesh;
  private readonly mouth = new THREE.Group();
  private readonly cavity: THREE.Mesh;
  private readonly upperLip: THREE.Mesh;
  private readonly jaw = new THREE.Group();
  private readonly tongue: THREE.Mesh;
  private readonly eyeL: EyeParts;
  private readonly eyeR: EyeParts;
  private readonly browL: THREE.Mesh;
  private readonly browR: THREE.Mesh;
  private readonly tail: THREE.Mesh;
  private readonly finL: THREE.Mesh;
  private readonly finR: THREE.Mesh;
  private readonly dorsal: THREE.Mesh;

  private readonly bodyScale = new THREE.Vector3(0.9, 0.75, 1.2);

  constructor() {
    const skin = new THREE.MeshStandardMaterial({
      color: 0xff8a3d,
      roughness: 0.55,
      metalness: 0.05,
    });
    // The body carries a vertex-colour gradient (orange back, pale belly);
    // every other part uses the plain material so the tint stays neutral.
    const bodySkin = skin.clone();
    bodySkin.color.set(0xffffff);
    bodySkin.vertexColors = true;
    const finMat = new THREE.MeshStandardMaterial({
      color: 0xffb35c,
      roughness: 0.6,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.92,
    });
    const lipMat = new THREE.MeshStandardMaterial({ color: 0xe6642a, roughness: 0.5 });
    const cavityMat = new THREE.MeshStandardMaterial({ color: 0x3a0a12, roughness: 0.9 });
    const tongueMat = new THREE.MeshStandardMaterial({ color: 0xe8657a, roughness: 0.7 });

    this.root.add(this.head);

    // Body: an ellipsoid, nose toward +z.
    this.body = new THREE.Mesh(paintBelly(new THREE.SphereGeometry(1, 48, 32)), bodySkin);
    this.body.scale.copy(this.bodyScale);
    this.head.add(this.body);


    // Mouth assembly sits on the lower front of the head.
    this.mouth.position.set(0, -0.22, 1.02);
    this.head.add(this.mouth);

    this.cavity = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16), cavityMat);
    this.cavity.scale.set(0.36, 0.02, 0.2);
    this.mouth.add(this.cavity);

    this.upperLip = new THREE.Mesh(new THREE.TorusGeometry(0.36, 0.05, 12, 32, Math.PI), lipMat);
    this.upperLip.scale.set(1, 0.32, 1);
    this.upperLip.position.set(0, 0.03, 0.18);
    this.mouth.add(this.upperLip);

    this.jaw.position.set(0, 0, 0);
    this.mouth.add(this.jaw);

    const lowerLip = new THREE.Mesh(new THREE.TorusGeometry(0.36, 0.05, 12, 32, Math.PI), lipMat);
    lowerLip.rotation.z = Math.PI;
    lowerLip.scale.set(1, 0.32, 1);
    lowerLip.position.set(0, -0.03, 0.18);
    this.jaw.add(lowerLip);

    const chin = new THREE.Mesh(
      new THREE.SphereGeometry(1, 32, 16, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2),
      skin,
    );
    chin.scale.set(0.42, 0.26, 0.36);
    chin.position.set(0, -0.02, -0.02);
    this.jaw.add(chin);

    this.tongue = new THREE.Mesh(new THREE.SphereGeometry(1, 24, 12), tongueMat);
    this.tongue.scale.set(0.18, 0.06, 0.24);
    this.tongue.position.set(0, -0.05, 0.05);
    this.jaw.add(this.tongue);

    // Eyes. `L` is on screen-left (-x), matching the mirrored user.
    this.eyeL = makeEye(skin);
    this.eyeL.group.position.set(-0.45, 0.22, 0.92);
    this.head.add(this.eyeL.group);
    this.eyeR = makeEye(skin);
    this.eyeR.group.position.set(0.45, 0.22, 0.92);
    this.head.add(this.eyeR.group);

    // Brows: little tilted ridges above the eyes.
    const browGeo = new THREE.CapsuleGeometry(0.045, 0.22, 6, 12);
    const browMat = new THREE.MeshStandardMaterial({ color: 0xd9531e, roughness: 0.6 });
    this.browL = new THREE.Mesh(browGeo, browMat);
    this.browL.rotation.z = Math.PI / 2;
    this.head.add(this.browL);
    this.browR = new THREE.Mesh(browGeo, browMat);
    this.browR.rotation.z = Math.PI / 2;
    this.head.add(this.browR);

    // Fins and tail.
    this.tail = new THREE.Mesh(makeTailGeometry(), finMat);
    this.tail.position.set(0, 0, -1.15);
    this.head.add(this.tail);

    this.dorsal = new THREE.Mesh(makeDorsalGeometry(), finMat);
    this.dorsal.position.set(0, 0.55, -0.1);
    this.head.add(this.dorsal);

    this.finL = new THREE.Mesh(makePectoralGeometry(), finMat);
    this.finL.position.set(-0.8, -0.2, 0.35);
    this.finL.rotation.set(0, Math.PI / 2 + 0.4, -0.3);
    this.head.add(this.finL);

    this.finR = new THREE.Mesh(makePectoralGeometry(), finMat);
    this.finR.position.set(0.8, -0.2, 0.35);
    this.finR.rotation.set(0, -Math.PI / 2 - 0.4, 0.3);
    this.finR.scale.x = -1;
    this.head.add(this.finR);

    this.root.traverse((o) => {
      if (o instanceof THREE.Mesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
  }

  mouthPosition(target: THREE.Vector3): THREE.Vector3 {
    return this.cavity.getWorldPosition(target);
  }

  /** Apply a pose. `time` in seconds drives ambient fin and tail motion. */
  update(pose: FishPose, _weights: Float32Array, time: number, _dt: number): void {
    // Head orientation and drift.
    this.head.rotation.set(pose.headPitch, pose.headYaw, pose.headRoll, 'YXZ');
    this.head.position.set(pose.headX, pose.headY + Math.sin(time * 0.9) * 0.03, pose.headZ);

    // Cheeks.
    const puff = 1 + pose.cheekPuff * 0.12;
    this.body.scale.set(this.bodyScale.x * puff, this.bodyScale.y, this.bodyScale.z * (1 + pose.cheekPuff * 0.05));

    // Mouth: open the cavity, drop the jaw, shape the lips.
    const open = pose.jawOpen;
    const width = 1 + pose.mouthCorner * 0.28 + pose.mouthStretch * 0.2 - pose.pucker * 0.45;
    const lift = pose.mouthCorner * 0.05;
    const forward = pose.pucker * 0.18;

    this.mouth.position.set(pose.jawSide * 0.08, -0.22 + lift, 1.02 + forward);
    this.mouth.scale.set(width, 1, 1);

    const gap = 0.03 + open * 0.34;
    this.cavity.scale.set(0.36, gap, 0.2);
    this.cavity.position.y = -gap * 0.5 + 0.02;

    this.jaw.position.y = -gap;
    this.jaw.rotation.x = open * 0.35;
    this.jaw.rotation.y = pose.jawSide * 0.15;

    this.upperLip.scale.y = 0.32 + pose.pucker * 0.5;
    const tongueVis = Math.min(1, Math.max(0, (open - 0.28) / 0.2));
    this.tongue.visible = tongueVis > 0;
    this.tongue.position.z = 0.05 + pose.tongue * 0.3;
    this.tongue.scale.set(0.18 * tongueVis, 0.06 + pose.tongue * 0.03, (0.24 + pose.tongue * 0.12) * tongueVis);

    // Eyes.
    applyEye(this.eyeL, pose.blinkL, pose.wideL, pose.eyeYawL, pose.eyePitchL);
    applyEye(this.eyeR, pose.blinkR, pose.wideR, pose.eyeYawR, pose.eyePitchR);

    // Brows.
    this.browL.position.set(-0.45, 0.47 + pose.browL * 0.08, 0.8);
    this.browL.rotation.z = Math.PI / 2 - 0.15 - pose.browInner * 0.35 + pose.browL * 0.1;
    this.browR.position.set(0.45, 0.47 + pose.browR * 0.08, 0.8);
    this.browR.rotation.z = Math.PI / 2 + 0.15 + pose.browInner * 0.35 - pose.browR * 0.1;

    // Ambient fin motion. Talking makes the tail beat harder.
    const energy = 0.6 + pose.jawOpen * 1.2;
    this.tail.rotation.y = Math.sin(time * 4.2) * 0.35 * energy;
    this.dorsal.rotation.y = Math.sin(time * 4.2 + 0.6) * 0.08;
    const flap = Math.sin(time * 3.1) * 0.25;
    this.finL.rotation.z = -0.3 + flap;
    this.finR.rotation.z = 0.3 - flap;
  }
}

interface EyeParts {
  group: THREE.Group;
  ball: THREE.Group;
  lid: THREE.Mesh;
}

function makeEye(skin: THREE.Material): EyeParts {
  const group = new THREE.Group();
  const r = 0.21;

  const white = new THREE.Mesh(
    new THREE.SphereGeometry(r, 32, 24),
    new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.35 }),
  );
  group.add(white);

  const ball = new THREE.Group();
  group.add(ball);

  const iris = new THREE.Mesh(
    new THREE.SphereGeometry(0.115, 24, 16),
    new THREE.MeshStandardMaterial({ color: 0x1f6fd1, roughness: 0.4 }),
  );
  iris.position.z = r - 0.06;
  iris.scale.z = 0.55;
  ball.add(iris);

  const pupil = new THREE.Mesh(
    new THREE.SphereGeometry(0.06, 20, 14),
    new THREE.MeshStandardMaterial({ color: 0x0a0a12, roughness: 0.3 }),
  );
  pupil.position.z = r + 0.005;
  pupil.scale.z = 0.4;
  ball.add(pupil);

  const glint = new THREE.Mesh(
    new THREE.SphereGeometry(0.03, 12, 8),
    new THREE.MeshBasicMaterial({ color: 0xffffff }),
  );
  glint.position.set(0.045, 0.05, r + 0.03);
  ball.add(glint);

  // Eyelid: a hemisphere cap that swings from the top (open) to the front (closed).
  const lid = new THREE.Mesh(
    new THREE.SphereGeometry(r + 0.015, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2),
    skin,
  );
  group.add(lid);

  return { group, ball, lid };
}

function applyEye(eye: EyeParts, blink: number, wide: number, yaw: number, pitch: number): void {
  eye.ball.rotation.set(pitch, yaw, 0, 'YXZ');
  // -0.35 rad shows a sliver of lid at rest; wide tilts it back, blink swings it over the front.
  const rest = -0.35 - wide * 0.4;
  eye.lid.rotation.x = rest + (Math.PI / 2 + 0.25 - rest) * blink;
}

function makeTailGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(0, 0);
  s.quadraticCurveTo(-0.25, 0.4, -0.75, 0.55);
  s.quadraticCurveTo(-0.45, 0.35, -0.5, 0);
  s.quadraticCurveTo(-0.45, -0.35, -0.75, -0.55);
  s.quadraticCurveTo(-0.25, -0.4, 0, 0);
  const geo = new THREE.ShapeGeometry(s, 12);
  // Shape lies in XY; rotate so it trails along -z and fans in Y.
  geo.rotateY(Math.PI / 2);
  return geo;
}

function makeDorsalGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-0.45, 0);
  s.quadraticCurveTo(-0.2, 0.55, 0.2, 0.5);
  s.quadraticCurveTo(0.35, 0.3, 0.55, 0);
  s.lineTo(-0.45, 0);
  const geo = new THREE.ShapeGeometry(s, 10);
  geo.rotateY(-Math.PI / 2);
  return geo;
}

function makePectoralGeometry(): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(0, 0.12);
  s.quadraticCurveTo(0.35, 0.2, 0.55, -0.05);
  s.quadraticCurveTo(0.35, -0.2, 0, -0.12);
  s.lineTo(0, 0.12);
  return new THREE.ShapeGeometry(s, 10);
}

/** Vertex colours: orange on top blending to a pale belly underneath. */
function paintBelly(geo: THREE.BufferGeometry): THREE.BufferGeometry {
  const pos = geo.getAttribute('position');
  const colors = new Float32Array(pos.count * 3);
  const top = new THREE.Color(0xff8a3d);
  const belly = new THREE.Color(0xffd9a8);
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i); // -1..1 on the unit sphere
    const t = smoothstep(-0.15, -0.75, y);
    c.copy(top).lerp(belly, t);
    colors[i * 3] = c.r;
    colors[i * 3 + 1] = c.g;
    colors[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  return geo;
}

function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}
