import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tema.dart';
import 'base.dart';

/// Um assunto do guia: título, resumo e passos numerados.
typedef _Assunto = (IconData, String, String, List<String>);

const _assuntos = <_Assunto>[
  (Icons.rocket_launch_outlined, 'Primeiros passos', 'Deixe a fazenda pronta para lançar.', [
    'Crie a conta com e-mail e senha e confirme o e-mail que chega na caixa de entrada.',
    'Em Propriedades, confira o nome da fazenda e preencha CAR, matrícula, NIRF/CIB e inscrição estadual se for usar exportações.',
    'Cadastre os piquetes/pastos em Piquete/Pasto e os lotes em Lotes.',
    'Coloque os animais: um a um em Animais, ou de uma vez pelo ícone de planilha (importar CSV).',
    'Chame a equipe em Equipe e permissões, no menu.',
  ]),
  (Icons.pets_outlined, 'Cadastrar animais', 'Individual, em planilha ou gado sem brinco.', [
    'Menu › Animais › botão de novo animal.',
    'Preencha brinco (ou deixe vazio para numeração automática), sexo, categoria, raça, nascimento, lote e pasto.',
    'Para vários de uma vez, toque no ícone de planilha, baixe o modelo, preencha no Excel, salve como CSV e escolha o arquivo.',
    'Para tirar uma foto, abra a ficha do animal e use o ícone de câmera.',
  ]),
  (Icons.touch_app_outlined, 'Modo Curral', 'Para trabalhar o gado no brete.', [
    'No Painel, toque em Modo Curral.',
    'Encoste o bastão no brinco, ou digite o número, e a ficha do animal abre.',
    'Lance peso, vacina, tratamento ou escore de condição corporal; o peso da balança entra direto.',
    'A Fila do dia mostra o que está vencido ou programado. Risque cada item ao fazer.',
  ]),
  (Icons.monitor_weight_outlined, 'Pesagem e vacinação em série', 'O lote inteiro de uma vez.', [
    'No Painel, escolha Pesagem em série ou Vacinação em série.',
    'Escolha o lote (e, na vacinação, o produto e a data).',
    'Passe animal por animal, pelo brinco ou pelo bastão. O ganho médio diário é calculado sozinho.',
    'Também dá para ditar o lançamento pelo modo de voz.',
  ]),
  (Icons.favorite_border, 'Inseminação e reprodução', 'Do protocolo ao parto.', [
    'Menu › Reprodução para ver protocolos, estação de monta e resultados.',
    'Cadastre o sêmen com preço por dose e estoque.',
    'No Painel, abra o Modo Inseminação, leia o brinco e registre IA, IATF ou TE com sêmen, inseminador e protocolo.',
    'Depois, use o diagnóstico em série para marcar prenhe ou vazia. O parto previsto aparece sozinho.',
    'Nas vazias, use a ressincronização ou o repasse com touro.',
  ]),
  (Icons.vaccines_outlined, 'Sanidade e carência', 'Vacinas, tratamentos e prazos.', [
    'Menu › Sanidade › novo manejo (vacina, vermífugo, tratamento).',
    'Informe o produto, a data e, se tiver, a carência em dias.',
    'O animal em carência aparece com aviso e o Eito alerta se você for vender para abate antes do prazo.',
    'O calendário sanitário pronto lembra as vacinas na Fila do dia.',
  ]),
  (Icons.child_friendly_outlined, 'Nascimentos', 'Registrar a cria.', [
    'Menu › Entrada › Nascimentos › novo.',
    'Escolha a mãe (e o pai, se souber), o sexo, o peso e o brinco.',
    'A cria entra no rebanho já ligada à mãe, e a genealogia é montada.',
  ]),
  (Icons.arrow_circle_down_outlined, 'Compras', 'Entrada de animais comprados.', [
    'Menu › Entrada › Compras › nova compra.',
    'Informe o fornecedor, a quantidade, o valor, a comissão, a nota e o frete.',
    'Para pagar a prazo, marque as parcelas; elas vão para Contas a pagar e receber.',
    'Os animais comprados entram no rebanho e o custo é somado ao lote.',
  ]),
  (Icons.arrow_circle_up_outlined, 'Vendas, mortes e outras saídas', 'Tirar animais do rebanho.', [
    'Menu › Saídas › Vendas › nova venda: escolha os animais, o comprador e o preço por arroba ou por cabeça.',
    'Informe os descontos (Funrural, Fundepec, nota, frete) e veja o lucro da venda.',
    'Em Mortes, escolha a causa na lista; o resumo mostra a mortalidade.',
    'Em Outras Causas, lance consumo, doação ou outras saídas.',
  ]),
  (Icons.fence, 'Pastos, mapa e rodízio', 'Onde o gado está.', [
    'Menu › Piquete/Pasto: cadastre área e animais de cada um.',
    'Para mudar o lote todo de pasto, toque em Mudar todos de pasto e escolha o destino.',
    'No Mapa, desenhe o contorno tocando nos cantos, andando com o GPS ou importando arquivo KML do Google Earth.',
    'O rodízio mostra dias de ocupação e de descanso, e a lotação aparece em UA/ha.',
  ]),
  (Icons.restaurant_outlined, 'Nutrição, insumos e batidas', 'Dieta, preços dos insumos e custo de cada batida.', [
    'Menu › Nutrição/Insumos › Estoque de insumos: cadastre milho, sorgo, sal e ingredientes e lance as entradas.',
    'Toque no insumo e use o cifrão para lançar o preço da embalagem; o histórico mostra a variação.',
    'Em Fórmulas: Proteínados/Racões, monte cada fórmula com os ingredientes e a quantidade da batida.',
    'Em Gerar batida, escolha a fórmula e quantas batidas: o Eito mostra o custo com os preços de hoje, baixa o estoque e guarda a batida.',
    'Em Histórico de batidas, veja cada batida e como o custo do quilo evoluiu.',
    'Em Dieta do cocho, monte a dieta de cada piquete e lance o trato do dia.',
  ]),
  (Icons.medication_outlined, 'Estoque de Medicamentos', 'Vacinas, remédios e vermífugos.', [
    'Menu › Rebanho › Estoque de Medicamentos › novo medicamento.',
    'Use o mesmo nome da sanidade (ex.: Aftosa) para a baixa ser automática a cada aplicação.',
    'Lance as entradas e acompanhe validade e estoque mínimo nos avisos.',
  ]),
  (Icons.attach_money, 'Financeiro', 'Custos, contas e resultado.', [
    'Menu › Financeiro › Custos e margem para ver custo por lote, por arroba e margem.',
    'Em Contas a pagar e receber, lance vencimentos e marque o que foi pago.',
    'Em Relatório financeiro (só o dono), veja o resultado do ano e compare anos; use o botão de PDF para imprimir.',
    'Em Cotação da arroba e Vender ou esperar, compare o preço de hoje com o ganho do lote.',
  ]),
  (Icons.bar_chart, 'Relatórios e documentos', 'Para o veterinário, o contador e a Agrodefesa.', [
    'Menu › Relatórios › escolha mensal ou anual.',
    'O relatório da fazenda em PDF resume o rebanho e a propriedade.',
    'Em Exportações, gere planilhas para o contador, o LCDPR e o resumo para a GTA com as faixas do SIDAGO.',
    'Em Exportações → Imposto de Renda, veja os quadros da atividade rural do IRPF (receitas e despesas mês a mês, resultado, rebanho, bens e dívidas) e baixe a planilha.',
    'O resumo da semana vira texto pronto para enviar pelo WhatsApp.',
  ]),
  (Icons.groups_outlined, 'Equipe e permissões', 'Quem vê e faz o quê.', [
    'Menu › Equipe e permissões.',
    'Para peão, toque em Criar login e defina usuário e senha. Para os demais, use Convidar pelo e-mail.',
    'Escolha o papel: gerente, veterinário, zootecnista, contador ou peão. Cada plano tem um limite de pessoas por papel.',
    'Em Quem lançou o quê, veja tudo o que cada pessoa registrou.',
  ]),
  (Icons.backup_outlined, 'Backup e segurança', 'Seus dados protegidos.', [
    'Menu › Backup: baixe o arquivo com todo o rebanho, lançamentos e fotos.',
    'Em Minha conta, troque senha e e-mail e ative a verificação em duas etapas com um aplicativo autenticador.',
    'O app funciona sem sinal e envia sozinho quando a internet volta. A faixa no topo mostra o que ainda espera.',
  ]),
];

/// Guia do Usuário: passo a passo de cada função do Eito.
class GuiaPage extends StatelessWidget {
  const GuiaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Pagina(
      titulo: 'Guia do Usuário',
      corpo: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Toque num assunto para ver o passo a passo. As telas citadas ficam no menu lateral.'),
        ),
        for (final (icone, titulo, resumo, passos) in _assuntos)
          ExpansionTile(
            leading: Icon(icone, color: Cores.oliva),
            title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(resumo),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedAlignment: Alignment.centerLeft,
            children: [
              for (var i = 0; i < passos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${i + 1}. ${passos[i]}'),
                ),
            ],
          ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined, color: Cores.oliva),
          title: const Text('Folder completo do Eito', style: TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.base.resolve('/folder.html'), webOnlyWindowName: '_blank'),
        ),
        ListTile(
          leading: const Icon(Icons.support_agent, color: Cores.oliva),
          title: const Text('Ainda com dúvida? Ajuda e suporte', style: TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Nav.ir(secAjuda),
        ),
      ]),
    );
  }
}
