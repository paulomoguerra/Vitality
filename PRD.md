# PRD — Vitality redesign

> Menu bar + dashboard + widgets do Mac: ver o que está errado, e agir.
> Versão 0.1 — 2026-08-28 · Autor: Mateus (One Studio) · Status: rascunho para análise — **não implementar ainda**

---

## 1. Visão

Vitality já mede os sinais vitais do Mac e deixa agir (encerrar processo, liberar disco, alertar). O redesign não é “mais telas”. É tornar isso **óbvio em um olhar** e **acionável em um clique**, com a linguagem visual da casa One Studio.

**One-liner:** “Os sinais vitais do seu Mac — e o que fazer com eles.”

## 2. O que já existe (não reinventar)

O app está mais completo do que o mockup em `design/dashboard-redesign-mockup.html` sugere. Vários itens marcados **NOVO** no HTML **já estão no código**:

| Superfície | O que já faz |
|---|---|
| Menu bar | 12 métricas escolhíveis, cor só quando importa, labels, sparkline de 40s, largura estável |
| Popover | Health, CPU, GPU, temp, RAM, disco, power/bateria, top process — cada um com detalhe |
| Dashboard | Overview, Activity (quit/force quit), Network, Storage (volumes + browser + duplicatas + Free up via Lixeira), Battery, Sensors, Alerts |
| Alertas | 5 regras com histerese, sustain, snooze 6h, cooldown 6h, notificação nativa |
| Histórico | 1h / 24h / 7d persistido em `~/Library/Application Support/Vitality/history.json` |
| Widgets | small / medium / large |
| Princípios | Zero deps, sem sandbox no app, SMC só para temp/watt, lixo só via Trash |

Há um restyle **em andamento e incompleto** (não commitado): `VitalityShared/Theme.swift` + Overview no dashboard já falam “Cochicho dark bento”. Popover, tabelas, Storage, Sensors, widgets e a maior parte dos panes **ainda parecem SwiftUI de fábrica**. O redesign deste PRD absorve esse trabalho — não começa do zero, e não deixa metade do app na pele antiga.

## 3. Problema

Três superfícies, três histórias.

1. **O popover é uma lista de Settings.** Nove linhas + rodapé. Serve para inspecionar, não para decidir. Quem só usa a menu bar quase nunca vê o diferencial do produto (liberar disco, duplicatas, health que se explica).
2. **O dashboard é um monitor, não um médico.** Overview empilha anel + alertas + 4 gráficos + 3 processos. Se está tudo bem, é um mural de números. Se está ruim, o alerta manda “Open Storage” — não “liberar 9,8 GB de DerivedData”. Alertas estão no grupo **SETTINGS** da sidebar, o que é um erro de IA: alerta é estado vivo, não configuração.
3. **A pele nova não chegou nas pontas.** Um Overview Cochicho com um popover cinza-sistema e um widget SF Pro quebra a promessa de produto único.

O mercado (Stats, iStat Menus, MenuMeters, Activity Monitor) já ganha em **quantidade de sensores**. Vitality não vai ganhar lá. Ganha no loop **diagnóstico → ação**, que quase ninguém no menu bar faz sem virar CleanMyMac.

## 4. Público e posicionamento

- **Usuário 1:** Mateus. O redesign só segue para as outras fases depois de ele usar a Fase 1 no Mac real.
- **Público do repo:** quem clona um MIT de menu bar no GitHub — desenvolvedores e power users de Mac. UI em **inglês** (README, GitHub, OSS). Não é um produto de App Store ainda: distribuição continua bloqueada no Developer ID / notarização.

**Vs. concorrentes**

| Produto | O que faz bem | Onde Vitality entra |
|---|---|---|
| Stats (exelban) | Menu bar gratuito, muitos módulos | Pouca ação; Vitality fecha o loop (quit, Trash, duplicatas) |
| iStat Menus | Profundidade de sensores, 20 anos | Pago, denso, pouco “o que eu faço agora” |
| Activity Monitor | Processos oficiais | Escondido; Vitality traz o recorte útil para a menu bar |
| CleanMyMac | Limpeza | Nuvem, upsell, medo; Vitality só Lixeira, sem teatro |

## 5. Decisões fundadoras

