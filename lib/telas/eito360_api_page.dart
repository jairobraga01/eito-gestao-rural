import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../servicos/eito360_api.dart';
import '../servicos/eito360_sync.dart';

/// Área de transição para testar a API nova sem alterar o banco offline legado.
class Eito360ApiPage extends StatefulWidget {
  const Eito360ApiPage({super.key});
  @override
  State<Eito360ApiPage> createState() => _Eito360ApiPageState();
}

class _Eito360ApiPageState extends State<Eito360ApiPage> {
  static const apiUrl = String.fromEnvironment('EITO360_API_URL');
  final _apiUrl = TextEditingController(text: apiUrl);
  final _tenantName = TextEditingController();
  final _farmName = TextEditingController();
  final _municipality = TextEditingController();
  final _state = TextEditingController();
  final _farmId = TextEditingController();
  final _tag = TextEditingController();
  final _animalName = TextEditingController();
  final _breed = TextEditingController();
  String? _tenantId;
  List<Map<String, dynamic>> _tenants = [], _farms = [], _animals = [];
  bool _busy = false;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _syncPreview = [];
  String? _message;
  Eito360Sync get _sync => Eito360Sync(baseUrl: _apiUrl.text.trim(), tenantId: _tenantId ?? '');
  Eito360Api get _api => Eito360Api(baseUrl: _apiUrl.text.trim(), tenantId: _tenantId ?? '');

