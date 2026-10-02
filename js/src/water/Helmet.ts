import * as THREE from 'three';

/**
 * The inside of the diving helmet, seen from where the iPad sits: a large
 * sphere rendered from the inside, with a riveted metal texture. It catches
 * the projected caustics, so the light ripples read on the walls behind the
 * fish as well as on the fish itself.
 *
 * The texture is generated procedurally unless a real one is provided at
 * `public/textures/helmet.jpg` (or `?helmet=<url>`), which should be an
 * equirectangular image (2:1) of the helmet interior.
 */
export class HelmetInterior {
  readonly group = new THREE.Group();
  readonly mesh: THREE.Mesh<THREE.SphereGeometry, THREE.MeshStandardMaterial>;
  /** Caustics projector aimed at the back wall. */
  readonly wallLight: THREE.SpotLight;
  private readonly baseIntensity = 110;

  constructor(caustics: THREE.Texture) {
    const material = new THREE.MeshStandardMaterial({
      map: makeProceduralTexture(),
      color: 0xffffff,
      roughness: 0.72,
      metalness: 0.12,
      side: THREE.BackSide,
    });
    this.mesh = new THREE.Mesh(new THREE.SphereGeometry(8, 96, 64), material);
    // Centre a little behind the camera so the walls wrap around the view and
    // the back wall sits well behind the lap path (which reaches z ≈ -5.2).
    this.mesh.position.set(0, 0.6, 1.8);
    this.mesh.rotation.y = Math.PI * 0.5;
    this.mesh.renderOrder = -1;
    this.group.add(this.mesh);

    // A wide projector just behind the fish, throwing the caustics onto the
    // back and side walls. The fish sits behind the light, outside its cone,
    // so it only gets its own narrower, brighter light.
    this.wallLight = new THREE.SpotLight(0xcfeeff, this.baseIntensity, 0, 1.15, 0.6, 1.2);
    this.wallLight.position.set(0.3, 3.2, -0.6);
    this.wallLight.target.position.set(0, -1.5, -7);
    this.wallLight.map = caustics;
    this.group.add(this.wallLight, this.wallLight.target);
  }

  /** Swap in a real texture; falls back to the procedural one on failure. */
  async loadTexture(url: string): Promise<boolean> {
    try {
      const tex = await new THREE.TextureLoader().loadAsync(url);
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.wrapS = THREE.RepeatWrapping;
      tex.anisotropy = 4;
      this.mesh.material.map = tex;
      this.mesh.material.needsUpdate = true;
      return true;
    } catch {
      return false;
    }
  }

  setCaustics(strength: number): void {
    this.wallLight.intensity = this.baseIntensity * (0.3 + 0.7 * Math.max(0, strength));
  }

  set visible(v: boolean) {
    this.group.visible = v;
  }
}

/**
 * Riveted, slightly corroded brass panels, drawn on a canvas. Equirectangular,
 * repeated twice around the sphere, which keeps the texels square.
 */
function makeProceduralTexture(): THREE.CanvasTexture {
  const w = 2048;
  const h = 1024;
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d')!;

  // Base: dark brass, darker toward the bottom of the helmet.
  const base = ctx.createLinearGradient(0, 0, 0, h);
  base.addColorStop(0, '#3d3527');
  base.addColorStop(0.45, '#2e281e');
  base.addColorStop(1, '#15130e');
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, w, h);

  // Grime and patina: soft blotches.
  const rand = mulberry32(7);
  for (let i = 0; i < 420; i++) {
    const x = rand() * w;
    const y = rand() * h;
    const r = 30 + rand() * 160;
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    const patina = rand() < 0.35;
    const a = 0.05 + rand() * 0.12;
    g.addColorStop(0, patina ? `rgba(70,110,90,${a})` : `rgba(10,8,5,${a})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(x - r, y - r, r * 2, r * 2);
  }

  // Panel seams: vertical every 256 px, horizontal bands.
  const seamsX = Array.from({ length: 16 }, (_, i) => i * 128);
  const seamsY = [0, 150, 310, 470, 640, 800, 930];
  ctx.lineWidth = 2;
  for (const x of seamsX) {
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.moveTo(x + 1, 0);
    ctx.lineTo(x + 1, h);
    ctx.stroke();
    ctx.strokeStyle = 'rgba(255,230,180,0.14)';
    ctx.beginPath();
    ctx.moveTo(x + 3, 0);
    ctx.lineTo(x + 3, h);
    ctx.stroke();
  }
  for (const y of seamsY) {
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.moveTo(0, y + 1);
    ctx.lineTo(w, y + 1);
    ctx.stroke();
    ctx.strokeStyle = 'rgba(255,230,180,0.14)';
    ctx.beginPath();
    ctx.moveTo(0, y + 3);
    ctx.lineTo(w, y + 3);
    ctx.stroke();
  }

  // Rivets along the seams.
  const rivet = (x: number, y: number): void => {
    const r = 4;
    const shade = ctx.createRadialGradient(x - 1.2, y - 1.2, 0.5, x, y, r);
    shade.addColorStop(0, 'rgba(255,225,170,0.85)');
    shade.addColorStop(0.5, 'rgba(120,100,70,0.9)');
    shade.addColorStop(1, 'rgba(20,15,10,0.95)');
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.beginPath();
    ctx.arc(x + 1.2, y + 1.8, r + 0.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = shade;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  };
  for (const x of seamsX) {
    for (let y = 12; y < h; y += 24) rivet(x + 10, y);
  }
  for (const y of seamsY) {
    for (let x = 22; x < w; x += 24) {
      if (seamsX.some((sx) => Math.abs(sx + 10 - x) < 14)) continue;
      rivet(x, y + 11);
    }
  }

  // Fine noise so flat areas don't band.
  const img = ctx.getImageData(0, 0, w, h);
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const n = (rand() - 0.5) * 14;
    d[i] += n;
    d[i + 1] += n;
    d[i + 2] += n;
  }
  ctx.putImageData(img, 0, 0);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = THREE.RepeatWrapping;
  tex.repeat.set(2, 1);
  tex.anisotropy = 4;
  return tex;
}

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