| Decisão | Escolha | Por quê |
|---|---|---|
| Trabalho | Redesign de produto, não reskin | Reskin já começou e não resolve o loop |
| Stack | SwiftUI / AppKit existentes | Zero deps se mantém; sem rewrite |
| Job to be done | Diagnóstico → ação | Diferencial real contra Stats/iStat |
| Visual | Família One Studio, não clone do Cochicho | Mesma casa, layout de instrumento |
| Idioma da UI | Inglês | Repo público, README, usuários GitHub |
| Light mode | Fora desta versão | Comprometer o dark; light depois se doer |
| i18n | Fora | Não é redesign |
| Novos sensores | Só se alimentarem o loop | Fan control, per-app network, charge limit = outro produto |
| Distribuição | Fora deste PRD | Gatekeeper / D-U-N-S não se resolve com UI |

## 6. Linguagem visual

Referências no disco: `design/visual-language-ref.png` (Cochicho), `design/ref-crops/` (DeerFlow / matriz), `VitalityShared/Theme.swift` (tokens já escritos).

**Família (igual Cochicho / site One Studio):** fundo charcoal quente, um accent quente (`#FF4500`), hairline 6%, números em mono tabular, cards com raio contínuo, anel pontilhado no score.

**O que *não* copiar do Cochicho:** seis painéis iguais numerados 01–06 numa ditação. Vitality é um instrumento de sinais vitais. Overview pode ter números de painel (são vizinhos na mesma tela). Telas de detalhe (Activity, Storage, Sensors) usam **título + conteúdo**, não “07 TABLE”. Numeração em todo lugar é cargo-cult.

**Hierarquia de cor**

- **Ink** para leitura. **Accent** só para o que pede ação (botão, item selecionado, crítico).
- CPU / GPU / RAM / Disk têm slots de gráfico (já no Theme). Status continua verde / âmbar / accent — nunca um arco-íris extra.
- Menu bar: cor **quando importa** continua o default. Sempre-colorido é opção, não estética nova.

**Motion:** 1 Hz de dados. Animar o número a cada segundo cansa. Transições só em navegação, hover, e no anel de health. Respeitar `Reduce Motion`.

**Tipo:** SF Mono para números e labels de instrumento; SF Pro para prosa rara (diálogos, confirmação de Trash). Sem Inter, sem fonte web.

## 7. Conceito central — diagnóstico → ação

Toda tela responde três perguntas, nesta ordem:

1. **Está bem?** (score + uma frase)
2. **O que está errado?** (alerta ou maior dedução do score)
3. **O que eu faço?** (um botão primário)

O health score já se explica (`HealthScore.swift`: disco > swap > CPU > bateria). O redesign **amarra a explicação a um destino**:

| Dedução / alerta | Ação primária |
|---|---|
| Disco cheio | Abrir Storage no modo Free up, com o total recuperável no botão (“Free 9.8 GB…”) |
| CPU sustentada | Abrir Activity com o processo culpado já filtrado / selecionado |
| Swap pesado | Activity ordenado por memória |
| Temperatura alta | Sensors, sensor mais quente visível |
| Bateria baixa | Sem destino de tela — o popover já mostra a carga. Não inventar Settings de bateria do sistema |

Se o Mac está saudável, a ação primária some. Overview vira um cockpit calmo, não um CTA inventado.

## 8. Superfícies

### 8.1 Menu bar (strip)

Continua o que é hoje: métricas escolhíveis, ordem fixa, largura reservada, sparkline opcional.

**Novo:** se há alerta ativo, o ícone/anel do Vitality usa a cor do alerta mais grave. Sem badge numérico (a menu bar não é Notification Centre). Clique continua abrindo o popover. **Option-clique** (ou clique no item “Open Dashboard…” do popover) abre o dashboard na seção do alerta, se houver um.

### 8.2 Popover

Largura ~300px. Deixa de ser uma lista de Settings.

```
┌ health ring + score + uma linha de diagnóstico ┐
│  [ação primária, só se houver]                 │
├ CPU    38%  ▁▂▃▅▃    GPU  12%                  │
│ RAM    71%           DISK 41 GB free           │
│ POWER  6.2 W         BAT  87% AC               │
├ top process: XcodeBuildService  92%  [Quit]    │
├ Dashboard…  ·  Settings…  ·  Quit              │
└ MacBook Air · updated now                       ┘
```

