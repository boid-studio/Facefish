import { DEFAULT_CONFIG, DEFAULT_KEYS, type AppConfig } from '../config';

/**
 * The control panel: one button per action (labelled with its keys) and
 * sliders/toggles for the live settings. Slides in from the right; opened
 * with the corner button or the `p` key. Everything it changes is written
 * straight into the shared AppConfig and reported through `onChange`.
 */
export interface PanelCallbacks {
  onAction(name: string): void;
  /** Called after any setting changed (the config object is already updated). */
  onChange(): void;
  /** "Center head": take the current head pose as the resting one. */
  onCenter(): void;
}

type NumKey = 'strength' | 'expression' | 'smoothing' | 'lidAngle' | 'headGain' | 'moveGain' | 'zoom' | 'offsetY' | 'caustics' | 'bubbles' | 'tint';
type BoolKey = 'mirror' | 'porthole' | 'gestures' | 'idleActions' | 'autoCenter' | 'helmet' | 'monitor';

interface RangeControl {
  kind: 'range';
  key: NumKey;
  label: string;
  hint: string;
  min: number;
  max: number;
  step: number;
}
interface ToggleControl {
  kind: 'toggle';
  key: BoolKey;
  label: string;
  hint: string;
}
type Control = RangeControl | ToggleControl;

const CONTROLS: Control[] = [
  { kind: 'range', key: 'strength', label: 'Action strength', hint: 'How big the laps, nods and wiggles are', min: 0.5, max: 3, step: 0.1 },
  { kind: 'range', key: 'expression', label: 'Expression', hint: 'Exaggerates the tracked face', min: 0.5, max: 2.5, step: 0.1 },
  { kind: 'range', key: 'smoothing', label: 'Smoothing', hint: 'Lower is snappier; 0 shows tracking raw', min: 0, max: 1, step: 0.05 },
  { kind: 'range', key: 'lidAngle', label: 'Lid close angle', hint: 'Degrees the eyelid bones turn on a full blink; negative turns the other way', min: -150, max: 150, step: 1 },
  { kind: 'range', key: 'headGain', label: 'Head turn', hint: 'Fish turns with the head; 1 follows exactly', min: 0, max: 2, step: 0.05 },
  { kind: 'range', key: 'moveGain', label: 'Head move', hint: 'Fish swims around the bowl as the head moves inside the helmet', min: 0, max: 3, step: 0.1 },
  { kind: 'toggle', key: 'autoCenter', label: 'Auto-center head', hint: 'Slowly relearns the resting pose; press c to center now' },
  { kind: 'range', key: 'zoom', label: 'Zoom', hint: 'Frame the fish in the porthole', min: 0.5, max: 2, step: 0.05 },
  { kind: 'range', key: 'offsetY', label: 'Vertical offset', hint: 'Positive moves the fish up', min: -0.6, max: 0.6, step: 0.02 },
  { kind: 'range', key: 'caustics', label: 'Caustics', hint: 'Light ripples on the fish', min: 0, max: 3, step: 0.1 },
  { kind: 'range', key: 'tint', label: 'Water tint', hint: 'Blue haze in front of the fish', min: 0, max: 1, step: 0.05 },
  { kind: 'range', key: 'bubbles', label: 'Bubbles', hint: 'From the mouth while singing and moving', min: 0, max: 3, step: 0.1 },
  { kind: 'toggle', key: 'helmet', label: 'Helmet walls', hint: 'Inside of the helmet behind the fish, catching the caustics' },
  { kind: 'toggle', key: 'mirror', label: 'Mirror', hint: 'On for desk testing, off inside the helmet' },
  { kind: 'toggle', key: 'porthole', label: 'Porthole mask', hint: 'Dark round vignette' },
  { kind: 'toggle', key: 'gestures', label: 'Face gestures', hint: 'Tongue out, wide eyes or a long wink fire actions' },
  { kind: 'toggle', key: 'idleActions', label: 'Idle actions', hint: 'Random actions while no one is tracked' },
  { kind: 'toggle', key: 'monitor', label: 'Key monitor', hint: 'Every incoming Face Cap value; press v' },
];

const KEY_NAMES: Record<string, string> = {
  ' ': 'Space',
  ArrowLeft: '←',
  ArrowRight: '→',
  ArrowUp: '↑',
  ArrowDown: '↓',
  PageUp: 'PgUp',
  PageDown: 'PgDn',
  Enter: '⏎',
};

export class Panel {
  private readonly root = document.getElementById('panel') as HTMLDivElement;
  private readonly toggleButton = document.getElementById('panel-toggle') as HTMLButtonElement;
  private readonly actionsEl = document.getElementById('panel-actions') as HTMLDivElement;
  private readonly settingsEl = document.getElementById('panel-settings') as HTMLDivElement;
  private readonly inputs = new Map<string, HTMLInputElement>();
  private readonly values = new Map<string, HTMLSpanElement>();
  private readonly actionButtons = new Map<string, HTMLButtonElement>();

