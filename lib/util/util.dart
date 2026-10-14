// Funções e componentes reutilizados pelas telas.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../dados/db.dart';

export 'formato.dart';

/// Duração média da gestação bovina (dias). Zebuínos (Nelore) ~290; taurinos ~283.
const diasGestacao = 290;

const categoriasF = ['Bezerra', 'Novilha', 'Vaca'];
const categoriasM = ['Bezerro', 'Garrote', 'Boi', 'Touro'];

final _fmtBr = DateFormat('dd/MM/yyyy', 'en_US');
final _fmtIso = DateFormat('yyyy-MM-dd', 'en_US');
final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _num1 = NumberFormat('#,##0.0', 'pt_BR');
final _num3 = NumberFormat('#,##0.000', 'pt_BR');

String hojeIso() => _fmtIso.format(DateTime.now());
String isoDe(DateTime d) => _fmtIso.format(d);

DateTime? parseIso(Object? s) {
  if (s == null) return null;
  final t = s.toString();
  return t.isEmpty ? null : DateTime.tryParse(t);
}

String br(Object? iso) {
  final d = parseIso(iso);
  return d == null ? '-' : _fmtBr.format(d);
}

String somaDias(String iso, int dias) {
  final d = parseIso(iso)!;
  return isoDe(DateTime(d.year, d.month, d.day + dias));
}

int diasEntre(String de, String ate) {
  final a = parseIso(de)!, b = parseIso(ate)!;
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

int? mesesDeIdade(Object? nascimento) {
  final n = parseIso(nascimento);
  if (n == null) return null;
  final h = DateTime.now();
  var m = (h.year - n.year) * 12 + h.month - n.month;
  if (h.day < n.day) m--;
  return m < 0 ? 0 : m;
}

String idade(Object? nascimento) {
  final m = mesesDeIdade(nascimento);
  if (m == null) return '';
  if (m < 12) return '$m ${m == 1 ? 'mês' : 'meses'}';
  final a = m ~/ 12, r = m % 12;
  return r == 0 ? '$a ${a == 1 ? 'ano' : 'anos'}' : '${a}a ${r}m';
}

String sugerirCategoria(String sexo, Object? nascimento) {
  final m = mesesDeIdade(nascimento);
  if (sexo == 'F') {
    if (m == null || m >= 24) return 'Vaca';
    return m < 12 ? 'Bezerra' : 'Novilha';
  }
  if (m == null || m >= 24) return 'Boi';
  return m < 12 ? 'Bezerro' : 'Garrote';
}

String moeda(num? v) => v == null ? '-' : _moeda.format(v);
String kg(num? v) => v == null ? '-' : '${_num1.format(v)} kg';
String gmd(double v) => '${_num3.format(v)} kg/dia';
String num1(num v) => _num1.format(v);

String txt(Object? v) => v == null ? '' : v.toString();
String? nulo(String s) => s.trim().isEmpty ? null : s.trim();

String rotulo(Reg a) {
  final n = txt(a['nome']);
  return n.isEmpty ? txt(a['brinco']) : '${a['brinco']} – $n';
}

void avisar(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirmar(BuildContext context, String titulo, String msg,
    {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

const gap = SizedBox(height: 12);

/// Lista suspensa simples.
Widget escolha(String label, String? valor, List<String> opcoes, ValueChanged<String?> onChanged) {
  return DropdownButtonFormField<String>(
    key: ValueKey('$label|$valor|${opcoes.join(',')}'),
    initialValue: (valor != null && opcoes.contains(valor)) ? valor : null,
    decoration: InputDecoration(labelText: label),
    items: [for (final o in opcoes) DropdownMenuItem(value: o, child: Text(o))],
    onChanged: onChanged,
  );
}

/// Lista suspensa de registros (lotes, piquetes...) pelo id.
Widget escolhaId(String label, int? valor, List<Reg> itens, ValueChanged<int?> onChanged,
    {String vazio = 'Nenhum', String campo = 'nome'}) {
  final ids = itens.map((e) => e['id'] as int).toList();
  return DropdownButtonFormField<int?>(
    key: ValueKey('$label|$valor|${ids.join(',')}'),
    initialValue: ids.contains(valor) ? valor : null,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem<int?>(value: null, child: Text(vazio)),
      for (final e in itens) DropdownMenuItem<int?>(value: e['id'] as int, child: Text(txt(e[campo]))),
    ],
    onChanged: onChanged,
  );
}

const ufs = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR',
  'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'];

Widget campoTexto(TextEditingController c, String label,
    {bool numero = false, int linhas = 1, String? sufixo, bool foco = false}) {
  return TextField(
    controller: c,
    autofocus: foco,
    maxLines: linhas,
    keyboardType: numero
        ? const TextInputType.numberWithOptions(decimal: true)
        : (linhas > 1 ? TextInputType.multiline : TextInputType.text),
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(labelText: label, suffixText: sufixo),
  );
}

/// Campo de data que abre o calendário.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.obrigatorio = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool obrigatorio;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final agora = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: parseIso(value) ?? agora,
          firstDate: DateTime(1990),
          lastDate: DateTime(agora.year + 3, 12, 31),
        );
        if (d != null) onChanged(isoDe(d));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: obrigatorio ? '$label *' : label,
          suffixIcon: (!obrigatorio && value != null)
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today),
        ),
        child: Text(value == null ? '' : br(value)),
      ),
    );
  }
}

