import * as THREE from 'three';
import { ActionPlayer } from './actions/ActionPlayer';
import { GestureTriggers, installKeyboardTriggers } from './actions/triggers';
import { loadConfig, loadFaceNeutral, saveConfig, saveFaceNeutral } from './config';
import { FaceCapDecoder } from './facecap/decoder';
import { WebSocketSource, type FaceSource } from './facecap/source';
import type { Avatar } from './fish/Avatar';
import { Fish } from './fish/Fish';
import { GltfFish } from './fish/GltfFish';
import { DEFAULT_MAPPING, FaceToFishMapper } from './fish/mapping';
import { Stage } from './scene';
import { Hud } from './ui/hud';
import { KeyMonitor } from './ui/monitor';
import { Panel } from './ui/panel';
import { RecordingUi } from './ui/recording';

const STORAGE_KEY = 'facefish.relayUrl';
const DEFAULT_MODEL = './models/fish.glb';
const DEFAULT_HELMET_TEXTURE = './textures/helmet.jpg';

function defaultRelayUrl(): string {
  const fromQuery = new URLSearchParams(location.search).get('ws');
  if (fromQuery) return fromQuery;
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) return saved;
  } catch {
    /* storage unavailable */
  }
  // When served by `vite --host` the hostname is the dev machine, which is
  // also where the relay runs. Inside Capacitor it's "localhost", so the
  // user has to enter the relay address once; it's then remembered.
  const host = location.hostname && location.hostname !== 'localhost' ? location.hostname : '192.168.1.10';
  return `ws://${host}:8765`;
}

/**
 * Load the Blender model if there is one (`public/models/fish.glb`, or
 * `?model=<url>`), otherwise fall back to the procedural fish.
 */
async function loadAvatar(): Promise<Avatar> {
  const param = new URLSearchParams(location.search).get('model');
  const url = param ?? DEFAULT_MODEL;
  try {
    const fish = await GltfFish.load(url);
    console.info(`[facefish] loaded model ${url}\n  ${fish.report.join('\n  ')}`);
    return fish;
  } catch (err) {
    // A missing file is normal (no Blender model yet); anything else is a broken export worth seeing.
    const missing = await fetch(url, { method: 'HEAD' }).then((r) => !r.ok).catch(() => true);
    if (missing && !param) console.info('[facefish] no models/fish.glb, using procedural fish');
    else console.error(`[facefish] could not load ${url}, using procedural fish:`, err);
    return new Fish();
  }
}

