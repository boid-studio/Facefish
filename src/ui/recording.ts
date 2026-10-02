import type { ControlMessage } from '../facecap/source';

/**
 * Record button (panel), REC badge and status line. The relay does the
 * recording; this sends start/stop and shows what the relay reports back.
 */
export class RecordingUi {
  private readonly button = document.getElementById('panel-record') as HTMLButtonElement;
  private readonly status = document.getElementById('panel-record-status') as HTMLParagraphElement;
  private readonly badge = document.getElementById('rec-badge') as HTMLDivElement;
  private readonly time = document.getElementById('rec-time') as HTMLSpanElement;
  private startedAt: number | null = null;
  private timer: number | null = null;

  constructor(private readonly send: (msg: ControlMessage) => boolean) {
    this.button.addEventListener('click', () => this.toggle());
  }

  toggle(): void {
    if (!this.send({ type: 'record', action: this.startedAt === null ? 'start' : 'stop' })) {
      this.status.textContent = 'Not connected to the relay, so nothing can be recorded.';
    }
  }

  /** Messages of type "record" from the relay. */
  handle(msg: ControlMessage): void {
    if (msg.state === 'recording') {
      if (this.startedAt === null) this.startedAt = performance.now();
      this.button.classList.add('recording');
      this.button.firstChild!.textContent = 'Stop recording ';
      this.badge.hidden = false;
      this.status.textContent = `Recording ${String(msg.name ?? '')}…`;
      this.tick();
      if (this.timer === null) this.timer = window.setInterval(() => this.tick(), 250);
      return;
    }
    this.startedAt = null;
    if (this.timer !== null) window.clearInterval(this.timer);
    this.timer = null;
    this.button.classList.remove('recording');
    this.button.firstChild!.textContent = 'Record take ';
    this.badge.hidden = true;
    if (msg.state === 'stopped') {
      this.status.textContent = msg.file
        ? `Saved ${String(msg.file)} (${Number(msg.seconds).toFixed(1)} s). Import it with blender/import_take.py.`
        : 'Stopped. No Face Cap data arrived, so nothing was saved.';
    }
  }

  private tick(): void {
    if (this.startedAt === null) return;
    const s = Math.floor((performance.now() - this.startedAt) / 1000);
    this.time.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
}
