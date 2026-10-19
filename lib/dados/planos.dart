// Planos do Eito: quantos animais e quem pode usar a fazenda.
//
// O plano da conta é escolhido pelo criador (Painel do criador, campo "plano" de
// contas/{uid}). Quem está na equipe segue o plano do dono. Conta em Teste ou
// Cortesia usa tudo, sem limite; os nomes antigos (Essencial, Profissional e
// Completa) valem como Simples, Média e Plus.
import 'db.dart';

class PlanoEito {
  const PlanoEito._(this.nome, this.maxAnimais, this.maxPorPapel, {this.completo = true, this.mes = '', this.ano = ''});

  final String nome;

  /// Animais ativos; null = sem limite.
  final int? maxAnimais;

  /// Pessoas por papel além do dono; papel ausente = não pode usar.
  final Map<String, int> maxPorPapel;

  /// Acesso integral (false no plano Simples, que fica com o básico).
  final bool completo;

  /// Preços de tabela, em reais (texto, como aparecem na tela).
  final String mes, ano;

  static const simples = PlanoEito._('Simples', 200, {'gerente': 1, 'peao': 1}, completo: false, mes: '9,90', ano: '99,90');
  static const media = PlanoEito._('Média', 500, {'gerente': 1, 'veterinario': 1, 'peao': 2}, mes: '29,90', ano: '299,90');
  static const plus = PlanoEito._('Plus', null, {'gerente': 1, 'veterinario': 1, 'zootecnista': 1, 'contador': 1, 'peao': 10}, mes: '59,99', ano: '599,90');

  /// Teste e Cortesia: tudo liberado, sem limite de animais nem de pessoas.
  static const livre = PlanoEito._('Livre', null, {'gerente': 99, 'veterinario': 99, 'zootecnista': 99, 'contador': 99, 'peao': 99});

  /// Planos à venda, do menor para o maior.
  static const todos = [simples, media, plus];

  static PlanoEito de(Object? nome) => switch ('$nome') {
        'Simples' || 'Essencial' => simples,
        'Média' || 'Profissional' => media,
        'Plus' || 'Completa' => plus,
        _ => livre,
      };

  /// Papéis que a equipe pode ter neste plano (o dono sempre tem acesso).
  bool permite(String papel) => (maxPorPapel[papel] ?? 0) > 0;

  /// Dá para convidar mais uma pessoa com [papel], dado quem já está na equipe?
  bool cabe(String papel, Map<String, int> naEquipe) => (naEquipe[papel] ?? 0) < (maxPorPapel[papel] ?? 0);

  String get resumoLimite => maxAnimais == null ? 'sem limite de animais' : 'até $maxAnimais animais';

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
  if (m == null || p.situacao(animaisAtivos()) != 'acima') return null; // passar do limite só começa a contar
  final d = diasParaTravar(hoje);
  if (d != null && d > 0) return null; // ainda na tolerância: só avisa
  return 'O plano ${p.nome} vai até $m animais e já passou de $diasDeTolerancia dias acima disso. '
      'Mude para um plano maior para cadastrar mais animais.';
}
