# Atualização OTA (delta-update) com Shorebird — guia para implementar depois

**Status: não implementado ainda.** Este documento só registra o plano para
quando formos ligar isso, pra não perder o raciocínio.

## O problema que isso resolve

Hoje, toda mudança no app — mesmo uma linha de Dart — exige gerar um APK
novo pelo GitHub Actions e reinstalar manualmente no celular. O
[Shorebird](https://shorebird.dev) permite publicar um "patch" que é
baixado e aplicado pelo próprio app já instalado, sem passar pela loja/APK
de novo — parecido com CodePush do React Native.

## O que o Shorebird cobre (e o que não cobre)

- **Cobre:** mudanças de código Dart/Flutter compiladas em AOT — telas,
  lógica de cálculo, correções de bug, novos widgets, etc. Isso é a
  imensa maioria das mudanças que temos feito nesta sessão.
- **Não cobre:** qualquer coisa no lado nativo — permissões do
  `AndroidManifest.xml`, plugins nativos novos/atualizados, o ícone do
  app, mudança de `minSdkVersion`, etc. Qualquer uma dessas exige gerar
  um **APK novo** (`shorebird release`, não `patch`) e reinstalar mais
  uma vez — depois disso, os patches seguintes voltam a ser OTA.

Ou seja: instala o APK base uma vez (via Shorebird), e diferenças no
código Dart depois disso viram patches automáticos. Só volta a precisar de
instalação manual se mexermos em algo nativo.

## Por que isso ficou pendente

O ambiente onde a sessão de desenvolvimento roda tem a rede bloqueada para
`api.shorebird.dev` (confirmado por `curl` retornando 403 de política).
Isso significa que **eu não consigo rodar `shorebird login:ci`,
`shorebird init`, `shorebird release` ou `shorebird patch` a partir desta
sessão** — precisa ser feito localmente pelo usuário (ou por um job do
GitHub Actions, que tem rede livre; optamos pela via local).

## Passo a passo (one-time setup, local, feito pelo usuário)

1. **Instalar a CLI do Shorebird** localmente:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh | bash
   ```
   (ou ver instruções atualizadas em https://docs.shorebird.dev/)

2. **Login** (abre o navegador para OAuth e gera um token de CI):
   ```bash
   shorebird login:ci
   ```
   Isso imprime um `SHOREBIRD_TOKEN` — guardar esse valor, ele vai virar
   secret do GitHub Actions no passo 6.

3. **Clonar/entrar no repo e trocar para a branch de desenvolvimento**:
   ```bash
   git clone https://github.com/nandomclaren/marley-app.git
   cd marley-app
   git checkout claude/nifty-johnson-ir4hx5   # ou a branch atual do app
   ```

4. **Inicializar o Shorebird no projeto** (cria `shorebird.yaml` com o
   `app_id` do app registrado na Shorebird):
   ```bash
   export SHOREBIRD_TOKEN=<token do passo 2>
   shorebird init
   ```

5. **Commitar e dar push do `shorebird.yaml`** gerado:
   ```bash
   git add shorebird.yaml
   git commit -m "Add Shorebird config for OTA updates"
   git push -u origin claude/nifty-johnson-ir4hx5
   ```

6. **Adicionar `SHOREBIRD_TOKEN` como secret do repositório** no GitHub
   (Settings → Secrets and variables → Actions → New repository secret),
   pra que o workflow do CI consiga publicar releases/patches.

## O que muda no CI depois disso (a fazer quando o setup acima estiver pronto)

Depois que o `shorebird.yaml` existir e o secret estiver configurado, o
`.github/workflows/build-apk.yml` precisa ganhar (ou um workflow novo
paralelo):

- Instalar a Shorebird CLI no runner.
- Trocar `flutter build apk --release` por **`shorebird release android`**
  para gerar o APK base instalável (o que o usuário instala manualmente
  uma vez).
- Um segundo workflow/job, disparado nos commits seguintes que só tocam
  código Dart, rodando **`shorebird patch android`** — isso publica o
  patch OTA; o app já instalado baixa e aplica sozinho (tipicamente no
  próximo start).
- Convém alguma regra simples pra decidir `release` vs `patch`: se o
  diff mexeu em `android/`, `ios/`, `pubspec.yaml` (dependências nativas)
  ou nos ícones, é `release` (novo APK); se mexeu só em `lib/`, é
  `patch`.

## Quando retomar

Assim que o usuário terminar os passos 1–6 acima localmente, é só avisar
que eu ajusto o workflow do GitHub Actions para usar `shorebird release`
no primeiro build e `shorebird patch` nos seguintes.
