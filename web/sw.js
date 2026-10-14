// Service worker do Eito: guarda o próprio app no aparelho para que ele
// abra no curral sem sinal. Os DADOS (animais, pesagens) não passam por aqui:
// quem guarda e sincroniza os dados é o Firestore, com cache próprio.
//
// O número abaixo é trocado sozinho a cada publicação pelo GitHub Actions,
// para os aparelhos baixarem o app novo.
const CACHE = 'eito-v1';
const ESSENCIAIS = ['./', 'index.html', 'manifest.json', 'flutter_bootstrap.js', 'main.dart.js', 'favicon.svg'];

// Scripts do Firebase e fontes vêm de servidores do Google: guardar também,
// senão o app não abre sem internet.
const EXTERNOS = ['https://www.gstatic.com', 'https://fonts.gstatic.com', 'https://fonts.googleapis.com'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ESSENCIAIS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
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

  // Abrir o app: tenta a rede (versão nova); sem sinal, usa a guardada.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((r) => {
          const copia = r.clone();
          caches.open(CACHE).then((c) => c.put('index.html', copia));
          return r;
        })
        .catch(() => caches.match('index.html'))
    );
    return;
  }

  // Arquivos do app: responde do aparelho na hora e atualiza por trás.
  e.respondWith(
    caches.match(req).then((guardado) => {
      const daRede = fetch(req)
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
