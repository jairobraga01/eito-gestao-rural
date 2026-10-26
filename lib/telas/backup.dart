import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/db.dart';
import '../util/util.dart';
import 'base.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool ocupado = false;

  /// Fotos lidas da nuvem para entrar no backup (null = ainda lendo ou sem sinal).
  int? fotos;
  bool lendoFotos = true;

  @override
  void initState() {
    super.initState();
    Db.carregarFotos().then((n) {
      if (mounted) {
        setState(() {
          fotos = n;
          lendoFotos = false;
        });
      }
    });
  }

  /// Copia sem esperar nada antes: o navegador do iPhone só deixa copiar
  /// logo após o toque no botão.
  void exportar() {
    final json = Db.exportarJson();
    Clipboard.setData(ClipboardData(text: json)).then((_) {
      if (!mounted) return;
      avisar(context,
          'Backup copiado (${(json.length / 1024).toStringAsFixed(1)} KB). Cole no WhatsApp, e-mail ou bloco de notas para guardar.');
    }).catchError((Object _) {
      if (mounted) _mostrarTexto(json);
    });
  }

  void _mostrarTexto(String json) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Texto do backup'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: SingleChildScrollView(child: SelectableText(json, style: const TextStyle(fontSize: 12))),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: json)),
            child: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> importar() async {
    final ctrl = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Cole abaixo o texto do backup. Todos os dados atuais serão substituídos.'),
              gap,
              TextField(controller: ctrl, maxLines: 6, decoration: const InputDecoration(hintText: '{"app": ...')),
              TextButton.icon(
                icon: const Icon(Icons.content_paste),
                label: const Text('Colar da área de transferência'),
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  ctrl.text = d?.text ?? '';
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Restaurar')),
        ],
      ),
    );
    if (texto == null || texto.trim().isEmpty || !mounted) return;
    if (!await confirmar(context, 'Substituir todos os dados?',
        'Os dados atuais (na nuvem e em todos os aparelhos desta conta) serão apagados e trocados pelos do backup.',
        ok: 'Substituir')) {
      return;
    }
    setState(() => ocupado = true);
    try {
      final n = await Db.importarJson(texto.trim());
      if (mounted) avisar(context, 'Backup restaurado: $n animal(is).');
    } catch (e) {
      if (mounted) avisar(context, 'Não foi possível restaurar: $e');
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Backup',
      corpo: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Os dados ficam na nuvem (na sua conta) e também guardados neste aparelho para funcionar sem internet. '
            'O backup é uma cópia extra de tudo, de todas as propriedades, para guardar onde quiser.',
          ),
          gap,
          const Text(
            'Também serve para trazer os dados do Eito Gestão antigo (APK, só no celular): '
            'lá, toque em "Copiar backup"; aqui, toque em "Restaurar backup" e cole.',
          ),
          const SizedBox(height: 24),
          Text(
            lendoFotos
                ? 'Buscando as fotos dos animais para o backup…'
                : fotos == null
                    ? 'Sem sinal: as fotos não entram neste backup (só os dados).'
                    : fotos == 0
                        ? 'Nenhuma foto de animal para incluir.'
                        : 'As $fotos foto(s) dos animais entram no backup.',
          ),
          gap,
          FilledButton.icon(
            onPressed: ocupado || lendoFotos ? null : exportar,
            icon: const Icon(Icons.copy_all),
            label: const Text('Copiar backup'),
          ),
          TextButton(
            onPressed: ocupado || lendoFotos ? null : () => _mostrarTexto(Db.exportarJson()),
            child: const Text('Ver o texto do backup'),
          ),
          gap,
          OutlinedButton.icon(
            onPressed: ocupado ? null : importar,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar backup'),
          ),
          if (ocupado) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
