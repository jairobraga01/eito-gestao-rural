import 'package:eito_gestao_rural/dados/db.dart';
import 'package:eito_gestao_rural/dados/estoque.dart';
import 'package:eito_gestao_rural/dados/nota_compra.dart';
import 'package:eito_gestao_rural/dados/proteinado.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _xml = '''
<nfeProc><NFe><infNFe>
<ide><dhEmi>2026-10-12T10:30:00-03:00</dhEmi></ide>
<emit><xNome>AGROPECUARIA BOA SAFRA LTDA</xNome></emit>
<det nItem="1"><prod><cProd>1</cProd><xProd>SAL MINERAL 25KG</xProd><uCom>SC</uCom><qCom>10.0000</qCom><vUnCom>148.5000000000</vUnCom><vProd>1485.00</vProd></prod></det>
<det nItem="2"><prod><cProd>2</cProd><xProd>VACINA AFTOSA 50 DOSES</xProd><uCom>FR</uCom><qCom>4.0000</qCom><vUnCom>95.0000000000</vUnCom><vProd>380.00</vProd></prod></det>
<det nItem="3"><prod><cProd>3</cProd><xProd>MILHO MOIDO</xProd><uCom>KG</uCom><qCom>2000.0000</qCom><vUnCom>1.2000000000</vUnCom><vProd>2400.00</vProd></prod></det>
</infNFe></NFe></nfeProc>''';

void main() {
  setUp(() async {
    Db.bancoTeste = FakeFirebaseFirestore();
    await Db.iniciar('teste');
  });

  tearDown(Db.encerrar);

  test('XML da NF-e: itens, embalagem, categoria e data', () {
    final n = lerNotaXml(_xml)!;
    expect(n.fornecedor, 'AGROPECUARIA BOA SAFRA LTDA');
    expect(n.data, '2026-10-12');
    expect(n.itens.length, 3);
    final sal = n.itens[0];
    expect((sal.categoria, sal.unidade, sal.embalagem, sal.qtdEstoque), ('Sal mineral', 'kg', 25, 250));
    final vac = n.itens[1];
    expect((vac.categoria, vac.unidade, vac.embalagem, vac.qtdEstoque), ('Vacina', 'dose', 50, 200));
    final milho = n.itens[2];
    expect((milho.unidade, milho.embalagem, milho.valorUnit), ('kg', 1, 1.2));
  });

  test('XML com 3 casas decimais não vira milhar', () {
    const xml = '<nfeProc><NFe><infNFe><emit><xNome>X</xNome></emit>'
        '<det nItem="1"><prod><xProd>MILHO MOIDO</xProd><uCom>KG</uCom><qCom>2.500</qCom>'
        '<vUnCom>125.000</vUnCom></prod></det></infNFe></NFe></nfeProc>';
    final i = lerNotaXml(xml)!.itens.single;
    expect((i.valorUnit, i.qtdEstoque), (125.0, 2.5));
  });

  test('texto de PDF ou foto: linhas com unidade e sem unidade', () {
    const t = '''
AGRO VETERINARIA CENTRAL LTDA
Emissão 05/10/2026
001 7891234 IVERMECTINA 1% 500ML 3 FR 185,00 555,00
002 NUCLEO MINERAL 25 KG 4 SC 2.150,00 8.600,00
ULTIMA LINHA SEM NUMEROS
SORGO GRAO 1000 1,05 1.050,00
TOTAL DA NOTA 10.205,00''';
    final n = lerNotaTexto(t);
    expect(n.data, '2026-10-05');
    expect(n.fornecedor, 'AGRO VETERINARIA CENTRAL LTDA');
    expect(n.itens.map((i) => i.descricao), ['IVERMECTINA 1% 500ML', 'NUCLEO MINERAL 25 KG', 'SORGO GRAO']);
    final iver = n.itens[0];
    expect((iver.qtd, iver.valorUnit, iver.categoria, iver.unidade, iver.embalagem), (3, 185, 'Medicamento e vermífugo', 'ml', 500));
    final nucleo = n.itens[1];
    expect((nucleo.qtd, nucleo.valorUnit, nucleo.unidade, nucleo.embalagem), (4, 2150, 'kg', 25));
  });

  test('linha que não fecha quantidade × preço = total é ignorada', () {
    expect(lerNotaTexto('MILHO 10 KG 2,00 99,00').itens, isEmpty);
  });

  test('lançar a nota cria o insumo, dá entrada e registra o preço; repetir soma no mesmo insumo', () async {
    final n = lerNotaXml(_xml)!;
    expect(await lancarNota(n, data: '2026-10-12'), 3);
    await pumpEventQueue();
    final sal = insumoParecido('SAL MINERAL 25KG')!;
    expect(saldo(sal['id'] as int), 250);
    expect(precoKgInsumo(sal), closeTo(148.5 / 25, 1e-9));
    expect(historicoPrecos(sal['id'] as int).length, 1);

    await lancarNota(lerNotaXml(_xml)!, data: '2026-10-20');
    await pumpEventQueue();
    expect(Db.registros('insumos').length, 3);
    expect(saldo(sal['id'] as int), 500);
  });
}
