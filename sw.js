/* Pocket Arcade offline copy: keeps the arcade and every game on this device. (c) 2026 Asaf */
const CACHE = 'pocket-arcade';
const VERSION = 'b42f601b3244';
const FILES = ["g/afterimage.html", "g/arcane-gambit.html", "g/bug-blockade.html", "g/court-crew.html", "g/dodge-duel.html", "g/dodge-fight.html", "g/dodge-rush.html", "g/dopamine-overload.html", "g/fold-and-fly.html", "g/gem-strike.html", "g/jelly-rumble.html", "g/lanternfall.html", "g/loaded-dice.html", "g/mic-clash.html", "g/monster-ball.html", "g/nightmare-sleepover.html", "g/orrery.html", "g/pocket-holdem.html", "g/rift-breaker.html", "g/rod-rivals.html", "g/sideways-rally.html", "g/skyline-sprint.html", "thumbs/afterimage.webp", "thumbs/arcane-gambit.webp", "thumbs/bug-blockade.webp", "thumbs/court-crew.webp", "thumbs/dodge-duel.webp", "thumbs/dodge-fight.webp", "thumbs/dodge-rush.webp", "thumbs/dopamine-overload.webp", "thumbs/fold-and-fly.webp", "thumbs/gem-strike.webp", "thumbs/jelly-rumble.webp", "thumbs/lanternfall.webp", "thumbs/loaded-dice.webp", "thumbs/mic-clash.webp", "thumbs/monster-ball.webp", "thumbs/nightmare-sleepover.webp", "thumbs/orrery.webp", "thumbs/pocket-holdem.webp", "thumbs/rift-breaker.webp", "thumbs/rod-rivals.webp", "thumbs/sideways-rally.webp", "thumbs/skyline-sprint.webp", "icon-512.png", "apple-touch-icon.png"];
const FONT_CSS = ["https://fonts.googleapis.com/css2?family=Chakra+Petch:ital,wght@0,500;0,600;1,600;1,700&display=swap", "https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@400;500;600;700&family=Michroma&display=swap", "https://fonts.googleapis.com/css2?family=Cinzel:wght@500;600;700&family=Jost:wght@400;500;600;700&display=swap", "https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700;900&display=swap", "https://fonts.googleapis.com/css2?family=Shippori+Mincho+B1:wght@600;700;800&family=Zen+Kaku+Gothic+New:wght@400;500;700&display=swap"];
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'favicon.png', 'icon-192.png'];
self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => Promise.all(SHELL.map((f) => fetch(f, { cache: 'reload' }).then((r) => r.ok && c.put(f, r)).catch(() => {})))));
});
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
function key(req) {
  const u = new URL(req.url);
  if (u.origin !== location.origin) return req.url;
  const base = new URL('./', self.registration.scope).pathname;
  let p = u.pathname.startsWith(base) ? u.pathname.slice(base.length) : u.pathname;
  if (p === '' || p.endsWith('/')) p += 'index.html';
  return new URL(p, self.registration.scope).href;
}
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const u = new URL(req.url);
  const fonts = /(^|\.)fonts\.(googleapis|gstatic)\.com$/.test(u.hostname);
  if (u.origin !== location.origin && !fonts) return;
  e.respondWith(caches.open(CACHE).then(async (c) => {
    const k = key(req);
    const hit = await c.match(k, { ignoreSearch: !fonts });
    // saved copy first (works on a plane), refreshed in the background when online
    const net = fetch(req).then((r) => { if (r && (r.ok || r.type === 'opaque')) c.put(k, r.clone()); return r; }).catch(() => null);
    if (hit) { e.waitUntil(net); return hit; }
    const r = await net;
    return r || new Response('Offline and not saved yet', { status: 503, headers: { 'Content-Type': 'text/plain' } });
  }));
});
self.addEventListener('message', (e) => { if (e.data && e.data.t === 'saveAll') e.waitUntil(saveAll(e.source)); });
async function saveAll(client) {
  const c = await caches.open(CACHE);
  const list = SHELL.concat(FILES);
  const total = list.length + FONT_CSS.length;
  let done = 0;
  const tell = (m) => { try { client && client.postMessage(m); } catch (x) { /* page gone */ } };
  for (const f of list) {
    try { const r = await fetch(f, { cache: 'reload' }); if (r.ok) await c.put(new URL(f, self.registration.scope).href, r); } catch (x) { /* try next */ }
    done++; if (done % 3 === 0 || done === total) tell({ t: 'progress', done, total });
  }
  for (const css of FONT_CSS) {
    try {
      const r = await fetch(css, { mode: 'cors' });
      if (r.ok) {
        const text = await r.clone().text();
        await c.put(css, r);
        const urls = Array.from(text.matchAll(/url\((https:[^)]+)\)/g)).map((m) => m[1]);
        for (const f of urls) { try { const fr = await fetch(f, { mode: 'cors' }); if (fr.ok) await c.put(f, fr); } catch (x) { /* skip */ } }
      }
    } catch (x) { /* skip */ }
    done++; tell({ t: 'progress', done, total });
  }
  tell({ t: 'saved', version: VERSION });
}
