/**
 * Runtime settings. Read from URL parameters, remembered in localStorage so
 * the iPad only has to be configured once (open the app with
 * `?mirror=0&head=0&zoom=1.1` and it sticks), and defaulting to the stage
 * setup: the iPad inside a diving helmet on the singer.
 */
export interface AppConfig {
  /**
   * true: the fish behaves like a mirror (desk testing, screen faces the
   * tracked person). false: the fish is the person's face seen from the
   * front (helmet on stage).
   */
  mirror: boolean;
  /**
   * How much tracked head rotation to apply. The helmet sits on the
   * shoulders and the head turns freely inside it, so 1 follows the singer.
   */
  headGain: number;
  /** How far the fish moves in the bowl when the head moves inside the helmet. */
  moveGain: number;
  /** Slowly re-learn the resting head pose while tracking. */
  autoCenter: boolean;
  /** Camera zoom, to frame the fish in the porthole. */
  zoom: number;
  /** Vertical framing offset in scene units; positive moves the fish up. */
  offsetY: number;
  /** Dark circular mask around the edges, for a round porthole. */
  porthole: boolean;
  /** HUD behaviour: auto hides once tracking is live; on / off force it. */
  hud: 'auto' | 'on' | 'off';
  /** Let the singer trigger actions with face gestures. */
  gestures: boolean;
  /** Fire random actions while idling between songs. */
  idleActions: boolean;
  /** Amplitude of the body actions (1 = authored, 1.5 = punchier). */
  strength: number;
  /** Exaggeration of the tracked face (1 = as tracked). */
  expression: number;
  /** Strength of the light caustics (1 = subtle). */
  caustics: number;
  /** Amount of bubbles from the fish's movement and mouth (0 = off). */
  bubbles: number;
  /** Blue water in front of the fish (0 = clear, 1 = murky). */
  tint: number;
  /** Show the inside of the helmet behind the fish (else open water). */
  helmet: boolean;
  /** Keyboard/clicker key → action name. */
  keys: Record<string, string>;
}

export const DEFAULT_KEYS: Record<string, string> = {
  // Presentation clickers and page-turner pedals send these.
  PageDown: 'lap',
  ArrowRight: 'lap',
  PageUp: 'spin',
  ArrowLeft: 'spin',
  ArrowUp: 'nod',
  ArrowDown: 'wiggle',
  ' ': 'nod',
  Enter: 'lap',
  // Plain keyboard.
  '1': 'lap',
  '2': 'spin',
  '3': 'nod',
  '4': 'wiggle',
  '5': 'shake',
  '6': 'bounce',
  '7': 'dash',
  l: 'lap',
  s: 'spin',
  n: 'nod',
  w: 'wiggle',
  k: 'shake',
  b: 'bounce',
  d: 'dash',
};

export const DEFAULT_CONFIG: AppConfig = {
  mirror: false,
  headGain: 1,
  moveGain: 1,
  autoCenter: true,
  zoom: 1,
  offsetY: 0,
  porthole: false,
  hud: 'auto',
  gestures: false,
  idleActions: false,
  strength: 1.5,
  expression: 1.3,
  caustics: 1.8,
  bubbles: 1,
  tint: 0.35,
  helmet: true,
  keys: DEFAULT_KEYS,
};
const DEFAULTS = DEFAULT_CONFIG;

const STORAGE_KEY = 'facefish.config';

export function loadConfig(): AppConfig {
  const saved = readSaved();
  const params = new URLSearchParams(location.search);
  const cfg: AppConfig = { ...DEFAULTS, ...saved, keys: { ...DEFAULT_KEYS, ...(saved.keys ?? {}) } };

  const bool = (key: string, current: boolean): boolean => {
    const v = params.get(key);
    if (v === null) return current;
    return v === '1' || v === 'true' || v === 'on';
  };
  const num = (key: string, current: number): number => {
    const v = params.get(key);
    if (v === null) return current;
    const n = Number(v);
    return Number.isFinite(n) ? n : current;
  };

  cfg.mirror = bool('mirror', cfg.mirror);
  cfg.headGain = num('head', cfg.headGain);
  cfg.moveGain = num('move', cfg.moveGain);
  cfg.autoCenter = bool('autocenter', cfg.autoCenter);
  cfg.zoom = num('zoom', cfg.zoom);
  cfg.offsetY = num('y', cfg.offsetY);
  cfg.porthole = bool('porthole', cfg.porthole);
  cfg.gestures = bool('gestures', cfg.gestures);
  cfg.idleActions = bool('idleActions', cfg.idleActions);
  cfg.strength = num('strength', cfg.strength);
  cfg.expression = num('expr', cfg.expression);
  cfg.caustics = num('caustics', cfg.caustics);
  cfg.bubbles = num('bubbles', cfg.bubbles);
  cfg.tint = num('tint', cfg.tint);
  cfg.helmet = bool('helmet', cfg.helmet);
  const hud = params.get('hud');
  if (hud === 'auto' || hud === 'on' || hud === 'off') cfg.hud = hud;
  if (params.get('reset') !== null) {
    Object.assign(cfg, DEFAULTS, { keys: { ...DEFAULT_KEYS } });
  }

  saveConfig(cfg);
  return cfg;
}

function readSaved(): Partial<AppConfig> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Partial<AppConfig>) : {};
  } catch {
    return {};
  }
}

export function saveConfig(cfg: AppConfig): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg));
  } catch {
    /* storage unavailable */
  }
}
