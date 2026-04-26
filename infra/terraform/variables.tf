variable "docker_host" {
  description = "Docker daemon socket (Linux: unix:///var/run/docker.sock, macOS: unix:///Users/<user>/.docker/run/docker.sock)"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "lb_port" {
  description = "External port for the Nginx load balancer"
  type        = number
  default     = 8080
}

variable "pg_primary_port" {
  description = "External port for PostgreSQL primary"
  type        = number
  default     = 5432
}

variable "pg_replica_port" {
  description = "External port for PostgreSQL replica"
  type        = number
  default     = 5433
}

variable "prometheus_port" {
  description = "External port for Prometheus"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "External port for Grafana"
  type        = number
  default     = 3001
}
