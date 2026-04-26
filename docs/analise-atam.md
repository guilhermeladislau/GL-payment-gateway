# Analise ATAM - Architecture Tradeoff Analysis Method

## 1 - Introducao

Este documento apresenta a avaliacao formal da arquitetura de alta disponibilidade do Gateway de Pagamentos utilizando o metodo ATAM (Architecture Tradeoff Analysis Method) O objetivo e identificar riscos arquiteturais, pontos de sensibilidade e trade-offs entre atributos de qualidade antes da implantacao em producao.

---

## 2 - Drivers de Negocio

| ID | Driver | Prioridade |
|----|--------|-----------|
| DN-1 | O sistema deve processar transacoes financeiras sem perda de dados | Critica |
| DN-2 | O sistema deve manter disponibilidade >= 99,9% (SLO) | Alta |
| DN-3 | A latencia de resposta deve ser inferior a 500ms (p95) | Alta |
| DN-4 | O custo operacional deve ser controlado (infraestrutura minima viavel) | Media |
| DN-5 | O sistema deve ser recuperavel em menos de 15 segundos (RTO) | Alta |

---

## 3 - Utility Tree (Arvore de Utilidade)

A Utility Tree organiza os atributos de qualidade em uma hierarquia priorizavel, classificando cada cenario por importancia de negocio (H=Alta, M=Media, L=Baixa) e dificuldade tecnica (H=Alta, M=Media, L=Baixa).

```
Utilidade do Sistema
|
|-- Disponibilidade
|   |-- [H,H] Falha de instancia de aplicacao nao causa indisponibilidade
|   |-- [H,H] Falha de zona de disponibilidade mantem servico operacional
|   |-- [H,M] Falha do banco primario permite promocao da replica
|   |-- [M,H] Particionamento de rede nao causa split-brain
|
|-- Desempenho
|   |-- [H,M] Latencia p95 < 500ms sob carga normal
|   |-- [M,H] Replicacao sincrona nao degrada latencia acima do aceitavel
|   |-- [M,M] Balanceamento round-robin distribui carga uniformemente
|
|-- Integridade de Dados
|   |-- [H,M] RPO = 0 (nenhuma transacao perdida)
|   |-- [H,H] Consistencia entre primario e replica apos falha
|   |-- [M,M] Validacao de dados via DTOs no ingresso
|
|-- Operabilidade
|   |-- [H,M] Infraestrutura reprodutivel via IaC (Terraform)
|   |-- [M,M] Observabilidade com metricas, dashboards e alertas
|   |-- [M,L] Health checks automaticos em todos os componentes
|
|-- Manutenibilidade
|   |-- [M,L] Codigo modular com separacao de responsabilidades (FastAPI)
|   |-- [L,L] Testes unitarios e E2E automatizados
```

---

## 4 - Abordagens Arquiteturais Identificadas

### AA-1: Active-Active Multi-Zona
- **Descricao**: Duas instancias identicas da aplicacao em zonas de disponibilidade separadas (AZ-1 e AZ-2), ambas recebendo trafego simultaneamente.
- **Atributo**: Disponibilidade
- **Justificativa**: Elimina ponto unico de falha na camada de aplicacao. Em caso de falha de uma instancia, o Nginx redireciona automaticamente para a instancia saudavel.

### AA-2: Replicacao Sincrona com WAL Streaming
- **Descricao**: PostgreSQL primario replica todas as escritas de forma sincrona para uma replica hot standby via WAL Streaming.
- **Atributo**: Integridade de Dados / Disponibilidade
- **Justificativa**: Garante RPO = 0 (nenhuma transacao confirmada e perdida). A replica esta pronta para promocao imediata.

### AA-3: Load Balancing com Health Checks Passivos
- **Descricao**: Nginx distribui trafego via round-robin com deteccao passiva de falhas (max_fails=3, fail_timeout=10s).
- **Atributo**: Disponibilidade / Desempenho
- **Justificativa**: Deteccao automatica de instancias indisponiveis sem overhead de health checks ativos.

