# Eito Gestão Rural

> O controle da sua fazenda, na palma da sua mão, direto no seu eito de trabalho.

App de gestão de rebanho bovino (Flutter web/PWA + Firebase): roda no iPhone, no
Android e no computador, com login por e-mail e dados na nuvem, e funciona sem internet.

## O que já tem

- **Modo Curral** (tela principal): encostou o bastão no brinco, a ficha do animal abre.
  Botões grandes, letras grandes e teclado numérico próprio, para usar com luva ou no sol.
- **Pesagem em série**: lê o brinco → a balança preenche o peso → CONFIRMAR → próximo.
  Calcula o ganho médio diário (GMD) desde a pesagem anterior.
- **Vacinação em série**: escolhe o produto uma vez e registra a cada brinco lido.
  Avisa se o mesmo animal for lido duas vezes.
- **Ficha do animal**: peso, idade, lote, histórico; pesar, medicar, vincular brinco
  eletrônico, registrar saída (venda, morte, descarte).
- **Rebanho**: lista com busca por brinco, nome, lote ou RFID.
- **Offline obrigatório**: tudo é gravado no aparelho na hora. A faixa no topo mostra
  "Sem sinal — N lançamentos guardados" e envia sozinha quando o celular pega internet.
- **Bastão RFID e balança via Bluetooth** no modo teclado (HID). Tela de teste em
  Modo Curral › ícone Bluetooth.

## Rodar no computador

Precisa do Flutter instalado (https://docs.flutter.dev/get-started/install/windows).

```bash
cd eito_gestao_rural
flutter create . --platforms=web --project-name eito_gestao_rural
flutter pub get
flutter run -d chrome
```

O `flutter create .` só completa o que falta; não apaga nada que já está aqui.

## Publicar (Firebase Hosting)

```bash
npm install -g firebase-tools
firebase login
flutter build web --release --no-web-resources-cdn
firebase deploy
```

O app fica em `https://caderneta-rebanho.web.app` logo após o primeiro deploy, e em
`https://eitoagro.com.br` depois de ligar o domínio (abaixo).
O `--no-web-resources-cdn` é obrigatório: sem ele o app busca arquivos na internet
ao abrir e não abre sem sinal. A cada versão nova, troque `eito-v1` em `web/sw.js`.

**No iPhone:** abra o endereço no Safari › Compartilhar › **Adicionar à Tela de Início**.
Instalado assim, ele abre em tela cheia, offline, e o iPhone não apaga os dados guardados.

### Domínio eitoagro.com.br

- Login: `eitoagro.com.br` e `www.eitoagro.com.br` já estão nos domínios autorizados.
- Depois do primeiro `firebase deploy`: Firebase › Hosting › **Adicionar domínio
  personalizado** › `eitoagro.com.br` (e depois `www.eitoagro.com.br` redirecionando).
  O Firebase mostra registros TXT e A; cadastre-os em registro.br › seu domínio ›
  DNS › Editar zona. O certificado HTTPS sai sozinho em algumas horas.

## Bastão de brinco eletrônico e balança

O Eito conversa com os aparelhos no **modo teclado (HID)**: pareados por Bluetooth como
teclado, eles "digitam" o número lido e apertam Enter. O app reconhece que veio do
aparelho pela velocidade, e cada tela usa a leitura do jeito certo (brinco ou peso).

- É o único caminho que funciona no **iPhone pelo navegador** (o Safari não tem
  Web Bluetooth) e funciona igual no Android e no computador.
- Confira se o seu modelo tem modo HID/teclado (a maioria dos bastões e indicadores
  com Bluetooth tem; o nome varia por marca).
- Aparelhos que só falam Bluetooth "serial" (sem modo teclado) precisam do app nativo
  Android/iOS com o protocolo daquele modelo. É um passo seguinte, feito por marca.

## Dados no Firestore

Tudo fica em `usuarios/{uid}/...`, e as regras (`firestore.rules`) só deixam cada
usuário ler e gravar o que é dele.

| Coleção | O que guarda |
|---|---|
| `usuarios/{uid}/animais` | brinco, rfid, nome, sexo, raça, lote, nascimento, pesoAtual, status |
| `usuarios/{uid}/eventos` | cadastro, pesagem (peso, GMD), sanidade (produto), rfid, saída |

## Estrutura

```
lib/
  main.dart                 Firebase, cache offline, login → Modo Curral
  firebase_options.dart     firebaseConfig do projeto
  marca.dart / tema.dart    nome, slogan, cores (verde oliva + laranja)
  dados/repositorio.dart    animais e eventos (gravação offline)
  dispositivos/leitor_teclado.dart   bastão RFID e balança (HID)
  telas/                    login, modo_curral, manejo_em_serie, ficha_animal,
                            novo_animal, rebanho, dispositivos
  widgets/                  botões grandes, teclado numérico, faixa de sincronia, logo
web/                        PWA: index.html, manifest, ícones, sw.js (offline)
assets/logo/                ícone (SVG) e logo horizontal (PNG)
assets/imagens/             fundo_gado.jpg: foto da entrada e do Modo Curral
                            (para trocar, substitua o arquivo mantendo o nome)
```
