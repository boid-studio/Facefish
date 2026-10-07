import * as THREE from 'three';

/**
 * Fin ripple, run on the GPU. Each fin carries a FinWave map as its second UV
 * set (U: 0 at the root -> 1 at the outer edge, V: across the fan), made in
 * Blender; the wave's settings come from the <model>.rig.json the exporter
 * writes next to the .glb (tuned with the "FinWave preview" modifier):
 *
 *   offset = axis * amplitude * U^falloff * sin(2*pi*(U/wavelength - phase + V*cross))
 *   phase += speed * dt
 *
 * The offset is added before skinning, so bone reactions (tail springs) stack on top.
 * The iOS app runs the same formula in a RealityKit geometry modifier (docs/ios-handoff.md).
 */
export interface FinWaveSettings {
  amplitude: number;
  wavelength: number;
  speed: number;
  falloff: number;
  cross: number;
  axis: [number, number, number];
}

export interface RigJson {
  format: string;
  finWave?: { uvSet: number; fins: Record<string, FinWaveSettings> };
  bones?: Record<string, string[]>;
}

/** "Fin_Pectoral.L", "Fin_PectoralL", "fin pectoral l" -> "finpectorall" */
export const normaliseName = (n: string): string => n.toLowerCase().replace(/[^a-z0-9]/g, '');

interface FinUniforms {
  phase: { value: number };
  params: { value: THREE.Vector4 }; // amplitude, wavelength, falloff, cross
  axis: { value: THREE.Vector3 };
  speed: number;
  amplitude: number;
}

export class FinWaves {
  private readonly fins: FinUniforms[] = [];
  readonly names: string[] = [];
  /** Multiplies every fin's amplitude (panel "Fin wave"). */
  amount = 1;
  /** Multiplies every fin's speed (panel "Fin wave speed"). */
  speed = 1;

  constructor(scene: THREE.Object3D, rig: RigJson | null) {
    const settings = rig?.finWave?.fins;
    if (!settings) return;
    const byName = new Map(Object.entries(settings).map(([k, v]) => [normaliseName(k), v]));
    scene.traverse((node) => {
      const s = byName.get(normaliseName(node.name));
      if (!s) return;
      byName.delete(normaliseName(node.name)); // a fin's own child meshes are handled with it
      let patched = 0;
      node.traverse((obj) => {
        const mesh = obj as THREE.Mesh;
        if (!mesh.isMesh) return;
        const uv1 = mesh.geometry.getAttribute('uv1');
        if (!uv1) return;
        mesh.geometry.setAttribute('finWave', uv1);
        const u: FinUniforms = {
          phase: { value: 0 },
          params: { value: new THREE.Vector4(s.amplitude, s.wavelength, s.falloff, s.cross) },
          axis: { value: new THREE.Vector3(...s.axis).normalize() },
          speed: s.speed,
          amplitude: s.amplitude,
        };
        const patch = (m: THREE.Material): THREE.Material => {
          const mat = m.clone();
          mat.onBeforeCompile = (shader) => {
            shader.uniforms.fwPhase = u.phase;
            shader.uniforms.fwParams = u.params;
            shader.uniforms.fwAxis = u.axis;
            shader.vertexShader = shader.vertexShader
              .replace(
                '#include <common>',
                '#include <common>\nattribute vec2 finWave;\nuniform float fwPhase;\nuniform vec4 fwParams;\nuniform vec3 fwAxis;',
              )
              .replace(
                '#include <begin_vertex>',
                [
                  '#include <begin_vertex>',
                  'float fwU = clamp(finWave.x, 0.0, 1.0);',
                  'transformed += fwAxis * fwParams.x * pow(fwU, fwParams.z)',
                  '  * sin(6.28318530718 * (fwU / fwParams.y - fwPhase + finWave.y * fwParams.w));',
                ].join('\n'),
              );
          };
          mat.customProgramCacheKey = () => 'facefish-finwave';
          return mat;
        };
        mesh.material = Array.isArray(mesh.material) ? mesh.material.map(patch) : patch(mesh.material);
        this.fins.push(u);
        patched++;
      });
      if (patched) this.names.push(node.name);
    });
  }

  get count(): number {
    return this.fins.length;
  }

  /** `energy` (0..1, e.g. how open the mouth is) livens the ripple a little while singing. */
  update(dt: number, energy = 0): void {
    const lively = 1 + 0.6 * Math.min(1, Math.max(0, energy));
    for (const f of this.fins) {
      f.phase.value = (f.phase.value + f.speed * this.speed * lively * dt) % 1000;
      f.params.value.x = f.amplitude * this.amount;
    }
  }
}
