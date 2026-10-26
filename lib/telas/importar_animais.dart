import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/importar_animais.dart';
import '../dados/planos.dart';
import '../dispositivos/arquivo_stub.dart' if (dart.library.js_interop) '../dispositivos/arquivo_web.dart';
import '../tema.dart';
import '../util/util.dart';
import 'financeiro.dart' show entregarArquivo;

/// Importa animais de uma planilha CSV: confere cada linha antes de gravar.
class ImportarAnimaisPage extends StatefulWidget {
  const ImportarAnimaisPage({super.key});

  @override
  State<ImportarAnimaisPage> createState() => _ImportarAnimaisPageState();
}

class _ImportarAnimaisPageState extends State<ImportarAnimaisPage> {
  ConferenciaImportacao? _c;
  bool _gravando = false;
  bool _soErros = false;

  Future<void> _escolher() async {
    final texto = await escolherArquivoTexto(aceitar: '.csv,.txt');
    if (texto == null || !mounted) return;
    setState(() => _c = conferirImportacao(texto, propriedadeId: Db.pid));
  }

  Future<void> _gravar() async {
    final c = _c;
    if (c == null || c.boas.isEmpty) return;
    final trava = bloqueioDeAnimais(hojeIso(), novos: c.boas.length);
    if (trava != null) {
      avisar(context, trava);
      return;
    }
    final ruins = c.ruins.length;
    final ok = await confirmar(
      context,
      'Gravar ${c.boas.length} animal(is)?',
      ruins == 0
          ? 'Todos entram na propriedade ${txt(Db.prop.value?['nome'])}.'
          : '$ruins linha(s) com erro ficam de fora. Corrija na planilha e importe só elas depois.',
      ok: 'Gravar',
    );
    if (!ok) return;
    setState(() => _gravando = true);
    final antes = c.boas.length;
    final n = await gravarImportacao(c, propriedadeId: Db.pid);
    if (!mounted) return;
    // Linhas recusadas na gravação (brinco cadastrado em outro aparelho nesse meio
    // tempo): a lista fica na tela, só com elas, para a pessoa ver quais faltaram.
    final recusadas = antes - n;
    setState(() {
      _gravando = false;
      if (recusadas <= 0) {
        _c = null;
      } else {
        c.linhas.removeWhere((l) => l.ok);
      }
    });
    avisar(context, recusadas <= 0 ? '$n animal(is) importado(s).' : '$n importado(s); $recusadas ficaram de fora (veja a lista).');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar animais (planilha)')),
      bottomNavigationBar: c != null && c.boas.isNotEmpty
          ? BotaoSalvar(
              texto: _gravando ? 'Gravando…' : 'Gravar ${c.boas.length} animal(is)',
              onPressed: _gravando ? null : _gravar,
            )
          : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Salve a planilha como CSV (no Excel: Arquivo › Salvar como › CSV). A primeira linha deve ter os '
          'nomes das colunas. Obrigatórias: brinco e sexo (F ou M). Opcionais: nome, raça, categoria, '
          'nascimento (dd/mm/aaaa), peso, data do peso, lote, RFID, SISBOV, mãe (brinco), pai, origem e obs.',
        ),
        gap,
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _gravando ? null : _escolher,
            icon: const Icon(Icons.upload_file),
            label: Text(c == null ? 'Escolher planilha' : 'Escolher outra'),
          ),
          OutlinedButton.icon(
            onPressed: () => entregarArquivo(context, 'modelo_animais_eito.csv', modeloCsv),
            icon: const Icon(Icons.download),
            label: const Text('Baixar modelo'),
          ),
        ]),
        if (c != null) ...[
          gap,
          if (c.erroGeral != null)
            Card(
              color: Cores.alerta.withValues(alpha: 0.08),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Cores.alerta),
                title: Text(c.erroGeral!),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: _numero('Prontas', c.boas.length, Cores.sucesso)),
                  Expanded(child: _numero('Com erro', c.ruins.length, Cores.alerta)),
                  Expanded(child: _numero('Linhas', c.linhas.length, Cores.tinta)),
                ]),
              ),
            ),
            if (c.colunasIgnoradas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Colunas ignoradas: ${c.colunasIgnoradas.join(', ')}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar só as linhas com erro'),
              value: _soErros,
              onChanged: (v) => setState(() => _soErros = v),
            ),
            for (final l in c.linhas)
              if (!_soErros || !l.ok)
                Card(
                  child: ListTile(
                    leading: Icon(l.ok ? Icons.check_circle : Icons.cancel, color: l.ok ? Cores.sucesso : Cores.alerta),
                    title: Text('Linha ${l.numero} · brinco ${l.brinco.isEmpty ? '—' : l.brinco}'
                        '${txt(l.animal['nome']).isEmpty ? '' : ' · ${l.animal['nome']}'}'),
                    subtitle: Text([
                      [
                        txt(l.animal['sexo']),
                        txt(l.animal['raca']),
                        txt(l.animal['categoria']),
                        if (l.animal['nascimento'] != null) 'nasc. ${br(l.animal['nascimento'])}',
                        if (l.peso != null) kg(l.peso),
                      ].where((x) => x.isNotEmpty).join(' · '),
                      ...l.erros,
                      ...l.avisos.map((a) => '⚠ $a'),
                    ].where((x) => x.isNotEmpty).join('\n')),
                  ),
                ),
          ],
        ],
        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _numero(String t, int n, Color cor) => Column(children: [
        Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cor)),
        Text(t),
      ]);
}
