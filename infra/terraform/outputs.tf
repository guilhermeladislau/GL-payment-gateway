output "lb_url" {
  value = "http://localhost:${var.lb_port}"
}

output "health_url" {
  value = "http://localhost:${var.lb_port}/health"
}

output "transaction_url" {
  value = "http://localhost:${var.lb_port}/transaction"
}

output "pg_primary_dsn" {
  value = "postgresql://postgres:postgres@localhost:${var.pg_primary_port}/gateway"
}

output "pg_replica_dsn" {
  value = "postgresql://postgres:postgres@localhost:${var.pg_replica_port}/gateway"
}

output "prometheus_url" {
  value = "http://localhost:${var.prometheus_port}"
}

output "grafana_url" {
  value = "http://localhost:${var.grafana_port} (admin/admin)"
}