### AA-4: Infraestrutura como Codigo (Terraform)
- **Descricao**: Toda infraestrutura provisionada via Terraform com Docker provider.
- **Atributo**: Operabilidade / Manutenibilidade
- **Justificativa**: Ambientes reprodutiveis, versionaveis e destrutiveis. Elimina configuracao manual.

### AA-5: Stack de Observabilidade (Prometheus + Grafana)
- **Descricao**: Coleta de metricas da aplicacao e banco de dados com dashboards para visualizacao de SLIs.
- **Atributo**: Operabilidade
- **Justificativa**: Permite monitoramento em tempo real de disponibilidade, latencia e integridade da replicacao, essencial para calculo do error budget.

---

## 5 - Analise de Cenarios

### Cenario 1: Falha de Componente Simples 

| Aspecto | Descricao |
|---------|-----------|
| **Estimulo** | Crash de uma instancia da aplicacao (app-1) |
| **Fonte** | Falha interna (OOM, bug, etc.) |
| **Artefato** | Container app-1 na AZ-1 |
| **Ambiente** | Operacao normal com carga distribuida |
| **Resposta** | Nginx detecta falha apos 3 tentativas, redireciona trafego para app-2. Container reinicia automaticamente (restart: unless-stopped). |
| **Medida** | RTO < 15s (validado via `validate-rto.sh`) |
| **Risco** | Durante os ~10s de fail_timeout, algumas requisicoes podem falhar (degradacao temporaria) |
| **Abordagem** | AA-1 (Active-Active) + AA-3 (Load Balancing) |

### Cenario 2: Falha de Zona de Disponibilidade 

| Aspecto | Descricao |
|---------|-----------|
| **Estimulo** | Perda completa da AZ-1 (rede e containers) |
| **Fonte** | Falha de infraestrutura (datacenter, energia) |
| **Artefato** | Rede az-1, app-1, servicos na zona |
| **Ambiente** | Operacao normal |
| **Resposta** | app-2 na AZ-2 continua servindo. Replica do banco na AZ-2 disponivel para promocao. |
| **Medida** | RTO < 15s para aplicacao; RTO banco depende de promocao (manual ou auto-failover) |
| **Risco** | Se o primario do banco esta na AZ-1, escritas ficam indisponiveis ate promocao da replica |
| **Abordagem** | AA-1 + AA-2 + Auto-failover script |

### Cenario 3: Particionamento de Rede / Split-Brain 

| Aspecto | Descricao |
|---------|-----------|
| **Estimulo** | Particao de rede isola replica do primario |
| **Fonte** | Falha de rede entre AZs |
| **Artefato** | Conexao de replicacao PostgreSQL |
| **Ambiente** | Operacao normal com replicacao sincrona ativa |
| **Resposta** | Replicacao sincrona BLOQUEIA escritas no primario quando replica nao confirma. Previne divergencia de dados. |
| **Medida** | RPO = 0 mantido; latencia de escrita aumenta (timeout); integridade preservada |
| **Risco** | Disponibilidade de escrita comprometida durante a particao (trade-off CAP: C sobre A) |
| **Abordagem** | AA-2 (Replicacao Sincrona) |

---

## 6 - Trade-offs Identificados

### T-1: Disponibilidade vs. Consistencia (Teorema CAP)

| Aspecto | Escolha A: Consistencia (Atual) | Escolha B: Disponibilidade |
|---------|-------------------------------|--------------------------|
| **Replicacao** | Sincrona | Assincrona |
| **RPO** | 0 (sem perda) | > 0 (possivel perda) |
| **Latencia de escrita** | Maior (espera confirmacao da replica) | Menor |
| **Comportamento em particao** | Bloqueia escritas | Aceita escritas (risco de divergencia) |
| **Decisao** | **Escolhida** - Dados financeiros exigem RPO = 0 | Rejeitada |
| **Justificativa** | "replicacao sincrona para dados de missao critica, visando RPO zero" |