/// Campo que abre a busca de animais.
class AnimalField extends StatelessWidget {
  const AnimalField({
    super.key,
    required this.label,
    required this.animal,
    required this.onChanged,
    this.sexo,
    this.enabled = true,
  });

  final String label;
  final Reg? animal;
  final ValueChanged<Reg?> onChanged;
  final String? sexo;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final a = await pickAnimal(context, sexo: sexo, titulo: label);
              if (a != null) onChanged(a);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(
          animal == null ? 'Toque para escolher' : rotulo(animal!),
          style: animal == null ? TextStyle(color: Theme.of(context).hintColor) : null,
        ),
      ),
    );
  }
}

Future<Reg?> pickAnimal(BuildContext context, {String? sexo, String titulo = 'Selecionar animal'}) async {
  final r = await showDialog<List<Reg>>(
    context: context,
    builder: (_) => _AnimalPicker(sexo: sexo, titulo: titulo, multi: false),
  );
  return (r == null || r.isEmpty) ? null : r.first;
}

Future<List<Reg>?> pickAnimais(BuildContext context,
    {String titulo = 'Selecionar animais', List<int> iniciais = const []}) {
  return showDialog<List<Reg>>(
    context: context,
    builder: (_) => _AnimalPicker(titulo: titulo, multi: true, iniciais: iniciais),
  );
}

class _AnimalPicker extends StatefulWidget {
  const _AnimalPicker({this.sexo, required this.titulo, required this.multi, this.iniciais = const []});

  final String? sexo;
  final String titulo;
  final bool multi;
  final List<int> iniciais;

  @override
  State<_AnimalPicker> createState() => _AnimalPickerState();
}

class _AnimalPickerState extends State<_AnimalPicker> {
  String busca = '';
  List<Reg> todos = [];
  bool carregado = false;
  final sel = <int, Reg>{};

  @override
  void initState() {
    super.initState();
    Db.animais(sexo: widget.sexo, soAtivos: true).then((v) {
      if (!mounted) return;
      setState(() {
        todos = v;
        carregado = true;
        for (final a in v) {
          if (widget.iniciais.contains(a['id'])) sel[a['id'] as int] = a;
        }
      });
    });
  }

  List<Reg> get visiveis {
    final b = busca.trim().toLowerCase();
    if (b.isEmpty) return todos;
    return todos
        .where((a) =>
            '${a['brinco']} ${txt(a['nome'])} ${txt(a['lote_nome'])} ${txt(a['rfid'])}'.toLowerCase().contains(b))
        .toList();
  }

