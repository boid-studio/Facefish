import { BS } from '../facecap/blendshapes';
import type { FaceFrame } from '../facecap/types';

/**
 * Keyboard triggers. Bluetooth presentation clickers and page-turner
 * pedals show up as keyboards on the iPad, so this is the no-network way
 * for an operator (or the singer) to fire actions from a few metres away.
 */
export function installKeyboardTriggers(
  keys: Record<string, string>,
  onAction: (name: string) => void,
  onOther?: (key: string) => void,
): () => void {
  const handler = (e: KeyboardEvent): void => {
    const target = e.target as HTMLElement | null;
    if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
    const name = keys[e.key];
    if (name) {
      e.preventDefault();
      onAction(name);
    } else {
      onOther?.(e.key);
    }
  };
  window.addEventListener('keydown', handler);
  return () => window.removeEventListener('keydown', handler);
}

interface Gesture {
  name: string;
  action: string;
  /** Returns true while the gesture is being held. */
  test(w: Float32Array): boolean;
  /** Seconds the gesture must be held. */
  hold: number;
}

const GESTURES: Gesture[] = [
  {
    name: 'tongue out',
    action: 'wiggle',
    test: (w) => w[BS.tongueOut] > 0.6,
    hold: 0.6,
  },
  {
    name: 'wide eyes + brows up',
    action: 'spin',
    test: (w) => w[BS.eyeWide_L] > 0.5 && w[BS.eyeWide_R] > 0.5 && w[BS.browInnerUp] > 0.5,
    hold: 0.7,
  },
  {
    name: 'long wink (left)',
    action: 'lap',
    test: (w) => w[BS.eyeBlink_L] > 0.7 && w[BS.eyeBlink_R] < 0.2,
    hold: 1.2,
  },
];

/**
 * Face-gesture triggers, for when there is no operator. Gestures must be
 * held for a moment and have a cooldown, so ordinary singing doesn't fire
 * them. Off by default.
 */
export class GestureTriggers {
  private held = new Map<string, number>();
  private cooldownUntil = 0;
  cooldown = 4;

  constructor(private readonly onAction: (name: string, gesture: string) => void) {}

  update(frame: FaceFrame, dt: number, time: number): void {
    if (time < this.cooldownUntil) return;
    for (const g of GESTURES) {
      const t = g.test(frame.weights) ? (this.held.get(g.name) ?? 0) + dt : 0;
      this.held.set(g.name, t);
      if (t >= g.hold) {
        this.held.set(g.name, 0);
        this.cooldownUntil = time + this.cooldown;
        this.onAction(g.action, g.name);
        return;
      }
    }
  }
}
