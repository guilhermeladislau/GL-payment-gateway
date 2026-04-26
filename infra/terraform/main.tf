terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

# -------------------- NETWORKS (Availability Zones) --------------------

resource "docker_network" "az1" {
  name = "az-1"
}

resource "docker_network" "az2" {
  name = "az-2"
}

# -------------------- IMAGES --------------------

resource "docker_image" "app" {
  name = "gateway-tcc:latest"
  build {
    context    = "${path.module}/../../"
    dockerfile = "Dockerfile"
  }
}

resource "docker_image" "nginx" {
  name = "nginx:1.25-alpine"
}

resource "docker_image" "postgres" {
  name = "postgres:16-alpine"
}

resource "docker_image" "prometheus" {
  name = "prom/prometheus:v2.51.0"
}

resource "docker_image" "grafana" {
  name = "grafana/grafana:10.4.0"
}

resource "docker_image" "pg_exporter" {
  name = "prometheuscommunity/postgres-exporter:v0.15.0"
}

# -------------------- POSTGRESQL PRIMARY (AZ-1) --------------------

resource "docker_container" "pg_primary" {
  name  = "pg-primary"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=postgres",
    "POSTGRES_DB=gateway",
  ]

  networks_advanced {
    name = docker_network.az1.id
  }

  networks_advanced {
    name = docker_network.az2.id
  }

  volumes {
    host_path      = abspath("${path.module}/../postgres/primary/init-primary.sh")
    container_path = "/docker-entrypoint-initdb.d/init-primary.sh"
  }

  ports {
    internal = 5432
    external = var.pg_primary_port
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "5s"
    timeout  = "3s"
    retries  = 5
  }

  must_run = true
  restart  = "unless-stopped"
}

# -------------------- POSTGRESQL REPLICA (AZ-2) --------------------

resource "docker_container" "pg_replica" {
  name  = "pg-replica"
  image = docker_image.postgres.image_id

  depends_on = [docker_container.pg_primary]

  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=postgres",
    "PGDATA=/var/lib/postgresql/data",
  ]

  networks_advanced {
    name = docker_network.az2.id
  }

  entrypoint = ["/bin/bash", "/init-replica.sh"]

  volumes {
    host_path      = abspath("${path.module}/../postgres/replica/init-replica.sh")
    container_path = "/init-replica.sh"
  }

  ports {
    internal = 5432
    external = var.pg_replica_port
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  must_run = true
  restart  = "unless-stopped"
}

# -------------------- APP CONTAINER 1 (AZ-1) --------------------

resource "docker_container" "app1" {
  name  = "app-1"
  image = docker_image.app.image_id

  depends_on = [docker_container.pg_primary, docker_container.pg_replica]

  env = [
    "PORT=3000",
    "DB_HOST=pg-primary",
    "DB_PORT=5432",
    "DB_USER=postgres",
    "DB_PASS=postgres",
    "DB_NAME=gateway",
  ]

  networks_advanced {
    name = docker_network.az1.id
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -qO- http://localhost:3000/health || exit 1"]
    interval = "5s"
    timeout  = "3s"
    retries  = 5
  }

  must_run = true
  restart  = "unless-stopped"
}

# -------------------- APP CONTAINER 2 (AZ-2) --------------------

resource "docker_container" "app2" {
  name  = "app-2"
  image = docker_image.app.image_id

  depends_on = [docker_container.pg_primary, docker_container.pg_replica]

  env = [
    "PORT=3000",
    "DB_HOST=pg-primary",
    "DB_PORT=5432",
    "DB_USER=postgres",
    "DB_PASS=postgres",
    "DB_NAME=gateway",
  ]

  networks_advanced {
    name = docker_network.az2.id
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -qO- http://localhost:3000/health || exit 1"]
    interval = "5s"
    timeout  = "3s"
    retries  = 5
  }

  must_run = true
  restart  = "unless-stopped"
}

# -------------------- NGINX LOAD BALANCER (both AZs) --------------------

resource "docker_container" "nginx" {
  name  = "lb-nginx"
  image = docker_image.nginx.image_id

  depends_on = [docker_container.app1, docker_container.app2]

  networks_advanced {
    name = docker_network.az1.id
  }

  networks_advanced {
    name = docker_network.az2.id
  }

  volumes {
    host_path      = abspath("${path.module}/../nginx/nginx.conf")
    container_path = "/etc/nginx/conf.d/default.conf"
  }

  ports {
    internal = 80
    external = var.lb_port
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -qO- http://localhost/nginx-health || exit 1"]
    interval = "5s"
    timeout  = "3s"
    retries  = 3
  }

  must_run = true
  restart  = "unless-stopped"
}

# -------------------- OBSERVABILITY STACK --------------------

# PostgreSQL Exporter - Primary
resource "docker_container" "pg_exporter_primary" {
  name  = "pg-exporter-primary"
  image = docker_image.pg_exporter.image_id

  depends_on = [docker_container.pg_primary]

  env = [
    "DATA_SOURCE_NAME=postgresql://postgres:postgres@pg-primary:5432/gateway?sslmode=disable",
  ]

  networks_advanced {
    name = docker_network.az1.id
  }

  must_run = true
  restart  = "unless-stopped"
}

# PostgreSQL Exporter - Replica
resource "docker_container" "pg_exporter_replica" {
  name  = "pg-exporter-replica"
  image = docker_image.pg_exporter.image_id

  depends_on = [docker_container.pg_replica]

  env = [
    "DATA_SOURCE_NAME=postgresql://postgres:postgres@pg-replica:5432/gateway?sslmode=disable",
  ]

  networks_advanced {
    name = docker_network.az2.id
  }

  must_run = true
  restart  = "unless-stopped"
}

# Prometheus
resource "docker_container" "prometheus" {
  name  = "prometheus"
  image = docker_image.prometheus.image_id

  depends_on = [
    docker_container.app1,
    docker_container.app2,
    docker_container.pg_exporter_primary,
    docker_container.pg_exporter_replica,
  ]

  networks_advanced {
    name = docker_network.az1.id
  }

  networks_advanced {
    name = docker_network.az2.id
  }

  volumes {
    host_path      = abspath("${path.module}/../prometheus/prometheus.yml")
    container_path = "/etc/prometheus/prometheus.yml"
  }

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  must_run = true
  restart  = "unless-stopped"
}

# Grafana
resource "docker_container" "grafana" {
  name  = "grafana"
  image = docker_image.grafana.image_id

  depends_on = [docker_container.prometheus]

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=admin",
    "GF_USERS_ALLOW_SIGN_UP=false",
  ]

  networks_advanced {
    name = docker_network.az1.id
  }

  networks_advanced {
    name = docker_network.az2.id
  }

  volumes {
    host_path      = abspath("${path.module}/../grafana/provisioning")
    container_path = "/etc/grafana/provisioning"
  }

  volumes {
    host_path      = abspath("${path.module}/../grafana/dashboards")
    container_path = "/var/lib/grafana/dashboards"
  }

  ports {
    internal = 3000
    external = var.grafana_port
  }

  must_run = true
  restart  = "unless-stopped"
}
