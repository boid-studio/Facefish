/**
 * Take recorder for the relay: keeps the latest Face Cap values (52 blendshape
 * weights, head rotation and position, eye rotations) as packets pass through,
 * and while recording samples them 60 times a second into
 * recordings/take-YYYYMMDD-HHMMSS.json.
 *
 * The file holds the raw tracked values (no Expression gain, mirroring or
 * smoothing); blender/import_take.py turns a take into keyframes on the fish
 * the same way the app maps them.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const RECORDINGS_DIR = path.join(ROOT, 'recordings');
const SAMPLE_HZ = 60;

// Face Cap blendshape order (same table as src/facecap/blendshapes.ts).
export const BLENDSHAPE_NAMES = [
  'browInnerUp', 'browDown_L', 'browDown_R', 'browOuterUp_L', 'browOuterUp_R',
  'eyeLookUp_L', 'eyeLookUp_R', 'eyeLookDown_L', 'eyeLookDown_R', 'eyeLookIn_L', 'eyeLookIn_R',
  'eyeLookOut_L', 'eyeLookOut_R', 'eyeBlink_L', 'eyeBlink_R', 'eyeSquint_L', 'eyeSquint_R',
  'eyeWide_L', 'eyeWide_R', 'cheekPuff', 'cheekSquint_L', 'cheekSquint_R', 'noseSneer_L', 'noseSneer_R',
  'jawOpen', 'jawForward', 'jawLeft', 'jawRight', 'mouthFunnel', 'mouthPucker', 'mouthLeft', 'mouthRight',
  'mouthRollUpper', 'mouthRollLower', 'mouthShrugUpper', 'mouthShrugLower', 'mouthClose',
  'mouthSmile_L', 'mouthSmile_R', 'mouthFrown_L', 'mouthFrown_R', 'mouthDimple_L', 'mouthDimple_R',
  'mouthUpperUp_L', 'mouthUpperUp_R', 'mouthLowerDown_L', 'mouthLowerDown_R', 'mouthPress_L', 'mouthPress_R',
  'mouthStretch_L', 'mouthStretch_R', 'tongueOut',
];

const align4 = (n) => (n + 3) & ~3;

function readString(buf, offset) {
  let end = offset;
  while (end < buf.length && buf[end] !== 0) end++;
  return [buf.toString('utf8', offset, end), align4(end + 1)];
}

/** OSC packet (message or nested bundles) → [{address, args}], numbers and strings only. */
export function parseOsc(buf, out = []) {
  if (buf.length >= 8 && buf.toString('utf8', 0, 7) === '#bundle') {
    let off = 16; // "#bundle\0" + 8-byte timetag
    while (off + 4 <= buf.length) {
      const size = buf.readInt32BE(off);
      off += 4;
      if (size <= 0 || off + size > buf.length) break;
      parseOsc(buf.subarray(off, off + size), out);
      off += size;
    }
    return out;
  }
  if (buf.length < 4 || buf[0] !== 0x2f) return out;
  const [address, afterAddr] = readString(buf, 0);
  if (afterAddr >= buf.length) {
    out.push({ address, args: [] });
    return out;
  }
  const [tags, afterTags] = readString(buf, afterAddr);
  const args = [];
  let off = afterTags;
  for (const tag of tags.slice(1)) {
    if (tag === 'f' && off + 4 <= buf.length) {
      args.push(buf.readFloatBE(off));
      off += 4;
    } else if (tag === 'i' && off + 4 <= buf.length) {
      args.push(buf.readInt32BE(off));
      off += 4;
    } else if (tag === 'd' && off + 8 <= buf.length) {
      args.push(buf.readDoubleBE(off));
      off += 8;
    } else if (tag === 's') {
      const [s, next] = readString(buf, off);
      args.push(s);
      off = next;
    } else {
      break;
    }
  }
  out.push({ address, args });
  return out;
}

function stamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

const r3 = (x) => Math.round(x * 1000) / 1000;

