# Tecnologias e Implementacao da Prova de Conceito

## Sumario

1. [Introducao](#1---introducao)
2. [Visao Geral da Arquitetura Implementada](#2---visao-geral-da-arquitetura-implementada)
3. [Linguagens de Programacao](#3---linguagens-de-programacao)
   - 3.1 [TypeScript](#31---typescript)
4. [Ambiente de Execucao](#4---ambiente-de-execucao)
   - 4.1 [Node.js](#41---nodejs)
5. [Framework de Aplicacao](#5---framework-de-aplicacao)
   - 5.1 [FastAPI](#51---FastAPI)
6. [Banco de Dados](#6---banco-de-dados)
   - 6.1 [PostgreSQL](#61---postgresql)
   - 6.2 [TypeORM](#62---typeorm)
7. [Infraestrutura e Contenerizacao](#7---infraestrutura-e-contenerizacao)
   - 7.1 [Docker](#71---docker)
   - 7.2 [Nginx](#72---nginx)
8. [Infraestrutura como Codigo](#8---infraestrutura-como-codigo)
   - 8.1 [Terraform](#81---terraform)
9. [Bibliotecas e Ferramentas Auxiliares](#9---bibliotecas-e-ferramentas-auxiliares)
   - 9.1 [Validacao de Dados](#91---validacao-de-dados)
   - 9.2 [Testes Automatizados](#92---testes-automatizados)
   - 9.3 [Qualidade de Codigo](#93---qualidade-de-codigo)
10. [Estrutura do Projeto](#10---estrutura-do-projeto)
11. [Detalhamento da Implementacao](#11---detalhamento-da-implementacao)
    - 11.1 [Modulo de Transacoes](#111---modulo-de-transacoes)
    - 11.2 [Endpoint de Health Check](#112---endpoint-de-health-check)
    - 11.3 [Configuracao do Balanceador de Carga](#113---configuracao-do-balanceador-de-carga)
    - 11.4 [Replicacao de Banco de Dados](#114---replicacao-de-banco-de-dados)
    - 11.5 [Provisionamento da Infraestrutura via Terraform](#115---provisionamento-da-infraestrutura-via-terraform)
12. [Scripts de Validacao](#12---scripts-de-validacao)
    - 12.1 [Smoke Test](#121---smoke-test)
    - 12.2 [Validacao de RPO](#122---validacao-de-rpo)
    - 12.3 [Validacao de RTO](#123---validacao-de-rto)
13. [Quadro Resumo das Tecnologias](#13---quadro-resumo-das-tecnologias)
14. [Consideracoes sobre as Escolhas Tecnologicas](#14---consideracoes-sobre-as-escolhas-tecnologicas)

---

## 1 - Introducao

Este capitulo apresenta a documentacao tecnica da prova de conceito (PoC) desenvolvida como parte pratica do trabalho de conclusao de curso intitulado "Modelagem Arquitetural de Alta Disponibilidade para Sistemas Criticos". A implementacao consiste em um gateway de pagamentos simulado (mock) que materializa os conceitos teoricos de alta disponibilidade discutidos nos capitulos anteriores, demonstrando na pratica a aplicacao de padroes como Active-Active Multi-Zona, replicacao de banco de dados via WAL Streaming e balanceamento de carga com failover automatico.

O objetivo da prova de conceito nao e construir um sistema de pagamentos funcional em producao, mas sim fornecer um ambiente controlado e reprodutivel onde as taticas de alta disponibilidade possam ser provisionadas, observadas e validadas por meio de metricas como RTO (Recovery Time Objective) e RPO (Recovery Point Objective). Todas as tecnologias foram selecionadas com base em criterios de maturidade, adequacao ao dominio de sistemas criticos e alinhamento com as praticas de Engenharia de Confiabilidade de Site (SRE) apresentadas no referencial teorico.

As secoes a seguir descrevem cada tecnologia utilizada, sua justificativa de adocao, o papel que desempenha na arquitetura e como se relaciona com os objetivos de alta disponibilidade do projeto.

---

## 2 - Visao Geral da Arquitetura Implementada

A arquitetura da prova de conceito implementa o padrao Active-Active Multi-Zona A topologia e composta por cinco servicos containerizados, organizados em duas redes Docker que simulam Zonas de Disponibilidade (AZ) distintas:

```
              Cliente (porta 8080)
                      |
               [Nginx - LB]              Balanceador de Carga
               /            \
         [app-1]          [app-2]         Instancias FastAPI (Active-Active)
          AZ-1              AZ-2
              \            /
           [pg-primary]                   PostgreSQL Primario
                  |
              WAL Streaming
                  |
           [pg-replica]                   PostgreSQL Replica (Hot Standby)
```

Os componentes da arquitetura sao:

- Balanceador de carga (Nginx): recebe todas as requisicoes externas na porta 8080 e distribui o trafego entre as duas instancias da aplicacao utilizando o algoritmo round-robin, com health checks passivos para deteccao de falhas.

- Duas instancias da aplicacao (FastAPI): executam simultaneamente em zonas de disponibilidade separadas (AZ-1 e AZ-2), ambas recebendo trafego ativo. Cada instancia se conecta ao banco de dados primario para operacoes de leitura e escrita.

- Banco de dados primario (PostgreSQL): responsavel por todas as operacoes de escrita. Configurado com WAL (Write-Ahead Log) Streaming para replicacao dos dados para a replica.

- Banco de dados replica (PostgreSQL): opera em modo Hot Standby, recebendo continuamente os registros WAL do banco primario. Aceita conexoes de leitura e garante que os dados estejam disponiveis mesmo em caso de falha do primario, visando RPO proximo de zero.

Esta topologia permite validar os cenarios de disponibilidade criticos descritos na : falha de componente simples (queda de uma instancia da aplicacao), falha de zona de disponibilidade (perda de uma AZ inteira) e verificacao da integridade dos dados replicados.

---

## 3 - Linguagens de Programacao

### 3.1 - TypeScript

O TypeScript e uma linguagem de programacao de codigo aberto desenvolvida pela Microsoft que estende o JavaScript adicionando tipagem estatica opcional e recursos avancados de orientacao a objetos, como interfaces, generics e decorators. O codigo TypeScript e transpilado para JavaScript puro antes da execucao, o que garante compatibilidade total com o ecossistema Node.js.

A adocao do TypeScript neste projeto se justifica por tres razoes principais. Primeiro, a tipagem estatica permite detectar erros em tempo de compilacao, reduzindo a probabilidade de falhas em tempo de execucao -- um aspecto relevante para sistemas que buscam alta disponibilidade, onde bugs nao detectados podem comprometer o MTBF (Mean Time Between Failures). Segundo, o suporte nativo a decorators e essencial para o funcionamento do framework FastAPI, que utiliza extensivamente este recurso para definicao de modulos, controladores, servicos e validacao de dados. Terceiro, a tipagem explicita melhora a legibilidade e a manutenibilidade do codigo, facilitando o trabalho colaborativo e a revisao de codigo.

A versao utilizada no projeto e o TypeScript 5.1.3, configurado com target ES2021 e sistema de modulos CommonJS. A configuracao inclui suporte a decorators experimentais (experimentalDecorators) e emissao de metadados de decorators (emitDecoratorMetadata), ambos requisitos do FastAPI e do TypeORM.

---

## 4 - Ambiente de Execucao

### 4.1 - Node.js

O Node.js e um ambiente de execucao JavaScript construido sobre o motor V8 do Google Chrome, projetado para construir aplicacoes de rede escalaveis com um modelo de entrada e saida nao bloqueante orientado a eventos (event-driven, non-blocking I/O). Este modelo o torna particularmente eficiente para aplicacoes que lidam com muitas conexoes simultaneas, como APIs REST e servicos de microsservicos.

No contexto deste projeto, o Node.js 22 (variante Alpine) foi selecionado como ambiente de execucao. A escolha da variante Alpine se deve ao tamanho reduzido da imagem Docker (aproximadamente 50 MB contra 350 MB da imagem padrao), o que contribui para tempos de build e deploy mais rapidos -- fator relevante para a reducao do MTTR, pois instancias que precisam ser recriadas apos uma falha se tornam operacionais mais rapidamente.

O modelo single-threaded com event loop do Node.js e adequado para a prova de conceito, uma vez que o gateway de pagamentos realiza predominantemente operacoes de I/O (comunicacao com banco de dados e recebimento de requisicoes HTTP), cenario onde o Node.js apresenta desempenho otimizado.

---

## 5 - Framework de Aplicacao

### 5.1 - FastAPI

O FastAPI e um framework progressivo para construcao de aplicacoes server-side eficientes e escalaveis com Node.js. Inspirado em padroes arquiteturais consolidados de frameworks como Angular e Spring Boot, o FastAPI adota uma arquitetura modular baseada em decorators, injecao de dependencias e separacao de responsabilidades (controllers, services, modules).

A versao 10.x do FastAPI foi utilizada neste projeto, operando sobre a plataforma Express (via @FastAPI/platform-express). A escolha do FastAPI se justifica pelos seguintes aspectos:

- Arquitetura modular: a organizacao em modulos (AppModule, TransactionModule) facilita a separacao de responsabilidades e permite que cada modulo encapsule sua logica de negocio, controladores e dependencias. Esta modularidade e fundamental para a manutenibilidade de sistemas criticos, onde alteracoes em um componente nao devem propagar efeitos colaterais para outros.

- Injecao de dependencias: o sistema nativo de injecao de dependencias do FastAPI permite desacoplar componentes, facilitando a substituicao de implementacoes e a criacao de mocks para testes unitarios. No contexto do projeto, o TransactionService recebe o repositorio do TypeORM via injecao, tornando-o testavel de forma isolada.

- ValidationPipe global: o FastAPI oferece um pipeline de validacao integrado que, quando habilitado globalmente (como feito no bootstrap da aplicacao via app.useGlobalPipes), valida automaticamente os dados de entrada de todas as requisicoes contra os DTOs (Data Transfer Objects) definidos com decorators do class-validator. A opcao whitelist ativa garante que propriedades nao declaradas no DTO sejam removidas automaticamente, prevenindo injecao de dados nao esperados.

- Health checks: a implementacao de um endpoint de health check (GET /health) e facilitada pela estrutura do FastAPI e e utilizada pelo Nginx para verificacao da saude das instancias, permitindo o failover automatico descrito na .

A inicializacao da aplicacao e realizada no arquivo main.ts, onde o NestFactory cria a instancia da aplicacao, configura o ValidationPipe global e inicia o servidor na porta definida pela variavel de ambiente PORT (padrao: 3000).

---

## 6 - Banco de Dados

### 6.1 - PostgreSQL

O PostgreSQL e um sistema de gerenciamento de banco de dados objeto-relacional de codigo aberto, reconhecido por sua robustez, conformidade com o padrao SQL e extenso conjunto de funcionalidades para integridade transacional (suporte completo a propriedades ACID). E amplamente utilizado em sistemas criticos de producao, incluindo sistemas financeiros e de pagamentos.

A versao 16 do PostgreSQL (variante Alpine) foi adotada neste projeto. A escolha se fundamenta em tres aspectos diretamente relacionados aos objetivos de alta disponibilidade:

- Replicacao nativa via WAL Streaming: o PostgreSQL possui suporte nativo a replicacao por streaming de Write-Ahead Log (WAL), sem necessidade de ferramentas externas. O WAL e o mecanismo pelo qual o PostgreSQL registra todas as alteracoes nos dados antes de aplica-las. Na configuracao deste projeto, o banco primario transmite continuamente os registros WAL para a replica, que os aplica em tempo real. Esta configuracao visa atingir RPO proximo de zero.

- Hot Standby: a replica e configurada em modo Hot Standby, o que significa que aceita conexoes de leitura enquanto replica os dados do primario. Este modo permite validar que os dados inseridos via API estao efetivamente sendo replicados.

- Health checks nativos: o utilitario pg_isready, incluido na distribuicao do PostgreSQL, permite verificar se o banco esta aceitando conexoes, sendo utilizado como health check nos containers Docker e nas definicoes do Terraform.

A configuracao do banco primario e realizada via script de inicializacao (init-primary.sh), que executa as seguintes operacoes: criacao do role de replicacao (replicator), configuracao do pg_hba.conf para permitir conexoes de replicacao, e ajuste dos parametros do postgresql.conf (wal_level=replica, max_wal_senders=3, wal_keep_size=64, hot_standby=on).

A replica e inicializada via script (init-replica.sh) que aguarda a disponibilidade do primario, executa o pg_basebackup para sincronizacao inicial e inicia o PostgreSQL em modo standby.

### 6.2 - TypeORM

O TypeORM e um ORM (Object-Relational Mapping) para TypeScript e JavaScript que suporta os padroes Active Record e Data Mapper. Permite definir entidades como classes TypeScript com decorators, mapeando-as automaticamente para tabelas no banco de dados.

A versao 0.3.28 do TypeORM foi utilizada, integrada ao FastAPI via o modulo @FastAPI/typeorm (versao 11.0.0). A configuracao e realizada no AppModule, onde o TypeOrmModule.forRoot() recebe os parametros de conexao com o PostgreSQL:

- host: definido pela variavel de ambiente DB_HOST (padrao: localhost)
- port: definido pela variavel de ambiente DB_PORT (padrao: 5432)
- username: definido pela variavel de ambiente DB_USER (padrao: postgres)
- password: definido pela variavel de ambiente DB_PASS (padrao: postgres)
- database: definido pela variavel de ambiente DB_NAME (padrao: gateway)
- synchronize: habilitado (true), permitindo que o TypeORM crie e atualize automaticamente o esquema do banco de dados com base nas entidades definidas

A entidade Transaction e definida com os seguintes campos: id (UUID, chave primaria gerada automaticamente), amount (decimal com precisao de 10 digitos e 2 casas decimais), card_type (varchar de 20 caracteres), card_number_hash (varchar de 64 caracteres), status (varchar de 20 caracteres, padrao: "approved") e created_at (timestamp gerado automaticamente na insercao).

A opcao synchronize: true foi adotada por se tratar de uma prova de conceito em ambiente de desenvolvimento. Em um ambiente de producao, esta opcao deveria ser substituida por um sistema formal de migracoes para garantir controle de versao do esquema do banco de dados.

---

## 7 - Infraestrutura e Contenerizacao

### 7.1 - Docker

O Docker e uma plataforma de contenerizacao que permite empacotar aplicacoes e suas dependencias em unidades padronizadas chamadas containers. Cada container executa de forma isolada, compartilhando o kernel do sistema operacional hospedeiro, o que resulta em menor overhead comparado a maquinas virtuais tradicionais.

No contexto deste projeto, o Docker desempenha um papel central ao simular uma arquitetura multi-zona de disponibilidade em um ambiente local. Cada componente da arquitetura (aplicacao, banco de dados, balanceador de carga) executa em seu proprio container, e as Zonas de Disponibilidade sao simuladas por meio de redes Docker isoladas (az-1 e az-2).

O Dockerfile do projeto utiliza o padrao multi-stage build, organizado em duas etapas:

- Estagio de build: utiliza a imagem node:22-alpine como base, instala as dependencias do projeto (npm ci) e compila o codigo TypeScript para JavaScript (npm run build). O comando npm ci (clean install) garante instalacoes reprodutiveis ao utilizar exatamente as versoes especificadas no package-lock.json.

- Estagio de producao: utiliza uma nova imagem node:22-alpine limpa, copia apenas as dependencias de producao e o codigo compilado do estagio anterior. A imagem final nao contem dependencias de desenvolvimento, ferramentas de build ou codigo-fonte TypeScript, resultando em uma imagem significativamente menor.

Esta abordagem de multi-stage build reduz o tamanho da imagem final e a superficie de ataque, alem de contribuir para tempos de deploy mais rapidos, fator que impacta diretamente o MTTR em cenarios de recuperacao.

### 7.2 - Nginx

O Nginx e um servidor web e proxy reverso de alto desempenho, amplamente utilizado como balanceador de carga em arquiteturas de microsservicos. Sua arquitetura orientada a eventos e capacidade de lidar com milhares de conexoes simultaneas com baixo consumo de memoria o tornam adequado para cenarios de alta disponibilidade.

A versao 1.25 (variante Alpine) do Nginx e utilizada neste projeto como balanceador de carga na camada de entrada, distribuindo o trafego entre as duas instancias da aplicacao FastAPI. A configuracao (nginx.conf) define os seguintes comportamentos:

- Upstream pool: o bloco upstream gateway_backend define as duas instancias da aplicacao (app-1:3000 e app-2:3000) como destinos para o trafego.

- Algoritmo de balanceamento: o round-robin (padrao do Nginx) distribui as requisicoes de forma alternada entre as instancias, garantindo utilizacao equilibrada dos recursos.

- Health checks passivos: os parametros max_fails=3 e fail_timeout=10s configuram a deteccao passiva de falhas. Se uma instancia falhar em responder a 3 requisicoes consecutivas, o Nginx a marca como indisponivel por 10 segundos, redirecionando todo o trafego para a instancia saudavel. Este mecanismo implementa o failover automatico descrito na .

- Proxy com failover: a diretiva proxy_next_upstream error timeout http_502 http_503 http_504 configura o Nginx para redirecionar automaticamente a requisicao para a proxima instancia em caso de erros de conexao ou respostas de erro do servidor, com no maximo 2 tentativas (proxy_next_upstream_tries 2).

- Timeouts: o proxy_connect_timeout e definido em 5 segundos e o proxy_read_timeout em 30 segundos, valores adequados para um gateway de pagamentos onde a latencia de conexao deve ser baixa, mas o processamento da transacao pode requerer mais tempo.

- Headers de forwarding: os headers X-Real-IP e X-Forwarded-For sao repassados para as instancias da aplicacao, permitindo rastreabilidade da origem das requisicoes.

- Endpoint de saude do Nginx: o endpoint /nginx-health retorna um status 200 com a mensagem "ok", utilizado para verificacao da saude do proprio balanceador de carga.

---

## 8 - Infraestrutura como Codigo

### 8.1 - Terraform

O Terraform e uma ferramenta de Infraestrutura como Codigo (IaC) desenvolvida pela HashiCorp que permite definir, provisionar e gerenciar infraestrutura por meio de arquivos de configuracao declarativos. O Terraform utiliza o conceito de providers para interagir com diferentes plataformas de infraestrutura (AWS, Azure, GCP, Docker, entre outros), e mantem um arquivo de estado (state) que rastreia os recursos provisionados.

A versao 3.x do provider Docker (kreuzwerker/docker) foi utilizada neste projeto. A escolha do Terraform com o provider Docker, em vez de provedores de nuvem publica, foi uma decisao deliberada para demonstrar que os principios de Infraestrutura como Codigo sao agnositcos de plataforma. Os mesmos conceitos de provisionamento declarativo, gerenciamento de estado e reprodutibilidade aplicam-se tanto a um ambiente Docker local quanto a uma infraestrutura em nuvem.

A infraestrutura e definida em tres arquivos:

- main.tf: contem a definicao de todos os recursos, incluindo duas redes Docker (az-1 e az-2), imagens Docker para a aplicacao, Nginx, PostgreSQL, Prometheus, Grafana e PostgreSQL Exporters, e nove containers (pg-primary, pg-replica, app-1, app-2, nginx, prometheus, grafana, pg-exporter-primary, pg-exporter-replica). Cada container e configurado com suas respectivas redes, variaveis de ambiente, volumes, portas expostas e health checks.

- variables.tf: define as variaveis configuraveis da infraestrutura, como docker_host (padrao: unix:///var/run/docker.sock), lb_port (porta do balanceador, padrao: 8080), pg_primary_port (porta do banco primario, padrao: 5432), pg_replica_port (porta da replica, padrao: 5433), prometheus_port (porta do Prometheus, padrao: 9090) e grafana_port (porta do Grafana, padrao: 3001).

- outputs.tf: define as saidas apos o provisionamento, incluindo URLs de acesso (balanceador, health check, endpoint de transacoes, Prometheus, Grafana) e DSNs (Data Source Names) de conexao com os bancos de dados.

O fluxo de provisionamento segue o padrao Terraform: terraform init para inicializacao do provider, terraform plan para visualizacao das alteracoes planejadas e terraform apply para execucao do provisionamento. Este fluxo garante previsibilidade e auditabilidade na criacao da infraestrutura, alinhando-se com as praticas de SRE de automacao e reproducibilidade.

Os health checks definidos no Terraform garantem que o orquestrador monitore a saude de cada componente:

- Containers da aplicacao: verificados via curl no endpoint /health a cada 10 segundos
- Containers do PostgreSQL: verificados via pg_isready a cada 10 segundos
- Container do Nginx: verificado via curl no endpoint /nginx-health a cada 10 segundos

A dependencia entre os containers e declarada explicitamente: a replica depende do primario, as instancias da aplicacao dependem do banco primario, e o Nginx depende de ambas as instancias da aplicacao. Esta cadeia de dependencias garante a ordem correta de inicializacao.

---

## 9 - Bibliotecas e Ferramentas Auxiliares

### 9.1 - Validacao de Dados

A validacao dos dados de entrada e realizada por duas bibliotecas complementares:

- class-validator (versao 0.14.3): fornece decorators para validacao declarativa de propriedades de classes TypeScript. No DTO (Data Transfer Object) CreateTransactionDto, os seguintes decorators sao utilizados: @IsNumber() e @Min(0.01) para validar que o valor da transacao e um numero positivo; @IsString() e @IsIn(['credit', 'debit']) para restringir o tipo de cartao; @IsNotEmpty() para garantir que o hash do numero do cartao nao esteja vazio; e @IsIn(['approved', 'declined', 'pending']) para restringir os status validos.

- class-transformer (versao 0.5.1): responsavel pela transformacao de objetos JSON recebidos nas requisicoes em instancias das classes DTO, permitindo que os decorators do class-validator sejam avaliados corretamente.

A validacao rigorosa dos dados de entrada e uma pratica de seguranca e confiabilidade, pois impede que dados malformados alcancem a camada de negocio ou o banco de dados, reduzindo o risco de erros que poderiam impactar a disponibilidade do sistema.

### 9.2 - Testes Automatizados

O framework de testes utilizado e o Jest (versao 29.5.0), integrado ao TypeScript via ts-jest (versao 29.1.0). Dois niveis de teste sao implementados:

- Testes unitarios: localizados junto aos arquivos de codigo-fonte (*.spec.ts), utilizam o sistema de mocking do Jest para isolar dependencias. O teste do TransactionController, por exemplo, utiliza um repositorio mockado para validar que o servico de transacoes cria registros corretamente sem depender de um banco de dados real.

- Testes de ponta a ponta (E2E): localizados no diretorio test/, utilizam a biblioteca Supertest (versao 7.0.0) para realizar requisicoes HTTP reais contra a aplicacao FastAPI instanciada em memoria. Estes testes validam o comportamento integrado de todos os componentes da aplicacao.

### 9.3 - Qualidade de Codigo

A qualidade do codigo e mantida por duas ferramentas:

- ESLint (versao 8.42.0): linter estatico configurado com o parser @typescript-eslint/parser e o plugin @typescript-eslint/eslint-plugin, que aplica regras especificas para TypeScript. A configuracao estende as regras recomendadas do TypeScript-ESLint e integra-se com o Prettier para evitar conflitos entre regras de formatacao e regras de estilo.

- Prettier (versao 3.0.0): formatador de codigo configurado com aspas simples (singleQuote: true) e virgula trailing (trailingComma: "all"), garantindo formatacao consistente em todo o projeto.

---

## 10 - Estrutura do Projeto

A organizacao do codigo-fonte segue a estrutura modular recomendada pelo FastAPI, complementada por diretorios dedicados a infraestrutura e testes:

```
ha-payment-gateway/
|-- src/                                    Codigo-fonte da aplicacao
|   |-- main.ts                            Ponto de entrada (bootstrap)
|   |-- app.module.ts                      Modulo raiz com configuracao do TypeORM
|   |-- app.controller.ts                  Controlador do health check
|   |-- app.service.ts                     Servico do health check
|   |-- app.controller.spec.ts             Testes unitarios do controlador
|   |-- metrics.controller.ts              Endpoint /metrics (Prometheus)
|   |-- metrics.middleware.ts              Middleware de instrumentacao HTTP
|   |-- transaction/                       Modulo de transacoes
|       |-- transaction.module.ts          Definicao do modulo
|       |-- transaction.controller.ts      Controlador REST (POST /transaction)
|       |-- transaction.service.ts         Logica de negocio
|       |-- transaction.entity.ts          Entidade TypeORM (mapeamento da tabela)
|       |-- create-transaction.dto.ts      DTO com validacao de entrada
|       |-- transaction.controller.spec.ts Testes unitarios
|-- test/                                   Testes de ponta a ponta
|   |-- app.e2e-spec.ts                    Testes E2E com Supertest
|   |-- jest-e2e.json                      Configuracao do Jest para E2E
|-- infra/                                  Infraestrutura
|   |-- nginx/
|   |   |-- nginx.conf                     Configuracao do balanceador de carga
|   |-- postgres/
|   |   |-- primary/
|   |   |   |-- init-primary.sh            Inicializacao do banco primario (sync)
|   |   |-- replica/
|   |       |-- init-replica.sh            Inicializacao da replica
|   |-- prometheus/
|   |   |-- prometheus.yml                 Configuracao de scrape do Prometheus
|   |-- grafana/
|   |   |-- provisioning/                  Configuracao automatica do Grafana
|   |   |-- dashboards/                    Dashboards pre-configurados (HA, SLIs)
|   |-- terraform/
|   |   |-- main.tf                        Definicao dos recursos de infraestrutura
|   |   |-- variables.tf                   Variaveis configuraveis
|   |   |-- outputs.tf                     Saidas do provisionamento
|   |-- scripts/
|       |-- smoke-test.sh                  Testes funcionais basicos
|       |-- validate-rpo.sh               Validacao do RPO (perda de dados)
|       |-- validate-rto.sh               Validacao do RTO (tempo de recuperacao)
|       |-- validate-split-brain.sh       Validacao de particao de rede (split-brain)
|       |-- auto-failover.sh              Failover automatico do banco de dados
|-- docs/                                   Documentacao
|   |-- atam-analysis.md                   Analise ATAM com trade-offs e riscos
|   |-- slo-sli-error-budget.md           Definicao de SLIs, SLOs e Error Budget
|   |-- c4-diagrams.md                    Diagramas C4 (Contexto e Conteineres)
|-- Dockerfile                              Build multi-stage da aplicacao
|-- package.json                            Dependencias e scripts do projeto
|-- tsconfig.json                           Configuracao do TypeScript
|-- .env.example                            Template de variaveis de ambiente
```

---

## 11 - Detalhamento da Implementacao

### 11.1 - Modulo de Transacoes

O modulo de transacoes (TransactionModule) e o componente central da prova de conceito, responsavel por simular o processamento de pagamentos. Sua implementacao segue o padrao Model-View-Controller (MVC) adaptado pelo FastAPI:

O controlador (TransactionController) expoe o endpoint POST /transaction, que recebe um corpo JSON validado pelo CreateTransactionDto. Ao receber uma requisicao valida, o controlador delega a criacao da transacao ao servico (TransactionService), que utiliza o repositorio do TypeORM para persistir o registro no banco de dados PostgreSQL. O registro retornado inclui o UUID gerado automaticamente e o timestamp de criacao.

O DTO CreateTransactionDto define o contrato da API com as seguintes propriedades e validacoes:

- amount: numero decimal com valor minimo de 0.01
- card_type: string restrita aos valores "credit" ou "debit"
- card_number_hash: string nao vazia representando o hash do numero do cartao
- status: string restrita aos valores "approved", "declined" ou "pending"

### 11.2 - Endpoint de Health Check

O endpoint GET /health, implementado no AppController, retorna um objeto JSON contendo o status do servico ("ok") e o identificador da instancia (hostname do container). Este endpoint e fundamental para a arquitetura de alta disponibilidade por dois motivos:

Primeiro, o Nginx utiliza este endpoint para determinar a saude das instancias da aplicacao. Se uma instancia nao responder ao health check, o Nginx redireciona o trafego para a instancia saudavel, implementando o failover automatico.

Segundo, o retorno do hostname permite verificar a distribuicao de carga: ao enviar multiplas requisicoes ao balanceador, a alternancia dos hostnames confirma que o algoritmo round-robin esta funcionando corretamente.

### 11.3 - Configuracao do Balanceador de Carga

A configuracao do Nginx (nginx.conf) implementa o padrao de balanceamento descrito na . O bloco upstream define o pool de servidores backend com as duas instancias da aplicacao. O bloco server configura o proxy reverso na porta 80, encaminhando todas as requisicoes para o upstream com suporte a failover automatico.

O parametro proxy_next_upstream garante que, em caso de erro de conexao (error), timeout ou resposta de erro do servidor (502, 503, 504), a requisicao seja automaticamente encaminhada para a proxima instancia disponivel. Este comportamento e essencial para manter a disponibilidade do servico durante a falha de uma das instancias.

### 11.4 - Replicacao de Banco de Dados

A replicacao do PostgreSQL e configurada por meio de dois scripts de inicializacao que implementam a replicacao por WAL Streaming descrita na :

O script init-primary.sh configura o banco primario para atuar como fonte de replicacao: cria o role replicator com permissao de login e replicacao, configura o pg_hba.conf para aceitar conexoes de replicacao de qualquer origem (necessario em ambiente Docker onde os IPs sao dinamicos), e define os parametros de replicacao no postgresql.conf (wal_level=replica para habilitar a geracao de WAL compativel com replicacao, max_wal_senders=3 para permitir ate tres conexoes de replicacao simultaneas, wal_keep_size=64 para reter segmentos WAL suficientes para sincronizacao, synchronous_commit=on para garantir que escritas so sejam confirmadas apos a replica receber os dados, e synchronous_standby_names='pg-replica' para identificar a replica sincrona). A replicacao sincrona garante RPO = 0 .

O script init-replica.sh configura o banco secundario como replica: aguarda que o banco primario esteja disponivel (loop com pg_isready), executa o pg_basebackup para copiar a base completa do primario, e inicia o PostgreSQL em modo standby. O parametro -Xs no pg_basebackup habilita a replicacao por streaming durante o backup, garantindo que a replica esteja o mais atualizada possivel ao iniciar.

### 11.5 - Provisionamento da Infraestrutura via Terraform

O arquivo main.tf define a infraestrutura completa da prova de conceito de forma declarativa. Os recursos sao provisionados na seguinte ordem, determinada pelas dependencias explicitas:

1. Redes Docker (az-1, az-2): criam o isolamento de rede que simula as Zonas de Disponibilidade.

2. Imagens Docker: fazem o build da imagem da aplicacao e o pull das imagens do Nginx e PostgreSQL.

3. Container pg-primary: banco de dados primario, conectado a ambas as redes (az-1 e az-2) para ser acessivel por ambas as instancias da aplicacao.

4. Container pg-replica: replica do banco, conectada a rede az-2, com dependencia explicita do pg-primary.

5. Containers app-1 e app-2: instancias da aplicacao, cada uma conectada a sua respectiva zona de disponibilidade, com dependencia do pg-primary.

6. Container nginx: balanceador de carga, conectado a ambas as redes para alcancar ambas as instancias, com dependencia de app-1 e app-2.

7. Containers pg-exporter-primary e pg-exporter-replica: exportadores de metricas do PostgreSQL para o Prometheus, conectados as suas respectivas zonas de disponibilidade.

8. Container prometheus: servidor de coleta de metricas, conectado a ambas as redes para acessar todos os exportadores e instancias da aplicacao.

9. Container grafana: plataforma de visualizacao de dashboards, conectada a ambas as redes, com datasource Prometheus pre-configurado e dashboard de HA provisionado automaticamente.

### 11.6 - Instrumentacao e Observabilidade

A observabilidade do sistema e implementada atraves de tres componentes integrados, :

O endpoint GET /metrics, implementado no MetricsController, expoe metricas no formato Prometheus. O middleware MetricsMiddleware intercepta todas as requisicoes HTTP e registra automaticamente: o contador gateway_http_requests_total (com labels de metodo, rota e codigo de status), o histograma gateway_http_request_duration_seconds (com buckets para calculo de percentis) e o contador gateway_transactions_total (com labels de tipo de cartao e status). As metricas de processo do Node.js (memoria, CPU, event loop) sao coletadas automaticamente via collectDefaultMetrics.

O Prometheus coleta metricas de quatro fontes a cada 5 segundos: as duas instancias da aplicacao (via /metrics) e os dois exportadores PostgreSQL (via pg-exporter). As metricas do PostgreSQL incluem estatisticas de replicacao, conexoes ativas, tamanho do banco e lag de replicacao.

O Grafana e provisionado automaticamente com um dashboard pre-configurado (gateway-ha-dashboard) que inclui paineis para: taxa de requisicoes por instancia, latencia p95, taxa de erros 5xx, transacoes por tipo, lag de replicacao PostgreSQL, conexoes ativas, gauge de disponibilidade SLI e gauge de error budget restante. Os dois ultimos paineis materializam as metricas de SLO definidas na documentacao de SLIs/SLOs.

### 11.7 - Auto-Failover do Banco de Dados

O script auto-failover.sh implementa monitoramento continuo do banco primario com promocao automatica da replica. O script executa health checks via pg_isready a cada 3 segundos e, apos 3 falhas consecutivas, promove a replica utilizando pg_ctl promote. O tempo total de deteccao e de aproximadamente 9 segundos (3 checks x 3s), com a promocao adicionando 1-5 segundos, resultando em um RTO total do banco de dados de 10-15 segundos.

Em producao, esta funcionalidade seria implementada por ferramentas como Patroni com etcd, que oferecem consenso distribuido (Raft) para evitar split-brain durante o failover. A implementacao via script e adequada para demonstrar o conceito na PoC.

### 11.8 - Validacao de Particao de Rede (Split-Brain)

O script validate-split-brain.sh implementa o cenario 3 descrito na . O script simula uma particao de rede entre primario e replica desconectando a replica das redes Docker. Com a replicacao sincrona configurada (synchronous_commit=on), o esperado e que as escritas no primario bloqueiem durante a particao, pois o primario aguarda confirmacao da replica que nao pode ser alcancada. Este comportamento demonstra a escolha arquitetural de Consistencia sobre Disponibilidade (C > A no teorema CAP), garantindo que nenhum dado seja persistido sem confirmacao da replica (RPO = 0 mantido mesmo durante particoes).

---

## 12 - Scripts de Validacao

Os scripts de validacao, localizados no diretorio infra/scripts/, permitem verificar empiricamente os atributos de alta disponibilidade da arquitetura. Estes scripts operacionalizam os cenarios de disponibilidade criticos descritos na .

### 12.1 - Smoke Test

O script smoke-test.sh realiza verificacoes funcionais basicas da arquitetura: testa o endpoint de health check (GET /health), testa a criacao de transacoes (POST /transaction), e envia 10 requisicoes consecutivas ao balanceador para validar que a distribuicao de carga esta sendo realizada entre ambas as instancias (verificando a alternancia dos hostnames retornados).

### 12.2 - Validacao de RPO

O script validate-rpo.sh valida o RPO (Recovery Point Objective) da arquitetura, verificando que os dados inseridos no banco primario sao efetivamente replicados para a replica. O script executa as seguintes etapas: cria uma transacao via API, aguarda 2 segundos para propagacao da replicacao, consulta a replica para verificar se o registro existe, simula a parada do banco primario e confirma que os dados sobreviveram na replica. Um resultado positivo indica RPO proximo de zero, conforme o objetivo estabelecido.

### 12.3 - Validacao de RTO

O script validate-rto.sh valida o RTO (Recovery Time Objective) da arquitetura, medindo o tempo necessario para que o sistema se recupere apos a falha de uma instancia da aplicacao. O script verifica que ambas as instancias estao saudaveis, simula a parada de uma instancia (app-1), envia requisicoes continuamente ao balanceador e conta o numero de falhas ate que 5 requisicoes consecutivas sejam bem-sucedidas. O tempo decorrido entre a falha e a recuperacao constitui o RTO medido. O resultado esperado e inferior a 15 segundos, compativel com a configuracao de health checks passivos do Nginx (max_fails=3, fail_timeout=10s).

---

## 13 - Quadro Resumo das Tecnologias

| Tecnologia | Versao | Categoria | Papel na Arquitetura |
|---|---|---|---|
| TypeScript | 5.1.3 | Linguagem de Programacao | Linguagem principal da aplicacao, com tipagem estatica |
| Node.js | 22 (Alpine) | Ambiente de Execucao | Runtime JavaScript para execucao do servidor |
| FastAPI | 10.x | Framework de Aplicacao | Estrutura modular para construcao da API REST |
| PostgreSQL | 16 (Alpine) | Banco de Dados | Armazenamento relacional com replicacao via WAL |
| TypeORM | 0.3.28 | ORM | Mapeamento objeto-relacional e abstracoes de banco |
| Docker | - | Contenerizacao | Isolamento de servicos e simulacao de multi-zona |
| Nginx | 1.25 (Alpine) | Balanceador de Carga | Distribuicao de trafego e failover automatico |
| Terraform | ~3.0 (provider Docker) | Infraestrutura como Codigo | Provisionamento declarativo da infraestrutura |
| Jest | 29.5.0 | Testes Automatizados | Execucao de testes unitarios e de integracao |
| Supertest | 7.0.0 | Testes HTTP | Testes de ponta a ponta contra a API |
| class-validator | 0.14.3 | Validacao | Validacao declarativa dos dados de entrada |
| class-transformer | 0.5.1 | Transformacao | Conversao de JSON para instancias de classe |
| ESLint | 8.42.0 | Linter | Analise estatica de qualidade de codigo |
| Prettier | 3.0.0 | Formatador | Formatacao automatica e consistente do codigo |
| prom-client | 15.x | Metricas | Exportacao de metricas no formato Prometheus |
| Prometheus | 2.51.0 | Observabilidade | Coleta e armazenamento de metricas (SLIs) |
| Grafana | 10.4.0 | Observabilidade | Visualizacao de dashboards e error budget |
| postgres-exporter | 0.15.0 | Observabilidade | Exportacao de metricas do PostgreSQL |

---

## 14 - Consideracoes sobre as Escolhas Tecnologicas

As tecnologias selecionadas para a prova de conceito foram escolhidas com base em criterios de alinhamento com os objetivos do trabalho, e nao apenas por preferencia pessoal ou popularidade. Cada escolha reflete uma decisao arquitetural consciente:

A adocao do PostgreSQL com replicacao WAL nativa, em vez de solucoes de replicacao de terceiros, garante que o mecanismo de replicacao seja parte integral do sistema de banco de dados, reduzindo pontos de falha adicionais e complexidade operacional. Esta decisao se alinha com o principio de simplicidade discutido na analise do algoritmo Raft versus Paxos (), onde protocolos mais simples resultam em menor MTTR.

A utilizacao de Docker com redes isoladas para simular Zonas de Disponibilidade permite que toda a arquitetura seja provisionada e testada em um ambiente local, sem custos de infraestrutura em nuvem, enquanto mantem a fidelidade conceitual da topologia multi-zona. A portabilidade dos containers garante que o mesmo ambiente pode ser reproduzido em qualquer maquina de desenvolvimento.

A escolha do Terraform como ferramenta de IaC, mesmo utilizando o provider Docker local, demonstra que a pratica de infraestrutura declarativa e independente de plataforma. A transicao desta prova de conceito para um ambiente de nuvem publica (AWS, GCP ou Azure) exigiria a substituicao do provider e a adaptacao dos recursos, mas os principios de provisionamento declarativo, gerenciamento de estado e reprodutibilidade permaneceriam identicos.

O Nginx foi selecionado como balanceador de carga por sua comprovada capacidade de operacao em ambientes de alta carga, seu consumo minimo de recursos e a simplicidade de configuracao dos health checks passivos. A configuracao adotada demonstra como o failover automatico pode ser alcancado sem dependencia de ferramentas externas de orquestracao, implementando na pratica os conceitos de deteccao e recuperacao de falhas discutidos nas secoes 3.3 e 3.4 .

Por fim, o FastAPI com TypeScript foi escolhido por proporcionar uma base estruturada para a aplicacao, onde a injecao de dependencias e a modularidade facilitam tanto a testabilidade quanto a manutencao. A tipagem estatica do TypeScript contribui para a deteccao precoce de erros, enquanto o sistema de validacao integrado (ValidationPipe + class-validator) garante a integridade dos dados na fronteira da aplicacao.


