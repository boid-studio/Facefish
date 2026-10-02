import * as THREE from 'three';

/**
 * Bubbles that come from the fish itself: a trickle while it talks, a trail
 * when it swims (actions), and a puff whenever the mouth snaps open. Kept as
 * one point cloud with a pool of particles, so it costs one draw call.
 */
export class MotionBubbles {
  readonly points: THREE.Points;
  /** Global multiplier from the control panel (0 = off). */
  amount = 1;

  private readonly max: number;
  private readonly pos: Float32Array;
  private readonly vel: Float32Array;
  private readonly size: Float32Array;
  private readonly life: Float32Array;
  private readonly age: Float32Array;
  private readonly maxAge: Float32Array;
  private readonly seed: Float32Array;
  private readonly sizeAttr: THREE.BufferAttribute;
  private readonly lifeAttr: THREE.BufferAttribute;
  private readonly posAttr: THREE.BufferAttribute;
  private readonly material: THREE.ShaderMaterial;
  private next = 0;
  private acc = 0;
  private prevJaw = 0;
  private lastPuff = -10;
  private readonly prevPos = new THREE.Vector3();
  private hasPrev = false;
  private readonly velocity = new THREE.Vector3();

  constructor(max = 400) {
    this.max = max;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.size = new Float32Array(max);
    this.life = new Float32Array(max);
    this.age = new Float32Array(max);
    this.maxAge = new Float32Array(max);
    this.seed = new Float32Array(max);
    for (let i = 0; i < max; i++) {
      this.pos[i * 3 + 1] = -100;
      this.seed[i] = Math.random() * 100;
    }

    const geo = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(this.pos, 3);
    this.sizeAttr = new THREE.BufferAttribute(this.size, 1);
    this.lifeAttr = new THREE.BufferAttribute(this.life, 1);
    geo.setAttribute('position', this.posAttr);
    geo.setAttribute('size', this.sizeAttr);
    geo.setAttribute('life', this.lifeAttr);

    this.material = new THREE.ShaderMaterial({
      uniforms: {
        scale: { value: 400 },
        color: { value: new THREE.Color(0xd6f1ff) },
      },
      vertexShader: /* glsl */ `
        attribute float size;
        attribute float life;
        uniform float scale;
        varying float vLife;
        void main() {
          vLife = life;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = life > 0.0 ? size * scale / -mv.z : 0.0;
          gl_Position = projectionMatrix * mv;
        }
      `,
      fragmentShader: /* glsl */ `
        precision highp float;
        uniform vec3 color;
        varying float vLife;
        void main() {
          vec2 p = gl_PointCoord - 0.5;
          float r = length(p);
          if (r > 0.5) discard;
          // Thin bright rim, faint centre, one glint up-left.
          float rim = smoothstep(0.5, 0.36, r) * smoothstep(0.22, 0.42, r);
          float fill = smoothstep(0.5, 0.0, r) * 0.18;
          float glint = smoothstep(0.17, 0.0, length(p - vec2(-0.15, -0.15)));
          float a = (rim * 0.7 + fill + glint * 0.9) * vLife;
          gl_FragColor = vec4(color, a);
        }
      `,
      transparent: true,
      depthWrite: false,
      blending: THREE.NormalBlending,
    });

    this.points = new THREE.Points(geo, this.material);
    this.points.frustumCulled = false;
    this.points.renderOrder = 2;
  }

  /** Call on resize: point size in pixels per world unit at z = 1. */
  setScale(viewportHeightPx: number, fovDeg: number, pixelRatio: number): void {
    this.material.uniforms.scale.value = (viewportHeightPx * pixelRatio) / (2 * Math.tan((fovDeg * Math.PI) / 360));
  }

  /**
   * Feed the mouth's world position and how open it is; the emitter works
   * out the speed itself. Call once per frame before `update`.
   */
  pump(dt: number, mouth: THREE.Vector3, jawOpen: number, time: number): void {
    if (dt <= 0) return;
    if (this.hasPrev) {
      this.velocity.subVectors(mouth, this.prevPos).divideScalar(dt);
    } else {
      this.velocity.set(0, 0, 0);
      this.hasPrev = true;
    }
    this.prevPos.copy(mouth);
    const speed = Math.min(6, this.velocity.length());
    const dJaw = (jawOpen - this.prevJaw) / dt;
    this.prevJaw = jawOpen;

    if (this.amount <= 0) return;
    // Trickle while the mouth is open, trail while moving.
    const rate = jawOpen * 5 + speed * 14;
    this.acc += rate * this.amount * dt;
    // A puff when the mouth snaps open.
    if (dJaw > 2.5 && time - this.lastPuff > 0.3) {
      this.lastPuff = time;
      this.acc += (4 + jawOpen * 6) * this.amount;
    }
    while (this.acc >= 1) {
      this.acc -= 1;
      this.spawn(mouth, this.velocity, jawOpen);
    }
  }

  private spawn(at: THREE.Vector3, vel: THREE.Vector3, jawOpen: number): void {
    const i = this.next;
    this.next = (this.next + 1) % this.max;
    const spread = 0.05 + jawOpen * 0.06;
    this.pos[i * 3] = at.x + (Math.random() - 0.5) * spread;
    this.pos[i * 3 + 1] = at.y + (Math.random() - 0.5) * spread;
    this.pos[i * 3 + 2] = at.z + (Math.random() - 0.5) * spread + 0.05;
    // Inherit some of the fish's motion, then drift up.
    this.vel[i * 3] = vel.x * 0.3 + (Math.random() - 0.5) * 0.35;
    this.vel[i * 3 + 1] = vel.y * 0.3 + 0.15 + Math.random() * 0.3;
    this.vel[i * 3 + 2] = vel.z * 0.3 + 0.1 + Math.random() * 0.3;
    this.size[i] = 0.025 + Math.random() * 0.05;
    this.age[i] = 0;
    this.maxAge[i] = 1.6 + Math.random() * 1.8;
    this.life[i] = 0.001;
  }

  update(dt: number, time: number): void {
    const drag = Math.max(0, 1 - 1.6 * dt);
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) continue;
      this.age[i] += dt;
      const remaining = this.maxAge[i] - this.age[i];
      if (remaining <= 0) {
        this.life[i] = 0;
        this.pos[i * 3 + 1] = -100;
        continue;
      }
      // Buoyancy, drag and a sideways wobble.
      this.vel[i * 3 + 1] = Math.min(1.3, this.vel[i * 3 + 1] + 0.9 * dt);
      this.vel[i * 3] *= drag;
      this.vel[i * 3 + 2] *= drag;
      const wobble = Math.sin(time * 4 + this.seed[i]) * 0.12;
      this.pos[i * 3] += (this.vel[i * 3] + wobble) * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      this.size[i] += 0.012 * dt;
      this.life[i] = Math.min(1, this.age[i] / 0.12) * Math.min(1, remaining / 0.5);
    }
    this.posAttr.needsUpdate = true;
    this.sizeAttr.needsUpdate = true;
    this.lifeAttr.needsUpdate = true;
  }
}
