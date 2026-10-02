/**
 * A FaceSource delivers raw Face Cap UDP payloads. Today that's a WebSocket
 * fed by `relay/relay.mjs`; a native Capacitor UDP plugin can implement the
 * same interface later and hand over identical bytes.
 */
export type SourceState = 'connecting' | 'open' | 'closed' | 'error';

export interface ControlMessage {
  type: string;
  [key: string]: unknown;
}

export interface FaceSource {
  readonly state: SourceState;
  onPacket: ((data: ArrayBuffer) => void) | null;
  /** JSON text frames from the relay (action triggers and the like). */
  onMessage: ((msg: ControlMessage) => void) | null;
  onStateChange: ((state: SourceState, detail?: string) => void) | null;
  start(): void;
  stop(): void;
  /** Send a JSON control message to the relay; false when not connected. */
  send?(msg: ControlMessage): boolean;
}

export interface WebSocketSourceOptions {
  url: string;
  /** Reconnect delay in ms (grows up to 5x on repeated failures). */
  reconnectDelay?: number;
}

export class WebSocketSource implements FaceSource {
  state: SourceState = 'closed';
  onPacket: ((data: ArrayBuffer) => void) | null = null;
  onMessage: ((msg: ControlMessage) => void) | null = null;
  onStateChange: ((state: SourceState, detail?: string) => void) | null = null;

  private ws: WebSocket | null = null;
  private stopped = true;
  private attempts = 0;
  private timer: number | null = null;
  private readonly url: string;
  private readonly reconnectDelay: number;

  constructor(options: WebSocketSourceOptions) {
    this.url = options.url;
    this.reconnectDelay = options.reconnectDelay ?? 1000;
  }

  start(): void {
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.timer !== null) {
      window.clearTimeout(this.timer);
      this.timer = null;
    }
    if (this.ws) {
      this.ws.onopen = this.ws.onmessage = this.ws.onerror = this.ws.onclose = null;
      this.ws.close();
      this.ws = null;
    }
    this.setState('closed');
  }

  send(msg: ControlMessage): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    this.ws.send(JSON.stringify(msg));
    return true;
  }

  private setState(state: SourceState, detail?: string): void {
    this.state = state;
    this.onStateChange?.(state, detail);
  }

  private connect(): void {
    if (this.stopped) return;
    this.setState('connecting', this.url);
    let ws: WebSocket;
    try {
      ws = new WebSocket(this.url);
    } catch (err) {
      this.setState('error', String(err));
      this.scheduleReconnect();
      return;
    }
    ws.binaryType = 'arraybuffer';
    this.ws = ws;

    ws.onopen = () => {
      this.attempts = 0;
      this.setState('open', this.url);
    };
    ws.onmessage = (ev: MessageEvent) => {
      if (ev.data instanceof ArrayBuffer) {
        this.onPacket?.(ev.data);
      } else if (typeof ev.data === 'string') {
        try {
          const msg = JSON.parse(ev.data) as ControlMessage;
          if (msg && typeof msg.type === 'string') this.onMessage?.(msg);
        } catch {
          /* ignore malformed control messages */
        }
      }
    };
    ws.onerror = () => {
      this.setState('error', 'websocket error');
    };
    ws.onclose = () => {
      this.ws = null;
      if (!this.stopped) {
        this.setState('closed', 'disconnected');
        this.scheduleReconnect();
      }
    };
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.timer !== null) return;
    this.attempts++;
    const delay = Math.min(this.reconnectDelay * this.attempts, this.reconnectDelay * 5);
    this.timer = window.setTimeout(() => {
      this.timer = null;
      this.connect();
    }, delay);
  }
}
