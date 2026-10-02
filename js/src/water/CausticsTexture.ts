import * as THREE from 'three';

/**
 * Renders an animated water-caustics pattern into an offscreen texture every
 * frame. The texture is tileable and is used both as a projected light map
 * (the light "landing" on the fish) and as surface shimmer in the background.
 */
export class CausticsTexture {
  readonly texture: THREE.Texture;
  private readonly target: THREE.WebGLRenderTarget;
  private readonly scene = new THREE.Scene();
  private readonly camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  private readonly material: THREE.ShaderMaterial;

  constructor(size = 512) {
    this.target = new THREE.WebGLRenderTarget(size, size, {
      wrapS: THREE.RepeatWrapping,
      wrapT: THREE.RepeatWrapping,
      minFilter: THREE.LinearFilter,
      magFilter: THREE.LinearFilter,
      generateMipmaps: false,
      depthBuffer: false,
      stencilBuffer: false,
    });
    this.texture = this.target.texture;

    this.material = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        tiles: { value: 7.0 },
        brightness: { value: 1.0 },
      },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() {
          vUv = uv;
          gl_Position = vec4(position.xy, 0.0, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        precision highp float;
        uniform float time;
        uniform float tiles;
        uniform float brightness;
        varying vec2 vUv;

        #define TAU 6.28318530718

        // Classic iterated-sine caustics. Periodic in uv, so the texture tiles.
        float caustic(vec2 uv, float t) {
          vec2 p = mod(uv * TAU, TAU) - 250.0;
          vec2 i = p;
          float c = 1.0;
          float inten = 0.005;
          for (int n = 0; n < 5; n++) {
            float k = t * (1.0 - (3.5 / float(n + 1)));
            i = p + vec2(cos(k - i.x) + sin(k + i.y), sin(k - i.y) + cos(k + i.x));
            c += 1.0 / length(vec2(p.x / (sin(i.x + k) / inten), p.y / (cos(i.y + k) / inten)));
          }
          c /= 5.0;
          c = 1.17 - pow(c, 1.4);
          return pow(abs(c), 8.0);
        }

        void main() {
          float t = time * 0.5 + 23.0;
          // Two layers at different scales and speeds read as depth.
          float a = caustic(vUv * tiles, t);
          float b = caustic(vUv * tiles * 0.5 + vec2(0.37, 0.11), t * 0.7 + 5.0);
          float v = clamp(a * 0.95 + b * 0.6, 0.0, 1.0);
          // Sharpen the ridges a little so they read as distinct light lines
          // on the fish. brightness scales the ridges, not the base, so the
          // shadows between them stay put.
          v = pow(v, 0.8);
          // Near-black between the ridges: the pattern must come from
          // contrast, not from more light, or tone mapping flattens it.
          vec3 col = vec3(0.08) + vec3(0.9, 1.0, 1.0) * v * brightness * 1.9;
          gl_FragColor = vec4(col, 1.0);
        }
      `,
      depthTest: false,
      depthWrite: false,
    });

    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.material);
    quad.frustumCulled = false;
    this.scene.add(quad);
  }

  /** Contrast of the pattern (1 = default). */
  setBrightness(value: number): void {
    this.material.uniforms.brightness.value = value;
  }

  render(renderer: THREE.WebGLRenderer, time: number): void {
    this.material.uniforms.time.value = time;
    const prev = renderer.getRenderTarget();
    renderer.setRenderTarget(this.target);
    renderer.render(this.scene, this.camera);
    renderer.setRenderTarget(prev);
  }

  dispose(): void {
    this.target.dispose();
    this.material.dispose();
  }
}