### T-2: Simplicidade vs. Automacao de Failover

| Aspecto | Escolha A: Script simples (Atual) | Escolha B: Patroni + etcd |
|---------|--------------------------------|--------------------------|
| **Complexidade** | Baixa | Alta (3+ containers extras) |
| **Confiabilidade** | Adequada para PoC | Producao-ready |
| **RTO de BD** | ~10-15s | ~5-10s |
| **Split-brain protection** | Basica | Consenso distribuido (Raft via etcd) |
| **Decisao** | **Escolhida** - Adequada ao escopo da PoC | Recomendada para producao |
| **Justificativa** | Escopo da PoC foca em demonstrar conceitos, nao implementacao production-grade |

### T-3: Observabilidade vs. Custo de Infraestrutura

| Aspecto | Escolha A: Stack completa (Atual) | Escolha B: Apenas health checks |
|---------|----------------------------------|--------------------------------|
| **Componentes** | Prometheus + Grafana + Exporters | Endpoint /health |
| **Containers adicionais** | 4 | 0 |
| **Visibilidade** | Metricas, dashboards, SLIs | Apenas up/down |
| **Custo** | Maior consumo de recursos | Minimo |
| **Decisao** | **Escolhida** - SRE exige observabilidade | Insuficiente para metas SRE |
| **Justificativa** | "observabilidade SRE permite coleta de metricas, logs e rastros" |

---

## 7 - Riscos Arquiteturais

| ID | Risco | Severidade | Mitigacao |
|----|-------|-----------|-----------|
| R-1 | Replicacao sincrona pode degradar latencia sob alta carga | Alta | Monitorar p95 de latencia; considerar replicacao semi-sincrona se necessario |
| R-2 | Failover de BD requer intervencao (script ou manual) | Media | Script auto-failover implementado; Patroni recomendado para producao |
| R-3 | Nginx como ponto unico de falha na camada de entrada | Alta | Em producao, usar DNS failover ou par de Nginx com keepalived/VRRP |
| R-4 | Credenciais de banco hardcoded em variaveis de ambiente | Media | Em producao, usar secrets manager (Vault, AWS Secrets Manager) |
| R-5 | synchronize: true no TypeORM pode causar alteracoes indesejadas | Baixa | Aceitavel na PoC; em producao, usar migrations explicitas |

---

## 8 - Pontos de Sensibilidade

| ID | Ponto | Atributo Afetado | Descricao |
|----|-------|-----------------|-----------|
| S-1 | fail_timeout do Nginx (10s) | Disponibilidade | Valor muito alto aumenta RTO; muito baixo causa false positives |
| S-2 | synchronous_standby_names | Consistencia/Disponibilidade | Se a replica cair, TODAS as escritas bloqueiam ate ela voltar |
| S-3 | max_wal_senders (3) | Escalabilidade | Limita o numero de replicas possiveis |
| S-4 | Intervalo de scrape do Prometheus (5s) | Observabilidade | Valor muito alto perde eventos; muito baixo sobrecarrega |

---

## 9 - Conclusao

A analise ATAM revelou que a arquitetura proposta faz trade-offs conscientes e alinhados aos requisitos do dominio financeiro:

1. **Prioriza consistencia sobre disponibilidade** (CAP: CP) durante particoes de rede, protegendo a integridade das transacoes financeiras.
2. **Aceita latencia adicional** da replicacao sincrona como custo aceitavel para garantir RPO = 0.
3. **Investe em observabilidade** para reduzir MTTR e possibilitar o calculo do error budget.
4. **Reconhece limitacoes** do escopo da PoC (failover de BD semi-automatico, Nginx como SPOF) e documenta recomendacoes para producao.

Os riscos identificados (R-1 a R-5) sao gerenciaveis e as mitigacoes propostas sao praticaveis. A arquitetura atende ao SLO >= 99,9% nos cenarios modelados, desde que os pontos de sensibilidade sejam monitorados e ajustados conforme a carga real.