- Quatro a seis vitals no grid, não nove rows. O que não cabe no grid (temp detalhada, per-core) continua **drill-in** a partir do vital.
- Top process ganha Quit/Force Quit no popover quando o processo é do usuário — hoje isso só vive no dashboard.
- “Buy me a coffee…” sai do root. Vive em Settings / About. O root de um instrumento não pede dinheiro.
- Settings do strip (“Menu bar…”) sai do popover de vitals e vai para a janela de Settings.

### 8.3 Dashboard

Sidebar de **cinco destinos + Settings**, não sete misturados:

| Nav | Papel |
|---|---|
| Overview | Cockpit. Health, alertas vivos, métricas com histórico, top 5, teaser de Free up |
| Activity | Tabela de processos. Filtro, sort, Quit / Force Quit, culpable pré-selecionado quando veio de alerta |
| Storage | Volumes + browser **ou** Duplicates **ou** Free up — três modos, um destino. Free up é o default quando o alerta é disco |
| Power | Bateria + consumo (o que hoje está em Battery + o power do Overview). Desktop sem bateria: só consumo, sem página vazia |
| Sensors | Temperaturas agrupadas, hottest em evidência |
| Settings | Menu bar strip, regras de alerta, login item, About / coffee |

**Alertas não são um item de nav.** Vivem no Overview (e como badge no item Overview se houver ativos). A configuração das regras vive em Settings.

Network **não merece nav próprio** nesta versão: o tráfego live cabe num card do Overview e, se precisar de mais, num drill do card. A pane Network atual (dois gráficos + totais da sessão) pode ficar como detalhe do card, não como sétima seção. Isso é uma decisão explícita: menos destinos, mais profundidade nos que importam para o loop.

Overview (bento, uma tela):

1. **Health** — anel pontilhado, frase, hardware numa linha, ação primária
2. **Alerts** — só se houver; senão uma linha “No action needed”, sem card vazio enorme
3. **Metrics** — CPU / GPU / Memory / Disk com histórico e período 1h / 24h / 7d compartilhado. Clique no card abre o destino certo (Activity / Sensors / Storage)
4. **Free up** — teaser com o total do último scan (ou “Scan for reclaimable space”). Já existe no Storage; Overview só aponta
5. **Activity** — top 5 com barra + Quit nos que o usuário possui

Hover nos gráficos: crosshair + tooltip com horário e valor (está no mockup; não está no Swift).

### 8.4 Widgets

Mesma pele do Theme. Small = score + uma métrica crítica. Medium = score + 4 vitals. Large = isso + sparkline ou top process.

Widget stale (“Open Vitality”) permanece — é honesto. Toque no widget abre o dashboard (hoje o widget é só leitura). Sem widget de “Free up”: WidgetKit não deve disparar Trash.

### 8.5 Settings

Janela ou seção única, não um quarto produto:

- Menu bar: quais métricas, cor, labels, graph, ícone (o que hoje está em `MenuBarSettingsPane`)
- Alerts: master switch, por regra, snooze status
- General: Open at login
- About: versão, MIT, coffee (Lightning QR)

## 9. Requisitos funcionais

### Deve (esta versão)

- Unificar Theme em **todas** as superfícies (strip, popover, dashboard, widgets, diálogos).
- Overview como cockpit do §8.3, com ação primária amarrada ao health/alerta.
- Alertas fora de Settings; Settings de verdade para regras + strip + login.
- Popover no layout de instrumento; coffee fora do root.
- Quit do top process no popover, com o mesmo diálogo de confirmação do dashboard.
- Alerta de disco leva ao modo Free up, não a um browser de volumes.
- Alerta de CPU seleciona/filtra o processo nomeado (já vai no texto do alerta).
- Power: uma seção. iMac/Studio sem bateria não mostram UI de ciclos/capacidade.
- Widget restyled; clique abre dashboard.
- Teclado no dashboard: `⌘1…⌘5` seções, `⌘,` Settings, `⌘F` filtro em Activity.
- Empty / loading / erro com a mesma voz (já existe “Limited data”; estender). Sem “Oops”.
- Confirmação de Trash e Force Quit inalterada em espírito: sempre reversível ou explícita.

