// Planos do Eito: quantos animais e quem pode usar a fazenda.
//
// O plano da conta é escolhido pelo criador (Painel do criador, campo "plano" de
// contas/{uid}). Quem está na equipe segue o plano do dono. Conta em Teste ou
// Cortesia usa tudo, sem limite; os nomes antigos (Essencial, Profissional e
// Completa) valem como Simples, Média e Plus.
//
// Versão simples x completa: o Fazenda Simples abre o app enxuto (menu curto e
// painel com poucos atalhos); os outros planos abrem a versão completa. Os dados
// são os mesmos nas duas, então subir de plano não perde nada.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'db.dart';

class PlanoEito {
  const PlanoEito._(this.nome, this.maxAnimais, this.maxPorPapel, {this.completo = true, this.mes = '', this.ano = ''});

  final String nome;

  /// Animais ativos; null = sem limite.
  final int? maxAnimais;

  /// Pessoas por papel além do dono; papel ausente = não pode usar.
  final Map<String, int> maxPorPapel;

  /// Versão completa do app (false no Fazenda Simples, que usa a versão simples).
  final bool completo;

  /// Nome de vitrine: "Fazenda Simples", "Fazenda Simples PRO"...
  String get titulo => 'Fazenda $nome';

  String get versao => completo ? 'versão completa' : 'versão simples';

  /// Preços de tabela, em reais (texto, como aparecem na tela).
  final String mes, ano;

  static const simples = PlanoEito._('Simples', 100, {}, completo: false, mes: '9,90', ano: '99,90');
  static const simplesPro = PlanoEito._('Simples PRO', 100, {'gerente': 1, 'peao': 1}, mes: '19,90', ano: '199,90');
  static const media = PlanoEito._('Média', 300, {'gerente': 1, 'veterinario': 1, 'peao': 2}, mes: '29,90', ano: '299,90');
  static const plus = PlanoEito._('Plus', null, {'gerente': 1, 'veterinario': 1, 'zootecnista': 1, 'contador': 1, 'peao': 10}, mes: '59,90', ano: '599,90');

  /// Teste e Cortesia: tudo liberado, sem limite de animais nem de pessoas.
  static const livre = PlanoEito._('Livre', null, {'gerente': 99, 'veterinario': 99, 'zootecnista': 99, 'contador': 99, 'peao': 99});

  /// Planos à venda, do menor para o maior.
  static const todos = [simples, simplesPro, media, plus];

  /// Teste, Cortesia e conta ainda não lida (null): livre. Nome desconhecido
  /// (erro de digitação no painel) vale como Simples, para não liberar tudo.
  static PlanoEito de(Object? nome) => switch (nome) {
        'Simples' || 'Essencial' => simples,
        'Simples PRO' => simplesPro,
        'Média' || 'Profissional' => media,
        'Plus' || 'Completa' => plus,
        null || 'Teste' || 'Cortesia' || 'Livre' || '' => livre,
        _ => simples,
      };

  /// Papéis que a equipe pode ter neste plano (o dono sempre tem acesso).
  bool permite(String papel) => (maxPorPapel[papel] ?? 0) > 0;

  /// Dá para convidar mais uma pessoa com [papel], dado quem já está na equipe?
  bool cabe(String papel, Map<String, int> naEquipe) => (naEquipe[papel] ?? 0) < (maxPorPapel[papel] ?? 0);

  String get resumoLimite => maxAnimais == null ? 'acima de 300 animais, sem limite' : 'até $maxAnimais animais';

  /// Equipe além do dono, em texto ("1 gerente, 1 peão" ou "só o dono").
  String get resumoEquipe => maxPorPapel.isEmpty
      ? 'só o dono'
      : maxPorPapel.entries.map((e) => '${e.value} ${e.value > 1 ? _plural[e.key] : _papel[e.key]}').join(', ');

  static const _plural = {
    'gerente': 'gerentes', 'veterinario': 'veterinários', 'zootecnista': 'zootecnistas', 'contador': 'contadores', 'peao': 'peões',
  };

