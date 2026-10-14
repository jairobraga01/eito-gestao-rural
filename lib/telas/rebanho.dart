import 'package:flutter/material.dart';

import '../dados/repositorio.dart';
import '../tema.dart';
import '../util/formato.dart';
import 'ficha_animal.dart';
import 'novo_animal.dart';

class TelaRebanho extends StatefulWidget {
  const TelaRebanho({super.key, required this.repo});
  final Repositorio repo;

  @override
  State<TelaRebanho> createState() => _TelaRebanhoState();
}

class _TelaRebanhoState extends State<TelaRebanho> {
  late final Stream<List<Animal>> _rebanho = widget.repo.rebanhoAtivo();
  String _filtro = '';

  // Ordena "2" antes de "10".
  static int _comparar(Animal a, Animal b) {
    final na = int.tryParse(a.brinco), nb = int.tryParse(b.brinco);
    if (na != null && nb != null) return na.compareTo(nb);
    return a.brinco.compareTo(b.brinco);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rebanho')),
      floatingActionButton: FloatingActionButton.large(
        backgroundColor: Cores.laranja,
        foregroundColor: Colors.white,
        tooltip: 'Novo animal',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => NovoAnimal(repo: widget.repo))),
        child: const Icon(Icons.add, size: 40),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar brinco, nome ou lote'),
            onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Animal>>(
            stream: _rebanho,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final lista = snap.data!
                  .where((a) =>
                      _filtro.isEmpty ||
                      a.brinco.toLowerCase().contains(_filtro) ||
                      (a.nome ?? '').toLowerCase().contains(_filtro) ||
                      (a.lote ?? '').toLowerCase().contains(_filtro) ||
                      (a.rfid ?? '').contains(_filtro))
                  .toList()
                ..sort(_comparar);
              if (lista.isEmpty) {
                return const Center(child: Text('Nenhum animal encontrado.', style: TextStyle(fontSize: 20)));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                itemCount: lista.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('${lista.length} ${lista.length == 1 ? 'cabeça' : 'cabeças'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    );
                  }
                  final a = lista[i - 1];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minVerticalPadding: 14,
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: a.femea ? Cores.oliva : Cores.olivaEscuro,
                        child: Text(a.femea ? 'F' : 'M',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                      title: Text(a.nome == null ? 'Brinco ${a.brinco}' : '${a.brinco} · ${a.nome}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [if (a.raca != null) a.raca!, if (a.lote != null) 'Lote ${a.lote}']
                            .join(' · '),
                        style: const TextStyle(fontSize: 16),
                      ),
                      trailing: Text(a.pesoAtual == null ? '—' : pesoKg(a.pesoAtual!),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Cores.oliva)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => FichaAnimal(repo: widget.repo, animalId: a.id))),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
