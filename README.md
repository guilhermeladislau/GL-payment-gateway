<h1>HA Payment Gateway</h1>

<p>
  <img src="https://img.shields.io/badge/Python-3.12-blue?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white" alt="Terraform" />
</p>

<p>
  Um gateway de pagamentos simulado com foco em <strong>alta disponibilidade</strong>. O projeto implementa uma arquitetura Multi-AZ com replicação síncrona de banco de dados, balanceamento de carga e monitoramento, tudo rodando em containers Docker.
</p>

<blockquote>
  O objetivo não é ser um sistema de pagamentos real, mas sim montar uma infraestrutura onde eu pudesse aplicar e testar na prática conceitos como failover automático, replicação de dados com RPO zero e observabilidade com Prometheus/Grafana.
</blockquote>

<h2>Arquitetura</h2>

<pre>
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
</pre>

<p>Em resumo:</p>

<ul>
  <li><strong>2 instâncias da API</strong> (FastAPI) rodando em Active-Active, em redes Docker separadas que simulam zonas de disponibilidade</li>
  <li><strong>Nginx</strong> fazendo round-robin entre as instâncias, com failover automático se uma cair</li>
  <li><strong>PostgreSQL</strong> com replicação síncrona via WAL Streaming — a réplica recebe tudo em tempo real, garantindo zero perda de dados</li>
  <li><strong>Prometheus + Grafana</strong> monitorando tudo: taxa de requests, latência, erros, lag de replicação</li>
</ul>

<h2>Tecnologias</h2>

<table>
  <thead>
    <tr>
      <th>Tecnologia</th>
      <th>Propósito</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Python 3.12 + FastAPI</td><td>API assíncrona</td></tr>
    <tr><td>SQLAlchemy 2.0 + Alembic</td><td>ORM async + migrations</td></tr>
    <tr><td>PostgreSQL 16</td><td>Banco com replicação síncrona</td></tr>
    <tr><td>Nginx</td><td>Load balancer</td></tr>
    <tr><td>Docker Compose</td><td>Orquestração dos containers</td></tr>
    <tr><td>Terraform</td><td>Infraestrutura como Código</td></tr>
    <tr><td>Prometheus + Grafana</td><td>Monitoramento e dashboards</td></tr>
    <tr><td>pytest</td><td>Testes automatizados</td></tr>
  </tbody>
</table>

<h2>Como Rodar</h2>

<h3>Pré-requisitos</h3>

<ul>
  <li>Python 3.12+</li>
  <li>Docker Desktop</li>
</ul>

<h3>Subindo Tudo</h3>

<pre><code>git clone &lt;url-do-repositorio&gt;
cd ha-payment-gateway
docker compose up -d --build</code></pre>

<p>Aguarde uns 30 segundos e pronto. A API fica em <a href="http://localhost:8080">http://localhost:8080</a> e o Swagger em <a href="http://localhost:8080/docs">http://localhost:8080/docs</a>.</p>

<table>
  <thead>
    <tr>
      <th>Serviço</th>
      <th>URL</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>API</td><td><a href="http://localhost:8080">http://localhost:8080</a></td></tr>
    <tr><td>Swagger</td><td><a href="http://localhost:8080/docs">http://localhost:8080/docs</a></td></tr>
    <tr><td>Grafana</td><td><a href="http://localhost:3001">http://localhost:3001</a> (<code>admin</code> / <code>admin</code>)</td></tr>
    <tr><td>Prometheus</td><td><a href="http://localhost:9090">http://localhost:9090</a></td></tr>
  </tbody>
</table>

<h3>Testando</h3>

<pre><code># Health check (vai alternar entre app-1 e app-2)
curl http://localhost:8080/health

# Criar transação
curl -X POST http://localhost:8080/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 150.75,
    "card_type": "credit",
    "card_number_hash": "a1b2c3d4e5f6",
    "status": "approved"
  }'

# Listar transações
curl http://localhost:8080/transactions</code></pre>

<h3>Derrubando</h3>

<pre><code>docker compose down</code></pre>

<h2>Endpoints</h2>

<table>
  <thead>
    <tr>
      <th>Método</th>
      <th>Rota</th>
      <th>Descrição</th>
    </tr>
  </thead>
  <tbody>
    <tr><td><code>GET</code></td><td><code>/health</code></td><td>Status da instância</td></tr>
    <tr><td><code>GET</code></td><td><code>/health/ready</code></td><td>Verifica se o banco está acessível</td></tr>
    <tr><td><code>POST</code></td><td><code>/transactions</code></td><td>Cria uma transação</td></tr>
    <tr><td><code>GET</code></td><td><code>/transactions</code></td><td>Lista transações (com paginação)</td></tr>
    <tr><td><code>GET</code></td><td><code>/transactions/{id}</code></td><td>Busca transação por ID</td></tr>
    <tr><td><code>GET</code></td><td><code>/metrics</code></td><td>Métricas Prometheus</td></tr>
    <tr><td><code>GET</code></td><td><code>/docs</code></td><td>Swagger UI</td></tr>
  </tbody>
</table>

<h2>Scripts de Validação</h2>

<p>São scripts bash em <code>infra/scripts/</code> que testam a resiliência da infraestrutura:</p>

<pre><code># Simula crash de uma instância e mede o tempo de recuperação
bash infra/scripts/validate-rto.sh

# Verifica que dados são replicados e sobrevivem à falha do primário
bash infra/scripts/validate-rpo.sh

# Simula partição de rede entre primário e réplica
bash infra/scripts/validate-split-brain.sh

# Monitora o primário e promove a réplica automaticamente se ele cair
bash infra/scripts/auto-failover.sh</code></pre>

<h2>Rodando os Testes</h2>

<pre><code>python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -r requirements.txt

pytest                   # Roda tudo
pytest --cov=src         # Com cobertura
ruff check src/ tests/   # Lint</code></pre>

<h2>Estrutura</h2>

<pre>
ha-payment-gateway/
├── src/
│   ├── main.py              # Entrypoint FastAPI
│   ├── database.py          # SQLAlchemy async (engine, session)
│   ├── models.py            # Model Transaction
│   └── routes.py            # Todos os endpoints + schemas + métricas
├── migrations/              # Alembic
├── tests/                   # Testes automatizados
├── infra/                   # Nginx, PostgreSQL, Prometheus, Grafana, Terraform, Scripts
├── docs/                    # Documentação técnica
├── Dockerfile
├── docker-compose.yml
└── pyproject.toml
</pre>

<h2>Variáveis de Ambiente</h2>

<table>
  <thead>
    <tr>
      <th>Variável</th>
      <th>Padrão</th>
      <th>Descrição</th>
    </tr>
  </thead>
  <tbody>
    <tr><td><code>PORT</code></td><td><code>3000</code></td><td>Porta do FastAPI</td></tr>
    <tr><td><code>DB_HOST</code></td><td><code>localhost</code></td><td>Host do PostgreSQL</td></tr>
    <tr><td><code>DB_PORT</code></td><td><code>5432</code></td><td>Porta do PostgreSQL</td></tr>
    <tr><td><code>DB_USER</code></td><td><code>postgres</code></td><td>Usuário</td></tr>
    <tr><td><code>DB_PASS</code></td><td><code>postgres</code></td><td>Senha</td></tr>
    <tr><td><code>DB_NAME</code></td><td><code>gateway</code></td><td>Database</td></tr>
    <tr><td><code>INSTANCE_NAME</code></td><td>hostname</td><td>Nome da instância</td></tr>
  </tbody>
</table>

<h2>Licença</h2>

<p>MIT</p>