  constructor(
    private readonly config: AppConfig,
    actions: string[],
    private readonly cb: PanelCallbacks,
  ) {
    this.toggleButton.addEventListener('click', () => this.toggle());
    (document.getElementById('panel-close') as HTMLButtonElement).addEventListener('click', () => this.hide());
    (document.getElementById('panel-reset') as HTMLButtonElement).addEventListener('click', () => this.reset());
    (document.getElementById('panel-center') as HTMLButtonElement).addEventListener('click', () => this.cb.onCenter());
    this.buildActions(actions);
    this.buildSettings();
    this.buildHudSelect();
    this.refresh();
  }

  get visible(): boolean {
    return this.root.classList.contains('open');
  }

  toggle(): void {
    if (this.visible) this.hide();
    else this.show();
  }

  show(): void {
    this.root.classList.add('open');
    this.toggleButton.classList.add('open');
  }

  hide(): void {
    this.root.classList.remove('open');
    this.toggleButton.classList.remove('open');
  }

  /** Highlight the action that is playing (null when idle). */
  setPlaying(name: string | null): void {
    for (const [n, b] of this.actionButtons) b.classList.toggle('playing', n === name);
  }

  /** Push the current config values into the inputs. */
  refresh(): void {
    for (const c of CONTROLS) {
      const input = this.inputs.get(c.key);
      if (!input) continue;
      if (c.kind === 'range') {
        input.value = String(this.config[c.key]);
        this.showValue(c);
      } else {
        input.checked = this.config[c.key];
      }
    }
    const hud = this.inputs.get('hud') as unknown as HTMLSelectElement | undefined;
    if (hud) hud.value = this.config.hud;
  }

  private keysFor(action: string): string[] {
    return Object.entries(this.config.keys)
      .filter(([, a]) => a === action)
      .map(([k]) => KEY_NAMES[k] ?? k)
      .slice(0, 4);
  }

  private buildActions(actions: string[]): void {
    this.actionsEl.replaceChildren();
    for (const name of actions) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'panel-action';
      const title = document.createElement('span');
      title.textContent = name;
      const keys = document.createElement('small');
      keys.textContent = this.keysFor(name).join(' · ');
      b.append(title, keys);
      b.addEventListener('click', () => this.cb.onAction(name));
      this.actionButtons.set(name, b);
      this.actionsEl.append(b);
    }
  }

  private buildSettings(): void {
    for (const c of CONTROLS) {
      const row = document.createElement('label');
      row.className = `panel-row ${c.kind}`;
      const head = document.createElement('div');
      head.className = 'panel-row-head';
      const label = document.createElement('span');
      label.textContent = c.label;
      head.append(label);
      const hint = document.createElement('small');
      hint.textContent = c.hint;

      const input = document.createElement('input');
      if (c.kind === 'range') {
        const value = document.createElement('span');
        value.className = 'panel-value';
        head.append(value);
        this.values.set(c.key, value);
        input.type = 'range';
        input.min = String(c.min);
        input.max = String(c.max);
        input.step = String(c.step);
        input.addEventListener('input', () => {
          this.config[c.key] = Number(input.value);
          this.showValue(c);
          this.cb.onChange();
        });
        row.append(head, input, hint);
      } else {
        input.type = 'checkbox';
        input.addEventListener('change', () => {
          this.config[c.key] = input.checked;
          this.cb.onChange();
        });
        head.append(input);
        row.append(head, hint);
      }
      this.inputs.set(c.key, input);
      this.settingsEl.append(row);
    }
  }

  private buildHudSelect(): void {
    const row = document.createElement('label');
    row.className = 'panel-row select';
    const head = document.createElement('div');
    head.className = 'panel-row-head';
    const label = document.createElement('span');
    label.textContent = 'Status HUD';
    const select = document.createElement('select');
    for (const v of ['auto', 'on', 'off']) {
      const o = document.createElement('option');
      o.value = v;
      o.textContent = v;
      select.append(o);
    }
    select.addEventListener('change', () => {
      this.config.hud = select.value as AppConfig['hud'];
      this.cb.onChange();
    });
    head.append(label, select);
    const hint = document.createElement('small');
    hint.textContent = 'auto hides the status once tracking is live';
    row.append(head, hint);
    this.inputs.set('hud', select as unknown as HTMLInputElement);
    this.settingsEl.append(row);
  }

  private showValue(c: RangeControl): void {
    const v = this.config[c.key];
    const el = this.values.get(c.key);
    if (el) el.textContent = c.step >= 0.1 ? `${v.toFixed(1)}×` : v.toFixed(2);
  }

  private reset(): void {
    Object.assign(this.config, DEFAULT_CONFIG, { keys: { ...DEFAULT_KEYS } });
    this.refresh();
    this.cb.onChange();
  }
}
