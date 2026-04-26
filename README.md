# GL Payment Gateway

![Python](https://img.shields.io/badge/Python-3.12-blue?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

Gateway de pagamentos simulado com foco em **alta disponibilidade**.

A ideia é ter uma infraestrutura onde eu pudesse aplicar e testar conceitos como failover, replicação de dados e observabilidade com Prometheus + Grafana. Não é um sistema de pagamentos real.

## Arquitetura

```
Cliente (curl :8080)
        │
        ▼
 ┌──────────────┐
 │ Nginx (LB)   │  ← Round-robin + failover
 └──────┬───────┘
        │
   ┌────┴────┐
   ▼         ▼
┌──────┐  ┌──────┐
│App 1 │  │App 2 │  ← FastAPI (AZ-1 e AZ-2)
└──┬───┘  └──┬───┘
   │         │
   └────┬────┘
        ▼
 ┌──────────────┐     WAL Streaming      ┌──────────────┐
 │  PG Primary  │ ──────(Síncrono)─────▶ │  PG Replica   │
 └──────────────┘                        └──────────────┘

 Prometheus ─── scrape ──▶ Apps + PG Exporters
      │
      ▼
   Grafana (Dashboards)
```

- 2 instâncias da API rodando em Active-Active, simulando zonas de disponibilidade
- Nginx fazendo round-robin com failover automático
- PostgreSQL com replicação síncrona (WAL Streaming) — RPO zero
- Prometheus + Grafana pra monitorar tudo

## Tecnologias

| Stack | Uso |
|-------|-----|
| Python 3.12 + FastAPI | API |
| SQLAlchemy 2.0 | ORM |
| PostgreSQL 16 | Banco (primary + replica) |
| Nginx | Load balancer |
| Docker Compose | Orquestração |
| Prometheus + Grafana | Monitoramento |
| pytest | Testes |

## Como rodar

Precisa ter Docker Desktop instalado.

```bash
git clone <url-do-repositorio>
cd gateway-payment
docker compose up -d --build
```

Espera uns 30 segundos e acessa:

| Serviço | URL |
|---------|-----|
| API | http://localhost:8080 |
| Swagger | http://localhost:8080/docs |
| Grafana | http://localhost:3001 (admin/admin) |
| Prometheus | http://localhost:9090 |

### Testando a API

```bash
# health check
curl http://localhost:8080/health

# criar transação
curl -X POST http://localhost:8080/transactions \
  -H "Content-Type: application/json" \
  -d '{"amount": 150.75, "card_type": "credit", "card_number_hash": "a1b2c3d4e5f6", "status": "approved"}'

# listar
curl http://localhost:8080/transactions
```

Para derrubar:

```bash
docker compose down
```

## Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | /health | Status da instância |
| GET | /health/ready | Verifica conexão com o banco |
| POST | /transactions | Cria uma transação |
| GET | /transactions | Lista transações (paginado) |
| GET | /transactions/{id} | Busca por ID |
| GET | /metrics | Métricas Prometheus |

## Testes

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
pytest
```

## Estrutura

```
gateway-payment/
├── src/
│   ├── main.py          # app FastAPI
│   ├── database.py      # engine e session
│   ├── models.py        # model Transaction
│   └── routes.py        # endpoints e métricas
├── tests/
├── infra/               # nginx, postgres, prometheus, grafana
├── Dockerfile
├── docker-compose.yml
└── requirements.txt
```

## Variáveis de ambiente

| Variável | Default | |
|----------|---------|---|
| PORT | 3000 | Porta da API |
| DB_HOST | localhost | Host do PostgreSQL |
| DB_PORT | 5432 | Porta |
| DB_USER | postgres | Usuário |
| DB_PASS | postgres | Senha |
| DB_NAME | gateway | Database |
| INSTANCE_NAME | hostname | Identificador da instância |

## Licença

MIT