async function main(): Promise<void> {
  const config = loadConfig();
  console.info('[facefish] config', config);
  if (config.porthole) document.body.classList.add('porthole');

  const canvas = document.getElementById('stage') as HTMLCanvasElement;
  const stage = new Stage(canvas);
  stage.setFraming(config.zoom, config.offsetY);
  const fish = await loadAvatar();
  stage.scene.add(fish.root);
  const monitor = new KeyMonitor();
  monitor.setModelShapes(fish.shapeKeys ?? null);
  // Optional photo of the real helmet interior; the procedural brass stays otherwise.
  const helmetUrl = new URLSearchParams(location.search).get('helmet_tex') ?? DEFAULT_HELMET_TEXTURE;
  void stage.helmet.loadTexture(helmetUrl).then((ok) => {
    if (ok) console.info(`[facefish] helmet texture ${helmetUrl}`);
  });

  const decoder = new FaceCapDecoder();
  const mapper = new FaceToFishMapper({
    ...DEFAULT_MAPPING,
    mirror: config.mirror,
    headGain: config.headGain,
    moveGain: config.moveGain,
    autoCenter: config.autoCenter ? DEFAULT_MAPPING.autoCenter : 0,
    expressionGain: config.expression,
    smoothing: config.smoothing,
    puckerPriority: config.puckerPriority,
  });
  let faceNeutral = loadFaceNeutral();
  const faceStatus = document.getElementById('panel-face-status') as HTMLParagraphElement;
  const showFaceStatus = (): void => {
    faceStatus.textContent = !faceNeutral
      ? 'Relax your face and press Center face: your resting face then counts as zero for every Face Cap value.'
      : config.faceCalibration
        ? 'Face centred: your resting face counts as zero. Press again to redo it.'
        : 'A resting face is stored but Face calibration is off.';
  };
  function centerFace(): void {
    if (mapper.capturingNeutral) return;
    hud.note('Center face: relax your face…', 4000);
    faceStatus.textContent = 'Hold a relaxed face…';
    mapper.captureNeutral(1.5, (rest) => {
      if (!rest) {
        hud.note('Center face: no tracking, nothing changed');
        showFaceStatus();
        applyConfig();
        return;
      }
      faceNeutral = rest;
      saveFaceNeutral(rest);
      config.faceCalibration = true;
      applyConfig();
      panel.refresh();
      hud.note('Face centred');
    });
  }
  // Development builds only: inspect the fish and the mapping from the browser console.
  if (import.meta.env.DEV) (window as unknown as { facefish: unknown }).facefish = { fish, mapper };
  const hud = new Hud(defaultRelayUrl());
  hud.setMode(config.hud);

  // Actions: procedural or Blender clips, triggered by keys, relay messages
  // and (optionally) face gestures.
  const actions = new ActionPlayer(fish);
  actions.strength = config.strength;
  console.info(`[facefish] actions: ${actions.available.join(', ')}`);

  const makeGestures = (): GestureTriggers =>
    new GestureTriggers((name, gesture) => {
      console.info(`[facefish] gesture "${gesture}" → ${name}`);
      actions.trigger(name);
    });
  let gestures: GestureTriggers | null = config.gestures ? makeGestures() : null;

  // Everything the panel can change is applied here, so a URL parameter,
  // a saved setting and a live slider all take the same path.
  function applyConfig(): void {
    saveConfig(config);
    mapper.config.mirror = config.mirror;
    mapper.config.headGain = config.headGain;
    mapper.config.moveGain = config.moveGain;
    mapper.config.autoCenter = config.autoCenter ? DEFAULT_MAPPING.autoCenter : 0;
    mapper.config.expressionGain = config.expression;
    mapper.config.smoothing = config.smoothing;
    mapper.config.puckerPriority = config.puckerPriority;
    mapper.config.faceNeutral = config.faceCalibration ? faceNeutral : null;
    showFaceStatus();
    if (fish.lidAngle !== undefined) fish.lidAngle = config.lidAngle;
    if (fish.lidNeutral !== undefined) fish.lidNeutral = config.lidNeutral;
    if (fish.finReaction !== undefined) fish.finReaction = config.finReaction;
    if (fish.finSway !== undefined) fish.finSway = config.finSway;
    if (fish.finWave !== undefined) fish.finWave = config.finWave;
    if (fish.finWaveSpeed !== undefined) fish.finWaveSpeed = config.finWaveSpeed;
    actions.strength = config.strength;
    stage.setFraming(config.zoom, config.offsetY);
    stage.setCaustics(config.caustics);
    stage.motionBubbles.amount = config.bubbles;
    stage.setTint(config.tint);
    stage.setHelmet(config.helmet);
    document.body.classList.toggle('porthole', config.porthole);
    monitor.setVisible(config.monitor);
    hud.setMode(config.hud);
    gestures = config.gestures ? (gestures ?? makeGestures()) : null;
  }

  const panel = new Panel(config, actions.available, {
    onAction: (name) => actions.trigger(name),
    onChange: applyConfig,
    onCenter: () => mapper.centerHead(),
    onCenterFace: () => centerFace(),
  });
  applyConfig();
  actions.onChange = (name) => {
    hud.flashAction(name);
    panel.setPlaying(name);
  };
  installKeyboardTriggers(
    config.keys,
    (name) => actions.trigger(name),
    (key) => {
      if (key === 'h') hud.toggle();
      if (key === 'p') panel.toggle();
      if (key === 'c') mapper.centerHead();
      if (key === 'f') centerFace();
      if (key === 'r') recording.toggle();
      if (key === 'v') {
        config.monitor = !config.monitor;
        applyConfig();
        panel.refresh();
      }
      if (key === 'Escape') panel.hide();
    },
  );

  let source: FaceSource | null = null;
  // Takes carry the resting face in use, so blender/import_take.py can apply the same calibration.
  const recording = new RecordingUi(
    (msg) => source?.send?.({ ...msg, neutral: mapper.config.faceNeutral ? Array.from(mapper.config.faceNeutral) : null }) ?? false,
  );
  let packetsThisSecond = 0;
  let packetRate = 0;
  let rateTimer = 0;

  function connect(url: string): void {
    source?.stop();
    try {
      localStorage.setItem(STORAGE_KEY, url);
    } catch {
      /* ignore */
    }
    source = new WebSocketSource({ url });
    source.onStateChange = (state, detail) => hud.setSource(state, detail);
    source.onPacket = (data) => {
      const now = performance.now();
      if (decoder.feedPacket(data, now) > 0) {
        mapper.notePacket(now);
        packetsThisSecond++;
      }
    };
    source.onMessage = (msg) => {
      if (msg.type === 'action' && typeof msg.name === 'string') actions.trigger(msg.name);
      if (msg.type === 'record') recording.handle(msg);
    };
    source.start();
  }

  hud.onConnect = connect;
  connect(hud.url);

  canvas.addEventListener('pointerdown', () => hud.toggle());

  const mouth = new THREE.Vector3();
  let last = performance.now();
  let wasLive = false;
  let nextIdleAction = 20;
  function frame(now: number): void {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    const time = now / 1000;

    const pose = mapper.update(decoder.frame, dt, time);
    gestures?.update(decoder.frame, dt, time);
    actions.update(dt);
    fish.update(pose, mapper.weights, time, dt);
    fish.root.updateMatrixWorld(true);
    if (fish.mouthPosition) stage.motionBubbles.pump(dt, fish.mouthPosition(mouth), pose.jawOpen, time);
    stage.update(dt, time);
    stage.render(time);

    // Wall-clock, not the clamped frame dt: while the tab is in the background
    // frames stop but packets keep arriving.
    if (now - rateTimer >= 1000) {
      packetRate = rateTimer > 0 ? (packetsThisSecond * 1000) / (now - rateTimer) : 0;
      packetsThisSecond = 0;
      rateTimer = now;
    }
    const live = mapper.isLive;
    monitor.setRate(packetRate);
    monitor.update(decoder.frame, mapper.weights, live, dt);
    if (live || wasLive) hud.setLive(live, packetRate);
    if (live && !wasLive) hud.trackingStarted();
    if (wasLive && !live && source) hud.setSource(source.state);
    wasLive = live;

    if (config.idleActions && !live && !actions.playing) {
      nextIdleAction -= dt;
      if (nextIdleAction <= 0) {
        nextIdleAction = 20 + Math.random() * 25;
        const pick = ['lap', 'wiggle', 'nod', 'spin'][Math.floor(Math.random() * 4)];
        actions.trigger(pick);
      }
    }

    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

void main();
