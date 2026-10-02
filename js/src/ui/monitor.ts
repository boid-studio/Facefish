import { BLENDSHAPE_COUNT, BLENDSHAPE_NAMES } from '../facecap/blendshapes';
import type { FaceFrame } from '../facecap/types';

/** Face Cap index ranges, in the order Face Cap sends them. */
const GROUPS: { title: string; from: number; to: number }[] = [
  { title: 'Brows', from: 0, to: 4 },
  { title: 'Eye look', from: 5, to: 12 },
  { title: 'Eyes', from: 13, to: 18 },
  { title: 'Cheeks and nose', from: 19, to: 23 },
  { title: 'Jaw', from: 24, to: 27 },
  { title: 'Mouth', from: 28, to: 50 },
  { title: 'Tongue', from: 51, to: 51 },
];

/** Repaint the numbers this often; peaks are tracked every frame. */
const PAINT_INTERVAL = 1 / 20;
/** How fast the peak marker falls back, in units per second. */
const PEAK_FALL = 0.6;

interface Row {
  el: HTMLDivElement;
  fill: HTMLDivElement;
  peak: HTMLDivElement;
  applied: HTMLDivElement;
  value: HTMLSpanElement;
}

/**
 * Overlay listing every value Face Cap sends: the 52 blendshapes as bars,
 * plus head and eye rotation. Shapes the loaded model has are bright; ones it
 * lacks are dimmed, so it's easy to see which movements reach the fish.
 *
 * Per shape: the bar is the incoming value, the faint marker is the recent
 * peak (catches quick blips), and the white tick is what the fish actually
 * receives after Expression, Smoothing and Mirror.
 */
export class KeyMonitor {
  private readonly root: HTMLDivElement;
  private readonly summary: HTMLDivElement;
  private readonly headText: HTMLPreElement;
  private readonly rows: Row[] = [];
  private readonly peaks = new Float32Array(BLENDSHAPE_COUNT);
  private visible = false;
  private sincePaint = 0;
  private modelShapes: ReadonlySet<number> | null = null;
  private rate = 0;

  constructor() {
    this.root = document.createElement('div');
    this.root.id = 'monitor';
    this.root.hidden = true;

    const head = document.createElement('div');
    head.className = 'monitor-head';
    const title = document.createElement('strong');
    title.textContent = 'Incoming keys';
    const hint = document.createElement('span');
    hint.className = 'monitor-hint';
    hint.textContent = 'v to hide';
    head.append(title, hint);

    this.summary = document.createElement('div');
    this.summary.className = 'monitor-summary';

    const legend = document.createElement('div');
    legend.className = 'monitor-legend';
    legend.innerHTML =
      '<span><i class="lg-fill"></i>from Face Cap</span>' +
      '<span><i class="lg-peak"></i>recent peak</span>' +
      '<span><i class="lg-applied"></i>sent to the fish</span>' +
      '<span><i class="lg-dim"></i>not on the model</span>';

    this.headText = document.createElement('pre');
    this.headText.className = 'monitor-pose';

    const list = document.createElement('div');
    list.className = 'monitor-list';
    for (const group of GROUPS) {
      const h = document.createElement('div');
      h.className = 'monitor-group';
      h.textContent = group.title;
      list.append(h);
      for (let i = group.from; i <= group.to; i++) {
        const el = document.createElement('div');
        el.className = 'monitor-row';
        const name = document.createElement('span');
        name.className = 'monitor-name';
        name.textContent = BLENDSHAPE_NAMES[i];
        const track = document.createElement('div');
        track.className = 'monitor-track';
        const fill = document.createElement('div');
        fill.className = 'monitor-fill';
        const peak = document.createElement('div');
        peak.className = 'monitor-peak';
        const applied = document.createElement('div');
        applied.className = 'monitor-applied';
        track.append(fill, peak, applied);
        const value = document.createElement('span');
        value.className = 'monitor-value';
        el.append(name, track, value);
        list.append(el);
        this.rows[i] = { el, fill, peak, applied, value };
      }
    }

    this.root.append(head, this.summary, legend, this.headText, list);
    document.body.append(this.root);
    this.setModelShapes(null);
  }

  /** Which Face Cap shapes (by index) the model has; null for the procedural fish. */
  setModelShapes(shapes: ReadonlySet<number> | null): void {
    this.modelShapes = shapes;
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      const off = shapes !== null && !shapes.has(i);
      this.rows[i].el.classList.toggle('off-model', off);
      this.rows[i].el.title = off ? `${BLENDSHAPE_NAMES[i]}: not on the model, so the fish ignores it` : BLENDSHAPE_NAMES[i];
    }
  }

  setVisible(on: boolean): void {
    this.visible = on;
    this.root.hidden = !on;
    if (on) this.sincePaint = PAINT_INTERVAL;
  }

  setRate(packetsPerSecond: number): void {
    this.rate = packetsPerSecond;
  }

  /**
   * @param frame   latest decoded Face Cap frame (raw values)
   * @param applied smoothed weights driving the model, same index order
   */
  update(frame: FaceFrame, applied: Float32Array, live: boolean, dt: number): void {
    const w = frame.weights;
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      const p = Math.max(w[i], this.peaks[i] - PEAK_FALL * dt);
      this.peaks[i] = live ? p : 0;
    }
    if (!this.visible) return;
    this.sincePaint += dt;
    if (this.sincePaint < PAINT_INTERVAL) return;
    this.sincePaint = 0;

    let active = 0;
    for (let i = 0; i < BLENDSHAPE_COUNT; i++) {
      const v = live ? w[i] : 0;
      if (v > 0.05) active++;
      const r = this.rows[i];
      r.fill.style.transform = `scaleX(${v})`;
      r.peak.style.left = `${this.peaks[i] * 100}%`;
      r.applied.style.left = `${Math.min(1, applied[i]) * 100}%`;
      r.value.textContent = v.toFixed(2);
      r.el.classList.toggle('active', v > 0.05);
    }

    const onModel = this.modelShapes === null ? 'procedural fish' : `${this.modelShapes.size} of 52 on the model`;
    this.summary.textContent = live
      ? `${onModel} · ${active} moving · ${Math.round(this.rate)} packets/s`
      : `${onModel} · no data from Face Cap`;

    const f1 = (n: number): string => n.toFixed(1).padStart(6);
    const f2 = (n: number): string => n.toFixed(2).padStart(6);
    const hr = frame.headRotation;
    const hp = frame.headPosition;
    this.headText.textContent =
      `head rot ${f1(hr.x)} ${f1(hr.y)} ${f1(hr.z)}\n` +
      `head pos ${f2(hp.x)} ${f2(hp.y)} ${f2(hp.z)}\n` +
      `eye L    ${f1(frame.eyeLeft.x)} ${f1(frame.eyeLeft.y)}\n` +
      `eye R    ${f1(frame.eyeRight.x)} ${f1(frame.eyeRight.y)}`;
  }
}
