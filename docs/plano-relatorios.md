# Plano — reforma dos relatórios

Escrito em 2026-09-07, depois do upgrade do fork para a 4.17.1.

Problema de origem: os relatórios estão pouco descritivos, e na prática quase não se
entende o que cada número significa. O objetivo é modernizar, criar relatórios novos e
dar filtros de verdade.

---

## 1. O que o upgrade já resolveu

Vale registrar para não refazermos trabalho. A 4.17.1 trouxe, no intervalo que o fork
tinha perdido:

- **Drilldown por barra** (`ReportDrilldownDrawer`, `useReportDrilldown`) — clicar num
  ponto do gráfico abre a gaveta com as conversas reais daquele bucket. Ataca
  diretamente o "não dá pra entender nada".
- **Gráficos migrados para `@chatwoot/viz`** — a modernização visual.
- **Tabela de rollup** `reporting_events_rollups`, com agregação pré-calculada, mais
  `ReportingEvents::RollupService` e `BackfillService`.
- **`Reports::ReportMetricRegistry`** — ponto de extensão declarativo. Métrica nova se
  adiciona registrando uma entrada, sem escrever query na mão.

## 2. O que continua ruim

### 2.1 Os textos das métricas

Sobreviveu ao upgrade e é a causa mais barata do problema. Em
`app/javascript/dashboard/i18n/locale/pt_BR/report.json`:

```
RESOLUTION_COUNT       NAME="Contagem de Resolução"      DESC="( Total )"
BOT_RESOLUTION_COUNT   NAME="Contagem de Resolução"      DESC="( Total )"   <- nome idêntico
REPLY_TIME             NAME="Tempo de espera do cliente" DESC=""
FIRST_RESPONSE_TIME    INFO_TEXT="Número total de conversas utilizadas para computação:"
```

Duas métricas diferentes com o mesmo nome, `DESC` que não descreve nada, e apenas 2 das
9 métricas têm `INFO_TEXT` — sendo que esses 2 são rótulos pendurados sem frase.
Cobertura: en=496 chaves, pt_BR=491, pt=491.

### 2.2 Os filtros

`ReportFilters.vue` **não mudou nada no upstream**. Continua oferecendo apenas:
intervalo de datas, **uma** entidade por vez, agrupamento e horário comercial.
Filtros novos são trabalho nosso.

## 3. Duas restrições que definem o que é viável

**O rollup agrega por dia e guarda só `count`, `sum_value` e
`sum_value_business_hours`.** A coluna é `date`, não `datetime`. Consequência:
**percentis e recorte por hora não podem sair do rollup** — precisam da tabela crua
`reporting_events`.

**A tabela crua aguenta.** Volume real no eletrofast (2026-09-07):

| tabela | linhas |
|---|---|
| `reporting_events` | 137.330 |
| `conversations` | 47.329 |
| `messages` | 589.081 |

Volume modesto. E já existe o índice `index_reporting_events_for_response_distribution`
(`account_id, name, inbox_id, created_at`) — o upstream antecipou análise de
distribuição. Percentis são viáveis sem infraestrutura nova.

---

## 4. Fase A — Tornar legível o que já existe

Melhor retorno por esforço, independente de todo o resto, sem tocar em backend.

- Nomes distintos e corretos para as 9 métricas
- `DESC` que explica a conta, no lugar de `( Total )`
- `INFO_TEXT` em todas as métricas
- Fechar as 5 chaves faltantes do pt_BR

## 5. Fase B — Filtros

Onde está o buraco real.

- **Multi-seleção** — comparar 3 agentes lado a lado; hoje só um por vez
- **Comparação com período anterior** em todo card; um número sozinho não informa nada
- **Recorte por status, por canal, e por combinação label × caixa**
- **Agrupamento por hora** — `V2::Reports::DrilldownBuilder::SUPPORTED_GROUP_BY` já
  aceita `hour`, mas a UI só oferece dia/semana/mês/ano. É destravar o que já existe.

## 6. Fase C — Relatórios novos

Ordenados por valor. A fonte de dados define o esforço: os de rollup entram pelo
`ReportMetricRegistry` e são baratos; os de tabela crua precisam de query própria e são
os mais informativos.

| Relatório | O que responde | Fonte |
|---|---|---|
| Percentis p50/p90/p95 de 1ª resposta e resolução | a média esconde o cliente que esperou 4h | crua |
| Heatmap hora × dia da semana | dimensionar escala de atendimento | crua |
| Backlog ao longo do tempo | hoje só existe fluxo, não estoque de conversas abertas | conversas |
| Funil: recebidas → respondidas → resolvidas → CSAT | onde se perde gente | rollup |
| Tabela comparativa de agentes, multi-métrica e ordenável | ranking real de equipe | rollup |
| Conversas sem resposta / abandonadas | o que está caindo no vão | crua |
| Motivo de encerramento por label | por que as conversas terminam | rollup |

## 7. Fase D — O MCP do fork

O fork expõe relatórios a assistentes externos via `app/services/mcp/reports.rb`
(ferramentas `relatorio_agora`, `relatorio_por`, `relatorio_resumo`). Métrica nova
deveria aparecer lá também, senão o assistente fica com visão mais pobre que a tela.
Decidir se entra junto ou depois.

---

## 8. Ordem sugerida

Começar pela **Fase A** (rápida, efeito imediato) e, em paralelo, prototipar **um**
relatório da Fase C — proposta: os **percentis**, por ser o que mais muda decisão e por
validar o caminho da tabela crua. Com os dois no ar, calibrar o resto.

## 9. Decisões pendentes

1. **Onde desenvolver.** A stack de teste roda 4.17.1 mas tem só 143 conversas, o que é
   pouco para avaliar relatório. Alternativa: trabalhar contra uma cópia do banco do
   eletrofast, que tem volume real.
2. **Fase A já?** É contida, não mexe em backend e não depende de nenhuma outra decisão.
