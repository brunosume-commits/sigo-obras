// SIGO — guarda os arquivos do sistema no aparelho para abrir sem internet.
// Os dados (Supabase) não passam por aqui: o app guarda os últimos dados e a fila de lançamentos.
const VERSAO = 'sigo-v3';
const CASCA = ['./', './index.html', './manifest.webmanifest', './icone-192.png', './icone-512.png'];
const CDN = [
  'https://cdn.tailwindcss.com',
  'https://unpkg.com/react@18/umd/react.production.min.js',
  'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone/babel.min.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
];
const HOSTS_CDN = ['cdn.tailwindcss.com', 'unpkg.com', 'cdn.jsdelivr.net'];

self.addEventListener('install', (ev) => {
  ev.waitUntil((async () => {
    const c = await caches.open(VERSAO);
    await c.addAll(CASCA).catch(() => {});
    for (const url of CDN) {
      try { await c.put(url, await fetch(url, { mode: 'cors' })); }
      catch { try { await c.put(url, await fetch(url, { mode: 'no-cors' })); } catch {} }
    }
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (ev) => {
  ev.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== VERSAO) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (ev) => {
  const req = ev.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Bibliotecas: usa a cópia guardada; se não tiver, baixa e guarda
  if (HOSTS_CDN.includes(url.hostname)) {
    ev.respondWith((async () => {
      const c = await caches.open(VERSAO);
      const salvo = await c.match(req, { ignoreVary: true });
      if (salvo) return salvo;
      const r = await fetch(req);
      if (r && (r.ok || r.type === 'opaque')) c.put(req, r.clone());
      return r;
    })());
    return;
  }

  // Arquivos do próprio SIGO: tenta a internet primeiro (pega atualizações) e cai para a cópia
  if (url.origin === self.location.origin) {
    ev.respondWith((async () => {
      const c = await caches.open(VERSAO);
      try {
        const r = await fetch(req);
        if (r.ok) c.put(req.mode === 'navigate' ? './index.html' : req, r.clone());
        return r;
      } catch {
        return (await c.match(req, { ignoreSearch: true })) ||
               (req.mode === 'navigate' ? await c.match('./index.html') : undefined) ||
               new Response('Sem internet', { status: 503 });
      }
    })());
  }
  // Supabase e o resto: direto para a internet
});
