#!/usr/bin/env node
/**
 * Replay a recorded take as live Face Cap data: OSC over UDP, exactly what the
 * iPhone sends (one bundle per frame: /W index value x 52, /HT, /HR, /ELR, /ERR).
 * Point it at the relay, the iPad/iOS app, or anything else that listens for Face Cap.
 *
 *   node relay/replay.mjs                         newest take in recordings/ -> 127.0.0.1:8080
 *   node relay/replay.mjs recordings/take-....json --to 192.168.1.42:8080 --loop
 *
 * Options: --to host:port (default 127.0.0.1:8080), --loop, --speed 0.5 (slow motion)
 */
import dgram from 'node:dgram';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const loop = args.includes('--loop');
const speed = Number(opt('speed', '1')) || 1;
const [host, portText] = opt('to', '127.0.0.1:8080').split(':');
const port = Number(portText || 8080);

let file = args.find((a) => a.endsWith('.json'));
if (!file) {
  const dir = path.join(ROOT, 'recordings');
  const takes = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => /^take-.*\.json$/.test(f)).sort() : [];
  if (!takes.length) {
    console.error('No takes in recordings/. Record one in the app (press r), or pass a file.');
    process.exit(1);
  }
  file = path.join(dir, takes[takes.length - 1]);
}
const take = JSON.parse(fs.readFileSync(file, 'utf8'));
const frames = take.frames;

const pad = (b) => {
  const out = Buffer.alloc(Math.ceil((b.length + 1) / 4) * 4);
  b.copy(out);
  return out;
};
const oscString = (s) => pad(Buffer.from(s));
function message(address, ints, floats) {
  const tags = ',' + 'i'.repeat(ints.length) + 'f'.repeat(floats.length);
  const data = Buffer.alloc(4 * (ints.length + floats.length));
  ints.forEach((v, i) => data.writeInt32BE(v, 4 * i));
  floats.forEach((v, i) => data.writeFloatBE(v, 4 * (ints.length + i)));
  return Buffer.concat([oscString(address), oscString(tags), data]);
}
function bundle(messages) {
  const head = Buffer.concat([oscString('#bundle'), Buffer.from([0, 0, 0, 0, 0, 0, 0, 1])]);
  const parts = [head];
  for (const m of messages) {
    const size = Buffer.alloc(4);
    size.writeInt32BE(m.length);
    parts.push(size, m);
  }
  return Buffer.concat(parts);
}
function packet(f) {
  const ms = f.w.map((v, i) => message('/W', [i], [v]));
  ms.push(message('/HT', [], f.ht), message('/HR', [], f.hr), message('/ELR', [], f.el), message('/ERR', [], f.er));
  return bundle(ms);
}

const socket = dgram.createSocket('udp4');
console.log(`[replay] ${path.relative(ROOT, file)}: ${frames.length} frames, ${take.seconds?.toFixed?.(1) ?? '?'} s -> ${host}:${port}${loop ? ' (looping)' : ''}${speed !== 1 ? ` at ${speed}x` : ''}`);

let i = 0;
let start = Date.now();
function tick() {
  const now = (Date.now() - start) / 1000 * speed;
  while (i < frames.length && frames[i].t <= now) {
    socket.send(packet(frames[i]), port, host);
    i++;
  }
  if (i >= frames.length) {
    if (!loop) {
      setTimeout(() => socket.close(), 100);
      console.log('[replay] done');
      return;
    }
    i = 0;
    start = Date.now();
  }
  setTimeout(tick, 4);
}
tick();