  @override
  void dispose() {
    for (final c in [_apiUrl,_tenantName,_farmName,_municipality,_state,_farmId,_tag,_animalName,_breed]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_apiUrl.text.trim().isEmpty || Uri.tryParse(_apiUrl.text.trim())?.hasAuthority != true) {
      setState(() => _message = 'Configure a URL HTTPS da API em EITO360_API_URL.'); return;
    }
    setState(() { _busy = true; _message = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => _message = e.toString().replaceFirst('Bad state: ', '')); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _loadTenants() async => _run(() async {
    final rows = await _api.listarMinhasContas();
    setState(() { _tenants = rows; if (_tenantId == null && rows.isNotEmpty) _tenantId = rows.first['id'].toString(); });
    if (_tenantId != null) await _loadData();
  });
  Future<void> _loadData() async {
    final farms = await _api.listarFazendas();
    final animals = await _api.listarAnimais();
    if (!mounted) return;
    setState(() { _farms = farms; _animals = animals; if (_farmId.text.isEmpty && farms.isNotEmpty) _farmId.text = farms.first['id'].toString(); });
  }

  Future<void> _createAccount() => _run(() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final result = await _api.criarContaRural(nomeConta: _tenantName.text.trim(), nomeFazenda: _farmName.text.trim(),
      municipio: _municipality.text.trim().isEmpty ? null : _municipality.text.trim(), estado: _state.text.trim().isEmpty ? null : _state.text.trim());
    final tenant = result['tenant'] as Map<String, dynamic>;
    setState(() => _tenantId = tenant['id'].toString());
    final rows = await _api.listarMinhasContas();
    if (mounted) setState(() => _tenants = rows);
    await _loadData();
    if (mounted) setState(() => _message = 'Conta criada. A fazenda inicial já está cadastrada.');
  });

  Future<void> _createFarm() => _run(() async {
    await _api.criarFazenda(nome: _farmName.text.trim(), municipio: _municipality.text.trim().isEmpty ? null : _municipality.text.trim(), estado: _state.text.trim().isEmpty ? null : _state.text.trim());
    await _loadData(); setState(() => _message = 'Fazenda cadastrada na API.');
  });
  Future<void> _createAnimal() => _run(() async {
    if (_farmId.text.trim().isEmpty) throw StateError('Selecione uma fazenda.');
    if (_farmId.text.startsWith('local-')) throw StateError('Esta fazenda ainda está só no aparelho. Envie as pendências ou use "Guardar animal offline".');
    await _api.criarAnimal(fazendaId: _farmId.text.trim(), identificacao: _tag.text.trim(), nome: _animalName.text.trim().isEmpty ? null : _animalName.text.trim(), raca: _breed.text.trim().isEmpty ? null : _breed.text.trim());
    await _loadData(); setState(() => _message = 'Animal cadastrado na API.');
  });

  Future<void> _refreshPending() async {
    if (_tenantId == null) return;
    final rows = await _sync.pendencias();
    if (mounted) setState(() => _pendingCount = rows.length);
  }

  Future<void> _enqueueFarm() => _run(() async {
    final localId = 'local-farm-${DateTime.now().microsecondsSinceEpoch}';
    await _sync.enfileirar(entityType: 'farm', operation: 'create', localId: localId, payload: {
      'name': _farmName.text.trim(),
      'municipality': _municipality.text.trim().isEmpty ? null : _municipality.text.trim(),
      'state': _state.text.trim().isEmpty ? null : _state.text.trim(),
    });
    _farmId.text = localId;
    await _refreshPending();
    setState(() => _message = 'Fazenda salva na fila local. Você pode enfileirar animais vinculados a ela; envie as pendências quando houver conexão.');
  });

  Future<void> _enqueueAnimal() => _run(() async {
    if (_farmId.text.trim().isEmpty) throw StateError('Selecione uma fazenda cadastrada ou enfileirada neste dispositivo.');
    if (_tag.text.trim().isEmpty) throw StateError('Informe a identificação do animal.');
    final localId = 'local-animal-${DateTime.now().microsecondsSinceEpoch}';
    await _sync.enfileirar(entityType: 'animal', operation: 'create', localId: localId, payload: {
      'farm_id': _farmId.text.trim(), 'tag': _tag.text.trim(),
      'name': _animalName.text.trim().isEmpty ? null : _animalName.text.trim(),
      'breed': _breed.text.trim().isEmpty ? null : _breed.text.trim(), 'status': 'active',
    });
    await _refreshPending();
    setState(() => _message = 'Animal salvo na fila local. A fazenda precisa já existir no servidor.');
  });

  Future<void> _sendPending() => _run(() async {
    final result = await _sync.enviarPendentes();
    await _refreshPending();
    await _loadData();
    setState(() => _message = 'Sincronização: ${result['applied'] ?? 0} aplicada(s), ${result['blocked'] ?? 0} bloqueada(s).');
  });

  Future<void> _previewChanges() => _run(() async {
    final result = await _sync.baixarAlteracoes();
    final changes = (result['changes'] as List).cast<Map<String, dynamic>>();
    setState(() { _syncPreview = changes; _message = '${changes.length} alteração(ões) aplicadas ao cache local do Eito 360; cursor atualizado após persistência.'; });
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Eito 360 · Integração API')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Área de transição', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Esta tela pertence exclusivamente ao Eito 360 e utiliza sua API PostgreSQL. Ela não acessa nem importa dados de outros aplicativos.'),
      const SizedBox(height: 12),
      TextField(controller: _apiUrl, decoration: const InputDecoration(labelText: 'URL base da API', hintText: 'https://sua-api.onrender.com')),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _busy ? null : _loadTenants, icon: const Icon(Icons.sync), label: const Text('Carregar minhas contas')),
      if (_tenants.isNotEmpty) ...[
        DropdownButtonFormField<String>(value: _tenantId, decoration: const InputDecoration(labelText: 'Conta rural ativa'), items: [for (final t in _tenants) DropdownMenuItem(value: t['id'].toString(), child: Text('${t['name']} · ${t['role']}'))], onChanged: _busy ? null : (v) {
          // Outra conta: as fazendas e os animais da anterior não valem mais.
          setState(() { _tenantId = v; _farms = []; _animals = []; _farmId.clear(); });
          _run(() async { await _loadData(); await _refreshPending(); });
        }),
        FilledButton.tonal(onPressed: _busy ? null : () => _run(_loadData), child: const Text('Atualizar fazendas e animais')),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sincronização operacional · fazendas e animais', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Operações pendentes neste dispositivo: $_pendingCount'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy ? null : () => _run(_refreshPending), icon: const Icon(Icons.pending_actions), label: const Text('Ver pendências')),
            FilledButton.tonalIcon(onPressed: _busy ? null : _sendPending, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Enviar pendentes')),
            OutlinedButton.icon(onPressed: _busy ? null : _previewChanges, icon: const Icon(Icons.cloud_download_outlined), label: const Text('Consultar alterações')),
          ]),
          if (_syncPreview.isNotEmpty) ...[const SizedBox(height: 8), Text('Prévia de alterações do servidor: ${_syncPreview.length}'), ..._syncPreview.take(5).map((c) => ListTile(dense: true, title: Text('${c['entity_type']} · ${c['change_type']}'), subtitle: Text('Sequência ${c['sequence_id']} · ${c['entity_id']}')))],
          const Text('No Android/iOS/desktop, a fila e o cache usam SQLite; na Web, o armazenamento usa SharedPreferences. O pull persiste as alterações antes de avançar o cursor. O armazenamento e a sincronização são exclusivos do Eito 360.', style: TextStyle(fontSize: 12)),
        ]))),
        const SizedBox(height: 8),
      ],
      const Divider(height: 32),
      const Text('Adesão · criar conta rural e primeira fazenda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      TextField(controller: _tenantName, decoration: const InputDecoration(labelText: 'Nome da conta / empresa')),
      TextField(controller: _farmName, decoration: const InputDecoration(labelText: 'Nome da primeira fazenda')),
      TextField(controller: _municipality, decoration: const InputDecoration(labelText: 'Município (opcional)')),
      TextField(controller: _state, maxLength: 2, decoration: const InputDecoration(labelText: 'UF (opcional)')),
      FilledButton(onPressed: _busy ? null : _createAccount, child: const Text('Criar conta e primeira fazenda')),
      const Divider(height: 32),
      const Text('Fazendas da conta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ..._farms.map((f) => ListTile(leading: const Icon(Icons.home_work_outlined), title: Text('${f['name'] ?? ''}'), subtitle: Text([f['municipality'], f['state'], f['area_hectares'] == null ? null : '${f['area_hectares']} ha'].where((v) => v != null && v.toString().isNotEmpty).join(' · ')), onTap: () => setState(() => _farmId.text = f['id'].toString()))),
      TextField(controller: _farmName, decoration: const InputDecoration(labelText: 'Nome para nova fazenda')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonal(onPressed: _busy || _tenantId == null ? null : _createFarm, child: const Text('Cadastrar fazenda adicional')),
        OutlinedButton(onPressed: _busy || _tenantId == null ? null : _enqueueFarm, child: const Text('Guardar fazenda offline')),
      ]),
      const Divider(height: 32),
      const Text('Animais cadastrados pela API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (_farms.isNotEmpty) DropdownButtonFormField<String>(value: _farms.any((f) => f['id'].toString() == _farmId.text) || _farmId.text.startsWith('local-') ? _farmId.text : null, decoration: const InputDecoration(labelText: 'Fazenda do animal'), items: [
        for (final f in _farms) DropdownMenuItem(value: f['id'].toString(), child: Text(f['name'].toString())),
        // Fazenda guardada só no aparelho: aparece com o nome digitado, para o valor mostrado ser o enviado.
        if (_farmId.text.startsWith('local-')) DropdownMenuItem(value: _farmId.text, child: Text('${_farmName.text.trim().isEmpty ? 'Fazenda' : _farmName.text.trim()} (offline)')),
      ], onChanged: (v) => setState(() => _farmId.text = v ?? '')),
      TextField(controller: _tag, decoration: const InputDecoration(labelText: 'Identificação / brinco')),
      TextField(controller: _animalName, decoration: const InputDecoration(labelText: 'Nome (opcional)')),
      TextField(controller: _breed, decoration: const InputDecoration(labelText: 'Raça (opcional)')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy || _tenantId == null || _farms.isEmpty ? null : _createAnimal, child: const Text('Cadastrar animal')),
        OutlinedButton(onPressed: _busy || _tenantId == null || _farms.isEmpty ? null : _enqueueAnimal, child: const Text('Guardar animal offline')),
      ]),
      ..._animals.map((a) => ListTile(leading: const Icon(Icons.pets_outlined), title: Text('${a['tag'] ?? ''}${a['name'] == null ? '' : ' · ${a['name']}'}'), subtitle: Text([a['breed'], a['sex'], a['status']].where((v) => v != null && v.toString().isNotEmpty).join(' · ')))),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!, style: TextStyle(color: _message!.contains('criada') || _message!.contains('cadastrad') ? Colors.green : Theme.of(context).colorScheme.error))),
    ]),
  );
}