export class TakeRecorder {
  constructor() {
    this.w = new Float32Array(52);
    this.hr = [0, 0, 0];
    this.ht = [0, 0, 0];
    this.el = [0, 0];
    this.er = [0, 0];
    this.fresh = false;
    this.take = null;
    this.timer = null;
  }

  get recording() {
    return this.take !== null;
  }

  /** Every Face Cap packet passes through here. */
  feed(buf) {
    for (const m of parseOsc(buf)) {
      const a = m.args;
      switch (m.address) {
        case '/W':
          if (a.length >= 2 && a[0] >= 0 && a[0] < 52) this.w[a[0] | 0] = a[1];
          break;
        case '/HR':
          if (a.length >= 3) this.hr = [a[0], a[1], a[2]];
          break;
        case '/HT':
          if (a.length >= 3) this.ht = [a[0], a[1], a[2]];
          break;
        case '/ELR':
          if (a.length >= 2) this.el = [a[0], a[1]];
          break;
        case '/ERR':
          if (a.length >= 2) this.er = [a[0], a[1]];
          break;
        default:
          continue;
      }
      this.fresh = true;
    }
  }

  start(neutral) {
    if (this.take) return this.status();
    const name = `take-${stamp()}`;
    this.take = { name, started: Date.now(), frames: [], neutral: validNeutral(neutral) };
    this.timer = setInterval(() => this.sample(), 1000 / SAMPLE_HZ);
    console.log(`[record] recording ${name}`);
    return this.status();
  }

  sample() {
    if (!this.take || !this.fresh) return; // only when new data arrived
    this.fresh = false;
    this.take.frames.push({
      t: r3((Date.now() - this.take.started) / 1000),
      w: Array.from(this.w, r3),
      hr: this.hr.map(r3),
      ht: this.ht.map(r3),
      el: this.el.map(r3),
      er: this.er.map(r3),
    });
  }

  stop(neutral) {
    if (!this.take) return this.status();
    if (validNeutral(neutral)) this.take.neutral = validNeutral(neutral);
    clearInterval(this.timer);
    this.timer = null;
    const take = this.take;
    this.take = null;
    const seconds = take.frames.length ? take.frames[take.frames.length - 1].t : 0;
    if (take.frames.length === 0) {
      console.log(`[record] ${take.name}: no Face Cap data arrived, nothing saved`);
      return { type: 'record', state: 'stopped', name: take.name, frames: 0, seconds: 0, file: null };
    }
    fs.mkdirSync(RECORDINGS_DIR, { recursive: true });
    const file = path.join(RECORDINGS_DIR, `${take.name}.json`);
    const doc = {
      format: 'facefish-take/1',
      name: take.name,
      recorded: new Date(take.started).toISOString(),
      sampleRate: SAMPLE_HZ,
      seconds,
      names: BLENDSHAPE_NAMES,
      // the performer's resting face from the app's Center face (raw values, same order as names), or null
      neutral: take.neutral ?? null,
      units: { w: '0..1', hr: 'degrees (x, y, z)', ht: 'centimetres', el: 'Face Cap /ELR', er: 'Face Cap /ERR' },
      frames: take.frames,
    };
    fs.writeFileSync(file, JSON.stringify(doc));
    const rel = path.relative(ROOT, file);
    console.log(`[record] saved ${rel} (${take.frames.length} frames, ${seconds.toFixed(1)} s)`);
    return { type: 'record', state: 'stopped', name: take.name, frames: take.frames.length, seconds, file: rel };
  }

  status() {
    return this.take
      ? { type: 'record', state: 'recording', name: this.take.name, started: this.take.started }
      : { type: 'record', state: 'idle' };
  }
}

/** A resting face from the app: 52 numbers, or null. */
function validNeutral(n) {
  return Array.isArray(n) && n.length === BLENDSHAPE_NAMES.length && n.every((v) => typeof v === 'number') ? n.map(r3) : null;
}
