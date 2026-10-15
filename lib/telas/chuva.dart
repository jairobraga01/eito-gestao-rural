import 'package:flutter/material.dart';

import '../dados/db.dart';
import '../dados/gestao.dart';
import '../dados/resumo_periodo.dart' show nomesMeses;
import '../util/util.dart';
import 'base.dart';

/// Pluviômetro: chuva de cada dia, total do mês e do ano.
class ChuvaPage extends StatefulWidget {
  const ChuvaPage({super.key});

  @override
  State<ChuvaPage> createState() => _ChuvaPageState();
}

class _ChuvaPageState extends State<ChuvaPage> {
  int ano = DateTime.now().year;

  Future<void> _lancar([Reg? c]) async {
    var data = (c?['data'] as String?) ?? hojeIso();
    final mm = TextEditingController(text: c?['mm'] is num ? numeroBr((c!['mm'] as num).toDouble()) : '');
    final op = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'Lançar chuva' : 'Editar chuva'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DateField(label: 'Data', value: data, obrigatorio: true, onChanged: (v) => set(() => data = v!)),
            gap,
            TextField(
              controller: mm,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Chuva', suffixText: 'mm'),
            ),
          ]),
          actions: [
            if (c != null) TextButton(onPressed: () => Navigator.pop(ctx, 'excluir'), child: const Text('Excluir')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'salvar'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = lerNumero(mm.text);
    mm.dispose();
    if (op == 'excluir') {
      await Db.excluir('chuvas', c!['id'] as int);
    } else if (op == 'salvar' && v != null && v >= 0) {
      if (c == null) {
        await Db.inserir('chuvas', {'propriedade_id': Db.pid, 'data': data, 'mm': v});
      } else {
        await Db.atualizar('chuvas', c['id'] as int, {'data': data, 'mm': v});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Chuva',
      fab: FloatingActionButton.extended(
        heroTag: null,
        icon: const Icon(Icons.water_drop_outlined),
        label: const Text('Lançar chuva'),
        onPressed: _lancar,
      ),
      corpo: AoMudar<(List<double>, List<Reg>)>(
        carregar: () async => (
          chuvaPorMes(ano),
          Db.registros('chuvas').where((c) => c['propriedade_id'] == Db.pid && txt(c['data']).startsWith('$ano-')).toList()
            ..sort((a, b) => txt(b['data']).compareTo(txt(a['data']))),
        ),
        builder: (context, d) {
          final (meses, dias) = d;
          final total = meses.fold<double>(0, (a, b) => a + b);
          return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ano--)),
              Expanded(
                child: Text('$ano · ${num1(total)} mm',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ano++)),
            ]),
            Barras({for (var i = 0; i < 12; i++) nomesMeses[i].substring(0, 3): meses[i]}, sufixo: ' mm'),
            Secao('Dias de chuva (${dias.length})'),
            for (final c in dias)
              ListTile(
                dense: true,
                leading: const Icon(Icons.water_drop, color: Colors.blue),
                title: Text(br(c['data'])),
                trailing: Text('${num1(c['mm'] as num)} mm'),
                onTap: () => _lancar(c),
              ),
          ]);
        },
      ),
    );
  }
}
