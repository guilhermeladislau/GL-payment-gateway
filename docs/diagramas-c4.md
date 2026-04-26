# Diagramas C4 - Gateway de Pagamentos HA

Documentacao arquitetural seguindo o C4 Model (Context, Containers, Components, Code) 

---

## Nivel 1 - Diagrama de Contexto

Visao geral do sistema e suas interacoes com atores e sistemas externos.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CONTEXTO DO SISTEMA                         │
│                                                                     │
│                                                                     │
│    ┌──────────┐         ┌─────────────────────────┐                 │
│    │          │         │                         │                 │
│    │ Cliente  │────────>│  Gateway de Pagamentos  │                 │
│    │ (API)    │  HTTPS  │                         │                 │
│    │          │<────────│  Sistema de processamento│                │
│    └──────────┘         │  de transacoes          │                 │
│                         │  financeiras com alta   │                 │
│    Aplicacoes que       │  disponibilidade        │                 │
│    consomem a API       │                         │                 │
│    de pagamentos        └────────────┬────────────┘                 │
│    (e-commerce,                      │                              │
│     mobile apps,                     │ Persiste                     │
│     sistemas ERP)                    │ transacoes                   │
│                                      │                              │
│                         ┌────────────▼────────────┐                 │
│                         │                         │                 │
│                         │  Banco de Dados         │                 │
│                         │  PostgreSQL             │                 │
│                         │                         │                 │
│                         │  Armazenamento          │                 │
│                         │  persistente de         │                 │
│                         │  transacoes com         │                 │
│                         │  replicacao sincrona    │                 │
│                         │                         │                 │
│                         └─────────────────────────┘                 │
│                                                                     │
│                         ┌─────────────────────────┐                 │
│                         │                         │                 │
│                         │  Stack de               │                 │
│                         │  Observabilidade        │                 │
│                         │                         │                 │
│                         │  Prometheus + Grafana   │                 │
│                         │  Monitoramento de       │                 │
│                         │  SLIs e Error Budget    │                 │
│                         │                         │                 │
│                         └─────────────────────────┘                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Descricao dos Elementos

| Elemento | Tipo | Descricao |
|----------|------|-----------|
| Cliente (API) | Ator Externo | Aplicacoes que consomem a API REST do gateway para processar transacoes financeiras |
| Gateway de Pagamentos | Sistema | Sistema central que recebe, valida e persiste transacoes de pagamento |
| Banco de Dados PostgreSQL | Sistema de Suporte | Armazena transacoes com replicacao sincrona para garantir RPO = 0 |
| Stack de Observabilidade | Sistema de Suporte | Coleta e visualiza metricas para monitoramento de SLIs e error budget |

---

## Nivel 2 - Diagrama de Conteineres

Detalha como o sistema e dividido em conteineres (unidades de deploy), mostrando a distribuicao Multi-AZ.

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              GATEWAY DE PAGAMENTOS                                  │
│                                                                                     │
│           Cliente (API Consumer)                                                    │
│                    │                                                                │
│                    │ HTTP :8080                                                      │
│                    ▼                                                                │
│  ┌─────────────────────────────────────┐                                            │
│  │         Nginx Load Balancer         │  Distribui trafego round-robin             │
│  │         [nginx:1.25-alpine]         │  Health check passivo                      │
│  │         Container: lb-nginx         │  max_fails=3, fail_timeout=10s             │
│  └──────────┬──────────────┬───────────┘                                            │
│             │              │                                                        │
│  ┌──────────┼──────────────┼───────────────────────────────────────────────────────┐ │
│  │          │   AZ-1       │                                                      │ │
│  │          ▼              │                                                      │ │
│  │  ┌──────────────┐      │                                                      │ │
│  │  │   App (1)    │      │                                                      │ │
│  │  │   FastAPI     │      │                                                      │ │
│  │  │   :3000      │      │     ┌──────────────────────┐                         │ │
│  │  │              │──────┼────>│  PostgreSQL Primary  │                         │ │
│  │  │  GET /health │      │     │  [postgres:16-alpine]│                         │ │
│  │  │  POST /txn   │      │     │  Container: pg-primary                        │ │
│  │  │  GET /metrics│      │     │  :5432               │                         │ │
│  │  └──────────────┘      │     │                      │   WAL Streaming         │ │
│  │                        │     │  Todas as escritas   │──(sincrono)──┐          │ │
│  └────────────────────────┘     │  e leituras          │              │          │ │
│                                 └──────────────────────┘              │          │ │
│  ┌──────────────────────────────────────────────────────────┐        │          │ │
│  │          │   AZ-2                                        │        │          │ │
│  │          ▼                                               │        ▼          │ │
│  │  ┌──────────────┐                 ┌──────────────────────┤                   │ │
│  │  │   App (2)    │                 │  PostgreSQL Replica  │                   │ │
│  │  │   FastAPI     │                 │  [postgres:16-alpine]│                   │ │
│  │  │   :3000      │                 │  Container: pg-replica                   │ │
│  │  │              │─────────────────│  :5433               │                   │ │
│  │  │  GET /health │  (writes via    │                      │                   │ │
│  │  │  POST /txn   │   pg-primary)   │  Hot Standby         │                   │ │
│  │  │  GET /metrics│                 │  Leituras apenas     │                   │ │
│  │  └──────────────┘                 └──────────────────────┘                   │ │
│  │                                                                              │ │
│  └──────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
│  ┌──────────────────────────── Observabilidade ────────────────────────────────┐   │
│  │                                                                             │   │
│  │  ┌────────────────┐    ┌──────────────┐    ┌──────────────────────────┐     │   │
│  │  │  PG Exporter   │    │  PG Exporter │    │                          │     │   │
│  │  │  (Primary)     │    │  (Replica)   │    │      Prometheus          │     │   │
│  │  │  :9187         │───>│  :9187       │───>│      [prom/prometheus]   │     │   │
│  │  └────────────────┘    └──────────────┘    │      :9090               │     │   │
│  │                                            │                          │     │   │
│  │  Scrape: app-1:3000/metrics ──────────────>│  Coleta metricas de     │     │   │
│  │  Scrape: app-2:3000/metrics ──────────────>│  todos os componentes   │     │   │
│  │                                            └────────────┬─────────────┘     │   │
│  │                                                         │                   │   │
│  │                                            ┌────────────▼─────────────┐     │   │
│  │                                            │                          │     │   │
│  │                                            │      Grafana             │     │   │
│  │                                            │      [grafana/grafana]   │     │   │
│  │                                            │      :3001               │     │   │
│  │                                            │                          │     │   │
│  │                                            │  Dashboards:             │     │   │
│  │                                            │  - Request Rate          │     │   │
│  │                                            │  - Latency p95           │     │   │
│  │                                            │  - Error Rate            │     │   │
│  │                                            │  - Replication Lag       │     │   │
│  │                                            │  - Availability SLI      │     │   │
│  │                                            │  - Error Budget          │     │   │
│  │                                            └──────────────────────────┘     │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Inventario de Conteineres

