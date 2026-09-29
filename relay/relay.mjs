#!/usr/bin/env node
/**
 * Face Cap → WebSocket relay.
 *
 * Face Cap live mode sends OSC over UDP, which a browser (and therefore a
 * Capacitor WebView) cannot receive directly. This script listens for those
 * UDP datagrams and forwards each one, byte for byte, to every connected
 * WebSocket client. All OSC parsing happens in the app.
 *
 *   node relay/relay.mjs [--udp 8080] [--ws 8765] [--fake]
 *
 * --fake generates synthetic Face Cap data at 60 fps so you can develop
 * without an iPhone.
 *
 * Control channel: the same WebSocket carries JSON text frames such as
 * {"type":"action","name":"lap"}. They come from
 *   - OSC on the UDP port: address "/action" with a string argument, or
 *     "/action/lap" (from QLab, TouchOSC, Ableton, ...)
 *   - the control page at http://<relay>:<ws port>/ (buttons + keyboard)
 *   - any WebSocket client sending a text frame
 * and are rebroadcast to every connected app.
 */
import dgram from 'node:dgram';
import http from 'node:http';
import os from 'node:os';
import { WebSocketServer } from 'ws';

const args = parseArgs(process.argv.slice(2));
const UDP_PORT = Number(args.udp ?? process.env.FACECAP_UDP_PORT ?? 8080);
const WS_PORT = Number(args.ws ?? process.env.FACECAP_WS_PORT ?? 8765);
const FAKE = Boolean(args.fake);

const httpServer = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(CONTROL_PAGE);
  } else if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ clients: clients.size, fake: FAKE }));
  } else {
    res.writeHead(404);
    res.end();
  }
});
const wss = new WebSocketServer({ server: httpServer });
let clients = new Set();
let packetsIn = 0;
let packetsOut = 0;

wss.on('connection', (ws, req) => {
  clients.add(ws);
  console.log(`[ws] client connected from ${req.socket.remoteAddress} (${clients.size} total)`);
  ws.on('message', (data, isBinary) => {
    // Text frames are control messages; pass them on to everyone else.
    if (!isBinary) sendControl(data.toString(), ws);
  });
  ws.on('close', () => {
    clients.delete(ws);
    console.log(`[ws] client disconnected (${clients.size} total)`);
  });
  ws.on('error', () => {});
});
httpServer.listen(WS_PORT);

function broadcast(buf) {
  for (const ws of clients) {
    if (ws.readyState === ws.OPEN) {
      ws.send(buf, { binary: true });
      packetsOut++;
    }
  }
}

function sendControl(text, except = null) {
  let msg;
  try {
    msg = JSON.parse(text);
  } catch {
    return;
  }
  if (!msg || typeof msg.type !== 'string') return;
  if (msg.type === 'action') console.log(`[action] ${msg.name}`);
  for (const ws of clients) {
    if (ws !== except && ws.readyState === ws.OPEN) ws.send(text);
  }
}

