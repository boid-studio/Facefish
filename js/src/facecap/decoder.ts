import { BLENDSHAPE_COUNT } from './blendshapes';
import { decodeOscPacket, type OscMessage } from './osc';
import { createFaceFrame, type FaceFrame } from './types';

/**
 * Accumulates Face Cap OSC messages into a single FaceFrame.
 *
 * Face Cap sends each blendshape as its own `/W` message and the head / eye
 * values as separate messages, usually bundled per capture frame. The
 * decoder simply keeps the latest value for everything, so it works whether
 * the packets arrive as bundles or as individual messages.
 */
export class FaceCapDecoder {
  readonly frame: FaceFrame = createFaceFrame();
  private messageCount = 0;
  private packetCount = 0;

  /** Feed one raw UDP payload (as forwarded by the relay). */
  feedPacket(data: ArrayBuffer | Uint8Array, now = performance.now()): number {
    const messages = decodeOscPacket(data);
    for (const m of messages) this.apply(m);
    if (messages.length > 0) {
      this.frame.timestamp = now;
      this.packetCount++;
    }
    return messages.length;
  }

  private num(m: OscMessage, i: number): number {
    const v = m.args[i];
    return typeof v === 'number' ? v : 0;
  }

  apply(m: OscMessage): void {
    this.messageCount++;
    const f = this.frame;
    switch (m.address) {
      case '/W': {
        const index = this.num(m, 0) | 0;
        if (index >= 0 && index < BLENDSHAPE_COUNT) {
          f.weights[index] = clamp01(this.num(m, 1));
        }
        break;
      }
      case '/HT':
        f.headPosition.x = this.num(m, 0);
        f.headPosition.y = this.num(m, 1);
        f.headPosition.z = this.num(m, 2);
        break;
      case '/HR':
        f.headRotation.x = this.num(m, 0);
        f.headRotation.y = this.num(m, 1);
        f.headRotation.z = this.num(m, 2);
        break;
      case '/HRQ':
        f.headQuaternion = {
          x: this.num(m, 0),
          y: this.num(m, 1),
          z: this.num(m, 2),
          w: this.num(m, 3),
        };
        break;
      case '/ELR':
        f.eyeLeft.x = this.num(m, 0);
        f.eyeLeft.y = this.num(m, 1);
        break;
      case '/ERR':
        f.eyeRight.x = this.num(m, 0);
        f.eyeRight.y = this.num(m, 1);
        break;
      default:
        break;
    }
  }

  get stats(): { messages: number; packets: number } {
    return { messages: this.messageCount, packets: this.packetCount };
  }
}

function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}
