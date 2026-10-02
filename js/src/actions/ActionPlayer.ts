import type { Avatar } from '../fish/Avatar';
import { PROCEDURAL_ACTIONS, type ProceduralAction } from './procedural';

/**
 * Plays one body action at a time on an avatar. If the avatar has an
 * animation clip with the action's name (a Blender NLA track), the clip is
 * used; otherwise the procedural version animates the root transform.
 *
 * Face tracking keeps running underneath either way.
 */
export class ActionPlayer {
  private current: { name: string; action: ProceduralAction; t: number } | null = null;
  private clipPlaying: string | null = null;
  private pending: string | null = null;
  onChange: ((playing: string | null) => void) | null = null;
  /** Amplitude multiplier for procedural actions (1 = authored size). */
  strength = 1;

  constructor(private readonly avatar: Avatar) {}

  get playing(): string | null {
    return this.current?.name ?? this.clipPlaying;
  }

  get available(): string[] {
    const names = new Set(Object.keys(PROCEDURAL_ACTIONS));
    for (const c of this.avatar.clips ?? []) names.add(c);
    return [...names];
  }

  /** Queue an action. A second trigger while busy replaces the pending one. */
  trigger(name: string): boolean {
    const hasClip = this.avatar.clips?.includes(name) ?? false;
    if (!hasClip && !(name in PROCEDURAL_ACTIONS)) {
      console.warn(`[actions] unknown action "${name}"`);
      return false;
    }
    if (this.playing) {
      this.pending = name;
      return true;
    }
    this.start(name);
    return true;
  }

  private start(name: string): void {
    if (this.avatar.clips?.includes(name) && this.avatar.playClip) {
      this.clipPlaying = name;
      this.onChange?.(name);
      void this.avatar.playClip(name).finally(() => {
        this.clipPlaying = null;
        this.finish();
      });
      return;
    }
    this.current = { name, action: PROCEDURAL_ACTIONS[name], t: 0 };
    this.onChange?.(name);
  }

  private finish(): void {
    this.avatar.root.position.set(0, 0, 0);
    this.avatar.root.rotation.set(0, 0, 0);
    this.onChange?.(null);
    const next = this.pending;
    this.pending = null;
    if (next) this.start(next);
  }

  update(dt: number): void {
    if (!this.current) return;
    this.current.t += dt / this.current.action.duration;
    const k = Math.min(3, Math.max(0.25, this.strength));
    if (this.current.t >= 1) {
      this.current.action.apply(this.avatar.root, 1, k);
      this.current = null;
      this.finish();
      return;
    }
    this.current.action.apply(this.avatar.root, this.current.t, k);
  }
}
