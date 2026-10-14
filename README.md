# Eito Gestão Rural

> O controle da sua fazenda, na palma da sua mão, direto no seu eito de trabalho.

App de gestão de rebanho bovino (Flutter web/PWA + Firebase): roda no iPhone, no
Android e no computador, com login por e-mail e senha, os mesmos dados na nuvem
em todos os aparelhos, e funciona sem internet.

Esta versão junta o Eito (marca, Modo Curral, bastão e balança) com todos os
módulos da Caderneta do Rebanho.

**Como publicar:** veja [PUBLICAR.md](PUBLICAR.md).

## Módulos

Navegação pelo **menu lateral** (no computador ele fica sempre aberto), pela
**faixa da propriedade** no topo (toque para trocar de fazenda) e pelo botão
**+** com atalhos de cadastro.

| Seção | O que faz |
|---|---|
| **Painel** | Botão grande do Modo Curral, busca de animal, indicadores (lotes, animais, fêmeas/machos, prenhes, em carência), atalhos e alertas (partos, diagnósticos atrasados, aplicações). |
| **Propriedades** | Várias fazendas, com áreas, UF, atividades e anotações. Cada uma tem o seu rebanho. |
| **Lotes** | Ativos e inativos, período com data inicial e final, animais sem lote, migrar categoria (bezerras → novilhas, novilhas → vacas…), mover animais. |
| **Rebanho** | Ordem por nascimento, número ou nome; filtros; ficha com pesagens e GMD, reprodução, crias, sanidade; brinco eletrônico (RFID). |
| **Nascimento** | Cria ligada à mãe, peso ao nascer, fecha o serviço e passa a mãe para Vaca. |
| **Reprodução** | Abas Inseminação e Monta natural, diagnóstico, parto previsto (290 dias, em `lib/util/util.dart`). |
| **Sanidade e pesagens** | Por animal ou por lote (com % do lote), abas Vacinação, Antiparasitário e Tratamento com listas de itens, carência e próxima dose. Pesagem individual e de lote. |
| **Piquetes** e **Pastagem** | Área, forrageira, capacidade, lotação, entrada e saída de animais, adubação, roçada, vedação, altura do capim. |
| **Vendas e saídas** | Venda, morte, consumo, transferência, doação, com R$/cabeça e R$/kg. |
| **Relatórios** | Rebanho por sexo, categoria e lote; prenhez; partos previstos; GMD; sanidade; saídas do ano. |
| **Backup** | Copia e restaura tudo; também traz os dados do APK antigo da Caderneta. |

## Modo Curral (atalho)

Botão no Painel, no menu, no **+** e no topo de cada tela. Botões grandes para
lançar rápido o serviço do curral — **grava nos mesmos módulos** acima:

- **Encostou o bastão no brinco** (em qualquer tela principal), abre a ficha rápida:
  PESAR, VACINAR/MEDICAR, NASCIMENTO, DIAGNÓSTICO, MOVER, VENDA/SAÍDA.
- **Pesagem em série**: brinco → balança preenche o peso → CONFIRMAR → próximo.
  Mostra o GMD desde a pesagem anterior. Vai para Sanidade e pesagens › Pesagens.
- **Vacina e remédio em série**: escolhe o produto (mesma lista do módulo
  Sanidade) e registra a cada brinco lido, num lançamento só. Avisa repetição.
- **Nascimento, Novo animal, Mover animais, Venda ou saída.**

## Offline e sincronização

- Tudo é gravado no aparelho na hora; a faixa no topo mostra
  "Sem sinal — N lançamentos guardados" e envia sozinha quando houver internet.
- O que é lançado no iPhone aparece no computador (e vice-versa) em segundos.
- O app em si fica guardado no aparelho (`web/sw.js`), então abre sem sinal.

## Bastão de brinco eletrônico e balança

Funcionam no **modo teclado (HID)** por Bluetooth: o aparelho "digita" o número
lido e aperta Enter. É o único caminho que funciona no iPhone pelo navegador.
Teste em menu › **Bastão e balança**. Aparelhos só com Bluetooth "serial"
precisariam de app nativo.

## Dados no Firestore

Tudo fica em `usuarios/{uid}/{tabela}/{id}`, e as regras (`firestore.rules`) só
deixam cada usuário ler e gravar o que é dele. Tabelas: `propriedades`, `lotes`,
`piquetes`, `pastagens`, `saidas`, `animais`, `reproducoes`, `sanidade`,
`pesagens`, `config`. Datas em texto `AAAA-MM-DD`; ids numéricos.

Custos: o plano gratuito do Firebase cobre com folga uma fazenda. Cada abertura
do app após um tempo fora relê os dados da conta; com rebanhos muito grandes
(dezenas de milhares de registros) vale acompanhar o uso no console.

## Estrutura

```
lib/
  main.dart                 Firebase, cache offline, login → carregar dados → Painel
  firebase_options.dart     configuração do projeto (caderneta-rebanho)
  marca.dart / tema.dart    nome, slogan, cores (verde oliva + laranja)
  dados/db.dart             dados: cópia local + Firestore, mesmas funções da Caderneta
  dispositivos/leitor_teclado.dart   bastão RFID e balança (HID)
  util/util.dart            datas, números, campos, seletor de animais
  util/formato.dart         formatos e leitura de balança
  telas/
    base.dart               menu lateral, faixa da propriedade, botão +
    inicio.dart             Painel
    propriedades, lotes, mover, animais, reproducao, sanidade,
    piquetes, vendas, relatorios, backup
    modo_curral.dart        Modo Curral (atalho)
    ficha_animal.dart       ficha rápida do curral e escolha do produto
    manejo_em_serie.dart    pesagem e sanidade em série
    login.dart, dispositivos.dart
  widgets/                  botões grandes, teclado numérico, faixa de sincronia, logo
web/                        PWA: index.html, manifest, ícones, sw.js (offline)
assets/                     logo e foto de fundo
.github/workflows/publicar.yml  compila e publica (cópia em publicar-github.yml)
```

Arquivos antigos que ficaram vazios e podem ser apagados:
`lib/dados/repositorio.dart`, `lib/telas/novo_animal.dart`, `lib/telas/rebanho.dart`.

## Rodar no computador (opcional, se um dia instalar o Flutter)

```bash
flutter create . --platforms=web --project-name eito_gestao_rural
flutter pub get
flutter run -d chrome
```

Ou dois cliques em `publicar.bat`, que compila e publica.
