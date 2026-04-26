# Definicao de SLIs, SLOs e Error Budget

## 1 - Introducao

Este documento define formalmente os Service Level Indicators (SLIs), Service Level Objectives (SLOs) e o Error Budget do Gateway de Pagamentos,  Estas metricas sao a base para avaliar se a arquitetura de alta disponibilidade atinge as metas operacionais propostas.

---

## 2 - Service Level Indicators (SLIs)

SLIs sao as metricas quantitativas que medem a qualidade do servico percebida pelo usuario.

### SLI-1: Disponibilidade (Availability)

- **Definicao**: Proporcao de requisicoes HTTP bem-sucedidas (status < 500) em relacao ao total de requisicoes.
- **Formula**: `SLI = 1 - (requisicoes_5xx / total_requisicoes)`
- **Fonte**: Metrica Prometheus `gateway_http_requests_total` com label `status_code`
- **Query Prometheus**:
  ```promql
  1 - (
    sum(rate(gateway_http_requests_total{status_code=~"5.."}[5m]))
    /
    sum(rate(gateway_http_requests_total[5m]))
  )
  ```

### SLI-2: Latencia (Latency)

- **Definicao**: Percentil 95 (p95) da duracao das requisicoes HTTP.
- **Formula**: `SLI = percentile(95, duracao_requisicoes)`
- **Fonte**: Metrica Prometheus `gateway_http_request_duration_seconds`
- **Query Prometheus**:
  ```promql
  histogram_quantile(0.95, rate(gateway_http_request_duration_seconds_bucket[5m]))
  ```

### SLI-3: Integridade de Dados (Data Integrity)

- **Definicao**: Proporcao de transacoes confirmadas no primario que estao presentes na replica.
- **Formula**: `SLI = transacoes_na_replica / transacoes_no_primario`
- **Fonte**: Consulta SQL direta ou metrica `pg_replication_lag` do PostgreSQL Exporter
- **Validacao**: Script `validate-rpo.sh`

### SLI-4: Tempo de Recuperacao (Recovery Time)

- **Definicao**: Tempo medido entre a deteccao de uma falha e a restauracao completa do servico.
- **Formula**: `SLI = timestamp_recuperacao - timestamp_falha`
- **Fonte**: Script `validate-rto.sh`

---

## 3 - Service Level Objectives (SLOs)

SLOs sao as metas de desempenho que a arquitetura se compromete a atingir.

| ID | SLI Associado | Objetivo (SLO) | Janela | Justificativa |
|----|--------------|----------------|--------|---------------|
| SLO-1 | Disponibilidade | >= 99,9% | 30 dias | Meta alinhada a "3 noves" (secao 2.1.1 do TCC). Permite no maximo 43 minutos de downtime mensal. |
| SLO-2 | Latencia (p95) | < 500ms | 30 dias | Requisito de experiencia do usuario para transacoes financeiras. |
| SLO-3 | Integridade | = 100% (RPO = 0) | Continua | Transacoes financeiras nao podem ser perdidas. Garantido pela replicacao sincrona. |
| SLO-4 | Recuperacao | RTO < 15s | Por incidente | Failover automatico deve restaurar servico em menos de 15 segundos. |

---

## 4 - Error Budget

O Error Budget e derivado diretamente do SLO e representa a "margem de erro" que o sistema pode consumir antes de violar o objetivo de nivel de servico.

### 4.1 - Calculo do Error Budget

Para SLO-1 (Disponibilidade >= 99,9%):

```
Error Budget = 1 - SLO = 1 - 0.999 = 0.001 (0.1%)

Em uma janela de 30 dias:
  Total de minutos: 30 * 24 * 60 = 43.200 minutos
  Error Budget:     43.200 * 0.001 = 43,2 minutos

Em requisicoes (assumindo 10.000 req/dia):
  Total de requisicoes: 300.000
  Error Budget:         300.000 * 0.001 = 300 requisicoes com erro permitidas
```

### 4.2 - Politica de Consumo do Error Budget

| Consumo do Budget | Acao |
|-------------------|------|
| 0% - 25% consumido | Operacao normal. Deploys e mudancas permitidos. |
| 25% - 50% consumido | Alerta amarelo. Revisar causa dos erros. Deploys com cautela. |
| 50% - 75% consumido | Alerta laranja. Priorizar estabilidade. Apenas hotfixes. |
| 75% - 100% consumido | Alerta vermelho. Freeze de deploys. Foco total em confiabilidade. |
| > 100% consumido | SLO violado. Post-mortem obrigatorio. Nenhum deploy ate recuperacao. |

### 4.3 - Monitoramento do Error Budget

O Error Budget e monitorado em tempo real atraves do dashboard Grafana (`gateway-ha-dashboard`), que exibe:

- **Gauge "Availability SLI"**: Mostra a porcentagem de disponibilidade atual
- **Gauge "Error Budget Remaining"**: Mostra quanto do error budget resta na janela de 24h

Query Prometheus para Error Budget restante:
```promql
100 * (1 - (
  sum(rate(gateway_http_requests_total{status_code=~"5.."}[24h]))
  / (sum(rate(gateway_http_requests_total[24h])) * 0.001)
))
```

---

## 5 - Service Level Agreement (SLA)

O SLA e o compromisso contratual baseado nos SLOs. Para esta PoC academica, o SLA nao e formalmente estabelecido com clientes externos. Porem, a estrutura esta preparada para definicao:

| SLA Proposto | Baseado em | Penalidade Sugerida |
|-------------|-----------|-------------------|
| Disponibilidade >= 99,5% | SLO-1 (99,9%) com margem | Credito de servico |
| Latencia p95 < 1000ms | SLO-2 (500ms) com margem | Notificacao ao cliente |
| RPO = 0 | SLO-3 (100%) | Compensacao financeira |

**Nota**: O SLA e deliberadamente menos restritivo que o SLO, conforme pratica de SRE. O SLO interno mais restritivo garante que o SLA externo seja cumprido com margem de seguranca.

---

## 6 - Relacao entre Metricas

```
MTBF (Tempo Medio Entre Falhas)
  |
  |-- Aumentado por: Active-Active (AA-1), Health Checks, Validacao de dados
  |
MTTR (Tempo Medio para Reparo)
  |
  |-- Reduzido por: Auto-failover, Observabilidade (Prometheus/Grafana), IaC (Terraform)
  |
Disponibilidade = MTBF / (MTBF + MTTR)
  |
  |-- SLO >= 99,9% exige MTTR < 43 min/mes
  |
RTO (Recovery Time Objective) < 15s
  |
  |-- Garantido por: Nginx failover (~10s) + App restart (~5s)
  |
RPO (Recovery Point Objective) = 0
  |
  |-- Garantido por: Replicacao sincrona (synchronous_commit = on)
```

---

## 7 - Validacao dos SLOs

Cada SLO pode ser validado atraves dos scripts e ferramentas da PoC:

| SLO | Metodo de Validacao | Script/Ferramenta |
|-----|-------------------|------------------|
| SLO-1 | Smoke test + monitoramento Grafana | `smoke-test.sh` + Dashboard |
| SLO-2 | Metricas de latencia via Prometheus | Dashboard Grafana (p95 panel) |
| SLO-3 | Teste de replicacao e validacao pos-falha | `validate-rpo.sh` |
| SLO-4 | Simulacao de falha com medicao de tempo | `validate-rto.sh` |