  static const _papel = {
    'gerente': 'gerente', 'veterinario': 'veterinário', 'zootecnista': 'zootecnista', 'contador': 'contador', 'peao': 'peão',
  };

  /// Situação do rebanho: 'ok', 'perto' (a partir de 90%), 'acima'.
  String situacao(int ativos) {
    final m = maxAnimais;
    if (m == null) return 'ok';
    if (ativos > m) return 'acima';
    return ativos >= m * 0.9 ? 'perto' : 'ok';
  }
}

/// Plano da fazenda em uso (do dono). Começa livre até a conta ser lida.
PlanoEito planoAtual() => PlanoEito.de(Db.planoDaFazenda.value);

/// Dias do teste grátis.
const diasDeTeste = 30;

/// Plano que vale para a conta: o Teste vencido (30 dias depois do cadastro
/// ou a data do painel, a mais tarde) passa a valer como Simples.
String? planoEfetivo(Map<String, dynamic>? conta, DateTime agora) {
  final plano = conta?['plano'] as String?;
  if (plano != 'Teste') return plano;
  if (testeVencido(conta!, agora)) return PlanoEito.simples.nome;
  return plano;
}

/// O teste grátis da conta já acabou?
bool testeVencido(Map<String, dynamic> conta, DateTime agora) {
  DateTime? data(Object? v) => switch (v) {
        DateTime d => d,
        String s => DateTime.tryParse(s),
        Timestamp t => t.toDate(),
        _ => null,
      };
  final ate = data(conta['teste_ate']);
  final criado = data(conta['criado_em']);
  final fim = [?ate, if (criado != null) criado.add(const Duration(days: diasDeTeste))]
      .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
  return fim != null && agora.isAfter(fim);
}

/// Dias de tolerância depois de passar do limite de animais.
const diasDeTolerancia = 15;

int animaisAtivos() => Db.registros('animais').where((a) => (a['status'] ?? 'Ativo') == 'Ativo').length;

/// Marca (ou limpa) o dia em que o rebanho passou do limite do plano.
Future<void> conferirLimiteAnimais(String hoje) async {
  final p = planoAtual();
  final acima = p.situacao(animaisAtivos()) == 'acima';
  final marca = Db.registro('config', 'plano_aviso')?['excedeu_em'] as String?;
  if (acima && marca == null) {
    await Db.salvarConfig('plano_aviso', {'excedeu_em': hoje});
  } else if (!acima && marca != null) {
    await Db.salvarConfig('plano_aviso', {'excedeu_em': null});
  }
}

/// Dias que faltam para travar novos cadastros (null = não está acima do limite).
int? diasParaTravar(String hoje) {
  if (planoAtual().situacao(animaisAtivos()) != 'acima') return null;
  final marca = Db.registro('config', 'plano_aviso')?['excedeu_em'] as String?;
  if (marca == null || marca.length < 10) return diasDeTolerancia;
  final passou = DateTime.parse(hoje.substring(0, 10)).difference(DateTime.parse(marca.substring(0, 10))).inDays;
  return diasDeTolerancia - passou;
}

/// Mensagem quando o cadastro de [novos] animais deve ser barrado; null se pode.
String? bloqueioDeAnimais(String hoje, {int novos = 1}) {
  final p = planoAtual();
  final m = p.maxAnimais;
  if (m == null) return null;
  final depois = animaisAtivos() + novos;
  // Em lote (planilha, compra), a tolerância cobre só uma folga de 10% acima do limite.
  if (novos > 1 && depois > (m * 11 + 9) ~/ 10) {
    return 'O plano ${p.nome} vai até $m animais; com estes $novos o rebanho ficaria com $depois. '
        'Mude para um plano maior ou cadastre menos animais.';
  }
  if (p.situacao(animaisAtivos()) != 'acima') return null; // passar do limite só começa a contar
  final d = diasParaTravar(hoje);
  if (d != null && d > 0) return null; // ainda na tolerância: só avisa
  return 'O plano ${p.nome} vai até $m animais e já passou de $diasDeTolerancia dias acima disso. '
      'Mude para um plano maior para cadastrar mais animais.';
}