| Container | Imagem | Porta | Rede(s) | Funcao |
|-----------|--------|-------|---------|--------|
| lb-nginx | nginx:1.25-alpine | 8080 | az-1, az-2 | Balanceador de carga com health checks passivos |
| app-1 | ha-payment-gateway:latest | 3000 | az-1 | Instancia da aplicacao FastAPI (Active-Active) |
| app-2 | ha-payment-gateway:latest | 3000 | az-2 | Instancia da aplicacao FastAPI (Active-Active) |
| pg-primary | postgres:16-alpine | 5432 | az-1, az-2 | Banco de dados primario (leitura + escrita) |
| pg-replica | postgres:16-alpine | 5433 | az-2 | Banco de dados replica (hot standby, leitura) |
| pg-exporter-primary | postgres-exporter:v0.15.0 | 9187 | az-1 | Exportador de metricas do PostgreSQL primario |
| pg-exporter-replica | postgres-exporter:v0.15.0 | 9187 | az-2 | Exportador de metricas do PostgreSQL replica |
| prometheus | prom/prometheus:v2.51.0 | 9090 | az-1, az-2 | Coleta e armazena metricas de todos os componentes |
| grafana | grafana/grafana:10.4.0 | 3001 | az-1, az-2 | Visualizacao de dashboards e SLIs |

### Comunicacao entre Conteineres

| Origem | Destino | Protocolo | Descricao |
|--------|---------|-----------|-----------|
| Cliente | lb-nginx | HTTP :8080 | Requisicoes da API |
| lb-nginx | app-1 | HTTP :3000 | Proxy reverso (round-robin) |
| lb-nginx | app-2 | HTTP :3000 | Proxy reverso (round-robin) |
| app-1 | pg-primary | TCP :5432 | Conexao de banco (TypeORM) |
| app-2 | pg-primary | TCP :5432 | Conexao de banco (TypeORM) |
| pg-primary | pg-replica | TCP :5432 | WAL Streaming (replicacao sincrona) |
| prometheus | app-1 | HTTP :3000/metrics | Scrape de metricas da aplicacao |
| prometheus | app-2 | HTTP :3000/metrics | Scrape de metricas da aplicacao |
| prometheus | pg-exporter-primary | HTTP :9187 | Scrape de metricas do PostgreSQL |
| prometheus | pg-exporter-replica | HTTP :9187 | Scrape de metricas do PostgreSQL |
| grafana | prometheus | HTTP :9090 | Consulta de metricas (PromQL) |

---

## Mapeamento para Cenarios de Disponibilidade (ATAM)

### Cenario 1: Falha de app-1

```
Cliente ──> lb-nginx ──X──> app-1 (DOWN)
                  │
                  └──────> app-2 ──> pg-primary  [servico mantido]
```

### Cenario 2: Falha da AZ-1

```
┌── AZ-1 (DOWN) ──┐
│ app-1    ██████  │
│ pg-primary ████  │     Cliente ──> lb-nginx ──> app-2 ──> pg-replica (promovido)
└──────────────────┘
```

### Cenario 3: Particao de Rede

```
AZ-1                         AZ-2
┌────────────┐    ████    ┌────────────┐
│ app-1      │    ████    │ app-2      │
│ pg-primary │──X─████──X─│ pg-replica │
└────────────┘    ████    └────────────┘

pg-primary BLOQUEIA escritas (sync commit sem confirmacao da replica)
Integridade dos dados PRESERVADA (trade-off: C sobre A)
```

