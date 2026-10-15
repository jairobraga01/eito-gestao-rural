# Como publicar o Eito (sem instalar o Flutter)

O GitHub compila o app e publica no Firebase sozinho, toda vez que você envia
arquivos para o repositório `jairobraga01/eito-gestao-rural`.

Faça as partes 1 e 2 uma vez só. Depois, para cada versão nova, só a parte 3.

---

## Parte 1 — Chave para o GitHub publicar no Firebase (uma vez)

1. Abra <https://console.cloud.google.com/iam-admin/serviceaccounts?project=caderneta-rebanho>
   (entre com a mesma conta Google do Firebase).
2. **+ Criar conta de serviço** → nome: `github-publicar` → **Criar e continuar**.
3. Em "Conceder acesso", adicione os dois papéis:
   - **Administrador do Firebase** (Firebase Admin)
   - **Consumidor do Service Usage** (Service Usage Consumer)

   → **Continuar** → **Concluir**.
4. Clique na conta `github-publicar` criada → aba **Chaves** → **Adicionar chave** →
   **Criar nova chave** → **JSON** → **Criar**. Um arquivo `.json` é baixado.
   Guarde-o bem: ele dá acesso ao projeto.
5. No GitHub, abra o repositório → **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**:
   - Name: `FIREBASE_SERVICE_ACCOUNT`
   - Secret: abra o arquivo `.json` no Bloco de Notas, copie **tudo** e cole aqui.
   - **Add secret**.
6. No Firebase (<https://console.firebase.google.com/project/caderneta-rebanho/hosting>),
   se aparecer **Vamos começar / Get started** em Hosting, clique e avance até o fim
   (não precisa rodar nenhum comando que ele mostrar).

## Parte 2 — Arquivo de compilação no GitHub (uma vez)

A pasta `.github` some quando você arrasta arquivos, então este arquivo é criado pelo site:

1. No repositório, clique em **Add file** → **Create new file**.
2. No nome, digite exatamente: `.github/workflows/publicar.yml`
   (ao digitar a `/` o GitHub cria as pastas).
3. Abra o arquivo **`publicar-github.yml`** (na pasta do projeto, no seu computador)
   com o Bloco de Notas, copie todo o conteúdo e cole no GitHub.
4. **Commit changes…** → **Commit changes**.

## Parte 3 — Enviar os arquivos e publicar (a cada versão)

1. No repositório, **Add file** → **Upload files**.
2. Arraste **o conteúdo** da pasta `eito_gestao_rural` (as pastas `lib`, `web`,
   `assets`, `test` e os arquivos soltos: `pubspec.yaml`, `firebase.json`,
   `firestore.rules`, `analysis_options.yaml` etc.).
   O GitHub substitui os arquivos com o mesmo nome.
3. **Commit changes**.
4. Abra a aba **Actions**: aparece "Publicar o Eito" rodando (cerca de 5 a 8 minutos).
   - ✅ verde: o app está em <https://caderneta-rebanho.web.app>.
   - ❌ vermelho: clique na execução, depois no passo com ❌, copie as últimas
     linhas e mande para o Claude.

O passo **"Completar o projeto"** roda o `flutter create` e já apaga o
`test/widget_test.dart` que ele gera, em toda compilação.

> Para publicar de novo sem mudar nada: aba **Actions** → **Publicar o Eito** →
> **Run workflow**.

## Parte 4 — Domínio eitogestao.com.br (uma vez, depois do primeiro ✅)

1. Firebase → **Hosting** → **Adicionar domínio personalizado** → `eitogestao.com.br`
   → Continuar. O Firebase mostra registros **TXT** e **A**.
2. <https://registro.br> → seu domínio → **DNS** → **Editar zona** → crie os registros
   exatamente como o Firebase mostrou. Salve.
3. Repita para `www.eitogestao.com.br` (marque "Redirecionar para eitogestao.com.br").
4. Firebase → **Authentication** → **Configurações** → **Domínios autorizados** →
   **Adicionar domínio**: `eitogestao.com.br` e `www.eitogestao.com.br`
   (sem isso o login não funciona pelo domínio).
5. A propagação e o certificado HTTPS levam de algumas horas até 1 dia.

## No iPhone

Abra o endereço no **Safari** → **Compartilhar** → **Adicionar à Tela de Início**.
Instalado assim, abre em tela cheia, funciona sem sinal e o iPhone não apaga os dados guardados.
O primeiro acesso de cada aparelho precisa de internet (login e primeira cópia dos dados).

## Trazer os dados da Caderneta do Rebanho (versão antiga só do celular)

Se você lançou dados no APK antigo: lá, menu → **Backup** → **Copiar backup**;
mande o texto para você mesmo (WhatsApp/e-mail). No Eito: menu → **Backup** →
**Restaurar backup** → cole. Atenção: isso substitui os dados da conta.
