# Marley para iOS (SwiftUI)

App nativo do Marley para iPhone, com Liquid Glass (iOS 26). Usa o mesmo `marley-data.json` no Gist que o Marley web, com as mesmas regras de sincronização e proteção de dados.

## Abrir e rodar no seu iPhone

Precisa: Mac com **Xcode 26** e o iPhone com **iOS 26**.

1. Clone o repositório e abra **`MarleyiOS/Marley.xcodeproj`** no Xcode.
2. Espere o Xcode resolver o pacote local **MarleyCore** (aparece em *Package Dependencies*).
3. Clique no projeto **Marley** → target **Marley** → **Signing & Capabilities**:
   - **Team:** escolha a sua conta Apple (uma conta gratuita serve);
   - se o Xcode reclamar do Bundle Identifier, troque `com.nandomclaren.marley` por algo único seu.
4. Conecte o iPhone por cabo, escolha-o no topo do Xcode e aperte **▶︎ (Cmd+R)**.
   - Na primeira vez, o iPhone pede para ativar o **Modo de Desenvolvedor** (Ajustes → Privacidade e Segurança) e confiar no desenvolvedor (Ajustes → Geral → VPN e Gerenciamento de Dispositivo).
   - Com conta gratuita, o app vale por 7 dias; depois é só rodar de novo pelo Xcode. Com o Apple Developer Program pago, vale 1 ano.
5. No app: ⚙️ → cole o **mesmo token do GitHub e o Gist ID** do Marley web → **Testar e salvar**. Para a IA, cole a chave da Anthropic.

Se o projeto não abrir ou der erro de build, me mande a mensagem do Xcode (Cmd+Shift+Y abre o painel de erros) que eu corrijo.

**Plano B para o projeto:** existe também um `project.yml`. Com `brew install xcodegen`, rode `xcodegen` dentro de `MarleyiOS/` para gerar o `Marley.xcodeproj` de novo.

## O que tem

- **Fluxo:** transações do mês por dia, com o saldo corrido. Para compensar, deslize para a direita; para apagar, para a esquerda.
- **Nova/editar transação:** inclui parcelas (valor total + nº de parcelas, a 1ª no mês da compra, "1/6" na descrição), recorrente, a confirmar, categoria e sugestão de descrições passadas.
- **Apagar parcela:** pergunta "só esta" ou "esta e as seguintes". As reconciliadas nunca são apagadas.
- **Contas:** saldo working/compensado/pendente por conta, mais a **reconciliação** com o mesmo fluxo do web.
- **Budget:** A Alocar, orçado/gasto/disponível por categoria (com o saldo carregado dos meses anteriores), editar o orçado e mover dinheiro.
- **Reflect:** gastos por grupo, entradas vs saídas, patrimônio, idade do dinheiro.
- **IA:** o mesmo consultor do web (mesmas instruções e ferramentas). Mudanças só depois de você tocar em **Aplicar**.
- **Meses automáticos:** o mês atual e mais 2 à frente, criados só depois de sincronizar.

## Proteção dos dados

- Mesmas regras do web: "o mais novo vence", e o app pergunta antes de adotar dados com menos reconciliadas.
- Nunca envia, sem perguntar, algo que pareça perda de dados. A tolerância é de 5 transações a menos, 5 reconciliadas a menos, ou o arquivo abaixo de 70% do tamanho.
- Melhoria em relação ao web: o iPhone lembra quando sincronizou pela última vez. Se o iPhone **e** outro aparelho mudaram os dados, ele pergunta qual versão fica, em vez de escolher sozinho.
- Cópias no próprio iPhone: uma por dia e uma antes de cada vez que os dados são substituídos (Configurações → Backups neste iPhone).
- Os segredos (token do GitHub, chave da Anthropic) ficam no Keychain.

## Código

- `Packages/MarleyCore`: lógica pura em Swift (sem UI), com testes. Para rodar: `swift test` dentro da pasta.
  - JSON sem perdas: a ordem dos campos e os campos desconhecidos são preservados.
  - Cálculos, sincronização e a IA.
- `Marley/`: telas SwiftUI e estado do app (`AppStore`).