  String? sub(Reg a) {
    final s = [txt(a['categoria']), txt(a['lote_nome'])].where((x) => x.isNotEmpty).join(' · ');
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final lista = visiveis;
    return AlertDialog(
      title: Text(widget.titulo),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Brinco, nome ou lote',
              ),
              onChanged: (v) => setState(() => busca = v),
            ),
            if (widget.multi)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: Text('Marcar os ${lista.length} visíveis'),
                  onPressed: () => setState(() {
                    for (final a in lista) {
                      sel[a['id'] as int] = a;
                    }
                  }),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: !carregado
                  ? const Center(child: CircularProgressIndicator())
                  : lista.isEmpty
                      ? const Center(child: Text('Nenhum animal ativo encontrado'))
                      : ListView.builder(
                          itemCount: lista.length,
                          itemBuilder: (c, i) {
                            final a = lista[i];
                            final id = a['id'] as int;
                            final s = sub(a);
                            if (widget.multi) {
                              return CheckboxListTile(
                                dense: true,
                                value: sel.containsKey(id),
                                title: Text(rotulo(a)),
                                subtitle: s == null ? null : Text(s),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    sel[id] = a;
                                  } else {
                                    sel.remove(id);
                                  }
                                }),
                              );
                            }
                            return ListTile(
                              dense: true,
                              leading: Icon(a['sexo'] == 'F' ? Icons.female : Icons.male),
                              title: Text(rotulo(a)),
                              subtitle: s == null ? null : Text(s),
                              onTap: () => Navigator.pop(context, [a]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (widget.multi)
          FilledButton(
            onPressed: () => Navigator.pop(context, sel.values.toList()),
            child: Text('Confirmar (${sel.length})'),
          ),
      ],
    );
  }
}

/// Título de seção.
class Secao extends StatelessWidget {
  const Secao(this.titulo, {super.key, this.acao});
  final String titulo;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (acao != null) acao!,
        ],
      ),
    );
  }
}

class Vazio extends StatelessWidget {
  const Vazio(this.msg, {super.key, this.icone = Icons.inbox_outlined});
  final String msg;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Cartão de indicador.
class Kpi extends StatelessWidget {
  const Kpi(this.titulo, this.valor, {super.key, this.icone, this.cor, this.onTap});
  final String titulo;
  final String valor;
  final IconData? icone;
  final Color? cor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icone != null) Icon(icone, color: cor ?? cs.primary, size: 22),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barras horizontais simples: rótulo, barra e contagem.
class Barras extends StatelessWidget {
  const Barras(this.dados, {super.key, this.sufixo = ''});
  final Map<String, num> dados;
  final String sufixo;

  @override
  Widget build(BuildContext context) {
    if (dados.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('Sem dados.'));
    }
    final maximo = dados.values.fold<num>(0, (a, b) => b > a ? b : a);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final e in dados.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 110, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maximo == 0 ? 0 : e.value / maximo,
                        minHeight: 14,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text('${e.value is int ? e.value : num1(e.value)}$sufixo',
                        textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Linha "rótulo: valor" usada nas fichas.
class Info extends StatelessWidget {
  const Info(this.rotulo, this.valor, {super.key, this.onTap});
  final String rotulo;
  final String valor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (valor.isEmpty || valor == '-') return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(rotulo, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(valor,
                  style: onTap == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recarrega sempre que algo é gravado no banco.
class AoMudar<T> extends StatelessWidget {
  const AoMudar({super.key, required this.carregar, required this.builder});
  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Db.changes,
      builder: (context, _, __) => FutureBuilder<T>(
        future: carregar(),
        builder: (context, s) {
          if (s.hasError) return Vazio('Erro ao carregar: ${s.error}', icone: Icons.error_outline);
          if (!s.hasData && s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return builder(context, s.data as T);
        },
      ),
    );
  }
}

/// Botão "SALVAR" de largura total no rodapé dos formulários.
class BotaoSalvar extends StatelessWidget {
  const BotaoSalvar({super.key, required this.onPressed, this.texto = 'Salvar'});
  final VoidCallback? onPressed;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: onPressed == null ? cs.outline : cs.primary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.save, color: cs.onPrimary),
                const SizedBox(width: 12),
                Text(texto.toUpperCase(),
                    style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
