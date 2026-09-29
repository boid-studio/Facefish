import * as THREE from 'three';

/**
 * A big plane far behind the fish: depth gradient, slanted light shafts and
 * a faint caustic shimmer toward the surface.
 */
export class UnderwaterBackground {
  readonly mesh: THREE.Mesh;
  private readonly material: THREE.ShaderMaterial;

  constructor(caustics: THREE.Texture) {
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        caustics: { value: caustics },
        deep: { value: new THREE.Color(0x03111f) },
        shallow: { value: new THREE.Color(0x0e5a78) },
        shaftColor: { value: new THREE.Color(0x3e9fb8) },
        causticStrength: { value: 1 },
      },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() {
          vUv = uv;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        precision highp float;
        uniform float time;
        uniform sampler2D caustics;
        uniform vec3 deep;
        uniform vec3 shallow;
        uniform vec3 shaftColor;
        uniform float causticStrength;
        varying vec2 vUv;

        float hash(float n) { return fract(sin(n) * 43758.5453123); }
        float noise(float x) {
          float i = floor(x);
          float f = fract(x);
          f = f * f * (3.0 - 2.0 * f);
          return mix(hash(i), hash(i + 1.0), f);
        }

        void main() {
          float depth = pow(vUv.y, 1.5);
          vec3 col = mix(deep, shallow, depth);

          // Light shafts: slanted 1D noise, brighter toward the surface.
          float x = vUv.x + (1.0 - vUv.y) * 0.45;
          float s = noise(x * 16.0 + time * 0.12) * 0.55
                  + noise(x * 37.0 - time * 0.08) * 0.3
                  + noise(x * 71.0 + time * 0.2) * 0.15;
          s = pow(s, 3.5) * smoothstep(0.05, 0.85, vUv.y);
          col += shaftColor * s * 0.9;

          // Surface shimmer: caustics stretched horizontally, fading with depth.
          float c = texture2D(caustics, vUv * vec2(2.5, 1.2) + vec2(time * 0.006, 0.0)).r;
          // Kept faint on purpose: the caustics should read on the fish,
          // not compete with it from behind.
          col += shaftColor * (c - 0.3) * pow(vUv.y, 2.6) * 0.18 * causticStrength;

          // Gentle vignette so the fish stays the focus.
          float d = distance(vUv, vec2(0.5, 0.55));
          col *= 1.0 - smoothstep(0.35, 0.9, d) * 0.5;

          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }
      `,
      depthWrite: false,
    });

    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(60, 40), this.material);
    this.mesh.position.z = -14;
    this.mesh.renderOrder = -1;
  }

  update(time: number): void {
    this.material.uniforms.time.value = time;
  }

  setCaustics(strength: number): void {
    this.material.uniforms.causticStrength.value = strength;
  }
}
