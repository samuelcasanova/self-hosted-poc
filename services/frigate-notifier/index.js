'use strict';

const mqtt = require('mqtt');
const http = require('node:http');

const MQTT_HOST        = process.env.MQTT_HOST        || 'mosquitto';
const FRIGATE_URL      = process.env.FRIGATE_URL      || 'http://frigate:5000';
const TOKEN            = process.env.TELEGRAM_BOT_TOKEN;
const CHAT_ID          = process.env.TELEGRAM_CHAT_ID;
const COOLDOWN_MS      = (Number.parseInt(process.env.COOLDOWN_SECONDS) || 60) * 1000;
const TRACKED_LABELS   = new Set((process.env.TRACKED_LABELS || 'person').split(','));
const CLIP_DELAY_MS    = 5_000; // wait for Frigate to finalize the clip after event end

if (!TOKEN || !CHAT_ID) {
  console.error('TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set');
  process.exit(1);
}

let lastNotificationAt = 0;

function isAlarmActive() {
  return process.env.ALARM_ACTIVE === 'true';
}

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        res.resume();
        return;
      }
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function sendTelegram(endpoint, form) {
  const res = await fetch(`https://api.telegram.org/bot${TOKEN}/${endpoint}`, {
    method: 'POST',
    body: form,
  });
  if (!res.ok) throw new Error(`Telegram ${endpoint}: ${await res.text()}`);
  return res.json();
}

async function handleEvent(event) {
  const { id, label, camera, top_score: score } = event;
  const pct = Math.round((score || 0) * 100);
  const caption = `[${camera}] ${label} detected (${pct}% confidence)`;

  console.log(`Notifying: event ${id} — ${caption}`);

  // 1. Send snapshot immediately so you get an alert without waiting for the clip
  if (event.has_snapshot) {
    try {
      const buf = await fetchBuffer(`${FRIGATE_URL}/api/events/${id}/snapshot.jpg`);
      const form = new FormData();
      form.append('chat_id', CHAT_ID);
      form.append('photo', new Blob([buf], { type: 'image/jpeg' }), 'snapshot.jpg');
      form.append('caption', caption);
      await sendTelegram('sendPhoto', form);
      console.log(`Snapshot sent for ${id}`);
    } catch (e) {
      console.error(`Snapshot failed for ${id}:`, e.message);
    }
  }

  // 2. Wait for Frigate to write the clip, then send the video
  if (event.has_clip) {
    await new Promise((r) => setTimeout(r, CLIP_DELAY_MS));
    try {
      const buf = await fetchBuffer(`${FRIGATE_URL}/api/events/${id}/clip.mp4`);
      const MB = buf.length / 1024 / 1024;
      if (MB > 49) {
        console.log(`Clip too large for Telegram (${MB.toFixed(1)} MB) — skipping video`);
      } else {
        const form = new FormData();
        form.append('chat_id', CHAT_ID);
        form.append('video', new Blob([buf], { type: 'video/mp4' }), 'clip.mp4');
        form.append('caption', caption);
        await sendTelegram('sendVideo', form);
        console.log(`Clip sent for ${id} (${MB.toFixed(1)} MB)`);
      }
    } catch (e) {
      console.error(`Clip failed for ${id}:`, e.message);
    }
  }
}

const client = mqtt.connect(`mqtt://${MQTT_HOST}`);

client.on('connect', () => {
  console.log(`Connected to MQTT at ${MQTT_HOST}`);
  client.subscribe('frigate/events', (err) => {
    if (err) console.error('Subscribe error:', err.message);
    else console.log('Subscribed to frigate/events');
  });
});

client.on('message', (_topic, payload) => {
  let data;
  try {
    data = JSON.parse(payload.toString());
  } catch {
    return;
  }

  // Only act when an event fully ends (clip + snapshot are finalized at this point)
  if (data.type !== 'end') return;

  const event = data.after;

  if (!TRACKED_LABELS.has(event.label)) return;
  if (!event.has_clip && !event.has_snapshot) return;

  if (!isAlarmActive()) {
    console.log(`[${event.id}] Alarm inactive — skipped`);
    return;
  }

  const now = Date.now();
  if (now - lastNotificationAt < COOLDOWN_MS) {
    const remaining = Math.round((COOLDOWN_MS - (now - lastNotificationAt)) / 1000);
    console.log(`[${event.id}] Cooldown (${remaining}s left) — skipped`);
    return;
  }

  lastNotificationAt = now;
  handleEvent(event).catch((e) => console.error('handleEvent failed:', e));
});

client.on('error', (err) => console.error('MQTT error:', err.message));
client.on('reconnect', () => console.log('MQTT reconnecting...'));
