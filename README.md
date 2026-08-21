# Marley (Flutter)

App de finanças pessoais da família (Nando & Thati), estilo YNAB, em EUR.
Recriação nativa em Flutter do app original em `index.html`
(`github.com/nandomclaren/marley`). Os dois compartilham o mesmo Gist do
GitHub como fonte de sincronização — o que tiver `_lastModified` mais
recente "ganha".

## Setup

Este repositório foi escrito à mão (sem o Flutter SDK disponível no
ambiente onde foi criado), então as pastas de plataforma (`android/`,
`ios/`, etc.) **ainda não existem**. Antes de rodar:

```bash
flutter create . --project-name marley --org com.marley
flutter pub get
```

Isso gera as pastas de plataforma sem tocar em `lib/` nem `pubspec.yaml`
(ele detecta o projeto existente e só preenche o que falta). Depois disso:

```bash
flutter run
```

Rode `flutter analyze` e `flutter test` em seguida — o código não foi
compilado/testado localmente ainda (sem SDK no ambiente de criação), então
vale a pena revisar o output com atenção na primeira vez.

## Sincronização (Gist)

Na primeira execução, abra o ícone de nuvem na AppBar (ou segure para abrir
direto as configurações) e informe:

- Um **GitHub Personal Access Token** com escopo `gist`.
- O **ID** de um Gist secreto já criado (pode estar vazio — o app cria o
  arquivo `marley-data.json` nele no primeiro push).

As credenciais ficam em `flutter_secure_storage` (Keychain/Keystore), nunca
em texto puro no dispositivo.

## Estrutura

```
lib/
  models/       Txn, Goal, AppData — mesmo schema JSON do app web
  data/         categorias/cores, storage local, sync com Gist
  state/        AppState (ChangeNotifier) — única fonte de verdade
  utils/        formatação (EUR, datas) e toda a lógica financeira
                (calculations.dart: saldo hoje, NDMP, carryover, net
                worth, Age of Money FIFO)
  theme/        cores e tema claro/escuro (escuro automático 18h–6h)
  screens/      Fluxo, Budget, Reflect, Contas — as 4 abas
  widgets/      componentes reutilizados pelas telas
```

A lógica financeira em `lib/utils/calculations.dart` é uma porta fiel do
`index.html` original — qualquer alteração de comportamento aí deve ser
validada contra a versão web antes de mergear.

## O que não foi portado

A antiga aba "Gráficos" (donut por grupo + Orçado vs Gasto) foi aposentada
por decisão do usuário; a aba Reflect cobre o que importa hoje.
