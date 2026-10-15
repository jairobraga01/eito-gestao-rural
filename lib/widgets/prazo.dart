// Campos de venda/compra a prazo: número de parcelas e primeiro vencimento.
import 'package:flutter/material.dart';

import '../util/util.dart';

class CamposPrazo extends StatelessWidget {
  const CamposPrazo({
    super.key,
    required this.receita,
    required this.aPrazo,
    required this.parcelas,
    required this.primeiro,
    required this.onAPrazo,
    required this.onPrimeiro,
    required this.onMudou,
  });

  final bool receita, aPrazo;
  final TextEditingController parcelas;
  final String primeiro;
  final ValueChanged<bool> onAPrazo;
  final ValueChanged<String> onPrimeiro;
  final VoidCallback onMudou;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: aPrazo,
          title: const Text('A prazo'),
          subtitle: Text(receita
              ? 'Cria as parcelas em Contas a receber'
              : 'Cria as parcelas em Contas a pagar'),
          onChanged: onAPrazo,
        ),
        if (aPrazo)
          Row(children: [
            Expanded(
              child: TextField(
                controller: parcelas,
                keyboardType: TextInputType.number,
                onChanged: (_) => onMudou(),
                decoration: const InputDecoration(labelText: 'Parcelas', helperText: 'Uma por mês'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DateField(
                label: '1º vencimento',
                value: primeiro,
                obrigatorio: true,
                onChanged: (x) => onPrimeiro(x!),
              ),
            ),
          ]),
      ]);
}

/// Primeiro vencimento sugerido: 30 dias depois da data do negócio.
String vencimentoSugerido(String data) => isoDe((parseIso(data) ?? DateTime.now()).add(const Duration(days: 30)));