/** OSC "/action lap" or "/action/lap" → control message. Anything else is Face Cap data. */
function handleOscControl(msg) {
  if (msg.length < 8 || msg[0] !== 0x2f) return false; // not a bare OSC message
  const end = msg.indexOf(0);
  const address = msg.toString('utf8', 0, end === -1 ? msg.length : end);
  if (!address.startsWith('/action')) return false;
  let name = address.slice('/action'.length).replace(/^\//, '');
  if (!name) {
    // First string argument, if any.
    const tagsStart = align4(end + 1);
    const tagsEnd = msg.indexOf(0, tagsStart);
    const tags = msg.toString('utf8', tagsStart, tagsEnd === -1 ? msg.length : tagsEnd);
    const argStart = align4(tagsEnd + 1);
    if (tags[1] === 's') {
      const strEnd = msg.indexOf(0, argStart);
      name = msg.toString('utf8', argStart, strEnd === -1 ? msg.length : strEnd);
    }
  }
  if (name) sendControl(JSON.stringify({ type: 'action', name }));
  return true;
}

function align4(n) {
  return (n + 3) & ~3;
}

// The UDP port is always open: Face Cap data plus OSC "/action" control
// messages. In --fake mode real Face Cap packets are ignored so the two
// streams don't fight.
const udp = dgram.createSocket('udp4');
udp.on('message', (msg) => {
  if (handleOscControl(msg)) return;
  if (FAKE) return;
  packetsIn++;
  broadcast(msg);
});
udp.on('error', (err) => {
  console.error('[udp] error', err);
  process.exit(1);
});
udp.bind(UDP_PORT, '0.0.0.0', () => {
  console.log(`[udp] listening on 0.0.0.0:${UDP_PORT}`);
});
if (FAKE) startFake();

console.log(`[ws]  listening on ws://0.0.0.0:${WS_PORT}`);
console.log(`[http] control page on http://0.0.0.0:${WS_PORT}/`);
console.log('');
console.log('In Face Cap → Live Mode, enter one of these addresses and the UDP port:');
for (const ip of lanAddresses()) console.log(`    ${ip}  port ${UDP_PORT}`);
console.log('');
console.log('In the app, connect to:');
for (const ip of lanAddresses()) console.log(`    ws://${ip}:${WS_PORT}`);
console.log('');
console.log('Trigger actions from:');
for (const ip of lanAddresses()) console.log(`    http://${ip}:${WS_PORT}/   (buttons + keyboard)`);
console.log(`    OSC "/action lap" or "/action/lap" to UDP port ${UDP_PORT}`);
console.log('');

setInterval(() => {
  if (packetsIn || packetsOut) {
    console.log(`[stats] in ${Math.round(packetsIn / 5)}/s  out ${Math.round(packetsOut / 5)}/s  clients ${clients.size}`);
  }
  packetsIn = 0;
  packetsOut = 0;
}, 5000);

// --- helpers ---------------------------------------------------------------

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith('--')) {
      out[key] = next;
      i++;
    } else {
      out[key] = true;
    }
  }
  return out;
}

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const iface of list ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) out.push(iface.address);
    }
  }
  return out.length ? out : ['127.0.0.1'];
}

// --- control page -----------------------------------------------------------

