# Marley (Flutter)

App de finanças pessoais da família (Nando & Thati), estilo YNAB, em EUR.
Recriação nativa em Flutter do app original em `index.html`
(`github.com/nandomclaren/marley`). Os dois compartilham o mesmo Gist do
GitHub como fonte de sincronização — o que tiver `_lastModified` mais
recente "ganha".

## Setup

```bash
flutter pub get
flutter run
```

As pastas de plataforma (`android/`, `ios/`) já estão no repositório
(geradas com `flutter create . --project-name marley --org com.marley` e
com `test/widget_test.dart` substituído por um smoke test real do app).

Validado com Flutter 3.47.1 / Dart 3.13.1: `flutter analyze` sem
apontamentos e `flutter test` passando (cálculos financeiros + um fluxo de
interação de ponta a ponta — adicionar transação, trocar de aba, abrir
detalhe de categoria). Duas coisas que só apareceram rodando de verdade,
não no `analyze` estático, e que já foram corrigidas:

- `AppState.selectedMonth` começava como string vazia até `init()`
  terminar, e qualquer tela que formatasse o mês (`monthLabel`) explodia
  nesse instante entre o primeiro frame e o carregamento do storage.
- As mutações chamavam `notifyListeners()` só depois do `await` na escrita
  em disco (`shared_preferences`); se essa escrita demorasse ou falhasse, a
  UI ficava sem saber que os dados já tinham mudado. Agora `notifyListeners()`
  roda antes da escrita (update otimista) e falha de disco não derruba nada.

Não fiz build de APK/IPA de verdade (sem Android SDK/Xcode no ambiente onde
isso foi escrito) — vale rodar `flutter build apk` ou `flutter build ios`
localmente antes de distribuir.

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

## Atualização OTA (Shorebird)

Ainda não implementado — o plano completo (o que cobre, passo a passo do
setup local, o que muda no CI) está documentado em
[`docs/OTA_UPDATES.md`](docs/OTA_UPDATES.md) para quando formos ligar isso.

## O que não foi portado

A antiga aba "Gráficos" (donut por grupo + Orçado vs Gasto) foi aposentada
por decisão do usuário; a aba Reflect cobre o que importa hoje.