### Deveria (se a Fase 1 passar no Mac real)

- Tooltip de gráfico (hover).
- Scan de Free up disparável do Overview, resultado cacheado até o próximo scan.
- Option-clique na menu bar → dashboard.
- Force Quit visível na tabela (hoje o diálogo mistura Quit / Force Quit; a coluna só diz “Quit”).

### Não deve

- Rede por app (precisa de APIs que o app deliberadamente não usa).
- Limite de carga 80% (API privada; território AlDente).
- Controle de fan.
- Export CSV / “Exportar…” do mockup.
- Conta, nuvem, telemetria, sandbox, Mac App Store.
- Light mode, i18n, onboarding alongado.
- Novo sensor que não alimenta health, alerta ou ação.
- Animação contínua no strip.

## 10. O que não muda (contratos)

Estes são o produto. O redesign os consome, não os reabre:

- Coleta a 1 Hz, um `StatusPoller`, deltas serializados.
- Health score e pesos em `HealthScore.swift` — pode mudar **copy** da mensagem, não a lógica, sem testes novos falhando de propósito.
- Alertas: histerese, sustain, cooldown, raw values de `AlertRuleID` (estão no disco).
- Histórico em `history.json`, mesmos ranges.
- App Group, widget sandboxed, app não-sandbox.
- Trash, nunca delete direto.
- SMC via IOKit público; valor ausente = omitir, nunca inventar.
- `LSUIElement` — continua app de menu bar, sem ícone no Dock por default.
- MIT, zero deps, macOS 14+.

## 11. Fora de escopo

Developer ID, notarização, GitHub Release, landing page, App Store. O redesign não desbloqueia download para terceiros.

## 12. Fases (avaliar uma, depois a próxima)

Lição da casa: não construir o bloco inteiro antes da primeira avaliação real.

**Fase 1 — Overview + IA do dashboard** (o pedaço que se julga)
Sidebar nova, Overview cockpit, alertas fora de Settings, Settings como destino, Power unificado, Network como card/detalhe. Theme no dashboard inteiro. Mateus usa isso uns dias. Só então Fase 2.

**Fase 2 — Menu bar + popover**
Strip com cor de alerta; popover instrumento; Quit no top process; coffee em About.

**Fase 3 — Profundidade**
Activity (culprit pré-selecionado, Force Quit visível, `⌘F`), Storage (Free up como default do alerta de disco, teaser no Overview), Sensors (hottest first), widgets, teclado, hover de gráfico.

Não há Fase 0 de “design system em abstrato”. Os tokens já estão em `Theme.swift`. A Fase 1 os aplica de verdade.

## 13. Critérios de aceite (Fase 1)

Mateus abre o dashboard no Mac dele e consegue, sem explicação:

1. Dizer em dois segundos se o Mac está bem.
2. Se não está, clicar **uma** coisa e cair no lugar que resolve (Free up ou o processo).
3. Não procurar Alertas em Settings.
4. Não ver metade da janela com a pele nova e metade com List/Table cinza de sistema — **dentro do dashboard**. (Popover e widget podem esperar a Fase 2/3.)
5. Desktop sem bateria: nenhuma seção “Battery” vazia.
6. Testes existentes (`VitalityTests`) passam. Health, cleanup, duplicatas, history não regridam.

## 14. Perguntas para você

Marca em cada uma. Sem isso a Fase 1 chuta.

1. **Nav:** concorda em matar Network e Alertas como itens de sidebar (Network vira card; Alertas vivem no Overview)?
2. **Coffee no popover:** sai do root, vai para Settings/About?
3. **Visual:** família One Studio (Theme atual) está fechada, ou quer pivotar para DeerFlow full dot-matrix?
4. **Idioma:** confirma inglês na UI?
5. **Fase 1 só no dashboard** — popover antigo até a Fase 2. Aguenta a mistura por uns dias, ou o popover tem que entrar na mesma leva?

---

Próximo passo depois da sua leitura: você marca as cinco perguntas. Aí implementamos **só a Fase 1**. Sem Notion, sem mockup extra, sem Fase 2 até você usar.