const CONTROL_PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Facefish control</title>
<style>
  body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;
       background:#04101c;color:#dbe9f5;font:16px/1.4 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;-webkit-user-select:none;user-select:none}
  h1{font-size:18px;font-weight:600;margin:0;opacity:.8}
  #grid{display:grid;grid-template-columns:repeat(2,minmax(140px,1fr));gap:12px;padding:0 16px;width:min(480px,100%);box-sizing:border-box}
  button{padding:28px 12px;border:0;border-radius:16px;background:#1b4a6b;color:#fff;font:600 20px/1 inherit;touch-action:manipulation}
  button:active{background:#3ddc84;color:#04101c}
  small{opacity:.55}
  #status{display:flex;align-items:center;gap:8px}
  #dot{width:10px;height:10px;border-radius:50%;background:#ffb648}
  #dot.ok{background:#3ddc84}#dot.bad{background:#ff5c5c}
  #last{min-height:1.4em;opacity:.8}
</style></head><body>
<h1>Facefish control</h1>
<div id="status"><span id="dot"></span><span id="text">connecting…</span></div>
<div id="grid">
  <button data-action="lap">Lap <small>1</small></button>
  <button data-action="spin">Spin <small>2</small></button>
  <button data-action="nod">Nod <small>3</small></button>
  <button data-action="wiggle">Wiggle <small>4</small></button>
  <button data-action="shake">Shake <small>5</small></button>
  <button data-action="bounce">Bounce <small>6</small></button>
  <button data-action="dash">Dash <small>7</small></button>
</div>
<div id="last"></div>
<small>Keys: 1–7, arrows, Page Up/Down, Space, Enter. MIDI note → action if a device is connected.</small>
<script>
  const keys = {'1':'lap','2':'spin','3':'nod','4':'wiggle','5':'shake','6':'bounce','7':'dash',PageDown:'lap',ArrowRight:'lap',PageUp:'spin',ArrowLeft:'spin',ArrowUp:'nod',ArrowDown:'wiggle',' ':'nod',Enter:'lap',l:'lap',s:'spin',n:'nod',w:'wiggle',k:'shake',b:'bounce',d:'dash'};
  const midiNotes = {36:'lap',37:'spin',38:'nod',39:'wiggle',40:'shake',41:'bounce',42:'dash',60:'lap',62:'spin',64:'nod',65:'wiggle',67:'shake',69:'bounce',71:'dash'};
  let ws;
  function connect(){
    ws = new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host);
    ws.onopen=()=>{dot.className='ok';text.textContent='connected to relay'};
    ws.onclose=()=>{dot.className='bad';text.textContent='disconnected, retrying…';setTimeout(connect,1000)};
    ws.onerror=()=>{};
  }
  connect();
  function trigger(name){
    if(!ws||ws.readyState!==1) return;
    ws.send(JSON.stringify({type:'action',name}));
    last.textContent='▶ '+name; setTimeout(()=>{ if(last.textContent==='▶ '+name) last.textContent=''; },1500);
  }
  document.querySelectorAll('button').forEach(b=>b.addEventListener('click',()=>trigger(b.dataset.action)));
  window.addEventListener('keydown',e=>{const a=keys[e.key]; if(a){e.preventDefault();trigger(a);}});
  if(navigator.requestMIDIAccess){
    navigator.requestMIDIAccess().then(m=>{
      const hook=()=>{ for(const input of m.inputs.values()){ input.onmidimessage=ev=>{ const [st,note,vel]=ev.data; if((st&0xf0)===0x90&&vel>0){ const a=midiNotes[note]; if(a) trigger(a);} }; } };
      hook(); m.onstatechange=hook;
    }).catch(()=>{});
  }
</script></body></html>`;

// --- fake Face Cap ----------------------------------------------------------

function oscString(s) {
  const bytes = Buffer.from(s + '\0', 'utf8');
  const pad = (4 - (bytes.length % 4)) % 4;
  return Buffer.concat([bytes, Buffer.alloc(pad)]);
}

function oscMessage(address, args) {
  const tags = ',' + args.map((a) => (Number.isInteger(a) && a.__int !== false ? 'i' : 'f')).join('');
  const parts = [oscString(address), oscString(tags)];
  for (const a of args) {
    const b = Buffer.alloc(4);
    if (Number.isInteger(a)) b.writeInt32BE(a);
    else b.writeFloatBE(a);
    parts.push(b);
  }
  return Buffer.concat(parts);
}

function oscBundle(messages) {
  const parts = [oscString('#bundle'), Buffer.alloc(8)];
  parts[1].writeUInt32BE(1, 4); // "immediately" timetag
  for (const m of messages) {
    const size = Buffer.alloc(4);
    size.writeInt32BE(m.length);
    parts.push(size, m);
  }
  return Buffer.concat(parts);
}

function startFake() {
  console.log('[fake] generating synthetic Face Cap data at 60 fps');
  const JAW_OPEN = 24;
  const BLINK_L = 13;
  const BLINK_R = 14;
  const SMILE_L = 37;
  const SMILE_R = 38;
  const BROW_INNER = 0;
  const LOOK_OUT_L = 11;
  const LOOK_IN_R = 10;
  const TONGUE = 51;
  const CHEEK = 19;

  const start = Date.now();
  setInterval(() => {
    const t = (Date.now() - start) / 1000;
    const w = new Float32Array(52);
    // Talking: rapid jaw motion with a slower envelope.
    w[JAW_OPEN] = Math.max(0, Math.sin(t * 9) * 0.5 + 0.3) * (0.5 + 0.5 * Math.sin(t * 0.7));
    // Blink every ~3 s.
    const blink = Math.max(0, Math.sin(((t % 3) / 0.25) * Math.PI)) * (t % 3 < 0.25 ? 1 : 0);
    w[BLINK_L] = w[BLINK_R] = blink;
    w[SMILE_L] = w[SMILE_R] = 0.5 + 0.5 * Math.sin(t * 0.5);
    w[BROW_INNER] = 0.5 + 0.5 * Math.sin(t * 0.8 + 1);
    const look = Math.sin(t * 0.6);
    w[LOOK_OUT_L] = Math.max(0, look);
    w[LOOK_IN_R] = Math.max(0, look);
    w[TONGUE] = Math.max(0, Math.sin(t * 0.3) - 0.7) / 0.3;
    w[CHEEK] = Math.max(0, Math.sin(t * 0.4 + 2) - 0.5) * 2;

    const messages = [];
    for (let i = 0; i < 52; i++) messages.push(oscMessage('/W', [i, w[i]]));
    // Centimetres from the phone, like Face Cap: a slow wander around the bowl.
    messages.push(oscMessage('/HT', [Math.sin(t * 0.3) * 6, Math.sin(t * 0.7) * 3, -40 + Math.sin(t * 0.45) * 8]));
    messages.push(oscMessage('/HR', [10 * Math.sin(t * 0.9), 25 * Math.sin(t * 0.5), 8 * Math.sin(t * 0.4)]));
    messages.push(oscMessage('/ELR', [0, 0]));
    messages.push(oscMessage('/ERR', [0, 0]));
    packetsIn++;
    broadcast(oscBundle(messages));
  }, 1000 / 60);
}
