// Service worker do Eito: guarda o próprio app no aparelho para que ele
// abra no curral sem sinal. Os DADOS (animais, pesagens) não passam por aqui:
// quem guarda e sincroniza os dados é o Firestore, com cache próprio.
//
// O número abaixo é trocado sozinho a cada publicação pelo GitHub Actions,
// para os aparelhos baixarem o app novo.
const CACHE = 'eito-v1';
const ESSENCIAIS = ['./', 'index.html', 'manifest.json', 'flutter_bootstrap.js', 'main.dart.js', 'favicon.png', 'icons/Icon-192.png'];
// Demais arquivos do app (CanvasKit, fontes, imagens). A lista é preenchida
// pela publicação; sem ela, esses arquivos vêm da versão anterior guardada.
const DO_BUILD = [/* ARQUIVOS_DO_BUILD */];

// Scripts do Firebase e fontes vêm de servidores do Google: guardar também,
// senão o app não abre sem internet. Os pedaços do mapa (satélite e ruas) já
// vistos também ficam guardados, para o mapa abrir no pasto sem sinal.
const EXTERNOS = [
  'https://www.gstatic.com',
  'https://fonts.gstatic.com',
  'https://fonts.googleapis.com',
  'https://server.arcgisonline.com',
  'https://tile.openstreetmap.org',
];

// Instala a versão nova inteira antes de trocar: se o aparelho ficar sem
// sinal logo depois da atualização, o app ainda abre.
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then(async (c) => {
      await c.addAll(ESSENCIAIS.map((u) => new Request(u, { cache: 'reload' })));
      // Os outros um a um: um arquivo que falhe não impede a atualização.
      await Promise.all(
        DO_BUILD.map((u) =>
          fetch(new Request(u, { cache: 'reload' }))
            .then((r) => (r.ok ? c.put(u, r) : null))
            .catch(() => null)
        )
      );
    }).then(() => self.skipWaiting())
  );
});

// Antes de apagar a versão antiga, traz dela o que a nova não conseguiu
// baixar (CanvasKit, fontes, mapas já vistos).
self.addEventListener('activate', (e) => {
  e.waitUntil(
    (async () => {
      const nova = await caches.open(CACHE);
      for (const k of await caches.keys()) {
        if (k === CACHE) continue;
        const velha = await caches.open(k);
        for (const req of await velha.keys()) {
          const u = new URL(req.url);
          const doApp = u.origin === self.location.origin;
          if (doApp && ESSENCIAIS.some((x) => u.pathname.endsWith('/' + x.replace('./', '')))) continue;
          if (!(await nova.match(req))) {
            const r = await velha.match(req);
            if (r) await nova.put(req, r);
          }
        }
        await caches.delete(k);
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  if (url.origin !== self.location.origin) {
    if (!EXTERNOS.includes(url.origin)) return; // Firestore e login: nunca do cache
    // Arquivos com versão no endereço: usa o guardado; se não tiver, baixa e guarda.
    e.respondWith(
      caches.match(req).then(
        (guardado) =>
          guardado ||
          fetch(req).then((r) => {
            if (r.ok || r.type === 'opaque') {
              const copia = r.clone();
              caches.open(CACHE).then((c) => c.put(req, copia));
            }
            return r;
          })
      )
    );
    return;
  }

  // Páginas avulsas (folder, cotação do fornecedor): sempre da rede, sem
  // trocar o app guardado.
  if (/\.html$/.test(url.pathname) && !url.pathname.endsWith('/index.html')) return;

  // Abrir o app: tenta a rede (versão nova); sem sinal, usa a guardada.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((r) => {
          // Só guarda o app de verdade: nada de erro, redirecionamento ou portal de Wi-Fi.
          const tipo = r.headers.get('content-type') || '';
          if (r.ok && !r.redirected && tipo.includes('text/html')) {
            const copia = r.clone();
            caches.open(CACHE).then((c) => c.put('index.html', copia));
          }
          return r;
        })
        .catch(() => caches.match('index.html'))
    );
    return;
  }

  // Arquivos do app: responde do aparelho na hora e atualiza por trás.
  e.respondWith(
    caches.match(req).then((guardado) => {
      const daRede = fetch(req, { cache: 'no-cache' })
        .then((r) => {
          if (r.ok) {
            const copia = r.clone();
            caches.open(CACHE).then((c) => c.put(req, copia));
          }
          return r;
        })
        .catch(() => guardado);
      return guardado || daRede;
    })
  );
});
