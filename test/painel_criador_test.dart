import 'package:eito_gestao_rural/dados/painel_criador.dart';
import 'package:eito_gestao_rural/dados/plataforma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preço mensal só conta planos pagos, com os nomes antigos', () {
    expect(precoMensal('Simples'), 9.90);
    expect(precoMensal('Profissional'), 29.90);
    expect(precoMensal('Plus'), 59.90);
    expect(precoMensal('Teste'), 0);
    expect(precoMensal('Cortesia'), 0);
    expect(nomePlano('Completa'), 'Plus');
    expect(nomePlano(null), 'Teste');
  });

  test('mensagem de cobrança do teste traz a data e os planos', () {
    final t = textoCobrancaTeste('Ana', DateTime(2020, 3, 5));
    expect(t, contains('terminou em 05/03'));
    expect(t, contains('Simples: R\$ 9,90/mês'));
    expect(textoSumido(''), startsWith('Olá! '));
  });

  test('saúde da conta vai de 0 a 100', () {
    final agora = DateTime(2026, 10, 20);
    expect(saudeConta({}, agora), 0);
    expect(
        saudeConta({
          'ultimo_acesso': DateTime(2026, 10, 19),
          'animais': 80,
          'propriedades': 1,
          'uso': {'Animais': 3, 'Lotes': 1, 'Sanidade': 2, 'Pesagem': 1, 'Painel': 9},
        }, agora),
        100);
    expect(saudeConta({'ultimo_acesso': DateTime(2026, 9, 1), 'animais': 5}, agora), 10);
  });

  test('estado pelo DDD e pela fazenda', () {
    expect(ufPorTelefone('(62) 99999-0000'), 'GO');
    expect(ufPorTelefone('+55 11 98888-7777'), 'SP');
    expect(ufPorTelefone('123'), isNull);
    expect(ufDaConta({'uf': 'MT', 'telefone': '62999990000'}), 'MT');
    expect(ufDaConta({'telefone': '62999990000'}), 'GO');
  });

  test('pagamento renova a partir do vencimento ou de hoje', () {
    final hoje = DateTime(2026, 10, 20);
    expect(vencimentoAposPagamento(null, hoje, 'mensal'), DateTime(2026, 11, 20));
    expect(vencimentoAposPagamento(DateTime(2026, 11, 5), hoje, 'mensal'), DateTime(2026, 12, 5));
    expect(vencimentoAposPagamento(DateTime(2026, 1, 1), hoje, 'anual'), DateTime(2027, 10, 20));
    // Fim de mês não pula para o mês seguinte.
    expect(vencimentoAposPagamento(DateTime(2027, 1, 31), hoje, 'mensal'), DateTime(2027, 2, 28));
    expect(vencimentoAposPagamento(DateTime(2028, 2, 29), hoje, 'anual'), DateTime(2029, 2, 28));
    expect(valorSugerido('Média', 'mensal'), 29.90);
    expect(valorSugerido('Simples', 'anual', desconto: 20), 79.92);
  });

  test('tempo médio de resposta e NPS', () {
    final t = tempoMedioResposta([
      {
        'mensagens': [
          {'de': 'cliente', 'em': '2026-10-20T10:00:00'},
          {'de': 'equipe', 'em': '2026-10-20T12:00:00'},
        ],
      },
      {
        'mensagens': [
          {'de': 'cliente', 'em': '2026-10-20T10:00:00'},
          {'de': 'equipe', 'em': '2026-10-20T14:00:00'},
        ],
      },
      {
        'mensagens': [
          {'de': 'cliente', 'em': '2026-10-20T10:00:00'},
        ],
      },
    ]);
    expect(t, const Duration(hours: 3));
    expect(textoDuracao(const Duration(minutes: 135)), '2 h 15 min');
    expect(calcularNps([10, 9, 8, 3]), 25);
    expect(calcularNps([]), isNull);
  });
}
