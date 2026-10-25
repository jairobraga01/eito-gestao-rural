// Lê o texto de uma nota de compra no próprio aparelho: XML da NF-e, PDF (pdf.js) e foto (Tesseract).
// As bibliotecas só são baixadas quando a pessoa usa a leitura de nota.
(function () {
  var PDFJS = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
  var PDFJS_WORKER = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
  var TESSERACT = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';
  var carregados = {};

  function script(src) {
    if (!carregados[src]) {
      carregados[src] = new Promise(function (ok, erro) {
        var s = document.createElement('script');
        s.src = src;
        s.onload = ok;
        // Falhou: esquece, para tentar de novo quando voltar o sinal.
        s.onerror = function () { delete carregados[src]; s.remove(); erro(new Error('Sem internet para carregar o leitor.')); };
        document.head.appendChild(s);
      });
    }
    return carregados[src];
  }

  // Junta os pedaços de texto do PDF em linhas, pela posição vertical.
  function linhasDaPagina(itens) {
    var linhas = [];
    itens.forEach(function (it) {
      if (!it.str || !it.str.trim()) return;
      var y = Math.round(it.transform[5] / 3);
      var l = linhas.find(function (x) { return Math.abs(x.y - y) <= 1; });
      if (!l) { l = { y: y, partes: [] }; linhas.push(l); }
      l.partes.push({ x: it.transform[4], t: it.str });
    });
    linhas.sort(function (a, b) { return b.y - a.y; });
    return linhas.map(function (l) {
      l.partes.sort(function (a, b) { return a.x - b.x; });
      return l.partes.map(function (p) { return p.t; }).join(' ');
    });
  }

  async function ocr(imagem, aviso) {
    await script(TESSERACT);
    var r = await window.Tesseract.recognize(imagem, 'por', {
      logger: function (m) { if (aviso && m.status) aviso(m.status, m.progress || 0); },
    });
    return r.data.text;
  }

  async function lerPdf(arquivo, aviso) {
    await script(PDFJS);
    window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER;
    var pdf = await window.pdfjsLib.getDocument({ data: await arquivo.arrayBuffer() }).promise;
    var texto = [];
    for (var n = 1; n <= Math.min(pdf.numPages, 6); n++) {
      var p = await pdf.getPage(n);
      var c = await p.getTextContent();
      texto = texto.concat(linhasDaPagina(c.items));
    }
    if (texto.join('').replace(/\s/g, '').length > 80) return texto.join('\n');
    // PDF de imagem (nota escaneada): desenha a página e lê como foto.
    var saida = [];
    for (var k = 1; k <= Math.min(pdf.numPages, 3); k++) {
      var pg = await pdf.getPage(k);
      var vp = pg.getViewport({ scale: 2 });
      var cv = document.createElement('canvas');
      cv.width = vp.width;
      cv.height = vp.height;
      await pg.render({ canvasContext: cv.getContext('2d'), viewport: vp }).promise;
      saida.push(await ocr(cv, aviso));
    }
    return saida.join('\n');
  }

  // arquivo: File escolhido; aviso(status, 0..1) opcional. Devolve o texto da nota.
  window.eitoLerNota = async function (arquivo, aviso) {
    var nome = (arquivo.name || '').toLowerCase();
    if (nome.endsWith('.xml') || arquivo.type === 'text/xml' || arquivo.type === 'application/xml') return await arquivo.text();
    if (nome.endsWith('.pdf') || arquivo.type === 'application/pdf') return await lerPdf(arquivo, aviso);
    return await ocr(arquivo, aviso);
  };
})();
